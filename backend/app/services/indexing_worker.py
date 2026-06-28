"""Background indexing worker thread."""

from __future__ import annotations

import logging
import threading
import time

from app.config import INDEXING_WORKER_BATCH_SIZE, INDEXING_WORKER_INTERVAL_SEC
from app.database import SessionLocal
from app.models.indexing_job import IndexingJob
from app.services.cos_db_service import flush_backup_sqlite_to_cos
from app.services.indexing_service import fetch_pending_jobs, process_index_job

logger = logging.getLogger(__name__)

_stop_event = threading.Event()
_worker_thread: threading.Thread | None = None


def _worker_loop() -> None:
    logger.info("Indexing worker started")
    while not _stop_event.is_set():
        db = SessionLocal()
        try:
            jobs = fetch_pending_jobs(db, limit=INDEXING_WORKER_BATCH_SIZE)
            for job in jobs:
                if _stop_event.is_set():
                    break
                process_index_job(db, job)
            if jobs:
                pending_left = (
                    db.query(IndexingJob)
                    .filter(IndexingJob.status == "pending")
                    .count()
                )
                if pending_left == 0:
                    flush_backup_sqlite_to_cos()
        except Exception as exc:
            logger.exception("Indexing worker iteration failed: %s", exc)
        finally:
            db.close()
        _stop_event.wait(INDEXING_WORKER_INTERVAL_SEC)
    logger.info("Indexing worker stopped")


def start_indexing_worker() -> None:
    global _worker_thread
    if _worker_thread and _worker_thread.is_alive():
        return
    _stop_event.clear()
    _worker_thread = threading.Thread(
        target=_worker_loop,
        name="indexing-worker",
        daemon=True,
    )
    _worker_thread.start()


def stop_indexing_worker() -> None:
    _stop_event.set()
    if _worker_thread and _worker_thread.is_alive():
        _worker_thread.join(timeout=5)
