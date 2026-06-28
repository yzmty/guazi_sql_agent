"""Backup SQLite database to CloudBase/COS object storage."""

from __future__ import annotations

import logging
import os
import shutil
import tempfile
import threading
import time
from pathlib import Path

import httpx

from app.config import (
    COS_BUCKET,
    COS_DB_BACKUP,
    COS_DB_KEY,
    COS_REGION,
    COS_SECRET_ID,
    COS_SECRET_KEY,
    DATABASE_PATH,
    DATABASE_URL,
)

logger = logging.getLogger(__name__)

# CloudBase open-interface: prefer in-container loopback (127.0.0.1) first.
_COS_AUTH_URLS = (
    "http://127.0.0.1/_/cos/getauth",
    "http://api.weixin.qq.com/_/cos/getauth",
)

_CREDENTIAL_RETRY_ATTEMPTS = int(os.getenv("COS_CREDENTIAL_RETRY_ATTEMPTS", "15"))
_CREDENTIAL_RETRY_DELAY = float(os.getenv("COS_CREDENTIAL_RETRY_DELAY", "2.0"))
_STARTUP_RESTORE_ATTEMPTS = int(os.getenv("COS_STARTUP_RESTORE_ATTEMPTS", "3"))

_backup_lock = threading.Lock()
_backup_generation = 0
_backup_last_uploaded = 0
_backup_scheduler_thread: threading.Thread | None = None
_backup_stop_event = threading.Event()


def is_cos_db_backup_enabled() -> bool:
    return COS_DB_BACKUP and not DATABASE_URL and bool(COS_BUCKET)


def is_cos_volume_mounted() -> bool:
    """True when CloudBase COS volume is mounted to DATA_DIR (see setup-storage-mount.js)."""
    return os.getenv("COS_VOLUME_MOUNTED", "").lower() == "true"


def _local_db_size() -> int:
    try:
        return DATABASE_PATH.stat().st_size if DATABASE_PATH.exists() else 0
    except OSError:
        return 0


def _parse_cos_auth_payload(data: dict) -> dict[str, str] | None:
    secret_id = data.get("TmpSecretId") or data.get("tmpSecretId")
    secret_key = data.get("TmpSecretKey") or data.get("tmpSecretKey")
    token = data.get("Token") or data.get("sessionToken") or ""
    if secret_id and secret_key:
        return {
            "secret_id": secret_id,
            "secret_key": secret_key,
            "token": token,
        }
    return None


def _fetch_runtime_cos_credentials_once() -> dict[str, str] | None:
    for url in _COS_AUTH_URLS:
        try:
            # Do NOT follow redirects: external https://api.weixin.qq.com returns 404
            # outside CloudBase open-interface proxy.
            with httpx.Client(follow_redirects=False, timeout=10.0) as client:
                resp = client.get(url)
            if resp.status_code != 200:
                logger.warning("COS auth %s returned HTTP %s", url, resp.status_code)
                continue
            data = resp.json()
            creds = _parse_cos_auth_payload(data)
            if creds:
                logger.info("COS runtime credentials obtained via %s", url)
                return creds
            logger.warning("COS auth %s returned empty credentials", url)
        except Exception as exc:
            logger.warning("COS auth via %s failed: %s", url, exc)
    return None


def _fetch_runtime_cos_credentials(*, max_attempts: int | None = None) -> dict[str, str] | None:
    if COS_SECRET_ID and COS_SECRET_KEY:
        return {
            "secret_id": COS_SECRET_ID,
            "secret_key": COS_SECRET_KEY,
            "token": "",
        }

    attempts = max_attempts or _CREDENTIAL_RETRY_ATTEMPTS
    for attempt in range(1, attempts + 1):
        creds = _fetch_runtime_cos_credentials_once()
        if creds:
            return creds
        if attempt < attempts:
            logger.info(
                "COS credentials not ready (attempt %s/%s), retry in %ss",
                attempt,
                attempts,
                _CREDENTIAL_RETRY_DELAY,
            )
            time.sleep(_CREDENTIAL_RETRY_DELAY)
    return None


def _load_cos_client(*, max_attempts: int | None = None):
    from qcloud_cos import CosConfig, CosS3Client

    creds = _fetch_runtime_cos_credentials(max_attempts=max_attempts)
    if not creds:
        return None

    config = CosConfig(
        Region=COS_REGION,
        SecretId=creds["secret_id"],
        SecretKey=creds["secret_key"],
        Token=creds.get("token") or None,
    )
    return CosS3Client(config)


