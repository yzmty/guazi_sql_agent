"""Agent REST API routes."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database import get_db
from app.schemas.agent import (
    AgentChatRequest,
    AgentChatResponse,
    AgentCrossSqlRewriteRequest,
    AgentExplainRequest,
    AgentGenerateSqlRequest,
    AgentRecommendRequest,
    AgentRewriteRequest,
)
from app.services import agent_service
from app.services.auth_service import CurrentUser
from app.services.cross_sql_rewrite_service import cross_sql_rewrite
from app.services.generate_sql_service import generate_sql

router = APIRouter(prefix="/api/agent", tags=["agent"])


@router.post("/chat", response_model=AgentChatResponse)
def agent_chat(
    body: AgentChatRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AgentChatResponse:
    result = agent_service.chat(
        db,
        message=body.message,
        current_sql_id=body.current_sql_id,
        mode_override=body.mode,
        user_email=user.owner_email,
    )
    return AgentChatResponse(**result)


@router.post("/explain", response_model=AgentChatResponse)
def agent_explain(
    body: AgentExplainRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AgentChatResponse:
    try:
        data = agent_service.explain_sql(db, body.sql_id, user_email=user.owner_email)
        return AgentChatResponse(success=True, mode="explain_sql", data=data)
    except ValueError as exc:
        return AgentChatResponse(
            success=False, mode="explain_sql", data=None, message=str(exc)
        )


@router.post("/recommend-similar", response_model=AgentChatResponse)
def agent_recommend(
    body: AgentRecommendRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AgentChatResponse:
    try:
        data = agent_service.recommend_similar_sql(
            db, body.sql_id, user_email=user.owner_email
        )
        return AgentChatResponse(
            success=True, mode="recommend_similar_sql", data=data
        )
    except ValueError as exc:
        return AgentChatResponse(
            success=False, mode="recommend_similar_sql", data=None, message=str(exc)
        )


@router.post("/rewrite", response_model=AgentChatResponse)
def agent_rewrite(
    body: AgentRewriteRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AgentChatResponse:
    try:
        if body.cross_sql or agent_service.is_cross_sql_rewrite_request(
            body.instruction, body.sql_id
        ):
            data = cross_sql_rewrite(
                db, body.sql_id, body.instruction, user_email=user.owner_email
            )
            return AgentChatResponse(success=True, mode="cross_sql_rewrite", data=data)
        data = agent_service.rewrite_sql(
            db, body.sql_id, body.instruction, user_email=user.owner_email
        )
        return AgentChatResponse(success=True, mode="rewrite_sql", data=data)
    except Exception as exc:
        mode = (
            "cross_sql_rewrite"
            if body.cross_sql or agent_service.is_cross_sql_rewrite_request(
                body.instruction, body.sql_id
            )
            else "rewrite_sql"
        )
        return AgentChatResponse(
            success=False, mode=mode, data=None, message=str(exc)
        )


@router.post("/cross-sql-rewrite", response_model=AgentChatResponse)
def agent_cross_sql_rewrite(
    body: AgentCrossSqlRewriteRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AgentChatResponse:
    try:
        data = cross_sql_rewrite(
            db, body.sql_id, body.instruction, user_email=user.owner_email
        )
        return AgentChatResponse(success=True, mode="cross_sql_rewrite", data=data)
    except Exception as exc:
        return AgentChatResponse(
            success=False, mode="cross_sql_rewrite", data=None, message=str(exc)
        )


@router.post("/generate-sql", response_model=AgentChatResponse)
def agent_generate_sql(
    body: AgentGenerateSqlRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AgentChatResponse:
    try:
        data = generate_sql(db, body.instruction, user_email=user.owner_email)
        return AgentChatResponse(success=True, mode="generate_sql", data=data)
    except Exception as exc:
        return AgentChatResponse(
            success=False, mode="generate_sql", data=None, message=str(exc)
        )
