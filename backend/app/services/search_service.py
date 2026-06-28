"""Search and filter SQL files with simple scoring."""

from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.models.sql_file import SqlFile
from app.schemas.sql_file import FilterOptionsResponse, SqlFileListItem
from app.utils.text_utils import parse_json_list

# Field weights for keyword relevance scoring
SCORE_WEIGHTS: dict[str, int] = {
    "file_name": 10,
    "metric_raw": 8,
    "business": 8,
    "scene": 7,
    "tag_raw": 6,
    "description": 6,
    "core_table_raw": 5,
    "dimension_raw": 4,
    "author_raw": 4,
    "sql_content": 2,
}


@dataclass
class SearchParams:
    keyword: str | None = None
    business: str | None = None
    scene: str | None = None
    tag: str | None = None
    core_table: str | None = None
    author: str | None = None
    page: int = 1
    page_size: int = 50


def _contains(haystack: str | None, needle: str) -> bool:
    if not haystack or not needle:
        return False
    return needle.lower() in haystack.lower()


def _json_list_contains(json_str: str | None, needle: str) -> bool:
    for item in parse_json_list(json_str):
        if _contains(item, needle):
            return True
    return False


def compute_score(record: SqlFile, keyword: str) -> float:
    """Score a record against a keyword using weighted field matches."""
    if not keyword.strip():
        return 0.0

    kw = keyword.strip()
    score = 0.0

    for field, weight in SCORE_WEIGHTS.items():
        value = getattr(record, field, None)
        if _contains(value, kw):
            score += weight

    # Also check raw fields that map to json
    if _json_list_contains(record.tags_json, kw):
        score += SCORE_WEIGHTS["tag_raw"]
    if _json_list_contains(record.metrics_json, kw):
        score += SCORE_WEIGHTS["metric_raw"]
    if _json_list_contains(record.core_tables_json, kw):
        score += SCORE_WEIGHTS["core_table_raw"]
    if _json_list_contains(record.authors_json, kw):
        score += SCORE_WEIGHTS["author_raw"]

    return score


def _matches_filters(record: SqlFile, params: SearchParams) -> bool:
    """Apply structured filters (exact / contains match on json lists)."""
    if params.business and not _contains(record.business, params.business):
        return False

    if params.scene and not _contains(record.scene, params.scene):
        return False

    if params.tag and not _json_list_contains(record.tags_json, params.tag):
        if not _contains(record.tag_raw, params.tag):
            return False

    if params.core_table and not _json_list_contains(
        record.core_tables_json, params.core_table
    ):
        if not _contains(record.core_table_raw, params.core_table):
            return False

    if params.author and not _json_list_contains(record.authors_json, params.author):
        if not _contains(record.author_raw, params.author):
            return False

    return True


def search_sql_files(
    db: Session, params: SearchParams, user_email: str | None = None
) -> tuple[int, list[SqlFileListItem]]:
    """
    Search and filter SQL files.
    Returns (total_count, paginated list with optional scores).
    """
    records: list[SqlFile] = db.query(SqlFile).all()
    if user_email:
        records = [r for r in records if r.user_email == user_email]

    keyword = (params.keyword or "").strip()
    scored: list[tuple[SqlFile, float]] = []

    for record in records:
        if not _matches_filters(record, params):
            continue

        if keyword:
            score = compute_score(record, keyword)
            if score <= 0:
                continue
            scored.append((record, score))
        else:
            scored.append((record, 0.0))

    # Sort: by score desc when keyword present, else by file_name
    if keyword:
        scored.sort(key=lambda x: (-x[1], x[0].file_name))
    else:
        scored.sort(key=lambda x: x[0].file_name)

    total = len(scored)
    start = (params.page - 1) * params.page_size
    end = start + params.page_size
    page_items = scored[start:end]

    items = [
        SqlFileListItem.from_orm_with_score(
            record, score if keyword else None
        )
        for record, score in page_items
    ]

    return total, items


def get_filter_options(db: Session, user_email: str | None = None) -> FilterOptionsResponse:
    records: list[SqlFile] = db.query(SqlFile).all()
    if user_email:
        records = [r for r in records if r.user_email == user_email]

    businesses: set[str] = set()
    authors: set[str] = set()
    tags: set[str] = set()
    core_tables: set[str] = set()

    for record in records:
        if record.business:
            businesses.add(record.business.strip())

        for author in parse_json_list(record.authors_json):
            if author.strip():
                authors.add(author.strip())

        for tag in parse_json_list(record.tags_json):
            if tag.strip():
                tags.add(tag.strip())

        for table in parse_json_list(record.core_tables_json):
            if table.strip():
                core_tables.add(table.strip())

    return FilterOptionsResponse(
        businesses=sorted(businesses),
        authors=sorted(authors),
        tags=sorted(tags),
        core_tables=sorted(core_tables),
    )


def get_sql_file_by_id(
    db: Session, file_id: int, user_email: str | None = None
) -> SqlFile | None:
    query = db.query(SqlFile).filter(SqlFile.id == file_id)
    if user_email:
        query = query.filter(SqlFile.user_email == user_email)
    return query.first()
