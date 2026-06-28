"""Encrypt/decrypt sensitive session data."""

import base64
import hashlib

from cryptography.fernet import Fernet

from app.config import JWT_SECRET


def _fernet() -> Fernet:
    digest = hashlib.sha256(JWT_SECRET.encode()).digest()
    key = base64.urlsafe_b64encode(digest)
    return Fernet(key)


def encrypt_text(plain: str) -> str:
    return _fernet().encrypt(plain.encode()).decode()


def decrypt_text(token: str) -> str:
    return _fernet().decrypt(token.encode()).decode()
