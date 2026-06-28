"""Authentication and session management."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from jose import JWTError, jwt
from sqlalchemy.orm import Session

from cryptography.fernet import InvalidToken

from app.config import JWT_SECRET, LOCAL_BRIDGE_LOGIN_SECRET, SESSION_TTL_HOURS, SUPER_ADMIN_EMAIL, SUPER_ADMIN_PASSWORD
from app.models.auth_session import AuthSession
from app.services.crypto_service import decrypt_text, encrypt_text
from app.services.doris_service import (
    CredentialCheckResult,
    DorisConnectionError,
    check_credentials,
    normalize_doris_username,
    normalize_login_email,
    resolve_doris_user,
)
from app.services.local_bridge_proof import verify_login_proof

ALGORITHM = "HS256"


@dataclass
class CurrentUser:
    email: str
    is_super_admin: bool
    session_id: str
    doris_user: str
    doris_password: str
    view_as_email: str | None = None

    @property
    def owner_email(self) -> str:
        """Email whose SQL records should be accessed."""
        if self.is_super_admin and self.view_as_email:
            return self.view_as_email.lower()
        return self.email


def _is_super_admin(email: str, password: str) -> bool:
    return email.lower() == SUPER_ADMIN_EMAIL.lower() and password == SUPER_ADMIN_PASSWORD


def _resolve_login_credentials(
    email: str,
    password: str,
    is_super_admin: bool,
    local_bridge_proof: str | None = None,
) -> tuple[str, str]:
    if is_super_admin:
        try:
            return resolve_doris_user(email, password, True)
        except DorisConnectionError:
            return email, password

    if local_bridge_proof and verify_login_proof(
        email, local_bridge_proof, LOCAL_BRIDGE_LOGIN_SECRET
    ):
        return email, password

    result = check_credentials(email, password)
    if result == CredentialCheckResult.OK:
        return email, password
    if result == CredentialCheckResult.AUTH_FAILED:
        raise DorisConnectionError("账号或密码错误，无法连接 Doris 数据库")

    raise DorisConnectionError(
        "云端无法连接 Doris 验证账号。请先连接公司 VPN，运行 启动Doris助手.bat，"
        "并在浏览器中允许此网站访问本地网络后重试。"
    )


def login(
    db: Session,
    email: str,
    password: str,
    local_bridge_proof: str | None = None,
) -> tuple[str, CurrentUser]:
    email = normalize_login_email(email)
    has_proof = bool(
        local_bridge_proof
        and verify_login_proof(email, local_bridge_proof, LOCAL_BRIDGE_LOGIN_SECRET)
    )
    if not email:
        raise DorisConnectionError("请输入账号和密码")
    if not password and not has_proof:
        raise DorisConnectionError("请输入账号和密码")

    is_admin = bool(password) and _is_super_admin(email, password)
    doris_username = normalize_doris_username(email)
    if has_proof and not is_admin:
        doris_user, doris_password = doris_username, password or ""
    else:
        doris_user, doris_password = _resolve_login_credentials(
            email, password, is_admin, local_bridge_proof
        )
        doris_user = normalize_doris_username(doris_user)

    session_id = str(uuid.uuid4())
    expires_at = datetime.utcnow() + timedelta(hours=SESSION_TTL_HOURS)

    db.query(AuthSession).filter(AuthSession.email == email).delete()
    db.add(
        AuthSession(
            id=session_id,
            email=email,
            doris_user=doris_user,
            password_encrypted=encrypt_text(doris_password),
            is_super_admin=is_admin,
            expires_at=expires_at,
        )
    )
    db.commit()

    token = jwt.encode(
        {"sid": session_id, "email": email, "adm": is_admin},
        JWT_SECRET,
        algorithm=ALGORITHM,
    )
    user = CurrentUser(
        email=email,
        is_super_admin=is_admin,
        session_id=session_id,
        doris_user=doris_user,
        doris_password=doris_password,
    )
    return token, user


def logout(db: Session, session_id: str) -> None:
    db.query(AuthSession).filter(AuthSession.id == session_id).delete()
    db.commit()


def get_user_from_token(db: Session, token: str, view_as: str | None = None) -> CurrentUser:
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
        session_id = payload.get("sid")
        if not session_id:
            raise JWTError("missing sid")
    except JWTError as exc:
        raise DorisConnectionError("登录已过期，请重新登录") from exc

    session = db.query(AuthSession).filter(AuthSession.id == session_id).first()
    if not session or session.expires_at < datetime.utcnow():
        raise DorisConnectionError("登录已过期，请重新登录")

    try:
        password = decrypt_text(session.password_encrypted)
    except InvalidToken as exc:
        raise DorisConnectionError("登录已过期，请重新登录") from exc
    view_as_email = None
    if view_as and session.is_super_admin:
        view_as_email = view_as.strip().lower()

    return CurrentUser(
        email=session.email,
        is_super_admin=session.is_super_admin,
        session_id=session.id,
        doris_user=session.doris_user,
        doris_password=password,
        view_as_email=view_as_email,
    )


def list_known_users(db: Session) -> list[str]:
    from app.models.sql_file import SqlFile

    rows = db.query(SqlFile.user_email).distinct().all()
    emails = sorted({r[0] for r in rows if r[0]})
    return emails
