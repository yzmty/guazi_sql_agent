@echo off
chcp 65001 >nul
title Guazi SQL Doris 助手
cd /d "%~dp0"

where python >nul 2>&1
if errorlevel 1 (
  echo [错误] 未找到 Python，请先安装 Python 3.10+ 并勾选 Add to PATH
  echo 下载: https://www.python.org/downloads/
  pause
  exit /b 1
)

if not exist "backend\.venv\Scripts\python.exe" (
  echo 首次运行，正在安装依赖（约 1 分钟）...
  python -m venv backend\.venv
  if errorlevel 1 (
    echo [错误] 创建虚拟环境失败
    pause
    exit /b 1
  )
  backend\.venv\Scripts\python.exe -m pip install -q -r backend\requirements.txt
  if errorlevel 1 (
    echo [错误] 安装依赖失败
    pause
    exit /b 1
  )
  echo 依赖安装完成。
)

echo.
echo ========================================
echo   Guazi SQL 本地 Doris 助手
echo   请保持本窗口打开，并连接公司 VPN
echo   然后在网页登录并运行 SQL 即可
echo ========================================
echo.

backend\.venv\Scripts\python.exe backend\scripts\run_local_bridge.py
pause
