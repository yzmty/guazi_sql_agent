"""Candidate SQL retrieval for Agent — no LLM calls."""

import re

from sqlalchemy.orm import Session

from app.models.sql_file import SqlFile
from app.services.search_service import compute_score
from app.utils.text_utils import parse_json_list


def _record_to_summary(record: SqlFile) -> dict:
    """Build a lightweight metadata summary for LLM prompts."""
    return {
        "id": record.id,
        "file_name": record.file_name,
        "metrics": parse_json_list(record.metrics_json),
        "business": record.business or "",
        "scene": record.scene or "",
        "tags": parse_json_list(record.tags_json),
        "core_tables": parse_json_list(record.core_tables_json),
        "description": record.description or "",
    }


def _token_overlap_score(a: set[str], b: set[str]) -> int:
    return len(a & b)


def search_candidates(
    db: Session, question: str, top_k: int = 15, user_email: str | None = None
) -> list[tuple[SqlFile, float]]:
    """
    Retrieve candidate SQL records for a natural-language question.
    Uses weighted field scoring from search_service.
    """
    question = question.strip()
    if not question:
        return []

    records: list[SqlFile] = db.query(SqlFile).all()
    if user_email:
        records = [r for r in records if r.user_email == user_email]
    scored: list[tuple[SqlFile, float]] = []

    # Multi-token: also score each whitespace-separated token
    tokens = [t for t in re.split(r"[\s，,、]+", question) if t]

    for record in records:
        score = compute_score(record, question)
        for token in tokens:
            if token != question:
                score += compute_score(record, token) * 0.5
        if score > 0:
            scored.append((record, score))

    scored.sort(key=lambda x: (-x[1], x[0].file_name))
    return scored[:top_k]


def get_similar_candidates(
    db: Session, sql_id: int, top_k: int = 10, user_email: str | None = None
) -> list[tuple[SqlFile, float]]:
    """
    Rule-based similar SQL recall, excluding the source record.
    Scoring: same business +10, same scene +10, tag overlap +3 each,
    core_table overlap +4 each, metric overlap +3 each.
    """
    source = db.query(SqlFile).filter(SqlFile.id == sql_id).first()
    if not source:
        return []
    if user_email and source.user_email != user_email:
        return []

    source_tags = set(parse_json_list(source.tags_json))
    source_tables = set(parse_json_list(source.core_tables_json))
    source_metrics = set(parse_json_list(source.metrics_json))

    records: list[SqlFile] = (
        db.query(SqlFile).filter(SqlFile.id != sql_id).all()
    )
    if user_email:
        records = [r for r in records if r.user_email == user_email]
    scored: list[tuple[SqlFile, float]] = []

    for record in records:
        score = 0.0

        if source.business and record.business:
            if source.business.strip() == record.business.strip():
                score += 10
            elif source.business in (record.business or "") or (
                record.business in source.business
            ):
                score += 5

        if source.scene and record.scene:
            if source.scene.strip() == record.scene.strip():
                score += 10
            elif source.scene[:20] in (record.scene or ""):
                score += 4

        rec_tags = set(parse_json_list(record.tags_json))
        rec_tables = set(parse_json_list(record.core_tables_json))
        rec_metrics = set(parse_json_list(record.metrics_json))

        score += _token_overlap_score(source_tags, rec_tags) * 3
        score += _token_overlap_score(source_tables, rec_tables) * 4
        score += _token_overlap_score(source_metrics, rec_metrics) * 3

        # Filename similarity bonus
        if source.file_name and record.file_name:
            src_prefix = source.file_name.split("-")[0].split("_")[0]
            if src_prefix and src_prefix in record.file_name:
                score += 2

        if score > 0:
            scored.append((record, score))

    scored.sort(key=lambda x: (-x[1], x[0].file_name))
    return scored[:top_k]


def candidates_to_summaries(candidates: list[tuple[SqlFile, float]]) -> list[dict]:
    """Convert scored candidates to summary dicts with retrieval_score."""
    return [
        {**_record_to_summary(record), "retrieval_score": score}
        for record, score in candidates
    ]


def record_to_full_context(record: SqlFile) -> dict:
    """Full record context for explain/rewrite prompts."""
    return {
        **_record_to_summary(record),
        "dimensions": parse_json_list(record.dimensions_json),
        "authors": parse_json_list(record.authors_json),
        "sql_content": record.sql_content or "",
    }
