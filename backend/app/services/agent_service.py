"""Agent orchestration — find / explain / recommend / rewrite SQL."""

import logging
import re

from sqlalchemy.orm import Session

from app.config import AGENT_CANDIDATE_TOP_K, AGENT_RESULT_TOP_N
from app.services.llm_service import LlmError, LlmNotConfiguredError, chat_json, is_llm_configured
from app.services.prompt_service import (
    SYSTEM_PROMPT,
    build_explain_sql_prompt,
    build_find_sql_prompt,
    build_recommend_sql_prompt,
    build_rewrite_sql_prompt,
)
from app.services.library_scope_service import (
    LibraryScope,
    candidates_to_summaries_scoped,
    enrich_find_results,
    get_similar_scoped,
    record_to_context,
    resolve_sql_record,
    semantic_search_scoped,
)
from app.services.cross_sql_rewrite_service import cross_sql_rewrite, extract_target_dimension
from app.services.generate_sql_service import generate_sql, is_generate_sql_request
from app.utils.text_utils import parse_json_list

logger = logging.getLogger(__name__)

AgentMode = str  # find_sql | explain_sql | recommend_similar_sql | rewrite_sql | cross_sql_rewrite | generate_sql | chat

FREE_CHAT_SYSTEM_PROMPT = """你是 Guazi SQL Data Agent，帮助数据分析同事使用个人 SQL 知识库。
规则：
1. 优先基于提供的 SQL 检索上下文回答；不要编造知识库中不存在的文件名或 sql_id。
2. 可解答业务分析问题、SQL 思路、口径讨论；信息不足时请明确说明。
3. 若用户要写全新 SQL，可建议使用「帮我写一条…SQL」触发合成功能。
4. 用简洁专业的中文回答。"""

# Cross-SQL rewrite: add dimension by borrowing from other SQLs in library
_CROSS_SQL_REWRITE_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"跨\s*sql", re.I),
    re.compile(r"从(其他|别的|库中|知识库).*(sql|SQL)"),
    re.compile(r"(借鉴|参考|引用).*(其他|别的|sql|SQL)"),
    re.compile(r"加.{0,8}维度"),
    re.compile(r"增加.{0,12}(维度|字段)"),
    re.compile(r"加上.{0,12}(维度|字段|城市|省份|区域|渠道|门店|车源|品牌|车系)"),
    re.compile(r"新增.{0,12}(维度|字段)"),
    re.compile(r"补充.{0,12}(维度|字段)"),
    re.compile(r"引入.{0,12}(维度|字段)"),
]

# Rule patterns for mode detection (order matters — more specific first)
MODE_PATTERNS: list[tuple[AgentMode, list[str]]] = [
    (
        "rewrite_sql",
        ["改成", "改写", "改为", "只看", "最近30天", "最近7天", "最近", "北京", "上海", "按日期", "新能源", "燃油"],
    ),
    (
        "recommend_similar_sql",
        ["相似 sql", "类似 sql", "相似sql", "类似sql", "推荐相似", "推荐类似", "相似", "类似"],
    ),
    (
        "explain_sql",
        ["解释", "干嘛", "干什么", "是什么", "用来分析", "适合分析", "用途", "什么意思"],
    ),
    (
        "find_sql",
        ["哪些 sql", "哪些sql", "相关 sql", "相关sql", "有没有", "搜索"],
    ),
]

_FIND_SQL_START_RE = re.compile(
    r"^(找|查|搜索|查询|帮我找|帮我查|帮我搜|列出|列举)",
    re.I,
)


def is_cross_sql_rewrite_request(message: str, current_sql_id: int | None) -> bool:
    """Public helper for cross-SQL rewrite intent detection."""
    return _is_cross_sql_rewrite_request(message, current_sql_id)


def _is_cross_sql_rewrite_request(message: str, current_sql_id: int | None) -> bool:
    """Detect intent to add a dimension by borrowing from other SQLs."""
    if not current_sql_id:
        return False
    text = message.strip()
    if not text:
        return False
    for pattern in _CROSS_SQL_REWRITE_PATTERNS:
        if pattern.search(text):
            return True
    if extract_target_dimension(text):
        add_verbs = ("加", "增加", "加上", "新增", "补充", "引入", "加入", "按")
        if any(v in text for v in add_verbs):
            return True
    return False


