"""Cross-SQL rewrite: retrieve dimension usage from library and merge into current SQL."""

from __future__ import annotations

import logging
import re

from sqlalchemy.orm import Session

from app.config import AGENT_CANDIDATE_TOP_K, CROSS_SQL_CANDIDATE_TOP_N
from app.models.sql_file import SqlFile
from app.services.dimension_stats_service import (
    dimension_matches,
    get_dimension_field_hints,
    get_dimension_table_cooccurrence,
)
from app.services.llm_service import LlmError, LlmNotConfiguredError, chat_json, is_llm_configured
from app.services.prompt_service import SYSTEM_PROMPT, build_cross_sql_rewrite_prompt
from app.services.library_scope_service import (
    LibraryScope,
    record_to_context,
    resolve_sql_record,
    semantic_search_scoped,
)
from app.services.retrieval_service import record_to_full_context
from app.services.search_service import get_sql_file_by_id
from app.utils.sql_join_extractor import extract_grain_hints, extract_join_fragments
from app.utils.text_utils import parse_json_list

logger = logging.getLogger(__name__)

_DIMENSION_EXTRACT_PATTERNS = [
    re.compile(r"加(?:上|入)?(?:一个|)?[「\"']?([^「」\"'\s，,、]+)[」\"']?(?:维度|字段)"),
    re.compile(r"增加[「\"']?([^「」\"'\s，,、]+)[」\"']?(?:维度|字段)"),
    re.compile(r"加上[「\"']?([^「」\"'\s，,、]+)[」\"']?(?:维度|字段)"),
    re.compile(r"新增[「\"']?([^「」\"'\s，,、]+)[」\"']?(?:维度|字段)"),
    re.compile(r"补充[「\"']?([^「」\"'\s，,、]+)[」\"']?(?:维度|字段)"),
    re.compile(r"(?:按|加入|引入)[「\"']?([^「」\"'\s，,、]+)[」\"']?(?:维度|分组)"),
    re.compile(r"维度[「\"']?([^「」\"'\s，,、]+)[」\"']"),
]

_COMMON_DIMENSIONS = (
    "城市",
    "省份",
    "区域",
    "渠道",
    "门店",
    "车源",
    "品牌",
    "车系",
    "日期",
    "月份",
    "周",
    "检车",
    "检测",
    "卖家",
    "买家",
    "顾问",
    "BD",
)


def extract_target_dimension(instruction: str) -> str | None:
    """Extract target dimension name from user instruction."""
    text = instruction.strip()
    if not text:
        return None

    for pattern in _DIMENSION_EXTRACT_PATTERNS:
        match = pattern.search(text)
        if match:
            dim = match.group(1).strip()
            if dim and len(dim) <= 20:
                return dim

    for dim in _COMMON_DIMENSIONS:
        if dim in text:
            return dim

    return None


def _build_search_query(dimension: str | None, instruction: str) -> str:
    if dimension:
        return f"{dimension} 维度 join 表 字段"
    return instruction


def _prepare_candidate_context(
    db: Session,
    record,
    score: float,
    dimension: str | None,
    library_scope: LibraryScope = "personal",
) -> dict:
    ctx = record_to_context(record, library_scope)
    sql_content = ctx.get("sql_content") or ""
    joins = extract_join_fragments(sql_content)
    grain = extract_grain_hints(sql_content)

    relevant_joins = joins
    if dimension:
        dim_lower = dimension.lower()
        filtered = [
            j
            for j in joins
            if dimension_matches(j.get("table", ""), dimension)
            or dimension_matches(j.get("on_condition", ""), dimension)
            or dimension_matches(j.get("join_sql", ""), dimension)
        ]
        if filtered:
            relevant_joins = filtered

    return {
        **ctx,
        "retrieval_score": round(score, 3),
        "dimensions": ctx.get("dimensions", []),
        "join_fragments": relevant_joins[:8],
        "all_join_count": len(joins),
        "grain_hints": grain,
        "sql_preview": sql_content[:2500],
    }


