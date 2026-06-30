"""Guazi SQL Data Agent - FastAPI application entry point."""

import logging
import os
import threading
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.api import agent, auth, conversations, execute, shared_group, sql_files
from app.config import (
    BACKEND_ROOT,
    CORS_ORIGINS,
    DATABASE_PATH,
    DATABASE_URL,
    EMBEDDING_PROVIDER,
    INDEXING_WORKER_ENABLED,
    SHARED_VECTOR_NAMESPACE,
    VECTOR_STORE_TYPE,
)
from app.database import SessionLocal, init_db
from app.models.sql_file import SqlFile

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database and sync SQL files on startup."""
    from app.services.cos_db_service import (
        backup_sqlite_to_cos,
        flush_backup_sqlite_to_cos,
        is_cos_db_backup_enabled,
        restore_sqlite_from_cos,
        start_cos_backup_scheduler,
        stop_cos_backup_scheduler,
    )

    restored_from_cos = False
    if is_cos_db_backup_enabled():
        restored_from_cos = restore_sqlite_from_cos()

    init_db()

    from app.services.shared_group_service import ensure_default_group

    db_boot = SessionLocal()
    try:
        ensure_default_group(db_boot)
    finally:
        db_boot.close()

    db = SessionLocal()
    sql_count = 0
    try:
        sql_count = db.query(SqlFile).count()
        if DATABASE_URL:
            logger.info("Database: external (DATABASE_URL), sql_files=%s", sql_count)
        else:
            db_path = DATABASE_PATH
            size = db_path.stat().st_size if db_path.exists() else 0
            logger.info(
                "Database: sqlite path=%s size=%s bytes sql_files=%s",
                db_path,
                size,
                sql_count,
            )
            if sql_count == 0 and size < 4096:
                logger.warning(
                    "SQLite database looks empty. On CloudBase Cloud Run, mount "
                    "persistent storage to /app/data or set DATABASE_URL."
                )
    except Exception as exc:
        logger.warning("Database startup check failed: %s", exc)
    finally:
        db.close()

    if is_cos_db_backup_enabled() and (restored_from_cos or sql_count > 0):
        backup_sqlite_to_cos()
        start_cos_backup_scheduler()
    elif is_cos_db_backup_enabled():
        logger.warning(
            "COS DB backup skipped on startup: restore failed and database is empty"
        )

    from app.config import INDEXING_WORKER_ENABLED
    from app.services.indexing_worker import start_indexing_worker

    def _background_embed_warmup() -> None:
        from app.services.embedding_service import preload_embedding_model
        from app.services.indexing_diagnostics import run_startup_embed_probe

        preload_embedding_model()
        run_startup_embed_probe()

    if INDEXING_WORKER_ENABLED:
        from app.services.indexing_service import enqueue_index_job

        from app.models.shared_sql_file import SharedSqlFile
        from app.services.shared_indexing_service import enqueue_shared_index_job

        db_boot = SessionLocal()
        try:
            stale = (
                db_boot.query(SqlFile)
                .filter(SqlFile.index_status.in_(["pending", "failed"]))
                .all()
            )
            for row in stale:
                enqueue_index_job(db_boot, row.user_email, row.id, "upsert")
            shared_stale = (
                db_boot.query(SharedSqlFile)
                .filter(SharedSqlFile.index_status.in_(["pending", "failed"]))
                .all()
            )
            for row in shared_stale:
                enqueue_shared_index_job(db_boot, row.id, "upsert")
            db_boot.commit()
            total = len(stale) + len(shared_stale)
            if total:
                logger.info("Enqueued %s SQL files for vector indexing", total)
        finally:
            db_boot.close()

        threading.Thread(
            target=_background_embed_warmup,
            name="embed-warmup",
            daemon=True,
        ).start()
        start_indexing_worker()

    if os.getenv("AUTO_SYNC_SQL", "false").lower() == "true":
        from app.services.sync_service import sync_sql_files

        db = SessionLocal()
        try:
            result = sync_sql_files(db)
            logger.info("Startup SQL sync: %s", result)
        except Exception as exc:
            logger.warning("Startup SQL sync failed: %s", exc)
        finally:
            db.close()

    yield

    from app.services.indexing_worker import stop_indexing_worker

    stop_indexing_worker()
    stop_cos_backup_scheduler()
    if is_cos_db_backup_enabled():
        flush_backup_sqlite_to_cos()


app = FastAPI(
    title="Guazi SQL Data Agent",
    description="Personal SQL / metrics knowledge base workbench",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(shared_group.router)
app.include_router(auth.router)
app.include_router(sql_files.router)
app.include_router(agent.router)
app.include_router(conversations.router)
app.include_router(execute.router)


@app.get("/api/health")
def health_check():
    from app.services.cos_db_service import is_cos_db_backup_enabled
    from app.services.llm_service import is_llm_configured, probe_llm

    storage: dict = {"backend": "mysql" if DATABASE_URL else "sqlite"}
    if not DATABASE_URL and DATABASE_PATH:
        storage["path"] = str(DATABASE_PATH)
        storage["exists"] = DATABASE_PATH.exists()
        if DATABASE_PATH.exists():
            storage["size_bytes"] = DATABASE_PATH.stat().st_size
    storage["cos_db_backup"] = is_cos_db_backup_enabled()
    from app.services.cos_db_service import get_cos_storage_status

    storage.update(get_cos_storage_status())
    storage["shared_vector_namespace"] = SHARED_VECTOR_NAMESPACE
    storage["vector_store"] = VECTOR_STORE_TYPE
    storage["embedding_provider"] = EMBEDDING_PROVIDER
    storage["indexing_worker"] = INDEXING_WORKER_ENABLED

    from app.services.indexing_diagnostics import get_diagnostics

    storage["indexing_diagnostics"] = get_diagnostics()

    return {
        "status": "ok",
        "llm_configured": is_llm_configured(),
        "llm_probe": probe_llm(),
        "storage": storage,
    }


def _spa_index() -> FileResponse:
    static_dir = BACKEND_ROOT / "static"
    index = static_dir / "index.html"
    if not index.is_file():
        raise HTTPException(status_code=404, detail="Frontend not built")
    return FileResponse(index)


@app.get("/login")
def spa_login_page():
    """SPA entry — CloudBase only serves index.html at documented paths."""
    return _spa_index()


def _mount_frontend_static() -> None:
    """Production: serve Vite build from backend/static."""
    if os.getenv("SERVE_STATIC", "").lower() != "true":
        return

    static_dir = BACKEND_ROOT / "static"
    if not static_dir.is_dir():
        logger.warning("SERVE_STATIC=true but static dir missing: %s", static_dir)
        return

    app.mount("/", StaticFiles(directory=str(static_dir), html=True), name="frontend")
    logger.info("Serving frontend static files from %s", static_dir)


_mount_frontend_static()