def detect_mode(message: str, current_sql_id: int | None) -> AgentMode:
    """Lightweight rule-based mode detection."""
    if _is_cross_sql_rewrite_request(message, current_sql_id):
        return "cross_sql_rewrite"

    if is_generate_sql_request(message):
        return "generate_sql"

    text = message.strip()
    msg = text.lower()

    for mode, keywords in MODE_PATTERNS:
        for kw in keywords:
            if kw.lower() in msg:
                if mode in (
                    "rewrite_sql",
                    "cross_sql_rewrite",
                    "explain_sql",
                    "recommend_similar_sql",
                ):
                    return mode
                return mode

    if _FIND_SQL_START_RE.search(text):
        return "find_sql"
    if "相关" in text and ("sql" in msg or "SQL" in text):
        return "find_sql"

    return "chat"


def _needs_sql_context(mode: AgentMode) -> bool:
    return mode in ("explain_sql", "recommend_similar_sql", "rewrite_sql", "cross_sql_rewrite")


def _enrich_results(
    db: Session, results: list[dict], scope: LibraryScope = "personal"
) -> list[dict]:
    return enrich_find_results(db, results, scope)


def _fallback_find_sql(
    question: str,
    candidates: list,
    *,
    scope: LibraryScope = "personal",
    llm_error: str | None = None,
) -> dict:
    summaries = candidates_to_summaries_scoped(candidates[:AGENT_RESULT_TOP_N], scope)
    results = [
        {
            "sql_id": s["id"],
            "file_name": s["file_name"],
            "reason": f"检索命中：业务「{s['business'][:30]}」，场景与「{question[:20]}」相关",
            "business": s["business"],
            "scene": s["scene"],
            "scope": scope,
        }
        for s in summaries
    ]
    if llm_error:
        summary = (
            f"基于本地检索找到 {len(results)} 条相关 SQL（LLM 调用失败：{llm_error[:120]}）。"
        )
    elif not is_llm_configured():
        summary = (
            f"基于本地检索找到 {len(results)} 条相关 SQL（未配置 LLM API Key，请在 .env 设置 LLM_API_KEY）。"
        )
    else:
        summary = f"基于本地检索找到 {len(results)} 条相关 SQL。"
    return {
        "mode": "find_sql",
        "summary": summary,
        "results": results,
        "llm_used": False,
        "semantic_used": True,
        "llm_error": llm_error,
    }


def _fallback_explain_sql(record, scope: LibraryScope = "personal") -> dict:
    ctx = record_to_context(record, scope)
    return {
        "mode": "explain_sql",
        "sql_id": record.id,
        "title": record.file_name,
        "summary": record.description or f"该 SQL 用于 {record.business or '数据分析'}",
        "business_meaning": record.scene or record.business or "暂无详细业务说明",
        "main_metrics": ctx["metrics"][:10],
        "main_dimensions": ctx["dimensions"][:10],
        "core_tables": ctx["core_tables"],
        "logic_points": ["请配置 LLM API Key 以获取更详细的逻辑解析"],
        "filter_conditions": [],
        "output_shape": "输出字段见指标列表",
        "applicable_questions": [
            f"与「{record.business}」相关的分析问题" if record.business else "相关业务分析问题"
        ],
        "llm_used": False,
    }


def _fallback_recommend(source, candidates: list, scope: LibraryScope = "personal") -> dict:
    results = []
    source_tags = set(parse_json_list(source.tags_json))
    source_tables = set(parse_json_list(source.core_tables_json))

    for record, score in candidates[:AGENT_RESULT_TOP_N]:
        reasons = []
        if record.business == source.business:
            reasons.append("同一业务")
        rec_tags = set(parse_json_list(record.tags_json))
        overlap_tags = source_tags & rec_tags
        if overlap_tags:
            reasons.append(f"标签重合：{', '.join(list(overlap_tags)[:3])}")
        rec_tables = set(parse_json_list(record.core_tables_json))
        overlap_tables = source_tables & rec_tables
        if overlap_tables:
            reasons.append(f"共用核心表：{', '.join(list(overlap_tables)[:2])}")

        results.append(
            {
                "sql_id": record.id,
                "file_name": record.file_name,
                "reason": "；".join(reasons) if reasons else f"元数据相似度 {score:.0f}",
                "business": record.business,
                "scene": record.scene,
                "scope": scope,
            }
        )

    return {
        "mode": "recommend_similar_sql",
        "source_sql_id": source.id,
        "summary": f"基于规则召回找到 {len(results)} 条相似 SQL（未调用 LLM）。",
        "results": results,
        "llm_used": False,
    }


def _clean_find_query(question: str) -> str:
    """Strip command words and trailing noise from find-sql questions."""
    q = question.strip()
    q = re.sub(r"^(找|查|搜索|有没有|哪些|帮我找|帮我查)\s*", "", q)
    q = re.sub(r"(相关\s*)?(sql|SQL)\s*$", "", q)
    q = re.sub(r"的\s*$", "", q)
    return q.strip() or question.strip()


