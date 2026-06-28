LOGIN_BRIDGE_HTML = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <title>Guazi Doris 登录验证</title>
  <style>
    body { font-family: sans-serif; padding: 24px; color: #333; }
    .err { color: #cf1322; white-space: pre-wrap; }
  </style>
</head>
<body>
  <p id="msg">正在通过本地助手验证 Doris 账号…</p>
  <script>
    const params = new URLSearchParams(location.search);
    const parentOrigin = params.get('parent') || '*';
    const bridgeOrigin = location.origin;

    function notify(type, payload) {
      if (window.opener) {
        window.opener.postMessage(Object.assign({ type }, payload || {}), parentOrigin);
      }
    }

    window.addEventListener('message', async (event) => {
      if (event.origin !== parentOrigin && parentOrigin !== '*') return;
      if (!event.data || event.data.type !== 'verify') return;
      const msg = document.getElementById('msg');
      try {
        const res = await fetch('/credentials/login-proof', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ user: event.data.user, password: event.data.password }),
        });
        const body = await res.json().catch(() => ({}));
        if (!res.ok) {
          throw new Error(body.detail || 'Doris 验证失败');
        }
        notify('bridge-proof', { proof: body.proof });
        msg.textContent = '验证成功，正在返回登录页…';
        setTimeout(() => window.close(), 500);
      } catch (err) {
        msg.innerHTML = '<span class="err">' + (err.message || err) + '</span>';
        notify('bridge-error', { detail: err.message || String(err) });
      }
    });

    notify('bridge-ready');
  </script>
</body>
</html>
"""
