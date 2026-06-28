"""Short-lived HMAC proof that local bridge validated Doris credentials."""

from __future__ import annotations

import base64
import hashlib
import hmac
import time

PROOF_TTL_SECONDS = 120


def create_login_proof(email: str, secret: str) -> str:
    email = email.strip().lower()
    ts = int(time.time())
    payload = f"{email}:{ts}"
    sig = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    token = f"{payload}:{sig}"
    return base64.urlsafe_b64encode(token.encode()).decode()


def verify_login_proof(email: str, proof: str, secret: str) -> bool:
    email = email.strip().lower()
    try:
        raw = base64.urlsafe_b64decode(proof.encode()).decode()
        payload, sig = raw.rsplit(":", 1)
        proof_email, ts_str = payload.split(":", 1)
        if proof_email != email:
            return False
        ts = int(ts_str)
        if time.time() - ts > PROOF_TTL_SECONDS:
            return False
        expected = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
        return hmac.compare_digest(sig, expected)
    except Exception:
        return False
