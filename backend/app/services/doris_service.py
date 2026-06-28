"""Doris/MySQL connection for login validation and SQL execution."""

from __future__ import annotations

import logging
import re
from contextlib import contextmanager
from enum import Enum
from typing import Any

import pymysql

from app.config import (
    DORIS_DATABASE,
    DORIS_FALLBACK_PASSWORD,
    DORIS_FALLBACK_USER,
    DORIS_HOST,
    DORIS_PORT,
    SQL_EXECUTE_MAX_ROWS,
    SQL_EXECUTE_TIMEOUT,
)

logger = logging.getLogger(__name__)


class DorisConnectionError(Exception):
    pass


class SqlExecutionError(Exception):
    pass


class CredentialCheckResult(str, Enum):
    OK = "ok"
    AUTH_FAILED = "auth_failed"
    NETWORK_ERROR = "network_error"


def normalize_doris_username(user: str) -> str:
    """Doris MySQL user must match [\\w-]+ — strip @guazi.com email suffix."""
    user = user.strip()
    if "@" in user:
        return user.split("@", 1)[0].strip()
    return user


def normalize_login_email(user: str) -> str:
    user = user.strip().lower()
    if "@" in user:
        return user
    return f"{user}@guazi.com"


@contextmanager
def doris_connection(user: str, password: str):
    conn = pymysql.connect(
        host=DORIS_HOST,
        port=DORIS_PORT,
        user=normalize_doris_username(user),
        password=password,
        database=DORIS_DATABASE,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=10,
        read_timeout=SQL_EXECUTE_TIMEOUT,
        write_timeout=SQL_EXECUTE_TIMEOUT,
    )
    try:
        yield conn
    finally:
        conn.close()


def _classify_pymysql_error(exc: pymysql.Error) -> CredentialCheckResult:
    code = exc.args[0] if exc.args else None
    if code == 1045:
        return CredentialCheckResult.AUTH_FAILED
    msg = str(exc).lower()
    if "access denied" in msg:
        return CredentialCheckResult.AUTH_FAILED
    return CredentialCheckResult.NETWORK_ERROR


def check_credentials(user: str, password: str) -> CredentialCheckResult:
    """Check Doris credentials; distinguish auth failure from network unreachable."""
    try:
        with doris_connection(user, password) as conn:
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1 AS ok")
                cursor.fetchone()
        return CredentialCheckResult.OK
    except pymysql.Error as exc:
        logger.info("Doris login failed for %s: %s", user, exc)
        return _classify_pymysql_error(exc)


def validate_credentials(user: str, password: str) -> bool:
    """Return True if Doris accepts the credentials."""
    return check_credentials(user, password) == CredentialCheckResult.OK


def resolve_doris_user(email: str, password: str, is_super_admin: bool) -> tuple[str, str]:
    """
    Normal users: email/password are Doris credentials.
    Super admin: try email/password first, then env fallback credentials.
    """
    result = check_credentials(email, password)
    if result == CredentialCheckResult.OK:
        return normalize_doris_username(email), password
    if result == CredentialCheckResult.AUTH_FAILED:
        if is_super_admin and DORIS_FALLBACK_USER and DORIS_FALLBACK_PASSWORD:
            if check_credentials(DORIS_FALLBACK_USER, DORIS_FALLBACK_PASSWORD) == CredentialCheckResult.OK:
                return DORIS_FALLBACK_USER, DORIS_FALLBACK_PASSWORD
        raise DorisConnectionError("账号或密码错误，无法连接 Doris 数据库")

    if is_super_admin and DORIS_FALLBACK_USER and DORIS_FALLBACK_PASSWORD:
        fallback = check_credentials(DORIS_FALLBACK_USER, DORIS_FALLBACK_PASSWORD)
        if fallback == CredentialCheckResult.OK:
            return DORIS_FALLBACK_USER, DORIS_FALLBACK_PASSWORD

    raise DorisConnectionError("账号或密码错误，无法连接 Doris 数据库")


def _strip_sql_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql.strip()


def assert_readonly_sql(sql: str) -> None:
    cleaned = _strip_sql_comments(sql).lower()
    if not cleaned:
        raise SqlExecutionError("SQL 不能为空")
    allowed = cleaned.startswith("select") or cleaned.startswith("with") or cleaned.startswith("show") or cleaned.startswith("desc") or cleaned.startswith("explain")
    if not allowed:
        raise SqlExecutionError("仅允许执行 SELECT / WITH / SHOW / DESC / EXPLAIN 查询")


def detect_sql_params(sql: str) -> list[str]:
    """Detect ${...} placeholder names in SQL."""
    return detect_dollar_params(sql)


def detect_dollar_params(sql: str) -> list[str]:
    """Return unique placeholder names inside ${...}."""
    return sorted(set(re.findall(r"\$\{([^}]+)\}", sql)))


# 起止日期自动映射到常见占位符名（大小写不敏感）
_START_DATE_ALIASES = frozenset(
    {
        "start",
        "start_date",
        "begin",
        "begin_date",
        "dt_start",
        "date_start",
    }
)
_END_DATE_ALIASES = frozenset(
    {
        "end",
        "end_date",
        "finish",
        "finish_date",
        "dt_end",
        "date_end",
        "date_y_m_d",
        "date_ymd",
    }
)


