"""Sync SQL files from disk into SQLite."""

import logging
from datetime import datetime
from pathlib import Path

from sqlalchemy.orm import Session

from app.config import SQLS_DIR
from app.models.sql_file import SqlFile
from app.services.parser_service import SqlParseError, parse_sql_file

logger = logging.getLogger(__name__)


def iter_sql_files(sqls_dir: Path | None = None) -> list[Path]:
    """Collect all .sql files under sqls directory (non-recursive)."""
    directory = sqls_dir or SQLS_DIR
    if not directory.exists():
        logger.warning("SQL directory does not exist: %s", directory)
        return []
    return sorted(directory.glob("*.sql"))


def sync_sql_files(db: Session, sqls_dir: Path | None = None) -> dict:
    """
    Scan sqls folder, parse each file, upsert by file_name.
    Returns sync statistics.
    """
    files = iter_sql_files(sqls_dir)
    inserted = 0
    updated = 0
    skipped = 0
    warnings: list[str] = []

    for file_path in files:
        try:
            parsed = parse_sql_file(file_path)
        except SqlParseError as exc:
            skipped += 1
            warnings.append(str(exc))
            continue
        except OSError as exc:
            skipped += 1
            warnings.append(f"读取失败 {file_path.name}: {exc}")
            continue

        if parsed is None:
            skipped += 1
            warnings.append(f"缺少注释块，已跳过: {file_path.name}")
            continue

        existing = (
            db.query(SqlFile)
            .filter(SqlFile.file_name == parsed["file_name"])
            .first()
        )

        now = datetime.utcnow()

        if existing:
            for key, value in parsed.items():
                setattr(existing, key, value)
            existing.updated_at = now
            updated += 1
        else:
            record = SqlFile(**parsed, user_email="legacy", created_at=now, updated_at=now)
            db.add(record)
            inserted += 1

    db.commit()

    return {
        "success": True,
        "total": len(files),
        "inserted": inserted,
        "updated": updated,
        "skipped": skipped,
        "warnings": warnings,
    }
