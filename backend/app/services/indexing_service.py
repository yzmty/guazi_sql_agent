"""Build index documents from SQL records and manage indexing jobs."""

from __future__ import annotations

import json
import logging
import time
from datetime import datetime

from sqlalchemy.orm import Session

from app.models.indexing_job import IndexingJob
from app.models.sql_file import SqlFile
from app.services.cos_db_service import schedule_backup_sqlite_to_cos
from app.services.embedding_service import embed_texts
from app.services.indexing_diagnostics import record_job_timing
from app.services.vector_store import get_vector_store

logger = logging.getLogger(__name__)


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


def build_sql_documents(record: SqlFile) -> list[tuple[str, str, dict]]:
    """Return list of (chunk_id, text, metadata)."""
    metrics = _parse_json_list(record.metrics_json)
    dimensions = _parse_json_list(record.dimensions_json)
    tags = _parse_json_list(record.tags_json)
    core_tables = _parse_json_list(record.core_tables_json)
    authors = _parse_json_list(record.authors_json)

    meta_base = {
        "user_email": record.user_email,
        "sql_file_id": int(record.id),
        "file_name": record.file_name,
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
        ]
    )
    chunks: list[tuple[str, str, dict]] = [
        (f"sql-{record.id}-meta", meta_text, {**meta_base, "chunk_type": "meta"}),
    ]

    sql_body = (record.sql_content or "").strip()
    if sql_body:
        preview = sql_body[:4000]
        chunks.append(
            (
                f"sql-{record.id}-body",
                f"SQL文件: {record.file_name}\n{preview}",
                {**meta_base, "chunk_type": "sql"},
            )
        )
    return chunks


def enqueue_index_job(
    db: Session,
    user_email: str,
    sql_file_id: int | None,
    op: str,
) -> None:
    """Enqueue upsert/delete; collapse duplicate pending jobs for same sql_file."""
    if sql_file_id and op == "upsert":
        pending = (
            db.query(IndexingJob)
            .filter(
                IndexingJob.user_email == user_email,
                IndexingJob.sql_file_id == sql_file_id,
                IndexingJob.op == "upsert",
                IndexingJob.status == "pending",
            )
            .all()
        )
        if pending:
            for job in pending[1:]:
                db.delete(job)
            pending[0].updated_at = datetime.utcnow()
            if sql_file_id:
                record = (
                    db.query(SqlFile)
                    .filter(SqlFile.id == sql_file_id, SqlFile.user_email == user_email)
                    .first()
                )
                if record:
                    record.index_status = "pending"
            return

    db.add(
        IndexingJob(
            user_email=user_email,
            sql_file_id=sql_file_id,
            op=op,
            status="pending",
        )
    )
    if sql_file_id and op == "upsert":
        record = (
            db.query(SqlFile)
            .filter(SqlFile.id == sql_file_id, SqlFile.user_email == user_email)
            .first()
        )
        if record:
            record.index_status = "pending"
            record.index_error = None