def _cos_object_size(client, key: str = COS_DB_KEY) -> int | None:
    try:
        head = client.head_object(Bucket=COS_BUCKET, Key=key)
        return int(head.get("Content-Length") or 0)
    except Exception as exc:
        if "NoSuchKey" in str(exc) or "404" in str(exc):
            return None
        logger.debug("COS head_object failed: %s", exc)
        return None


def _download_db_snapshot(client) -> Path | None:
    tmp_path = Path(tempfile.mkstemp(suffix=".db")[1])
    try:
        client.download_file(
            Bucket=COS_BUCKET,
            Key=COS_DB_KEY,
            DestFilePath=str(tmp_path),
        )
        if tmp_path.stat().st_size <= 0:
            logger.info("COS DB object empty")
            return None
        return tmp_path
    except Exception as exc:
        if "NoSuchKey" in str(exc) or "404" in str(exc):
            logger.info("No COS DB snapshot yet (%s)", COS_DB_KEY)
            return None
        logger.warning("COS DB download failed: %s", exc)
        return None
    finally:
        if tmp_path.exists() and tmp_path.stat().st_size <= 0:
            tmp_path.unlink(missing_ok=True)


def _apply_downloaded_db(tmp_path: Path) -> bool:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(tmp_path, DATABASE_PATH)
    logger.info(
        "Restored SQLite from COS bucket=%s key=%s size=%s",
        COS_BUCKET,
        COS_DB_KEY,
        DATABASE_PATH.stat().st_size,
    )
    return True


def _should_restore_from_remote(local_size: int, remote_size: int | None) -> bool:
    if not remote_size or remote_size <= 0:
        return False
    if local_size <= 0:
        return True
    if remote_size >= 8192 and local_size < remote_size * 0.5:
        return True
    return False


def restore_sqlite_from_cos(*, max_attempts: int | None = None) -> bool:
    """
    Download sqlite snapshot from COS before app init.
    Startup uses a short retry budget; login-time ensure uses longer retries.
    """
    if not is_cos_db_backup_enabled():
        return False

    attempts = max_attempts or _STARTUP_RESTORE_ATTEMPTS
    cred_attempts = min(attempts, 3)

    local_size = _local_db_size()
    if is_cos_volume_mounted() and local_size >= 8192:
        logger.info(
            "COS volume mounted and local db present (%s bytes), skip SDK restore",
            local_size,
        )
        return True

    for attempt in range(1, attempts + 1):
        client = _load_cos_client(max_attempts=cred_attempts)
        if not client:
            if attempt < attempts:
                logger.info(
                    "COS restore waiting for credentials (%s/%s)",
                    attempt,
                    attempts,
                )
                time.sleep(_CREDENTIAL_RETRY_DELAY)
                continue
            logger.warning("COS DB restore skipped: no credentials after retries")
            return False

        remote_size = _cos_object_size(client)
        local_size = _local_db_size()
        if not _should_restore_from_remote(local_size, remote_size):
            if remote_size:
                logger.info(
                    "Local db (%s bytes) OK vs remote (%s bytes), skip restore",
                    local_size,
                    remote_size,
                )
            return local_size > 0

        tmp_path = _download_db_snapshot(client)
        if tmp_path:
            try:
                return _apply_downloaded_db(tmp_path)
            finally:
                tmp_path.unlink(missing_ok=True)

        if attempt < attempts:
            time.sleep(_CREDENTIAL_RETRY_DELAY)

    return False


def ensure_sqlite_from_cos() -> bool:
    """
    Login / request-time fallback: if local DB is empty or much smaller than COS
    snapshot, re-download and re-open the database.
    """
    if not is_cos_db_backup_enabled():
        return False

    client = _load_cos_client(max_attempts=_CREDENTIAL_RETRY_ATTEMPTS)
    if not client:
        logger.warning("ensure_sqlite_from_cos: no COS credentials")
        return False

    local_size = _local_db_size()
    remote_size = _cos_object_size(client)
    if not _should_restore_from_remote(local_size, remote_size):
        return False

    logger.warning(
        "Local db (%s bytes) behind COS snapshot (%s bytes), restoring on demand",
        local_size,
        remote_size,
    )

    tmp_path = _download_db_snapshot(client)
    if not tmp_path:
        return False

    try:
        from app.database import dispose_engine, init_db

        dispose_engine()
        restored = _apply_downloaded_db(tmp_path)
        if restored:
            init_db()
        return restored
    finally:
        tmp_path.unlink(missing_ok=True)


