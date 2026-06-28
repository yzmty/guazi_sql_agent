# 启动本地 Doris 执行助手（需 VPN 连接瓜子内网）
$ErrorActionPreference = "Stop"
$Backend = Join-Path $PSScriptRoot "..\backend"
Set-Location $Backend

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "未找到 python，请先安装 Python 3.10+"
}

python scripts/run_local_bridge.py