def process_index_job(db: Session, job: IndexingJob) -> None:
    store = get_vector_store()
    t_total = time.perf_counter()
    phases_ms: dict[str, float] = {}
    job.status = "processing"
    job.updated_at = datetime.utcnow()
    db.commit()

    try:
        if job.op == "delete":
            t0 = time.perf_counter()
            if job.sql_file_id:
                store.delete_by_sql_file(job.user_email, job.sql_file_id)
            phases_ms["delete"] = (time.perf_counter() - t0) * 1000
            job.status = "done"
            job.error_message = None
            return

        if not job.sql_file_id:
            raise ValueError("upsert job missing sql_file_id")

        t0 = time.perf_counter()
        record = (
            db.query(SqlFile)
            .filter(
                SqlFile.id == job.sql_file_id,
                SqlFile.user_email == job.user_email,
            )
            .first()
        )
        phases_ms["load_record"] = (time.perf_counter() - t0) * 1000
        if not record:
            job.status = "done"
            job.error_message = "record deleted"
            return

        t0 = time.perf_counter()
        chunks = build_sql_documents(record)
        store.delete_by_sql_file(job.user_email, record.id)
        phases_ms["build_and_delete"] = (time.perf_counter() - t0) * 1000
        if not chunks:
            record.index_status = "ready"
            record.index_error = None
            record.indexed_at = datetime.utcnow()
            job.status = "done"
            return

        ids = [c[0] for c in chunks]
        docs = [c[1] for c in chunks]
        metas = [c[2] for c in chunks]
        t0 = time.perf_counter()
        vectors = embed_texts(docs)
        phases_ms["embed"] = (time.perf_counter() - t0) * 1000
        t0 = time.perf_counter()
        store.upsert(ids, vectors, docs, metas)
        phases_ms["upsert"] = (time.perf_counter() - t0) * 1000

        record.index_status = "ready"
        record.index_error = None
        record.indexed_at = datetime.utcnow()
        job.status = "done"
        job.error_message = None
    except Exception as exc:
        logger.exception("Indexing job %s failed", job.id)
        job.status = "failed"
        job.error_message = str(exc)[:500]
        if job.sql_file_id:
            record = (
                db.query(SqlFile)
                .filter(SqlFile.id == job.sql_file_id)
                .first()
            )
            if record:
                record.index_status = "failed"
                record.index_error = job.error_message
    finally:
        job.updated_at = datetime.utcnow()
        db.commit()
        if job.status == "done":
            schedule_backup_sqlite_to_cos()
        record_job_timing(
            job_id=int(job.id),
            sql_file_id=job.sql_file_id,
            phases_ms={k: round(v, 1) for k, v in phases_ms.items()},
            total_ms=(time.perf_counter() - t_total) * 1000,
            status=str(job.status),
        )


def reconcile_user_index(db: Session, user_email: str) -> int:
    """
    On login / cloud restore: ensure each user's SQL has vector chunks in cloud DB.
    Re-enqueue upsert when vectors are missing or index is not ready.
    """
    store = get_vector_store()
    records = db.query(SqlFile).filter(SqlFile.user_email == user_email).all()
    enqueued = 0
    for record in records:
        chunk_count = store.count_for_sql_file(user_email, record.id)
        needs_index = (
            record.index_status != "ready"
            or chunk_count == 0
            or record.index_status == "failed"
        )
        if needs_index:
            enqueue_index_job(db, user_email, record.id, "upsert")
            enqueued += 1
    if enqueued:
        db.commit()
        logger.info("Reconcile index for %s: enqueued %s jobs", user_email, enqueued)
    return enqueued


def fetch_pending_jobs(db: Session, limit: int = 5) -> list[IndexingJob]:
    return (
        db.query(IndexingJob)
        .filter(IndexingJob.status == "pending")
        .order_by(IndexingJob.created_at.asc())
        .limit(limit)
        .all()
    )


def get_index_stats(db: Session, user_email: str) -> dict:
    total = db.query(SqlFile).filter(SqlFile.user_email == user_email).count()
    ready = (
        db.query(SqlFile)
        .filter(SqlFile.user_email == user_email, SqlFile.index_status == "ready")
        .count()
    )
    pending = (
        db.query(SqlFile)
        .filter(SqlFile.user_email == user_email, SqlFile.index_status == "pending")
        .count()
    )
    failed = (
        db.query(SqlFile)
        .filter(SqlFile.user_email == user_email, SqlFile.index_status == "failed")
        .count()
    )
    queue_pending = (
        db.query(IndexingJob)
        .filter(IndexingJob.user_email == user_email, IndexingJob.status == "pending")
        .count()
    )
    vector_chunks = get_vector_store().count_for_user(user_email)
    return {
        "total": total,
        "ready": ready,
        "pending": pending,
        "failed": failed,
        "queue_pending": queue_pending,
        "vector_chunks": vector_chunks,
        "storage": "cloud_sqlite",
    }
