"""Parse standardized comment blocks from SQL files."""

import logging
from pathlib import Path

from app.utils.text_utils import (
    FIELD_AUTHOR,
    FIELD_BUSINESS,
    FIELD_CORE_TABLE,
    FIELD_DESCRIPTION,
    FIELD_DIMENSION,
    FIELD_FILE,
    FIELD_METRIC,
    FIELD_SCENE,
    FIELD_TAG,
    PIPE_SPLIT_FIELDS,
    extract_comment_block,
    parse_comment_line,
    split_pipe_values,
    to_json_list,
)

logger = logging.getLogger(__name__)


class SqlParseError(Exception):
    """Raised when a SQL file cannot be parsed."""


def read_sql_file(file_path: Path) -> str:
    """Read SQL file with UTF-8, fallback to GBK on decode errors."""
    try:
        return file_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        try:
            content = file_path.read_text(encoding="gbk")
            logger.warning("File %s decoded with GBK fallback", file_path.name)
            return content
        except UnicodeDecodeError as exc:
            raise SqlParseError(
                f"无法读取文件编码（请使用 UTF-8）: {file_path.name}"
            ) from exc


def parse_comment_fields(comment_block: str) -> dict[str, str]:
    """Parse key-value pairs from inside a comment block."""
    inner = comment_block
    if inner.startswith("/*"):
        inner = inner[2:]
    if inner.endswith("*/"):
        inner = inner[:-2]

    fields: dict[str, str] = {}
    for line in inner.splitlines():
        parsed = parse_comment_line(line)
        if parsed:
            key, value = parsed
            fields[key] = value
    return fields


def parse_sql_content(content: str, file_name: str = "untitled.sql") -> dict | None:
    """Parse SQL text (not from disk). Returns None if no comment block."""
    comment_block, sql_content = extract_comment_block(content)

    if not comment_block:
        logger.warning("No comment block found, skipping: %s", file_name)
        return None

    fields = parse_comment_fields(comment_block)
    display_name = fields.get(FIELD_FILE) or file_name

    def pipe_field(key: str) -> tuple[str, list[str]]:
        raw = fields.get(key, "")
        values = split_pipe_values(raw) if key in PIPE_SPLIT_FIELDS else []
        return raw, values

    metric_raw, metrics = pipe_field(FIELD_METRIC)
    tag_raw, tags = pipe_field(FIELD_TAG)
    dimension_raw, dimensions = pipe_field(FIELD_DIMENSION)
    core_table_raw, core_tables = pipe_field(FIELD_CORE_TABLE)
    author_raw, authors = pipe_field(FIELD_AUTHOR)

    return {
        "file_name": display_name.strip(),
        "file_path": "",
        "metric_raw": metric_raw,
        "metrics_json": to_json_list(metrics),
        "business": fields.get(FIELD_BUSINESS, "").strip() or None,
        "scene": fields.get(FIELD_SCENE, "").strip() or None,
        "tag_raw": tag_raw,
        "tags_json": to_json_list(tags),
        "dimension_raw": dimension_raw,
        "dimensions_json": to_json_list(dimensions),
        "core_table_raw": core_table_raw,
        "core_tables_json": to_json_list(core_tables),
        "author_raw": author_raw,
        "authors_json": to_json_list(authors),
        "description": fields.get(FIELD_DESCRIPTION, "").strip() or None,
        "sql_content": sql_content.strip(),
        "comment_block": comment_block.strip(),
    }


def parse_sql_file(file_path: Path) -> dict | None:
    """
    Parse a single SQL file and return structured metadata dict.
    Returns None if no comment block is found (caller should skip).
    """
    file_path = Path(file_path)
    content = read_sql_file(file_path)
    comment_block, sql_content = extract_comment_block(content)

    if not comment_block:
        logger.warning("No comment block found, skipping: %s", file_path.name)
        return None

    fields = parse_comment_fields(comment_block)

    file_name = fields.get(FIELD_FILE) or file_path.name

    def pipe_field(key: str) -> tuple[str, list[str]]:
        raw = fields.get(key, "")
        values = split_pipe_values(raw) if key in PIPE_SPLIT_FIELDS else []
        return raw, values

    metric_raw, metrics = pipe_field(FIELD_METRIC)
    tag_raw, tags = pipe_field(FIELD_TAG)
    dimension_raw, dimensions = pipe_field(FIELD_DIMENSION)
    core_table_raw, core_tables = pipe_field(FIELD_CORE_TABLE)
    author_raw, authors = pipe_field(FIELD_AUTHOR)

    return {
        "file_name": file_name.strip(),
        "file_path": str(file_path.resolve()),
        "metric_raw": metric_raw,
        "metrics_json": to_json_list(metrics),
        "business": fields.get(FIELD_BUSINESS, "").strip() or None,
        "scene": fields.get(FIELD_SCENE, "").strip() or None,
        "tag_raw": tag_raw,
        "tags_json": to_json_list(tags),
        "dimension_raw": dimension_raw,
        "dimensions_json": to_json_list(dimensions),
        "core_table_raw": core_table_raw,
        "core_tables_json": to_json_list(core_tables),
        "author_raw": author_raw,
        "authors_json": to_json_list(authors),
        "description": fields.get(FIELD_DESCRIPTION, "").strip() or None,
        "sql_content": sql_content.strip(),
        "comment_block": comment_block.strip(),
    }
