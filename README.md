# Guazi Personal SQL Data Agent

瓜子二手车商业分析个人 SQL / 指标知识库工作台（V2）。

本地 Web 应用：统一管理 SQL 知识库 + AI Agent 自然语言对话。

## 功能

### V1 基础能力
- 扫描 `backend/sqls/` 中的 `.sql` 文件并解析注释块
- 关键词搜索 + 业务/标签/核心表/作者筛选
- 三栏工作台：SQL 列表 | SQL 详情 | AI Agent 面板
- SQL 语法高亮与一键复制

### V2 AI Agent 能力
| 模式 | 说明 |
|------|------|
| **找 SQL** | 自然语言搜索，如「找 C2C 成交价格相关 SQL」 |
| **解释 SQL** | 结构化解释用途、指标、维度、逻辑、适用问题 |
| **推荐相似 SQL** | 基于元数据规则召回 + LLM 重排 |
| **改写 SQL** | 生成 SQL 草稿，**绝不覆盖原文件** |

## 技术栈

| 层 | 技术 |
|----|------|
| 后端 | Python 3.11+, FastAPI, SQLAlchemy, SQLite, httpx |
| 前端 | React, Vite, TypeScript, Ant Design |
| LLM | OpenAI 兼容接口（可选，未配置时使用本地检索兜底） |

## 快速开始

### 1. 配置 DeepSeek 大模型（免费额度）

1. 打开 https://platform.deepseek.com 注册并创建 API Key  
2. 复制配置：

```bash
cd backend
copy .env.example .env   # Windows
```

3. 编辑 `backend/.env`，填入 Key：

```env
LLM_BASE_URL=https://api.deepseek.com
LLM_API_KEY=sk-你的DeepSeek密钥
LLM_MODEL=deepseek-chat
```

`deepseek-chat` 为 DeepSeek-V3 对话模型（平台提供免费额度）。复杂分析可改用 `deepseek-reasoner`。

### 2. 启动后端

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 3. 启动前端

```bash
cd frontend
npm install
npm run dev
```

浏览器打开 http://localhost:5173

### 4. 首次同步

点击 **「同步 SQL」** 导入 `backend/sqls/` 中的文件。

## Agent 使用示例

1. **找 SQL**：在右侧 Agent 输入「找魔方计划相关 SQL」
2. **解释 SQL**：选中一条 SQL → 点击「解释 SQL」或 Agent 快捷按钮
3. **推荐相似**：选中 SQL → 点击「推荐相似 SQL」
4. **改写 SQL**：选中 SQL → 输入「把这个 SQL 改成最近30天」→ 获得草稿（不覆盖原文件）

## 项目结构

```text
guazi_sql_agent/
├─ backend/
│  ├─ app/services/
│  │  ├─ agent_service.py      # Agent 总入口
│  │  ├─ llm_service.py        # LLM 调用
│  │  ├─ retrieval_service.py  # 候选召回
│  │  └─ prompt_service.py     # Prompt 构建
│  ├─ sqls/
│  └─ .env.example
├─ frontend/src/components/agent/
│  ├─ AgentPanel.tsx
│  ├─ ChatMessage.tsx
│  └─ ...
└─ README.md
```

## 安全说明

- AI 改写的 SQL **仅展示在会话中**，不会写入数据库或 `sqls/` 目录
- V2 不执行 SQL，不自动修改文件系统

## 部署到腾讯云 CloudBase

环境 ID：`yzmty-d5gqs0ufzac842072`

**公网访问地址（前后端一体）：**

https://guazi-sql-agent-273429-4-1325615965.sh.run.tcloudbase.com

本地重新部署：

```bash
npm install -g @cloudbase/cli
cloudbase login
echo n | cloudbase cloudrun deploy -e yzmty-d5gqs0ufzac842072 -s guazi-sql-agent --port 8000 --force
```

### 配置 AI Agent（DeepSeek）

CloudBase 控制台 → 云托管 → `guazi-sql-agent` → 服务设置 → 环境变量，添加：

| 变量 | 值 |
|------|-----|
| `LLM_API_KEY` | 你的 DeepSeek API Key |
| `LLM_BASE_URL` | `https://api.deepseek.com` |
| `LLM_MODEL` | `deepseek-chat` |

保存后服务会自动滚动更新。未配置 Key 时，SQL 检索/列表仍可用，Agent 对话功能受限。

### 说明

- 默认域名仅供开发测试，首次浏览器访问可能出现 CloudBase 提示中间页，点继续即可
- 生产环境建议绑定已备案自定义域名

---

## 安全提示

- **切勿**将腾讯云密码、DeepSeek API Key 提交到 Git 或写入代码
- 仅在 CloudBase 控制台配置敏感环境变量
