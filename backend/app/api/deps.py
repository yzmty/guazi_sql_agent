"""FastAPI auth dependencies."""

from fastapi import Depends, Header, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.auth_service import CurrentUser, get_user_from_token
from app.services.doris_service import DorisConnectionError


def get_current_user(
    authorization: str | None = Header(None, alias="Authorization"),
    view_as: str | None = Query(None, description="Super admin: view another user's SQL"),
    db: Session = Depends(get_db),
) -> CurrentUser:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="未登录")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        return get_user_from_token(db, token, view_as=view_as)
    except DorisConnectionError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