def _resolve_param_values(
    start_date: str,
    end_date: str,
    extra: dict[str, str] | None = None,
) -> dict[str, str]:
    """Build placeholder name -> value map from dates and user overrides."""
    values: dict[str, str] = {}
    if extra:
        for key, val in extra.items():
            if val is not None and str(val).strip():
                values[key.strip()] = str(val).strip()

    values.setdefault("start_date", start_date)
    values.setdefault("end_date", end_date)
    values.setdefault("start", start_date)
    values.setdefault("end", end_date)
    values.setdefault("date_y_m_d", end_date)
    values.setdefault("date_ymd", end_date)
    return values


def _escape_sql_string(val: str) -> str:
    return val.replace("'", "''")


def _replace_one_placeholder(sql: str, name: str, val: str) -> str:
    """Replace ${name}; avoid ''value'' when SQL already wraps the placeholder in quotes."""
    escaped = _escape_sql_string(val)
    token = f"${{{name}}}"
    quoted_single = f"'{token}'"
    quoted_double = f'"{token}"'
    if quoted_single in sql:
        return sql.replace(quoted_single, f"'{escaped}'")
    if quoted_double in sql:
        return sql.replace(quoted_double, f'"{escaped}"')
    return sql.replace(token, f"'{escaped}'")


def apply_sql_params(
    sql: str,
    start_date: str,
    end_date: str,
    extra: dict[str, str] | None = None,
) -> str:
    """Replace every ${...} placeholder with quoted literal values."""
    if not start_date or not end_date:
        raise SqlExecutionError("请先填写起止日期")

    placeholders = detect_dollar_params(sql)
    if not placeholders:
        return sql

    values = _resolve_param_values(start_date, end_date, extra)

    def lookup_value(name: str) -> str | None:
        if name in values and values[name]:
            return values[name]
        lower = name.lower()
        if lower in _START_DATE_ALIASES:
            return start_date
        if lower in _END_DATE_ALIASES:
            return end_date
        if lower in values and values[lower]:
            return values[lower]
        return None

    missing: list[str] = []
    result = sql
    for name in placeholders:
        val = lookup_value(name)
        if val is None:
            missing.append(name)
            continue
        result = _replace_one_placeholder(result, name, val)

    if missing:
        raise SqlExecutionError(
            f"以下占位符缺少替换值，请在前端填写: {', '.join(missing)}"
        )

    remaining = detect_dollar_params(result)
    if remaining:
        raise SqlExecutionError(
            f"仍有未替换的占位符: {', '.join(remaining)}"
        )
    return result


def apply_date_params(sql: str, start_date: str, end_date: str) -> str:
    """Backward-compatible wrapper."""
    return apply_sql_params(sql, start_date, end_date)


def format_doris_error(exc: Exception) -> str:
    """Turn low-level driver errors into actionable messages."""
    msg = str(exc)
    if "MEM_LIMIT_EXCEEDED" in msg or "memory not enough" in msg.lower():
        return (
            "Doris 集群内存不足，查询已被取消（连接正常，是 SQL 太「吃内存」或集群当前繁忙）。"
            "建议：缩小日期范围、增加 WHERE 过滤、减少大表 JOIN / GROUP BY / DISTINCT，"
            "或稍后再试；若在 Adhoc 上也跑不动，需联系 BDP 平台同学。"
        )
    if "Name or service not known" in msg or "Errno -2" in msg:
        return (
            f"无法解析 Doris 地址 {DORIS_HOST}。"
            "当前服务部署在腾讯云公网，访问不了瓜子内网域名。"
            "请在内网/VPN 环境运行，或在云托管环境变量里改成云端可达的 DORIS_HOST（IP 或专线地址）。"
        )
    if "timed out" in msg.lower() or "Timeout" in msg:
        return (
            f"连接 Doris 超时（{DORIS_HOST}:{DORIS_PORT}）。"
            "请确认云端网络能访问该地址，且安全组/防火墙已放行 9030 端口。"
        )
    if "Access denied" in msg or "1045" in msg:
        return "Doris 账号或密码错误，请重新登录后再试。"
    if "errCode" in msg or "detailMessage" in msg:
        return f"SQL 执行失败: {msg}"
    return f"连接 Doris 失败: {msg}"


def format_doris_connection_error(exc: Exception) -> str:
    """Backward-compatible alias."""
    return format_doris_error(exc)


def execute_query(user: str, password: str, sql: str) -> dict[str, Any]:
    assert_readonly_sql(sql)
    limited_sql = sql.rstrip().rstrip(";")
    if "limit" not in limited_sql.lower().split("union")[0]:
        limited_sql = f"{limited_sql}\nLIMIT {SQL_EXECUTE_MAX_ROWS + 1}"

    try:
        with doris_connection(user, password) as conn:
            with conn.cursor() as cursor:
                cursor.execute(limited_sql)
                rows = cursor.fetchall()
                columns = [desc[0] for desc in cursor.description] if cursor.description else []
    except pymysql.Error as exc:
        raise SqlExecutionError(format_doris_error(exc)) from exc

    truncated = len(rows) > SQL_EXECUTE_MAX_ROWS
    if truncated:
        rows = rows[:SQL_EXECUTE_MAX_ROWS]

    return {
        "columns": columns,
        "rows": [list(row.values()) for row in rows],
        "row_count": len(rows),
        "truncated": truncated,
    }
