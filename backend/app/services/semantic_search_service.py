"""Semantic vector search over user SQL library."""

from __future__ import annotations

import logging

from sqlalchemy.orm import Session

from app.models.sql_file import SqlFile
from app.services.embedding_service import embed_texts
from app.services.retrieval_service import search_candidates
from app.services.vector_store import get_vector_store

logger = logging.getLogger(__name__)


def semantic_search_sql(
    db: Session,
    question: str,
    user_email: str,
    top_k: int = 15,
) -> list[tuple[SqlFile, float]]:
    """Return SQL records ranked by semantic similarity."""
    query = question.strip()
    if not query:
        return []

    try:
        vector = embed_texts([query])[0]
        hits = get_vector_store().search(vector, user_email=user_email, top_k=top_k)
    except Exception as exc:
        logger.warning("Semantic search failed, fallback to keyword: %s", exc)
        return search_candidates(db, query, top_k=top_k, user_email=user_email)

    if not hits:
        return search_candidates(db, query, top_k=top_k, user_email=user_email)

    results: list[tuple[SqlFile, float]] = []
    seen: set[int] = set()
    for hit in hits:
        meta = hit.get("metadata") or {}
        sql_id = meta.get("sql_file_id")
        if not sql_id or sql_id in seen:
            continue
        record = (
            db.query(SqlFile)
            .filter(SqlFile.id == sql_id, SqlFile.user_email == user_email)
            .first()
        )
        if record:
            seen.add(sql_id)
            results.append((record, float(hit.get("score", 0.0))))

    if len(results) < top_k // 2:
        keyword_hits = search_candidates(db, query, top_k=top_k, user_email=user_email)
        for record, score in keyword_hits:
            if record.id not in seen:
                results.append((record, score * 0.5))
                seen.add(record.id)

    results.sort(key=lambda x: x[1], reverse=True)
    return results[:top_k]
