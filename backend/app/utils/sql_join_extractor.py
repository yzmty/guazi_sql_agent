"""Extract JOIN / FROM fragments from SQL using sqlglot with sqlparse fallback."""

from __future__ import annotations

import logging
import re
from typing import Any

logger = logging.getLogger(__name__)

_JOIN_KEYWORD_RE = re.compile(
    r"\b((?:LEFT|RIGHT|FULL|INNER|OUTER|CROSS)\s+)?JOIN\b",
    re.IGNORECASE,
)
_ON_RE = re.compile(r"\bON\b", re.IGNORECASE)
_TABLE_REF_RE = re.compile(
    r"(?:FROM|JOIN)\s+([`\"[\w.]+\.?[\w.]*[`\"]?)\s*(?:AS\s+)?(\w+)?",
    re.IGNORECASE,
)
_GROUP_BY_RE = re.compile(r"\bGROUP\s+BY\b([\s\S]*?)(?:\bORDER\b|\bHAVING\b|\bLIMIT\b|$)", re.IGNORECASE)
_SELECT_RE = re.compile(r"\bSELECT\b([\s\S]*?)\bFROM\b", re.IGNORECASE)


def _normalize_identifier(name: str | None) -> str:
    if not name:
        return ""
    return name.strip().strip("`\"[]")


def _split_select_fields(select_clause: str) -> list[str]:
    fields: list[str] = []
    depth = 0
    current: list[str] = []
    for ch in select_clause:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        elif ch == "," and depth == 0:
            part = "".join(current).strip()
            if part:
                fields.append(part)
            current = []
            continue
        current.append(ch)
    tail = "".join(current).strip()
    if tail:
        fields.append(tail)
    return fields[:80]


def _extract_grain_hints_sqlglot(sql: str) -> dict[str, Any]:
    try:
        import sqlglot
        from sqlglot import exp, parse_one

        tree = parse_one(sql, read="hive")
        group_exprs = []
        for node in tree.find_all(exp.Group):
            for expr in node.expressions:
                group_exprs.append(expr.sql(dialect="hive"))
        select_exprs = []
        if isinstance(tree, exp.Select):
            for expr in tree.expressions:
                select_exprs.append(expr.sql(dialect="hive"))
        tables: list[str] = []
        for table in tree.find_all(exp.Table):
            name = table.sql(dialect="hive")
            if name and name not in tables:
                tables.append(name)
        return {
            "group_by_fields": group_exprs[:20],
            "select_fields": select_exprs[:30],
            "tables": tables[:20],
            "parser": "sqlglot",
        }
    except Exception as exc:
        logger.debug("sqlglot grain hints failed: %s", exc)
        return _extract_grain_hints_sqlparse(sql)


def _extract_grain_hints_sqlparse(sql: str) -> dict[str, Any]:
    group_by_fields: list[str] = []
    select_fields: list[str] = []
    tables: list[str] = []

    gb = _GROUP_BY_RE.search(sql)
    if gb:
        group_by_fields = [
            p.strip()
            for p in gb.group(1).replace("\n", " ").split(",")
            if p.strip()
        ][:20]

    sel = _SELECT_RE.search(sql)
    if sel:
        select_fields = _split_select_fields(sel.group(1))[:30]

    for match in _TABLE_REF_RE.finditer(sql):
        table = _normalize_identifier(match.group(1))
        if table and table not in tables:
            tables.append(table)

    return {
        "group_by_fields": group_by_fields,
        "select_fields": select_fields,
        "tables": tables,
        "parser": "sqlparse",
    }


def extract_grain_hints(sql: str) -> dict[str, Any]:
    """Infer grain hints from GROUP BY / SELECT / tables."""
    if not sql or not sql.strip():
        return {"group_by_fields": [], "select_fields": [], "tables": [], "parser": "none"}
    return _extract_grain_hints_sqlglot(sql)