def _compare_grain(source_grain: dict, candidate_grain: dict) -> list[str]:
    notes: list[str] = []
    src_gb = set(source_grain.get("group_by_fields") or [])
    cand_gb = set(candidate_grain.get("group_by_fields") or [])

    if src_gb and cand_gb:
        overlap = src_gb & cand_gb
        if overlap:
            notes.append(f"GROUP BY 有重合字段：{', '.join(list(overlap)[:5])}")
        else:
            notes.append("GROUP BY 字段与候选 SQL 不一致，合并后需确认粒度")

    src_tables = set(source_grain.get("tables") or [])
    cand_tables = set(candidate_grain.get("tables") or [])
    shared = src_tables & cand_tables
    if shared:
        notes.append(f"共用表：{', '.join(list(shared)[:5])}，JOIN 路径可能可复用")
    elif src_tables and cand_tables:
        notes.append("当前 SQL 与候选 SQL 核心表无交集，JOIN 键需人工核对")

    return notes


def _fallback_cross_sql_rewrite(
    source: SqlFile,
    dimension: str | None,
    candidates: list[dict],
    cooccurrence: list[dict],
    instruction: str,
) -> dict:
    top_table = cooccurrence[0]["table"] if cooccurrence else "未知表"
    ref_names = ", ".join(
        f"{c['file_name']}(id={c['id']})" for c in candidates[:3]
    ) or "无"
    dim_label = dimension or "目标维度"
    summary = (
        f"未调用 LLM，已检索到 {len(candidates)} 条与「{dim_label}」相关的 SQL。"
        f"库内共现最高的表是 {top_table}。请参考借鉴 SQL 手动合并。"
    )
    return {
        "mode": "cross_sql_rewrite",
        "sql_id": source.id,
        "instruction": instruction,
        "target_dimension": dimension,
        "summary": summary,
        "changes": [
            f"语义检索召回 {len(candidates)} 条候选 SQL",
            f"维度「{dim_label}」库内共现表：{top_table}",
        ],
        "risk_notes": [
            "LLM 未配置或调用失败，以下为占位草稿，请务必人工校验",
            "跨 SQL 合并需确认 JOIN 键与 GROUP BY 粒度一致",
        ],
        "rewritten_sql": source.sql_content or "",
        "reference_sqls": [
            {
                "sql_id": c["id"],
                "file_name": c["file_name"],
                "reason": f"检索分 {c.get('retrieval_score', 0)}",
                "join_fragments": c.get("join_fragments", [])[:3],
                "grain_comparison": c.get("grain_comparison", []),
            }
            for c in candidates[:CROSS_SQL_CANDIDATE_TOP_N]
        ],
        "dimension_cooccurrence": cooccurrence,
        "dimension_field_hints": [],
        "is_draft": True,
        "warning": "这是 AI 生成的 SQL 草稿，不会覆盖原始 SQL 文件，请执行前自行校验。",
        "llm_used": False,
        "semantic_used": True,
    }


