"""In-memory indexing performance diagnostics (for /api/health)."""

from __future__ import annotations

import time
from typing import Any

_last_job: dict[str, Any] | None = None
_startup_embed_ms: float | None = None
_startup_embed_error: str | None = None


def record_job_timing(
    *,
    job_id: int,
    sql_file_id: int | None,
    phases_ms: dict[str, float],
    total_ms: float,
    status: str,
) -> None:
    global _last_job
    _last_job = {
        "job_id": job_id,
        "sql_file_id": sql_file_id,
        "phases_ms": phases_ms,
        "total_ms": round(total_ms, 1),
        "status": status,
        "at": time.time(),
    }


def run_startup_embed_probe() -> None:
    """Measure cold/warm embed once at process start."""
    global _startup_embed_ms, _startup_embed_error
    try:
        from app.services.embedding_service import embed_texts

        t0 = time.perf_counter()
        embed_texts(["索引探针: 文件名 test.sql 业务 二手车"])
        _startup_embed_ms = round((time.perf_counter() - t0) * 1000, 1)
        _startup_embed_error = None
    except Exception as exc:
        _startup_embed_ms = None
        _startup_embed_error = str(exc)[:200]


def get_diagnostics() -> dict[str, Any]:
    out: dict[str, Any] = {
        "startup_embed_ms": _startup_embed_ms,
        "startup_embed_error": _startup_embed_error,
        "last_job": _last_job,
    }
    try:
        import fastembed  # noqa: F401

        out["fastembed_installed"] = True
    except ImportError:
        out["fastembed_installed"] = False
    return out
