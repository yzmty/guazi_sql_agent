"""Multi-turn conversation persistence."""

from __future__ import annotations

import json
from datetime import datetime

from sqlalchemy.orm import Session

from app.models.conversation import Conversation, ConversationMessage


def list_conversations(db: Session, user_email: str, limit: int = 30) -> list[Conversation]:
    return (
        db.query(Conversation)
        .filter(Conversation.user_email == user_email)
        .order_by(Conversation.updated_at.desc())
        .limit(limit)
        .all()
    )


def create_conversation(
    db: Session,
    user_email: str,
    title: str = "新对话",
    current_sql_id: int | None = None,
) -> Conversation:
    conv = Conversation(
        user_email=user_email,
        title=title,
        current_sql_id=current_sql_id,
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)
    return conv


def get_conversation(
    db: Session, conversation_id: int, user_email: str
) -> Conversation | None:
    return (
        db.query(Conversation)
        .filter(
            Conversation.id == conversation_id,
            Conversation.user_email == user_email,
        )
        .first()
    )


def delete_conversation(db: Session, conversation_id: int, user_email: str) -> bool:
    conv = get_conversation(db, conversation_id, user_email)
    if not conv:
        return False
    db.delete(conv)
    db.commit()
    return True


def add_message(
    db: Session,
    conversation_id: int,
    role: str,
    content: str,
    mode: str | None = None,
    data: dict | None = None,
) -> ConversationMessage:
    msg = ConversationMessage(
        conversation_id=conversation_id,
        role=role,
        content=content,
        mode=mode,
        data_json=json.dumps(data, ensure_ascii=False) if data else None,
    )
    db.add(msg)
    conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
    if conv:
        conv.updated_at = datetime.utcnow()
        if role == "user" and conv.title == "新对话":
            conv.title = content[:40] + ("..." if len(content) > 40 else "")
    db.commit()
    db.refresh(msg)
    return msg


def get_messages(
    db: Session, conversation_id: int, limit: int = 50
) -> list[ConversationMessage]:
    return (
        db.query(ConversationMessage)
        .filter(ConversationMessage.conversation_id == conversation_id)
        .order_by(ConversationMessage.created_at.asc())
        .limit(limit)
        .all()
    )


def message_to_dict(msg: ConversationMessage) -> dict:
    data = None
    if msg.data_json:
        try:
            data = json.loads(msg.data_json)
        except json.JSONDecodeError:
            data = None
    return {
        "id": msg.id,
        "role": msg.role,
        "content": msg.content,
        "mode": msg.mode,
        "data": data,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
    }
