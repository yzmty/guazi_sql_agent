"""Build index documents and enqueue jobs for shared SQL files."""

from __future__ import annotations

import json
from datetime import datetime

from sqlalchemy.orm import Session

from app.config import SHARED_VECTOR_NAMESPACE
from app.models.indexing_job import IndexingJob
from app.models.shared_sql_file import SharedSqlFile
from app.services.shared_sql_crypto import decrypt_shared_record


def _parse_json_list(value: str | None) -> list[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
        if isinstance(parsed, list):
            return [str(x) for x in parsed]
    except (json.JSONDecodeError, TypeError):
        pass
    return []


def build_shared_sql_documents(record: SharedSqlFile) -> list[tuple[str, str, dict]]:
    r = decrypt_shared_record(record)
    metrics = _parse_json_list(r.metrics_json)
    dimensions = _parse_json_list(r.dimensions_json)
    tags = _parse_json_list(r.tags_json)
    core_tables = _parse_json_list(r.core_tables_json)
    authors = _parse_json_list(r.authors_json)

    meta_base = {
        "user_email": SHARED_VECTOR_NAMESPACE,
        "sql_file_id": int(record.id),
        "file_name": record.file_name,
        "scope": "shared",
    }

    meta_text = "\n".join(
        [
            f"文件名: {record.file_name}",
            f"业务: {record.business or ''}",
            f"场景: {record.scene or ''}",
            f"指标: {', '.join(metrics)}",
            f"维度: {', '.join(dimensions)}",
            f"标签: {', '.join(tags)}",
            f"核心表: {', '.join(core_tables)}",
            f"作者: {', '.join(authors)}",
            f"描述: {record.description or ''}",
            "来源: 共享群",
        ]
    )
    chunks: list[tuple[str, str, dict]] = [
        (
            f"shared-{record.id}-meta",
            meta_text,
            {**meta_base, "chunk_type": "meta"},
        ),
    ]
    sql_body = (r.sql_content or "").strip()
    if sql_body:
        preview = sql_body[:4000]
        chunks.append(
            (
                f"shared-{record.id}-body",
                f"SQL文件: {record.file_name}\n{preview}",
                {**meta_base, "chunk_type": "sql"},
            )
        )
    return chunks


def enqueue_shared_index_job(db: Session, shared_sql_file_id: int, op: str) -> None:
    if op == "upsert":
        pending = (
            db.query(IndexingJob)
            .filter(
                IndexingJob.user_email == SHARED_VECTOR_NAMESPACE,
                IndexingJob.sql_file_id == shared_sql_file_id,
                IndexingJob.op == "upsert",
                IndexingJob.status == "pending",
            )
            .all()
        )
        if pending:
            for job in pending[1:]:
                db.delete(job)
            pending[0].updated_at = datetime.utcnow()
            record = db.query(SharedSqlFile).filter(SharedSqlFile.id == shared_sql_file_id).first()
            if record:
                record.index_status = "pending"
            return

    db.add(
        IndexingJob(
            user_email=SHARED_VECTOR_NAMESPACE,
            sql_file_id=shared_sql_file_id,
            op=op,
            status="pending",
        )
    )
    if op == "upsert":
        record = db.query(SharedSqlFile).filter(SharedSqlFile.id == shared_sql_file_id).first()
        if record:
            record.index_status = "pending"
            record.index_error = None
