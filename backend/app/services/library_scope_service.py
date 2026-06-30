"""Unified personal / shared SQL library access for Agent and search."""

from __future__ import annotations

from typing import Literal, Union

from sqlalchemy.orm import Session

from app.config import SHARED_VECTOR_NAMESPACE
from app.models.shared_sql_file import SharedSqlFile
from app.models.sql_file import SqlFile
from app.services.embedding_service import embed_texts
from app.services.retrieval_service import (
    candidates_to_summaries,
    get_similar_candidates,
    record_to_full_context,
)
from app.services.search_service import compute_score, get_sql_file_by_id
from app.services.shared_group_service import is_approved_member, require_approved_member
from app.services.shared_sql_service import (
    get_shared_sql,
    shared_record_to_context,
)
from app.services.vector_store import get_vector_store
from app.utils.text_utils import parse_json_list

LibraryScope = Literal["personal", "shared"]
AnySqlRecord = Union[SqlFile, SharedSqlFile]


def _require_shared_access(db: Session, user_email: str) -> None:
    require_approved_member(db, user_email)


def resolve_sql_record(
    db: Session,
    sql_id: int,
    user_email: str,
    scope: LibraryScope = "personal",
) -> AnySqlRecord | None:
    if scope == "shared":
        _require_shared_access(db, user_email)
        return get_shared_sql(db, user_email, sql_id)
    return get_sql_file_by_id(db, sql_id, user_email=user_email)


def record_to_context(record: AnySqlRecord, scope: LibraryScope = "personal") -> dict:
    if scope == "shared" or isinstance(record, SharedSqlFile):
        return shared_record_to_context(record)  # type: ignore[arg-type]
    return record_to_full_context(record)  # type: ignore[arg-type]


def _shared_search_candidates(
    db: Session, question: str, top_k: int = 15
) -> list[tuple[SharedSqlFile, float]]:
    from app.models.shared_group import SharedGroup

    group = db.query(SharedGroup).order_by(SharedGroup.id.asc()).first()
    if not group:
        return []
    question = question.strip()
    if not question:
        return []
    records = (
        db.query(SharedSqlFile)
        .filter(SharedSqlFile.group_id == group.id)
        .order_by(SharedSqlFile.file_name)
        .all()
    )
    scored: list[tuple[SharedSqlFile, float]] = []
    for record in records:
        score = compute_score(record, question)
        if score > 0:
            scored.append((record, score))
    scored.sort(key=lambda x: (-x[1], x[0].file_name))
    return scored[:top_k]


def _semantic_search_shared(
    db: Session,
    question: str,
    top_k: int = 15,
) -> list[tuple[SharedSqlFile, float]]:
    query = question.strip()
    if not query:
        return []

    try:
        vector = embed_texts([query])[0]
        hits = get_vector_store().search(
            vector, user_email=SHARED_VECTOR_NAMESPACE, top_k=top_k
        )
    except Exception:
        return _shared_search_candidates(db, query, top_k=top_k)

    if not hits:
        return _shared_search_candidates(db, query, top_k=top_k)

    results: list[tuple[SharedSqlFile, float]] = []
    seen: set[int] = set()
    for hit in hits:
        meta = hit.get("metadata") or {}
        sql_id = meta.get("sql_file_id")
        if not sql_id or sql_id in seen:
            continue
        record = db.query(SharedSqlFile).filter(SharedSqlFile.id == sql_id).first()
        if record:
            seen.add(sql_id)
            results.append((record, float(hit.get("score", 0.0))))

    if len(results) < top_k // 2:
        for record, score in _shared_search_candidates(db, query, top_k=top_k):
            if record.id not in seen:
                results.append((record, score * 0.5))
                seen.add(record.id)

    results.sort(key=lambda x: x[1], reverse=True)
    return results[:top_k]