def find_sql(
    db: Session,
    question: str,
    user_email: str | None = None,
    library_scope: LibraryScope = "personal",
) -> dict:
    """Natural language SQL search: semantic retrieval + LLM rerank."""
    query = _clean_find_query(question)

    candidates = semantic_search_scoped(
        db, query, user_email or "", scope=library_scope, top_k=AGENT_CANDIDATE_TOP_K
    )
    if not candidates and query != question.strip():
        candidates = semantic_search_scoped(
            db,
            question.strip(),
            user_email or "",
            scope=library_scope,
            top_k=AGENT_CANDIDATE_TOP_K,
        )
    if not candidates:
        return {
            "mode": "find_sql",
            "summary": "未找到匹配的 SQL，请尝试其他关键词。",
            "results": [],
            "llm_used": False,
        }

    llm_error: str | None = None
    if is_llm_configured():
        try:
            summaries = candidates_to_summaries_scoped(candidates, library_scope)
            prompt = build_find_sql_prompt(question, summaries)
            result = chat_json(prompt, system=SYSTEM_PROMPT)
            result["results"] = _enrich_results(
                db, result.get("results", []), library_scope
            )
            result["llm_used"] = True
            return result
        except LlmError as exc:
            llm_error = str(exc)
            logger.warning("LLM find_sql failed, using fallback: %s", exc)

    return _fallback_find_sql(question, candidates, scope=library_scope, llm_error=llm_error)


def explain_sql(
    db: Session,
    sql_id: int,
    user_email: str | None = None,
    library_scope: LibraryScope = "personal",
) -> dict:
    record = resolve_sql_record(db, sql_id, user_email or "", library_scope)
    if not record:
        raise ValueError(f"SQL id={sql_id} 不存在")

    if is_llm_configured():
        try:
            ctx = record_to_context(record, library_scope)
            prompt = build_explain_sql_prompt(ctx)
            result = chat_json(prompt, system=SYSTEM_PROMPT)
            result["llm_used"] = True
            result["scope"] = library_scope
            return result
        except LlmError as exc:
            logger.warning("LLM explain_sql failed, using fallback: %s", exc)

    data = _fallback_explain_sql(record, library_scope)
    data["scope"] = library_scope
    return data


def recommend_similar_sql(
    db: Session,
    sql_id: int,
    user_email: str | None = None,
    library_scope: LibraryScope = "personal",
) -> dict:
    record = resolve_sql_record(db, sql_id, user_email or "", library_scope)
    if not record:
        raise ValueError(f"SQL id={sql_id} 不存在")

    candidates = get_similar_scoped(
        db, sql_id, user_email or "", scope=library_scope, top_k=AGENT_CANDIDATE_TOP_K
    )
    if not candidates:
        return {
            "mode": "recommend_similar_sql",
            "source_sql_id": sql_id,
            "summary": "未找到相似的 SQL。",
            "results": [],
            "llm_used": False,
        }

    if is_llm_configured():
        try:
            source_ctx = record_to_context(record, library_scope)
            cand_summaries = candidates_to_summaries_scoped(candidates, library_scope)
            prompt = build_recommend_sql_prompt(source_ctx, cand_summaries)
            result = chat_json(prompt, system=SYSTEM_PROMPT)
            result["results"] = _enrich_results(
                db, result.get("results", []), library_scope
            )
            result["scope"] = library_scope
            result["llm_used"] = True
            return result
        except LlmError as exc:
            logger.warning("LLM recommend failed, using fallback: %s", exc)

    data = _fallback_recommend(record, candidates, library_scope)
    data["scope"] = library_scope
    return data


def _build_free_chat_context(
    db: Session,
    user_email: str,
    message: str,
    sql_id: int | None,
    library_scope: LibraryScope = "personal",
) -> str:
    import json

    parts: list[str] = []
    if sql_id:
        record = resolve_sql_record(db, sql_id, user_email, library_scope)
        if record:
            ctx = record_to_context(record, library_scope)
            sql_text = ctx.get("sql_content") or ""
            parts.append(
                f"当前选中 SQL: id={record.id}, 文件={record.file_name}, 来源={library_scope}\n"
                f"业务={record.business}, 场景={record.scene}\n"
                f"指标={ctx['metrics']}, 维度={ctx['dimensions']}\n"
                f"SQL片段:\n{sql_text[:2000]}"
            )

    candidates = semantic_search_scoped(
        db, message, user_email, scope=library_scope, top_k=8
    )
    if candidates:
        summaries = candidates_to_summaries_scoped(candidates, library_scope)
        parts.append(
            "语义检索候选 SQL:\n" + json.dumps(summaries, ensure_ascii=False, indent=2)
        )
    return "\n\n".join(parts)


