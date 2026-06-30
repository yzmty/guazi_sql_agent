"""Conversation + streaming agent API."""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database import get_db
from app.services.auth_service import CurrentUser
from app.services.conversation_service import (
    create_conversation,
    delete_conversation,
    get_conversation,
    get_messages,
    list_conversations,
    message_to_dict,
)
from app.services.indexing_service import get_index_stats
from app.services.langchain_agent_service import (
    run_conversation_turn,
    stream_conversation_turn,
)

router = APIRouter(prefix="/api/conversations", tags=["conversations"])


class ConversationCreateRequest(BaseModel):
    title: str = "新对话"
    current_sql_id: int | None = None


class ConversationChatRequest(BaseModel):
    message: str = Field(..., min_length=1)
    current_sql_id: int | None = None
    stream: bool = False
    library_scope: str = "personal"


@router.get("")
def list_user_conversations(
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = list_conversations(db, user.owner_email)
    return {
        "items": [
            {
                "id": c.id,
                "title": c.title,
                "current_sql_id": c.current_sql_id,
                "updated_at": c.updated_at.isoformat() if c.updated_at else None,
            }
            for c in rows
        ]
    }


@router.post("")
def create_user_conversation(
    body: ConversationCreateRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = create_conversation(
        db,
        user.owner_email,
        title=body.title,
        current_sql_id=body.current_sql_id,
    )
    return {
        "id": conv.id,
        "title": conv.title,
        "current_sql_id": conv.current_sql_id,
    }


@router.get("/index-stats")
def index_stats(
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return get_index_stats(db, user.owner_email)


@router.get("/{conversation_id}")
def get_user_conversation(
    conversation_id: int,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = get_conversation(db, conversation_id, user.owner_email)
    if not conv:
        raise HTTPException(status_code=404, detail="会话不存在")
    messages = get_messages(db, conversation_id)
    return {
        "id": conv.id,
        "title": conv.title,
        "current_sql_id": conv.current_sql_id,
        "messages": [message_to_dict(m) for m in messages],
    }


@router.delete("/{conversation_id}")
def remove_conversation(
    conversation_id: int,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not delete_conversation(db, conversation_id, user.owner_email):
        raise HTTPException(status_code=404, detail="会话不存在")
    return {"success": True}


@router.post("/{conversation_id}/chat")
def conversation_chat(
    conversation_id: int,
    body: ConversationChatRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = get_conversation(db, conversation_id, user.owner_email)
    if not conv:
        raise HTTPException(status_code=404, detail="会话不存在")

    if body.stream:
        return StreamingResponse(
            stream_conversation_turn(
                db, conv, body.message, body.current_sql_id, body.library_scope
            ),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    result = run_conversation_turn(
        db, conv, body.message, body.current_sql_id, body.library_scope
    )
    return result