def semantic_search_scoped(
    db: Session,
    question: str,
    user_email: str,
    scope: LibraryScope = "personal",
    top_k: int = 15,
) -> list[tuple[AnySqlRecord, float]]:
    if scope == "shared":
        _require_shared_access(db, user_email)
        return _semantic_search_shared(db, question, top_k=top_k)

    from app.services.semantic_search_service import semantic_search_sql

    return semantic_search_sql(db, question, user_email, top_k=top_k)


def get_similar_scoped(
    db: Session,
    sql_id: int,
    user_email: str,
    scope: LibraryScope = "personal",
    top_k: int = 10,
) -> list[tuple[AnySqlRecord, float]]:
    if scope == "shared":
        _require_shared_access(db, user_email)
        source = get_shared_sql(db, user_email, sql_id)
        if not source:
            return []
        from app.models.shared_group import SharedGroup

        group = db.query(SharedGroup).order_by(SharedGroup.id.asc()).first()
        if not group:
            return []

        source_tags = set(parse_json_list(source.tags_json))
        source_tables = set(parse_json_list(source.core_tables_json))
        source_metrics = set(parse_json_list(source.metrics_json))
        records = (
            db.query(SharedSqlFile)
            .filter(
                SharedSqlFile.group_id == group.id,
                SharedSqlFile.id != sql_id,
            )
            .all()
        )
        scored: list[tuple[SharedSqlFile, float]] = []
        for record in records:
            score = 0.0
            if source.business and record.business:
                if source.business.strip() == record.business.strip():
                    score += 10
            if source.scene and record.scene:
                if source.scene.strip() == record.scene.strip():
                    score += 10
            rec_tags = set(parse_json_list(record.tags_json))
            rec_tables = set(parse_json_list(record.core_tables_json))
            rec_metrics = set(parse_json_list(record.metrics_json))
            score += len(source_tags & rec_tags) * 3
            score += len(source_tables & rec_tables) * 4
            score += len(source_metrics & rec_metrics) * 3
            if score > 0:
                scored.append((record, score))
        scored.sort(key=lambda x: (-x[1], x[0].file_name))
        return scored[:top_k]

    return get_similar_candidates(db, sql_id, top_k=top_k, user_email=user_email)


def candidates_to_summaries_scoped(
    candidates: list[tuple[AnySqlRecord, float]],
    scope: LibraryScope = "personal",
) -> list[dict]:
    if scope == "shared":
        out: list[dict] = []
        for record, score in candidates:
            ctx = shared_record_to_context(record)  # type: ignore[arg-type]
            out.append(
                {
                    "id": ctx["id"],
                    "file_name": ctx["file_name"],
                    "metrics": ctx["metrics"],
                    "business": ctx["business"],
                    "scene": ctx["scene"],
                    "tags": ctx["tags"],
                    "core_tables": ctx["core_tables"],
                    "description": ctx["description"],
                    "scope": "shared",
                    "retrieval_score": score,
                }
            )
        return out
    summaries = candidates_to_summaries(candidates)  # type: ignore[arg-type]
    for item in summaries:
        item["scope"] = "personal"
    return summaries


def enrich_find_results(
    db: Session,
    results: list[dict],
    scope: LibraryScope = "personal",
) -> list[dict]:
    from app.models.shared_sql_file import SharedSqlFile

    enriched = []
    for item in results:
        sql_id = item.get("sql_id")
        record = None
        if sql_id:
            if scope == "shared":
                record = db.query(SharedSqlFile).filter(SharedSqlFile.id == sql_id).first()
            else:
                record = db.query(SqlFile).filter(SqlFile.id == sql_id).first()
        enriched.append(
            {
                **item,
                "scope": scope,
                "business": record.business if record else item.get("business", ""),
                "scene": record.scene if record else item.get("scene", ""),
            }
        )
    return enriched


def can_use_shared_library(db: Session, user_email: str) -> bool:
    return is_approved_member(db, user_email)
