"""Multi-turn SQL assistant (LangChain-style orchestration, OpenAI-compatible LLM)."""

from __future__ import annotations

import json
import logging
from typing import Any, Iterator

from sqlalchemy.orm import Session

from app.models.conversation import Conversation
from app.services import agent_service
from app.services.conversation_service import add_message, get_messages
from app.services.llm_service import LlmError, chat_messages, chat_messages_stream, is_llm_configured
from app.services.retrieval_service import candidates_to_summaries, record_to_full_context
from app.services.search_service import get_sql_file_by_id
from app.services.cross_sql_rewrite_service import cross_sql_rewrite
from app.services.generate_sql_service import generate_sql
from app.services.semantic_search_service import semantic_search_sql

logger = logging.getLogger(__name__)


def _sse_payload(payload: dict[str, Any]) -> str:
    return f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"

SYSTEM_PROMPT = """你是 Guazi SQL Data Agent，帮助数据分析同事在个人 SQL 知识库中找 SQL、解释逻辑、推荐相似 SQL、生成改写草稿。
规则：
1. 只基于提供的 SQL 上下文回答，不要编造不存在的表或文件。
2. 引用 SQL 时写出文件名和 sql_id。
3. 改写 SQL 时只输出草稿，提醒用户不会自动覆盖原文件。
4. 用简洁专业的中文回答。"""


def _history_for_llm(db: Session, conversation_id: int) -> list[dict[str, str]]:
    from app.config import AGENT_CONVERSATION_HISTORY_LIMIT

    rows = get_messages(db, conversation_id, limit=AGENT_CONVERSATION_HISTORY_LIMIT)
    messages: list[dict[str, str]] = [{"role": "system", "content": SYSTEM_PROMPT}]
    for row in rows:
        if row.role in ("user", "assistant"):
            messages.append({"role": row.role, "content": row.content})
    return messages


def _build_context(db: Session, user_email: str, message: str, sql_id: int | None) -> str:
    parts: list[str] = []
    if sql_id:
        record = get_sql_file_by_id(db, sql_id, user_email=user_email)
        if record:
            ctx = record_to_full_context(record)
            parts.append(
                f"当前选中 SQL: id={record.id}, 文件={record.file_name}\n"
                f"业务={record.business}, 场景={record.scene}\n"
                f"指标={ctx['metrics']}, 维度={ctx['dimensions']}\n"
                f"SQL片段:\n{(record.sql_content or '')[:2000]}"
            )

    candidates = semantic_search_sql(db, message, user_email, top_k=8)
    if candidates:
        summaries = candidates_to_summaries(candidates)
        parts.append("语义检索候选 SQL:\n" + json.dumps(summaries, ensure_ascii=False, indent=2))
    return "\n\n".join(parts)


def _run_structured(
    db: Session,
    user_email: str,
    intent: str,
    message: str,
    sql_id: int | None,
) -> tuple[str, dict]:
    if intent == "find_sql":
        data = agent_service.find_sql(db, message, user_email=user_email)
        data["semantic_used"] = True
        return "find_sql", data
    if intent == "explain_sql":
        if not sql_id:
            raise ValueError("请先在左侧选择一个 SQL")
        return "explain_sql", agent_service.explain_sql(db, sql_id, user_email=user_email)
    if intent == "recommend_similar_sql":
        if not sql_id:
            raise ValueError("请先在左侧选择一个 SQL")
        return "recommend_similar_sql", agent_service.recommend_similar_sql(
            db, sql_id, user_email=user_email
        )
    if intent == "rewrite_sql":
        if not sql_id:
            raise ValueError("请先在左侧选择一个 SQL")
        return "rewrite_sql", agent_service.rewrite_sql(
            db, sql_id, message, user_email=user_email
        )
    if intent == "cross_sql_rewrite":
        if not sql_id:
            raise ValueError("请先在左侧选择一个 SQL")
        return "cross_sql_rewrite", cross_sql_rewrite(
            db, sql_id, message, user_email=user_email
        )
    if intent == "generate_sql":
        return "generate_sql", generate_sql(db, message, user_email=user_email)
    raise ValueError(f"unknown intent {intent}")


