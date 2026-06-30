"""CRUD and search for shared group SQL files."""

from __future__ import annotations

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import SHARED_VECTOR_NAMESPACE
from app.models.shared_sql_file import SharedSqlFile
from app.services.cos_db_service import backup_sqlite_to_cos
from app.services.shared_sql_crypto import decrypt_shared_record, encrypt_parsed_fields
from app.services.shared_indexing_service import enqueue_shared_index_job
from app.services.search_service import SearchParams, _matches_filters, compute_score
from app.services.shared_group_service import (
    SharedGroupAccessError,
    get_default_group,
    require_approved_member,
)
from app.utils.text_utils import parse_json_list


def _apply_parsed(record: SharedSqlFile, parsed: dict) -> None:
    for key, value in parsed.items():
        if hasattr(record, key):
            setattr(record, key, value)
    if not record.file_path:
        record.file_path = ""


def shared_record_to_context(record: SharedSqlFile) -> dict:
    r = decrypt_shared_record(record)
    return {
        "id": r.id,
        "file_name": r.file_name,
        "metrics": parse_json_list(r.metrics_json),
        "business": r.business or "",
        "scene": r.scene or "",
        "tags": parse_json_list(r.tags_json),
        "core_tables": parse_json_list(r.core_tables_json),
        "description": r.description or "",
        "dimensions": parse_json_list(r.dimensions_json),
        "authors": parse_json_list(r.authors_json),
        "sql_content": r.sql_content or "",
        "scope": "shared",
        "uploaded_by": record.uploaded_by,
        "storage_mode": record.storage_mode,
    }


def get_shared_sql(db: Session, user_email: str, file_id: int) -> SharedSqlFile | None:
    require_approved_member(db, user_email)
    group = get_default_group(db)
    record = (
        db.query(SharedSqlFile)
        .filter(SharedSqlFile.id == file_id, SharedSqlFile.group_id == group.id)
        .first()
    )
    return record


def list_shared_sql(
    db: Session,
    user_email: str,
    params: SearchParams | None = None,
) -> tuple[int, list[SharedSqlFile]]:
    from app.services.search_service import SearchParams as SP

    require_approved_member(db, user_email)
    group = get_default_group(db)
    search = params or SP()
    records = (
        db.query(SharedSqlFile)
        .filter(SharedSqlFile.group_id == group.id)
        .order_by(SharedSqlFile.file_name)
        .all()
    )

    keyword = (search.keyword or "").strip()
    scored: list[tuple[SharedSqlFile, float]] = []

    for record in records:
        if not _matches_filters(record, search):
            continue
        if keyword:
            score = compute_score(record, keyword)
            if score <= 0:
                continue
            scored.append((record, score))
        else:
            scored.append((record, 0.0))

    if keyword:
        scored.sort(key=lambda x: (-x[1], x[0].file_name))
    else:
        scored.sort(key=lambda x: x[0].file_name)

    total = len(scored)
    start = (search.page - 1) * search.page_size
    end = start + search.page_size
    return total, [r for r, _ in scored[start:end]]


def get_shared_filter_options(db: Session, user_email: str):
    from app.schemas.sql_file import FilterOptionsResponse

    require_approved_member(db, user_email)
    group = get_default_group(db)
    records = (
        db.query(SharedSqlFile).filter(SharedSqlFile.group_id == group.id).all()
    )

    businesses: set[str] = set()
    authors: set[str] = set()
    tags: set[str] = set()
    core_tables: set[str] = set()

    for record in records:
        if record.business:
            businesses.add(record.business.strip())
        for author in parse_json_list(record.authors_json):
            if author.strip():
                authors.add(author.strip())
        for tag in parse_json_list(record.tags_json):
            if tag.strip():
                tags.add(tag.strip())
        for table in parse_json_list(record.core_tables_json):
            if table.strip():
                core_tables.add(table.strip())

    return FilterOptionsResponse(
        businesses=sorted(businesses),
        authors=sorted(authors),
        tags=sorted(tags),
        core_tables=sorted(core_tables),
    )


