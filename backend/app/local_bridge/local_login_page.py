"""Standalone local login form — avoids HTTPS page calling localhost."""

from __future__ import annotations

from urllib.parse import quote

DEFAULT_CLOUD_LOGIN = (
    "https://guazi-sql-agent-273429-4-1325615965.sh.run.tcloudbase.com/"
)


def render_local_login_page(return_url: str) -> str:
    safe_return = quote(return_url, safe="")
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Guazi Doris 本地登录</title>
  <style>
    body {{ font-family: "Segoe UI", sans-serif; max-width: 420px; margin: 48px auto; padding: 0 16px; color: #222; }}
    h1 {{ font-size: 20px; margin-bottom: 8px; }}
    p {{ color: #666; line-height: 1.5; }}
    label {{ display: block; margin-top: 16px; font-weight: 600; }}
    input {{ width: 100%; box-sizing: border-box; margin-top: 6px; padding: 10px; font-size: 14px; }}
    button {{ margin-top: 20px; width: 100%; padding: 12px; font-size: 15px; cursor: pointer; }}
    .err {{ color: #cf1322; margin-top: 12px; white-space: pre-wrap; }}
  </style>
</head>
<body>
  <h1>Guazi SQL 本地登录验证</h1>
  <p>请使用 Adhoc 查数密码。账号可填 <b>zhangsan@guazi.com</b> 或 <b>zhangsan</b>（系统自动去掉邮箱后缀连 Doris）。</p>
  <form method="post" action="/login">
    <input type="hidden" name="return_url" value="{safe_return}" />
    <label>账号</label>
    <input name="user" type="text" required placeholder="zhangsan 或 zhangsan@guazi.com" autocomplete="username" />
    <label>密码（Adhoc 查数密码）</label>
    <input name="password" type="password" required autocomplete="current-password" />
    <button type="submit">验证并返回网页登录</button>
  </form>
  <p id="err" class="err"></p>
  <script>
    const params = new URLSearchParams(location.search);
    const err = params.get('error');
    if (err) document.getElementById('err').textContent = decodeURIComponent(err);
  </script>
</body>
</html>
"""


def is_allowed_return_url(url: str) -> bool:
    url = (url or "").strip()
    if not url:
        return False
    allowed_prefixes = (
        "https://guazi-sql-agent-",
        "http://localhost:5173/",
        "http://127.0.0.1:5173/",
    )
    return url.startswith(allowed_prefixes)