def run_conversation_turn(
    db: Session,
    conversation: Conversation,
    message: str,
    current_sql_id: int | None = None,
) -> dict[str, Any]:
    user_email = conversation.user_email
    message = message.strip()
    if not message:
        return {"success": False, "message": "请输入内容"}

    sql_id = current_sql_id or conversation.current_sql_id
    if sql_id:
        conversation.current_sql_id = sql_id

    add_message(db, conversation.id, "user", message)
    intent = agent_service.detect_mode(message, sql_id)

    try:
        if intent in (
            "find_sql",
            "explain_sql",
            "recommend_similar_sql",
            "rewrite_sql",
            "cross_sql_rewrite",
            "generate_sql",
        ):
            mode, data = _run_structured(db, user_email, intent, message, sql_id)
        else:
            if not is_llm_configured():
                raise LlmError("未配置 LLM API Key")
            data = agent_service.free_chat(
                db, message, user_email=user_email, current_sql_id=sql_id
            )
            mode = "chat"
    except LlmError as exc:
        return {"success": False, "mode": intent, "message": str(exc)}
    except ValueError as exc:
        return {"success": False, "mode": intent, "message": str(exc)}
    except Exception as exc:
        logger.exception("Conversation turn failed")
        return {"success": False, "mode": intent, "message": str(exc)}

    summary = data.get("summary") or data.get("title") or "已完成"
    add_message(db, conversation.id, "assistant", summary, mode=mode, data=data)
    db.commit()
    return {"success": True, "mode": mode, "data": data}


def stream_conversation_turn(
    db: Session,
    conversation: Conversation,
    message: str,
    current_sql_id: int | None = None,
) -> Iterator[str]:
    user_email = conversation.user_email
    message = message.strip()
    if not message:
        yield f"data: {json.dumps({'success': False, 'message': '请输入内容'}, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"
        return

    sql_id = current_sql_id or conversation.current_sql_id
    intent = agent_service.detect_mode(message, sql_id)

    if intent != "chat" and intent in (
        "find_sql",
        "explain_sql",
        "recommend_similar_sql",
        "rewrite_sql",
        "cross_sql_rewrite",
        "generate_sql",
    ):
        result = run_conversation_turn(db, conversation, message, current_sql_id)
        yield _sse_payload({"event": "result", **result})
        yield "data: [DONE]\n\n"
        return

    add_message(db, conversation.id, "user", message)
    if sql_id:
        conversation.current_sql_id = sql_id
    db.commit()

    try:
        if not is_llm_configured():
            raise LlmError("未配置 LLM API Key")
        context = agent_service._build_free_chat_context(
            db, user_email, message, sql_id
        )
        msgs = _history_for_llm(db, conversation.id)
        msgs[0] = {"role": "system", "content": agent_service.FREE_CHAT_SYSTEM_PROMPT}
        user_content = (
            f"上下文:\n{context}\n\n用户问题: {message}" if context else message
        )
        if msgs and msgs[-1]["role"] == "user":
            msgs[-1]["content"] = user_content
        else:
            msgs.append({"role": "user", "content": user_content})
        parts: list[str] = []
        for token in chat_messages_stream(msgs):
            parts.append(token)
            yield _sse_payload({"event": "token", "text": token})
        text = "".join(parts)
        data = {"mode": "chat", "summary": text, "llm_used": True}
        add_message(db, conversation.id, "assistant", text, mode="chat", data=data)
        db.commit()
        yield _sse_payload(
            {"event": "done", "success": True, "mode": "chat", "data": data}
        )
    except Exception as exc:
        yield _sse_payload(
            {"event": "done", "success": False, "mode": "chat", "message": str(exc)}
        )
    yield "data: [DONE]\n\n"