def create_shared_sql(
    db: Session,
    user_email: str,
    full_content: str,
    file_name: str | None = None,
    *,
    storage_mode: str = "public",
    is_public: bool = True,
) -> tuple[SharedSqlFile | None, str | None]:
    require_approved_member(db, user_email)
    group = get_default_group(db)
    parsed = parse_sql_content(full_content, file_name or "untitled.sql")
    if not parsed:
        return None, "未找到标准注释块 /* ... */，请检查文件格式"
    if file_name:
        parsed["file_name"] = file_name.strip()

    mode = storage_mode if storage_mode in ("public", "encrypted") else "public"
    if mode == "encrypted":
        enc_sql, enc_comment = encrypt_parsed_fields(parsed)
        parsed["sql_content"] = enc_sql
        parsed["comment_block"] = enc_comment

    existing = (
        db.query(SharedSqlFile)
        .filter(
            SharedSqlFile.group_id == group.id,
            SharedSqlFile.file_name == parsed["file_name"],
        )
        .first()
    )
    if existing:
        _apply_parsed(existing, parsed)
        existing.storage_mode = mode
        existing.is_public = is_public
        existing.uploaded_by = user_email.lower()
        record = existing
    else:
        record = SharedSqlFile(
            group_id=group.id,
            uploaded_by=user_email.lower(),
            storage_mode=mode,
            is_public=is_public,
        )
        _apply_parsed(record, parsed)
        db.add(record)

    db.flush()
    db.commit()
    backup_sqlite_to_cos()
    enqueue_shared_index_job(db, record.id, "upsert")
    db.commit()
    db.refresh(record)
    return record, None


def delete_shared_sql(db: Session, user_email: str, file_id: int) -> bool:
    require_approved_member(db, user_email)
    group = get_default_group(db)
    record = (
        db.query(SharedSqlFile)
        .filter(SharedSqlFile.id == file_id, SharedSqlFile.group_id == group.id)
        .first()
    )
    if not record:
        return False
    db.delete(record)
    db.commit()
    backup_sqlite_to_cos()
    enqueue_shared_index_job(db, file_id, "delete")
    db.commit()
    return True


def batch_save_shared(
    db: Session,
    user_email: str,
    items: list[dict],
) -> dict:
    inserted = 0
    updated = 0
    errors: list[str] = []
    for item in items:
        full_content = item.get("full_content", "")
        file_name = item.get("file_name")
        storage_mode = item.get("storage_mode", "public")
        is_public = item.get("is_public", True)
        try:
            record, err = create_shared_sql(
                db,
                user_email,
                full_content,
                file_name,
                storage_mode=storage_mode,
                is_public=is_public,
            )
            if err:
                errors.append(f"{file_name or '新 SQL'}: {err}")
            elif record:
                inserted += 1
        except (SqlParseError, SharedGroupAccessError) as exc:
            errors.append(f"{file_name or '新 SQL'}: {exc}")
        except IntegrityError as exc:
            errors.append(f"{file_name or '新 SQL'}: {exc}")
    return {
        "success": len(errors) == 0,
        "inserted": inserted,
        "updated": updated,
        "errors": errors,
    }


def shared_sql_detail_dict(record: SharedSqlFile) -> dict:
    r = decrypt_shared_record(record)
    return {
        "id": record.id,
        "file_name": record.file_name,
        "business": record.business,
        "scene": record.scene,
        "metrics": parse_json_list(record.metrics_json),
        "tags": parse_json_list(record.tags_json),
        "dimensions": parse_json_list(record.dimensions_json),
        "core_tables": parse_json_list(record.core_tables_json),
        "authors": parse_json_list(record.authors_json),
        "description": record.description,
        "sql_content": r.sql_content,
        "comment_block": r.comment_block,
        "storage_mode": record.storage_mode,
        "is_public": record.is_public,
        "uploaded_by": record.uploaded_by,
        "index_status": record.index_status,
        "created_at": record.created_at.isoformat() if record.created_at else None,
        "scope": "shared",
    }
