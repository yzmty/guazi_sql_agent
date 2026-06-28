"""Authentication API."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database import SessionLocal, get_db
from app.services.auth_service import CurrentUser, list_known_users, login, logout
from app.services.doris_service import DorisConnectionError
from app.services.indexing_service import reconcile_user_index

router = APIRouter(prefix="/api/auth", tags=["auth"])


class LoginRequest(BaseModel):
    email: str
    password: str
    local_bridge_proof: str | None = None


class LoginResponse(BaseModel):
    token: str
    email: str
    is_super_admin: bool


class UserInfoResponse(BaseModel):
    email: str
    is_super_admin: bool
    view_as_email: str | None = None
    owner_email: str


class UsersListResponse(BaseModel):
    users: list[str]


@router.post("/login", response_model=LoginResponse)
def auth_login(body: LoginRequest, db: Session = Depends(get_db)) -> LoginResponse:
    from app.services.cos_db_service import ensure_sqlite_from_cos

    try:
        if ensure_sqlite_from_cos():
            db.close()
            db = SessionLocal()
        token, user = login(db, body.email, body.password, body.local_bridge_proof)
        reconcile_user_index(db, user.email)
        return LoginResponse(
            token=token,
            email=user.email,
            is_super_admin=user.is_super_admin,
        )
    except DorisConnectionError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc


@router.post("/logout")
def auth_logout(
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    logout(db, user.session_id)
    return {"success": True}


@router.get("/me", response_model=UserInfoResponse)
def auth_me(user: CurrentUser = Depends(get_current_user)) -> UserInfoResponse:
    return UserInfoResponse(
        email=user.email,
        is_super_admin=user.is_super_admin,
        view_as_email=user.view_as_email,
        owner_email=user.owner_email,
    )


@router.get("/users", response_model=UsersListResponse)
def auth_users(
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> UsersListResponse:
    if not user.is_super_admin:
        raise HTTPException(status_code=403, detail="需要超级管理员权限")
    return UsersListResponse(users=list_known_users(db))
