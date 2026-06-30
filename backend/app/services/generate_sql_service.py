"""Generate new SQL drafts by synthesizing patterns from the user's SQL library."""

from __future__ import annotations

import logging
import re

from sqlalchemy.orm import Session

from app.config import AGENT_CANDIDATE_TOP_K, CROSS_SQL_CANDIDATE_TOP_N
from app.models.sql_file import SqlFile
from app.services.llm_service import LlmError, LlmNotConfiguredError, chat_json, is_llm_configured
from app.services.prompt_service import SYSTEM_PROMPT, build_generate_sql_prompt
from app.services.library_scope_service import (
    LibraryScope,
    record_to_context,
    semantic_search_scoped,
)
from app.services.retrieval_service import record_to_full_context
from app.utils.sql_join_extractor import extract_grain_hints, extract_join_fragments

logger = logging.getLogger(__name__)

_GENERATE_SQL_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"写(一|条|个|段)?\s*(新)?\s*(sql|SQL|代码|查询)", re.I),
    re.compile(r"生成\s*(一|条|个|段)?\s*(sql|SQL|代码|查询)", re.I),
    re.compile(r"创造\s*(一|条|个|段)?\s*(sql|SQL|代码|查询)", re.I),
    re.compile(r"合成\s*(一|条|个|段)?\s*(sql|SQL|代码|查询)", re.I),
    re.compile(r"帮我写", re.I),
    re.compile(r"编写\s*(一|条|个|段)?\s*(sql|SQL|代码|查询)?", re.I),
    re.compile(r"根据\s*(整个|全部|知识库|代码库|库)", re.I),
    re.compile(r"新写\s*(一|条|个|段)?\s*(sql|SQL|代码|查询)?", re.I),
    re.compile(r"从零\s*(写|生成|开始)", re.I),
]

_GENERATE_KEYWORDS = (
    "写一条",
    "写一个",
    "写一段",
    "生成sql",
    "生成 sql",
    "创造",
    "合成",
    "帮我写",
    "根据知识库",
    "根据代码库",
    "根据库",
    "根据整个",
)


def is_generate_sql_request(message: str) -> bool:
    """Detect intent to compose a new SQL from the library."""
    text = message.strip()
    if not text:
        return False
    if any(kw in text for kw in ("改写", "改成", "改为", "修改当前")):
        return False
    for pattern in _GENERATE_SQL_PATTERNS:
        if pattern.search(text):
            return True
    lower = text.lower()
    return any(kw in lower or kw in text for kw in _GENERATE_KEYWORDS)


def _prepare_reference_context(record, score: float, scope: LibraryScope = "personal") -> dict:
    ctx = record_to_context(record, scope)
    sql_content = ctx.get("sql_content") or ""
    joins = extract_join_fragments(sql_content)
    grain = extract_grain_hints(sql_content)
    return {
        **ctx,
        "retrieval_score": round(score, 3),
        "join_fragments": joins[:8],
        "grain_hints": grain,
        "sql_preview": sql_content[:2500],
    }


def generate_sql(
    db: Session,
    instruction: str,
    user_email: str | None = None,
    library_scope: LibraryScope = "personal",
) -> dict:
    """
    Retrieve related SQLs from library and synthesize a new SQL draft.
    Does not require a currently selected SQL file.
    """
    if not is_llm_configured():
        raise LlmNotConfiguredError(
            "生成 SQL 需要配置 LLM API Key。请在 backend/.env 中设置 LLM_API_KEY 后重试。"
        )

    instruction = instruction.strip()
    candidates = semantic_search_scoped(
        db, instruction, user_email or "", scope=library_scope, top_k=AGENT_CANDIDATE_TOP_K
    )[:CROSS_SQL_CANDIDATE_TOP_N]

    reference_contexts = [
        _prepare_reference_context(record, score, library_scope)
        for record, score in candidates
    ]

    if not reference_contexts:
        return {
            "mode": "generate_sql",
            "instruction": instruction,
            "summary": "知识库中未找到可参考的 SQL，无法合成新 SQL。请先上传相关 SQL 或换关键词。",
            "changes": [],
            "risk_notes": ["无候选 SQL，未生成有效草稿"],
            "rewritten_sql": "-- 未找到可参考 SQL\nSELECT 1",
            "reference_sqls": [],
            "is_draft": True,
            "warning": "未生成有效 SQL，请补充知识库后重试。",
            "llm_used": False,
            "semantic_used": True,
        }

    llm_error: str | None = None
    try:
        prompt = build_generate_sql_prompt(instruction, reference_contexts)
        result = chat_json(prompt, system=SYSTEM_PROMPT)
        result["mode"] = "generate_sql"
        result["instruction"] = instruction
        result["is_draft"] = True
        result["warning"] = (
            "这是 AI 基于知识库合成的 SQL 草稿，不会自动入库，请执行前自行校验表名、字段与口径。"
        )
        result["llm_used"] = True
        result["semantic_used"] = True
        if not result.get("rewritten_sql") and result.get("generated_sql"):
            result["rewritten_sql"] = result["generated_sql"]
        if not result.get("reference_sqls"):
            result["reference_sqls"] = [
                {
                    "sql_id": c["id"],
                    "file_name": c["file_name"],
                    "reason": f"语义检索分 {c.get('retrieval_score', 0)}",
                    "borrowed_joins": [
                        j.get("join_sql", "") for j in c.get("join_fragments", [])[:2]
                    ],
                }
                for c in reference_contexts
            ]
        return result
    except LlmError as exc:
        llm_error = str(exc)
        logger.warning("LLM generate_sql failed: %s", exc)

    top = reference_contexts[0]
    return {
        "mode": "generate_sql",
        "instruction": instruction,
        "summary": (
            f"LLM 调用失败，已检索到 {len(reference_contexts)} 条参考 SQL，"
            f"请手动参考 {top['file_name']} 编写。"
        ),
        "changes": [f"语义检索召回 {len(reference_contexts)} 条候选 SQL"],
        "risk_notes": [f"LLM 失败：{llm_error[:120] if llm_error else '未知错误'}"],
        "rewritten_sql": top.get("sql_preview") or "-- 请参考知识库手动编写",
        "reference_sqls": [
            {
                "sql_id": c["id"],
                "file_name": c["file_name"],
                "reason": f"检索分 {c.get('retrieval_score', 0)}",
            }
            for c in reference_contexts
        ],
        "is_draft": True,
        "warning": "LLM 未成功合成，以下为参考 SQL 片段。",
        "llm_used": False,
        "semantic_used": True,
    }