def backup_sqlite_to_cos(*, force: bool = False) -> bool:
    """Upload current sqlite file to COS after data changes."""
    if not is_cos_db_backup_enabled():
        return False
    if not DATABASE_PATH.exists():
        return False

    client = _load_cos_client(max_attempts=_CREDENTIAL_RETRY_ATTEMPTS)
    if not client:
        logger.warning("COS DB backup skipped: no credentials")
        return False

    local_size = DATABASE_PATH.stat().st_size
    if not force:
        remote_size = _cos_object_size(client)
        if remote_size and remote_size >= 8192 and local_size < remote_size * 0.5:
            logger.warning(
                "COS DB backup skipped: local db (%s bytes) is much smaller than "
                "remote snapshot (%s bytes); refusing to overwrite",
                local_size,
                remote_size,
            )
            return False
        if local_size < 8192:
            logger.warning(
                "COS DB backup skipped: local db looks empty (%s bytes)", local_size
            )
            return False

    tmp_path = Path(tempfile.mkstemp(suffix=".db")[1])
    try:
        shutil.copyfile(DATABASE_PATH, tmp_path)
        client.upload_file(
            Bucket=COS_BUCKET,
            LocalFilePath=str(tmp_path),
            Key=COS_DB_KEY,
        )
        logger.info(
            "Backed up SQLite to COS bucket=%s key=%s size=%s",
            COS_BUCKET,
            COS_DB_KEY,
            tmp_path.stat().st_size,
        )
        return True
    except Exception as exc:
        logger.warning("COS DB backup failed: %s", exc)
        return False
    finally:
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)


def schedule_backup_sqlite_to_cos() -> None:
    """Mark DB dirty; periodic scheduler uploads within COS_BACKUP_INTERVAL_SEC."""
    if not is_cos_db_backup_enabled():
        return
    global _backup_generation
    with _backup_lock:
        _backup_generation += 1


def flush_backup_sqlite_to_cos(*, force: bool = False) -> bool:
    """Upload immediately when there are pending index changes (or force=True)."""
    if not is_cos_db_backup_enabled():
        return False
    with _backup_lock:
        if not force and _backup_generation <= _backup_last_uploaded:
            return False
    ok = backup_sqlite_to_cos(force=force)
    with _backup_lock:
        if ok:
            _backup_last_uploaded = _backup_generation
        return ok


def _backup_scheduler_loop() -> None:
    from app.config import COS_BACKUP_INTERVAL_SEC

    logger.info("COS backup scheduler started (interval=%ss)", COS_BACKUP_INTERVAL_SEC)
    while not _backup_stop_event.is_set():
        _backup_stop_event.wait(COS_BACKUP_INTERVAL_SEC)
        if _backup_stop_event.is_set():
            break
        with _backup_lock:
            pending = _backup_generation > _backup_last_uploaded
        if pending:
            flush_backup_sqlite_to_cos()


def start_cos_backup_scheduler() -> None:
    global _backup_scheduler_thread
    if not is_cos_db_backup_enabled():
        return
    if _backup_scheduler_thread and _backup_scheduler_thread.is_alive():
        return
    _backup_stop_event.clear()
    _backup_scheduler_thread = threading.Thread(
        target=_backup_scheduler_loop,
        name="cos-backup-scheduler",
        daemon=True,
    )
    _backup_scheduler_thread.start()


def stop_cos_backup_scheduler() -> None:
    _backup_stop_event.set()
    if _backup_scheduler_thread and _backup_scheduler_thread.is_alive():
        _backup_scheduler_thread.join(timeout=5)


def get_cos_storage_status() -> dict:
    """Diagnostics for /api/health."""
    status: dict = {
        "cos_db_backup": is_cos_db_backup_enabled(),
        "cos_volume_mounted": is_cos_volume_mounted(),
        "local_db_bytes": _local_db_size(),
        "remote_db_bytes": None,
        "credentials_ok": False,
    }
    if not is_cos_db_backup_enabled():
        return status

    client = _load_cos_client(max_attempts=3)
    if client:
        status["credentials_ok"] = True
        status["remote_db_bytes"] = _cos_object_size(client)
    return status
