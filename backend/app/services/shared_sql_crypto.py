"""Encrypt/decrypt helpers for shared SQL files (no service imports)."""

from copy import copy

from app.models.shared_sql_file import SharedSqlFile
from app.services.crypto_service import decrypt_text, encrypt_text


def encrypt_parsed_fields(parsed: dict) -> tuple[str, str]:
    sql = parsed.get("sql_content") or ""
    comment = parsed.get("comment_block") or ""
    return encrypt_text(sql), encrypt_text(comment)


def decrypt_shared_record(record: SharedSqlFile) -> SharedSqlFile:
    """Return a shallow copy with decrypted fields for read/index (in-memory only)."""
    if record.storage_mode != "encrypted":
        return record
    r = copy(record)
    try:
        if r.sql_content:
            r.sql_content = decrypt_text(r.sql_content)
        if r.comment_block:
            r.comment_block = decrypt_text(r.comment_block)
    except Exception:
        pass
    return r
