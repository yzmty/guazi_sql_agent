# Backend

Guazi SQL Data Agent 后端服务（FastAPI + SQLite）。

## 环境要求

- Python 3.11+

## 安装

```bash
cd backend
python -m venv .venv

# Windows
.venv\Scripts\activate

# macOS / Linux
source .venv/bin/activate

pip install -r requirements.txt
```

## 准备 SQL 文件

将 `.sql` 文件放入 `backend/sqls/` 目录。每个文件顶部需包含标准化注释块（见项目根 README）。

## 启动

```bash
cd backend
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API 文档：http://localhost:8000/docs

## 首次同步

启动后调用：

```bash
curl -X POST http://localhost:8000/api/sql-files/sync
```

或在 Web 页面点击「同步 SQL」。

## 目录说明

| 路径 | 说明 |
|------|------|
| `app/` | 应用代码 |
| `sqls/` | SQL 源文件目录 |
| `data/sql_agent.db` | SQLite 数据库（自动生成） |

## API 概览

### SQL 知识库

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/sql-files/sync` | 扫描并同步 SQL |
| GET | `/api/sql-files` | 搜索 / 列表 |
| GET | `/api/sql-files/{id}` | 详情 |
| GET | `/api/sql-files/filter-options` | 筛选项聚合 |

### AI Agent（V2）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/agent/chat` | 通用对话（自动识别模式） |
| POST | `/api/agent/explain` | 解释 SQL |
| POST | `/api/agent/recommend-similar` | 推荐相似 SQL |
| POST | `/api/agent/rewrite` | 改写 SQL（仅草稿） |

## LLM 配置

复制 `.env.example` 为 `.env` 并填写：

```env
LLM_BASE_URL=https://api.openai.com/v1
LLM_API_KEY=your-api-key
LLM_MODEL=gpt-4o-mini
```

健康检查 `GET /api/health` 返回 `llm_configured` 字段。