def _extract_joins_sqlglot(sql: str) -> list[dict[str, Any]]:
    import sqlglot
    from sqlglot import exp, parse_one

    tree = parse_one(sql, read="hive")
    joins: list[dict[str, Any]] = []

    if not isinstance(tree, exp.Select):
        return joins

    from_tables: list[str] = []
    if tree.args.get("from"):
        from_expr = tree.args["from"]
        if isinstance(from_expr, exp.From):
            for table in from_expr.find_all(exp.Table):
                from_tables.append(table.sql(dialect="hive"))

    for join_node in tree.find_all(exp.Join):
        join_type = join_node.args.get("kind") or "JOIN"
        if isinstance(join_type, str):
            join_kind = join_type.upper()
        else:
            join_kind = join_type.sql(dialect="hive").upper() if join_type else "JOIN"

        table_sql = ""
        alias = ""
        if join_node.this:
            if isinstance(join_node.this, exp.Table):
                table_sql = join_node.this.sql(dialect="hive")
                alias = join_node.this.alias_or_name or ""
            else:
                table_sql = join_node.this.sql(dialect="hive")

        on_sql = ""
        if join_node.args.get("on"):
            on_sql = join_node.args["on"].sql(dialect="hive")

        joins.append(
            {
                "join_type": join_kind,
                "table": table_sql,
                "alias": alias,
                "on_condition": on_sql,
                "join_sql": join_node.sql(dialect="hive"),
                "parser": "sqlglot",
            }
        )

    if from_tables and not joins:
        joins.append(
            {
                "join_type": "FROM",
                "table": from_tables[0],
                "alias": "",
                "on_condition": "",
                "join_sql": f"FROM {from_tables[0]}",
                "parser": "sqlglot",
            }
        )
    return joins


def _extract_joins_sqlparse(sql: str) -> list[dict[str, Any]]:
    """Regex-based JOIN extraction when sqlglot cannot parse."""
    joins: list[dict[str, Any]] = []
    normalized = re.sub(r"\s+", " ", sql)
    parts = _JOIN_KEYWORD_RE.split(normalized)
    if len(parts) <= 1:
        from_match = re.search(r"\bFROM\s+(.+?)(?:\bWHERE\b|\bGROUP\b|\bORDER\b|\bLIMIT\b|$)", normalized, re.I)
        if from_match:
            joins.append(
                {
                    "join_type": "FROM",
                    "table": from_match.group(1).strip()[:200],
                    "alias": "",
                    "on_condition": "",
                    "join_sql": f"FROM {from_match.group(1).strip()[:200]}",
                    "parser": "sqlparse",
                }
            )
        return joins

    cursor = 0
    for match in _JOIN_KEYWORD_RE.finditer(normalized):
        join_type = (match.group(1) or "").strip().upper() + " JOIN"
        start = match.end()
        on_match = _ON_RE.search(normalized, start)
        if not on_match:
            continue
        table_part = normalized[start : on_match.start()].strip()
        next_join = _JOIN_KEYWORD_RE.search(normalized, on_match.end())
        where_match = re.search(r"\bWHERE\b", normalized[on_match.end() :], re.I)
        end = on_match.end()
        if next_join:
            end = next_join.start()
        elif where_match:
            end = on_match.end() + where_match.start()
        else:
            end = min(len(normalized), on_match.end() + 300)
        on_part = normalized[on_match.end() : end].strip().rstrip(",")
        joins.append(
            {
                "join_type": join_type.strip(),
                "table": table_part[:200],
                "alias": "",
                "on_condition": on_part[:300],
                "join_sql": f"{join_type.strip()} {table_part} ON {on_part}"[:500],
                "parser": "sqlparse",
            }
        )
        cursor = end
    return joins


def extract_join_fragments(sql: str) -> list[dict[str, Any]]:
    """Extract JOIN fragments; prefer sqlglot, fall back to sqlparse/regex."""
    if not sql or not sql.strip():
        return []
    try:
        joins = _extract_joins_sqlglot(sql)
        if joins:
            return joins
    except Exception as exc:
        logger.debug("sqlglot join extract failed: %s", exc)
    return _extract_joins_sqlparse(sql)


def extract_tables_from_sql(sql: str) -> list[str]:
    """Best-effort table name list from SQL body."""
    hints = extract_grain_hints(sql)
    tables = list(hints.get("tables") or [])
    for join in extract_join_fragments(sql):
        table = join.get("table") or ""
        base = table.split()[0] if table else ""
        base = _normalize_identifier(base)
        if base and base.upper() not in ("SELECT", "FROM") and base not in tables:
            tables.append(base)
    return tables[:30]
