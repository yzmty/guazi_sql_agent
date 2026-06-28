"""Dimension ↔ table co-occurrence stats across a user's SQL library."""

from __future__ import annotations

import re
from collections import Counter

from sqlalchemy.orm import Session

from app.models.sql_file import SqlFile
from app.utils.sql_join_extractor import extract_tables_from_sql
from app.utils.text_utils import parse_json_list


def _normalize_token(text: str) -> str:
    return re.sub(r"\s+", "", text.strip().lower())


def dimension_matches(text: str, keyword: str) -> bool:
    """Check if keyword appears in text (fuzzy for Chinese dimension names)."""
    if not text or not keyword:
        return False
    t = _normalize_token(text)
    k = _normalize_token(keyword)
    if k in t or t in k:
        return True
    # Partial match for compound dimension names (e.g. 城市等级 vs 城市)
    if len(k) >= 2 and k[:2] in t:
        return True
    return False


def _record_mentions_dimension(record: SqlFile, keyword: str) -> bool:
    dims = parse_json_list(record.dimensions_json)
    if any(dimension_matches(d, keyword) for d in dims):
        return True
    if record.dimension_raw and dimension_matches(record.dimension_raw, keyword):
        return True
    if record.description and dimension_matches(record.description, keyword):
        return True
    if record.sql_content and dimension_matches(record.sql_content, keyword):
        return True
    if record.comment_block and dimension_matches(record.comment_block, keyword):
        return True
    return False


def get_dimension_table_cooccurrence(
    db: Session,
    dimension_keyword: str,
    user_email: str,
    *,
    top_n: int = 10,
) -> list[dict]:
    """
    Count which tables most often appear in SQLs that mention a given dimension.
    Uses comment metadata + SQL body table extraction.
    """
    keyword = (dimension_keyword or "").strip()
    if not keyword:
        return []

    records: list[SqlFile] = (
        db.query(SqlFile).filter(SqlFile.user_email == user_email).all()
    )
    table_counter: Counter[str] = Counter()
    sql_hits = 0

    for record in records:
        if not _record_mentions_dimension(record, keyword):
            continue
        sql_hits += 1
        seen_in_record: set[str] = set()

        for table in parse_json_list(record.core_tables_json):
            t = table.strip()
            if t:
                seen_in_record.add(t)

        for table in extract_tables_from_sql(record.sql_content or ""):
            if table:
                seen_in_record.add(table)

        for table in seen_in_record:
            table_counter[table] += 1

    if not table_counter:
        return []

    results: list[dict] = []
    for table, count in table_counter.most_common(top_n):
        results.append(
            {
                "table": table,
                "count": count,
                "sql_count": sql_hits,
                "ratio": round(count / sql_hits, 3) if sql_hits else 0.0,
            }
        )
    return results


def get_dimension_field_hints(
    db: Session,
    dimension_keyword: str,
    user_email: str,
    *,
    top_n: int = 8,
) -> list[dict]:
    """Extract field-like tokens near dimension keyword from SQL bodies."""
    keyword = (dimension_keyword or "").strip()
    if not keyword:
        return []

    records: list[SqlFile] = (
        db.query(SqlFile).filter(SqlFile.user_email == user_email).all()
    )
    field_counter: Counter[str] = Counter()

    pattern = re.compile(
        rf"([\w.`\"]+[\w_.]*{re.escape(keyword[: min(len(keyword), 4)])}[\w_]*)",
        re.IGNORECASE,
    )

    for record in records:
        if not _record_mentions_dimension(record, keyword):
            continue
        sql = record.sql_content or ""
        for match in pattern.finditer(sql):
            token = match.group(1).strip("`")
            if len(token) >= 2:
                field_counter[token] += 1

    return [
        {"field": field, "count": count}
        for field, count in field_counter.most_common(top_n)
    ]
