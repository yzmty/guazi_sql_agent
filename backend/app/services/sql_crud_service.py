"""CRUD operations for user-scoped SQL knowledge entries."""

from __future__ import annotations

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.sql_file import SqlFile
from app.services.cos_db_service import backup_sqlite_to_cos
from app.services.indexing_service import enqueue_index_job
from app.services.parser_service import SqlParseError, parse_sql_content


def _apply_parsed(record: SqlFile, parsed: dict) -> None:
    for key, value in parsed.items():
        if hasattr(record, key):
            setattr(record, key, value)
    if not record.file_path:
        record.file_path = ""


def get_owned_sql(db: Session, user_email: str, file_id: int) -> SqlFile | None:
    return (
        db.query(SqlFile)
        .filter(SqlFile.id == file_id, SqlFile.user_email == user_email)
        .first()
    )


def create_from_content(
    db: Session,
    user_email: str,
    full_content: str,
    file_name: str | None = None,
) -> tuple[SqlFile | None, str | None, bool]:
    """Returns (record, error, is_update)."""
    parsed = parse_sql_content(full_content, file_name or "untitled.sql")
    if not parsed:
        return None, "未找到标准注释块 /* ... */，请检查文件格式", False

    if file_name:
        parsed["file_name"] = file_name.strip()

    existing = (
        db.query(SqlFile)
        .filter(
            SqlFile.user_email == user_email,
            SqlFile.file_name == parsed["file_name"],
        )
        .first()
    )
    if existing:
        _apply_parsed(existing, parsed)
        return existing, None, True

    record = SqlFile(user_email=user_email)
    _apply_parsed(record, parsed)
    db.add(record)
    return record, None, False


def update_from_content(
    db: Session,
    user_email: str,
    file_id: int,
    full_content: str,
    file_name: str | None = None,
) -> tuple[SqlFile | None, str | None]:
    record = get_owned_sql(db, user_email, file_id)
    if not record:
        return None, "SQL 不存在或无权访问"

    parsed = parse_sql_content(full_content, file_name or record.file_name)
    if not parsed:
        return None, "未找到标准注释块 /* ... */"

    new_name = (file_name or parsed["file_name"]).strip()
    if new_name != record.file_name:
        conflict = (
            db.query(SqlFile)
            .filter(SqlFile.user_email == user_email, SqlFile.file_name == new_name)
            .first()
        )
        if conflict:
            return None, f"已存在同名 SQL: {new_name}"
        parsed["file_name"] = new_name

    _apply_parsed(record, parsed)
    return record, None


def delete_sql(db: Session, user_email: str, file_id: int) -> bool:
    record = get_owned_sql(db, user_email, file_id)
    if not record:
        return False
    db.delete(record)
    return True


def batch_save(
    db: Session,
    user_email: str,
    items: list[dict],
) -> dict:
    inserted = 0
    updated = 0
    errors: list[str] = []

    saved_ids: list[int] = []

    for item in items:
        full_content = item.get("full_content", "")
        file_name = item.get("file_name")
        item_id = item.get("id")

        try:
            if item_id:
                record, err = update_from_content(db, user_email, item_id, full_content, file_name)
                if err:
                    errors.append(f"{file_name or item_id}: {err}")
                elif record:
                    updated += 1
                    saved_ids.append(record.id)
            else:
                record, err, is_update = create_from_content(
                    db, user_email, full_content, file_name
                )
                if err:
                    errors.append(f"{file_name or '新 SQL'}: {err}")
                elif record:
                    db.flush()
                    if is_update:
                        updated += 1
                    else:
                        inserted += 1
                    saved_ids.append(record.id)
        except SqlParseError as exc:
            errors.append(f"{file_name or '新 SQL'}: {exc}")

    try:
        db.commit()
        backup_sqlite_to_cos()
        for sid in saved_ids:
            enqueue_index_job(db, user_email, sid, "upsert")
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        return {
            "success": False,
            "inserted": 0,
            "updated": 0,
            "errors": [f"保存失败: {exc.orig}"],
        }
    return {
        "success": len(errors) == 0,
        "inserted": inserted,
        "updated": updated,
        "errors": errors,
    }


def preview_parse(items: list[dict]) -> list[dict]:
    results = []
    for item in items:
        content = item.get("full_content", "")
        file_name = item.get("file_name", "untitled.sql")
        try:
            parsed = parse_sql_content(content, file_name)
            if not parsed:
                results.append(
                    {
                        "file_name": file_name,
                        "valid": False,
                        "error": "未找到标准注释块",
                        "parsed": None,
                    }
                )
            else:
                results.append(
                    {
                        "file_name": parsed["file_name"],
                        "valid": True,
                        "error": None,
                        "parsed": parsed,
                        "full_content": content,
                    }
                )
        except SqlParseError as exc:
            results.append(
                {
                    "file_name": file_name,
                    "valid": False,
                    "error": str(exc),
                    "parsed": None,
                }
            )
    return results
