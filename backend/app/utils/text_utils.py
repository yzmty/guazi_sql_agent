"""Text parsing helpers."""

import json
import re
from typing import Any


# Field names in the standardized comment block
FIELD_FILE = "文件"
FIELD_METRIC = "指标"
FIELD_BUSINESS = "业务"
FIELD_SCENE = "场景"
FIELD_TAG = "标签"
FIELD_DIMENSION = "维度"
FIELD_CORE_TABLE = "核心表"
FIELD_AUTHOR = "作者"
FIELD_DESCRIPTION = "描述"

# 兼容英文/别名键名（如 file: / 文件:）
FIELD_ALIASES: dict[str, str] = {
    "file": FIELD_FILE,
    "filename": FIELD_FILE,
    "name": FIELD_FILE,
    "文件": FIELD_FILE,
    "metric": FIELD_METRIC,
    "metrics": FIELD_METRIC,
    "指标": FIELD_METRIC,
    "business": FIELD_BUSINESS,
    "业务": FIELD_BUSINESS,
    "scene": FIELD_SCENE,
    "场景": FIELD_SCENE,
    "tag": FIELD_TAG,
    "tags": FIELD_TAG,
    "标签": FIELD_TAG,
    "dimension": FIELD_DIMENSION,
    "dimensions": FIELD_DIMENSION,
    "维度": FIELD_DIMENSION,
    "table": FIELD_CORE_TABLE,
    "tables": FIELD_CORE_TABLE,
    "core_table": FIELD_CORE_TABLE,
    "核心表": FIELD_CORE_TABLE,
    "author": FIELD_AUTHOR,
    "authors": FIELD_AUTHOR,
    "作者": FIELD_AUTHOR,
    "desc": FIELD_DESCRIPTION,
    "description": FIELD_DESCRIPTION,
    "描述": FIELD_DESCRIPTION,
}

PIPE_SPLIT_FIELDS = {
    FIELD_METRIC,
    FIELD_TAG,
    FIELD_DIMENSION,
    FIELD_CORE_TABLE,
    FIELD_AUTHOR,
}


def split_pipe_values(raw: str | None) -> list[str]:
    """Split pipe-delimited values and strip whitespace."""
    if not raw or not raw.strip():
        return []
    return [part.strip() for part in raw.split("|") if part.strip()]


def to_json_list(values: list[str]) -> str:
    """Serialize a string list to JSON."""
    return json.dumps(values, ensure_ascii=False)


def parse_json_list(raw: str | None) -> list[str]:
    """Deserialize a JSON list column."""
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return [str(v) for v in parsed]
    except (json.JSONDecodeError, TypeError):
        pass
    return []


def normalize_field_key(key: str) -> str:
    """Normalize comment block field name to canonical Chinese key."""
    raw = key.strip().rstrip(":").strip()
    canonical = FIELD_ALIASES.get(raw.lower(), raw)
    return FIELD_ALIASES.get(raw, canonical)


def clean_field_value(key: str, value: str) -> str:
    """Strip trailing commas/spaces; normalize file names."""
    value = value.strip().rstrip(",").strip()
    if key == FIELD_FILE:
        if value and not value.lower().endswith(".sql"):
            value = f"{value}.sql"
    return value


def parse_comment_line(line: str) -> tuple[str, str] | None:
    """
    Parse a single line like '指标: a|b' or '指标：a|b'.
    Returns (field_name, field_value) or None.
    """
    line = line.strip()
    if not line or line.startswith("*") or line.startswith("/"):
        return None

    match = re.match(r"^(.+?)[:：]\s*(.*)$", line)
    if not match:
        return None

    key = normalize_field_key(match.group(1))
    value = clean_field_value(key, match.group(2).strip())
    return key, value


def extract_comment_block(content: str) -> tuple[str | None, str]:
    """
    Extract top /* ... */ block from SQL content.
    Returns (comment_block, remaining_sql).
    """
    content = content.lstrip("\ufeff")  # strip BOM if present
    match = re.match(r"^\s*/\*(.*?)\*/", content, re.DOTALL)
    if not match:
        return None, content

    comment_block = match.group(0)
    remaining = content[match.end() :].lstrip("\n")
    return comment_block, remaining