def cross_sql_rewrite(
    db: Session,
    sql_id: int,
    instruction: str,
    user_email: str | None = None,
    library_scope: LibraryScope = "personal",
) -> dict:
    """
    Cross-SQL rewrite pipeline:
    1. Semantic search for dimension-related SQLs
    2. sqlglot/sqlparse JOIN extraction + co-occurrence stats
    3. LLM merge with attribution and risk notes
    """
    record = resolve_sql_record(db, sql_id, user_email or "", library_scope)
    if not record:
        raise ValueError(f"SQL id={sql_id} 不存在")

    dimension = extract_target_dimension(instruction)
    search_query = _build_search_query(dimension, instruction)

    raw_candidates = semantic_search_scoped(
        db, search_query, user_email or "", scope=library_scope, top_k=AGENT_CANDIDATE_TOP_K
    )
    filtered: list[tuple] = [
        (r, s) for r, s in raw_candidates if r.id != sql_id
    ][:CROSS_SQL_CANDIDATE_TOP_N]

    cooccurrence = (
        get_dimension_table_cooccurrence(db, dimension, user_email or "")
        if dimension
        else []
    )
    field_hints = (
        get_dimension_field_hints(db, dimension, user_email or "") if dimension else []
    )

    source_ctx = record_to_context(record, library_scope)
    source_grain = extract_grain_hints((source_ctx.get("sql_content") or ""))
    source_joins = extract_join_fragments((source_ctx.get("sql_content") or ""))

    candidate_contexts: list[dict] = []
    for cand_record, score in filtered:
        ctx = _prepare_candidate_context(db, cand_record, score, dimension, library_scope)
        ctx["grain_comparison"] = _compare_grain(source_grain, ctx.get("grain_hints") or {})
        candidate_contexts.append(ctx)

    if not candidate_contexts and dimension:
        keyword_hits = semantic_search_scoped(
            db, dimension, user_email or "", scope=library_scope, top_k=AGENT_CANDIDATE_TOP_K
        )
        for cand_record, score in keyword_hits:
            if cand_record.id == sql_id:
                continue
            ctx = _prepare_candidate_context(db, cand_record, score, dimension, library_scope)
            ctx["grain_comparison"] = _compare_grain(source_grain, ctx.get("grain_hints") or {})
            candidate_contexts.append(ctx)
            if len(candidate_contexts) >= CROSS_SQL_CANDIDATE_TOP_N:
                break

    if not is_llm_configured():
        raise LlmNotConfiguredError(
            "跨 SQL 改写需要配置 LLM API Key。请在 backend/.env 中设置 LLM_API_KEY 后重试。"
        )

    if not candidate_contexts:
        dim_label = dimension or "该维度"
        return {
            "mode": "cross_sql_rewrite",
            "sql_id": sql_id,
            "instruction": instruction,
            "target_dimension": dimension,
            "summary": f"未在知识库中找到与「{dim_label}」相关的 SQL，无法跨 SQL 借鉴 JOIN 路径。",
            "changes": [],
            "risk_notes": [
                "建议先用「找 SQL」搜索相关案例，或检查该维度是否已在其他 SQL 中使用",
            ],
            "rewritten_sql": source_ctx.get("sql_content") or "",
            "reference_sqls": [],
            "dimension_cooccurrence": cooccurrence,
            "dimension_field_hints": field_hints,
            "is_draft": True,
            "warning": "未生成有效改写，保留原 SQL。",
            "llm_used": False,
            "semantic_used": True,
        }

    source_dimensions = parse_json_list(record.dimensions_json)
    if dimension and any(dimension_matches(d, dimension) for d in source_dimensions):
        logger.info("Target dimension %s may already exist in source SQL metadata", dimension)

    llm_error: str | None = None
    try:
        prompt = build_cross_sql_rewrite_prompt(
            source_sql={
                **source_ctx,
                "join_fragments": source_joins[:8],
                "grain_hints": source_grain,
            },
            instruction=instruction,
            target_dimension=dimension,
            candidate_sqls=candidate_contexts,
            dimension_cooccurrence=cooccurrence,
            dimension_field_hints=field_hints,
        )
        result = chat_json(prompt, system=SYSTEM_PROMPT)
        result["mode"] = "cross_sql_rewrite"
        result["sql_id"] = sql_id
        result["instruction"] = instruction
        result["target_dimension"] = dimension
        result["is_draft"] = True
        result["warning"] = (
            "这是 AI 跨 SQL 借鉴生成的草稿，不会覆盖原始 SQL 文件，请执行前自行校验 JOIN 键与粒度。"
        )
        result["llm_used"] = True
        result["semantic_used"] = True
        result["dimension_cooccurrence"] = cooccurrence
        result["dimension_field_hints"] = field_hints

        if not result.get("reference_sqls"):
            result["reference_sqls"] = [
                {
                    "sql_id": c["id"],
                    "file_name": c["file_name"],
                    "reason": f"语义检索分 {c.get('retrieval_score', 0)}",
                    "join_fragments": c.get("join_fragments", [])[:3],
                    "grain_comparison": c.get("grain_comparison", []),
                }
                for c in candidate_contexts
            ]
        return result
    except LlmError as exc:
        llm_error = str(exc)
        logger.warning("LLM cross_sql_rewrite failed: %s", exc)

    fallback = _fallback_cross_sql_rewrite(
        record, dimension, candidate_contexts, cooccurrence, instruction
    )
    if llm_error:
        fallback["risk_notes"].insert(0, f"LLM 调用失败：{llm_error[:120]}")
    fallback["dimension_field_hints"] = field_hints
    return fallback