def free_chat(
    db: Session,
    message: str,
    user_email: str | None = None,
    current_sql_id: int | None = None,
    library_scope: LibraryScope = "personal",
) -> dict:
    """Free-form multi-turn chat with optional SQL library context."""
    from app.services.llm_service import chat_messages

    if not is_llm_configured():
        raise LlmNotConfiguredError(
            "自由对话需要配置 LLM API Key。请在 backend/.env 中设置 LLM_API_KEY 后重试。"
        )

    context = _build_free_chat_context(
        db, user_email or "", message, current_sql_id, library_scope
    )
    user_content = f"上下文:\n{context}\n\n用户问题: {message}" if context else message
    text = chat_messages(
        [
            {"role": "system", "content": FREE_CHAT_SYSTEM_PROMPT},
            {"role": "user", "content": user_content},
        ]
    )
    return {"mode": "chat", "summary": text, "llm_used": True}


def rewrite_sql(
    db: Session,
    sql_id: int,
    instruction: str,
    user_email: str | None = None,
    library_scope: LibraryScope = "personal",
) -> dict:
    record = resolve_sql_record(db, sql_id, user_email or "", library_scope)
    if not record:
        raise ValueError(f"SQL id={sql_id} 不存在")

    if not is_llm_configured():
        raise LlmNotConfiguredError(
            "改写 SQL 需要配置 LLM API Key。请在 backend/.env 中设置 LLM_API_KEY 后重试。"
        )

    ctx = record_to_context(record, library_scope)
    prompt = build_rewrite_sql_prompt(ctx, instruction)
    result = chat_json(prompt, system=SYSTEM_PROMPT)
    result["llm_used"] = True
    result["is_draft"] = True
    result["scope"] = library_scope
    result["warning"] = "这是 AI 生成的 SQL 草稿，不会覆盖原始 SQL 文件，请执行前自行校验。"
    return result


def chat(
    db: Session,
    message: str,
    current_sql_id: int | None = None,
    mode_override: str | None = None,
    user_email: str | None = None,
    library_scope: LibraryScope = "personal",
) -> dict:
    """
    Unified Agent chat entry — detect mode and dispatch.
    Returns { success, mode, data, message? }.
    """
    message = message.strip()
    if not message:
        return {
            "success": False,
            "mode": None,
            "data": None,
            "message": "请输入您的问题或指令",
        }

    mode = mode_override or detect_mode(message, current_sql_id)

    if _needs_sql_context(mode) and not current_sql_id:
        hints = {
            "explain_sql": "解释 SQL",
            "recommend_similar_sql": "推荐相似 SQL",
            "rewrite_sql": "改写 SQL",
            "cross_sql_rewrite": "跨 SQL 改写",
        }
        return {
            "success": False,
            "mode": mode,
            "data": None,
            "message": f"请先在左侧选择一个 SQL，再进行「{hints.get(mode, '此操作')}」。",
        }

    try:
        if mode == "find_sql":
            data = find_sql(db, message, user_email=user_email, library_scope=library_scope)
        elif mode == "explain_sql":
            data = explain_sql(
                db, current_sql_id, user_email=user_email, library_scope=library_scope
            )  # type: ignore[arg-type]
        elif mode == "recommend_similar_sql":
            data = recommend_similar_sql(
                db, current_sql_id, user_email=user_email, library_scope=library_scope
            )  # type: ignore[arg-type]
        elif mode == "rewrite_sql":
            data = rewrite_sql(
                db,
                current_sql_id,
                message,
                user_email=user_email,
                library_scope=library_scope,
            )  # type: ignore[arg-type]
        elif mode == "cross_sql_rewrite":
            data = cross_sql_rewrite(
                db,
                current_sql_id,
                message,
                user_email=user_email,
                library_scope=library_scope,
            )  # type: ignore[arg-type]
        elif mode == "generate_sql":
            data = generate_sql(
                db, message, user_email=user_email, library_scope=library_scope
            )
        elif mode == "chat":
            data = free_chat(
                db,
                message,
                user_email=user_email,
                current_sql_id=current_sql_id,
                library_scope=library_scope,
            )
        else:
            data = free_chat(
                db,
                message,
                user_email=user_email,
                current_sql_id=current_sql_id,
                library_scope=library_scope,
            )
            mode = "chat"

        return {"success": True, "mode": mode, "data": data}

    except LlmNotConfiguredError as exc:
        return {"success": False, "mode": mode, "data": None, "message": str(exc)}
    except ValueError as exc:
        return {"success": False, "mode": mode, "data": None, "message": str(exc)}
    except LlmError as exc:
        return {"success": False, "mode": mode, "data": None, "message": str(exc)}
