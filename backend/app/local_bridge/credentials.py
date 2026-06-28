"""Persist Doris credentials for the local execution bridge."""

from __future__ import annotations

import json
import os
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "guazi-sql-agent"
CREDS_FILE = CONFIG_DIR / "doris-credentials.json"


def load_credentials() -> tuple[str, str] | None:
    if not CREDS_FILE.is_file():
        return None
    try:
        data = json.loads(CREDS_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    user = str(data.get("user", "")).strip()
    password = data.get("password", "")
    if user and password:
        return user, password
    return None


def save_credentials(user: str, password: str) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CREDS_FILE.write_text(
        json.dumps({"user": user.strip(), "password": password}, ensure_ascii=False),
        encoding="utf-8",
    )
    try:
        os.chmod(CREDS_FILE, 0o600)
    except OSError:
        pass


def clear_credentials() -> None:
    if CREDS_FILE.is_file():
        CREDS_FILE.unlink()


def credentials_status() -> dict[str, object]:
    creds = load_credentials()
    if not creds:
        return {"configured": False, "user": None}
    return {"configured": True, "user": creds[0]}
