"""Start the local Doris execution bridge on 127.0.0.1:8765."""

from __future__ import annotations

import os
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

import uvicorn  # noqa: E402


def main() -> None:
    port = int(os.getenv("LOCAL_BRIDGE_PORT", "8765"))
    print(f"Guazi SQL 本地 Doris 执行助手: http://127.0.0.1:{port}")
    print("保持此窗口运行；在 guazi_sql_agent 页面点击「运行」即可通过本机 VPN 查数。")
    uvicorn.run(
        "app.local_bridge.app:app",
        host="127.0.0.1",
        port=port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
