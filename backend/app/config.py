"""Application configuration."""

import os
from pathlib import Path

from dotenv import load_dotenv

BACKEND_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(BACKEND_ROOT / ".env")

SQLS_DIR = BACKEND_ROOT / "sqls"

# 持久化存储：云托管容器本地磁盘会在重启/缩容/重新部署后清空，生产环境请挂载 COS/CFS 到 DATA_DIR，
# 或使用 DATABASE_URL 连接 MySQL。
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
_data_dir = os.getenv("DATA_DIR", "").strip()
DATA_DIR = Path(_data_dir) if _data_dir else BACKEND_ROOT / "data"
DATABASE_PATH = DATA_DIR / "sql_agent.db"

if DATABASE_URL:
    SQLALCHEMY_DATABASE_URL = DATABASE_URL
else:
    SQLALCHEMY_DATABASE_URL = f"sqlite:///{DATABASE_PATH.as_posix()}"

CORS_ORIGINS = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]

_tcb_url = os.getenv("TCB_SERVICE_URL", "").rstrip("/")
if _tcb_url:
    CORS_ORIGINS.append(_tcb_url)

# Auth / session
JWT_SECRET = os.getenv("JWT_SECRET", "guazi-sql-agent-dev-secret-change-me")
SESSION_TTL_HOURS = int(os.getenv("SESSION_TTL_HOURS", "24"))
SUPER_ADMIN_EMAIL = os.getenv("SUPER_ADMIN_EMAIL", "yangyuefang@guazi.com").lower()
SUPER_ADMIN_PASSWORD = os.getenv("SUPER_ADMIN_PASSWORD", "Yyf010103")

# Local bridge login proof (must match bridge/config.py default)
LOCAL_BRIDGE_LOGIN_SECRET = os.getenv(
    "LOCAL_BRIDGE_LOGIN_SECRET", "guazi-sql-local-bridge-login-v1"
)

# Doris (Adhoc) — used for login validation and SQL execution
DORIS_HOST = os.getenv("DORIS_HOST", "doris-adhoc.dns.guazi.com")
DORIS_PORT = int(os.getenv("DORIS_PORT", "9030"))
DORIS_DATABASE = os.getenv("DORIS_DATABASE", "hive.mysql")
DORIS_FALLBACK_USER = os.getenv("ONLINE_DASHBOARD_DORIS_USER", "")
DORIS_FALLBACK_PASSWORD = os.getenv("ONLINE_DASHBOARD_DORIS_PASSWORD", "")

# SQL execution limits
SQL_EXECUTE_MAX_ROWS = int(os.getenv("SQL_EXECUTE_MAX_ROWS", "1000"))
SQL_EXECUTE_TIMEOUT = int(os.getenv("SQL_EXECUTE_TIMEOUT", "120"))

# LLM settings
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://api.deepseek.com")
LLM_API_KEY = os.getenv("LLM_API_KEY", "")
LLM_MODEL = os.getenv("LLM_MODEL", "deepseek-chat")
LLM_TIMEOUT = int(os.getenv("LLM_TIMEOUT", "60"))

AGENT_CANDIDATE_TOP_K = int(os.getenv("AGENT_CANDIDATE_TOP_K", "15"))
AGENT_RESULT_TOP_N = int(os.getenv("AGENT_RESULT_TOP_N", "5"))
CROSS_SQL_CANDIDATE_TOP_N = int(os.getenv("CROSS_SQL_CANDIDATE_TOP_N", "5"))

# CloudBase 对象存储备份 SQLite（无需控制台「存储挂载」）
COS_DB_BACKUP = os.getenv("COS_DB_BACKUP", "false").lower() == "true"
COS_BUCKET = os.getenv("COS_BUCKET", "").strip()
COS_REGION = os.getenv("COS_REGION", "ap-shanghai").strip()
COS_DB_KEY = os.getenv("COS_DB_KEY", "sql-agent-data/sql_agent.db").strip()
COS_SECRET_ID = os.getenv("COS_SECRET_ID", os.getenv("TENCENTCLOUD_SECRETID", "")).strip()
COS_SECRET_KEY = os.getenv(
    "COS_SECRET_KEY", os.getenv("TENCENTCLOUD_SECRETKEY", "")
).strip()

# Vector / semantic search
VECTOR_STORE_TYPE = os.getenv("VECTOR_STORE_TYPE", "sqlite").strip().lower()
CHROMA_PERSIST_DIR = Path(
    os.getenv("CHROMA_PERSIST_DIR", str(DATA_DIR / "chroma"))
)
# fastembed = local BAAI/bge-small-zh (default; DeepSeek API has no embedding endpoint)
# api = OpenAI-compatible /embeddings (set EMBEDDING_MODEL to a real embedding model)
EMBEDDING_PROVIDER = os.getenv("EMBEDDING_PROVIDER", "fastembed").strip().lower()
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small").strip()
EMBEDDING_DIM = int(os.getenv("EMBEDDING_DIM", "1536"))
EMBEDDING_BATCH_SIZE = int(os.getenv("EMBEDDING_BATCH_SIZE", "16"))
EMBEDDING_USE_FASTEMBED_FALLBACK = (
    os.getenv("EMBEDDING_USE_FASTEMBED_FALLBACK", "true").lower() == "true"
)

# Indexing worker
INDEXING_WORKER_ENABLED = os.getenv("INDEXING_WORKER_ENABLED", "true").lower() == "true"
INDEXING_WORKER_INTERVAL_SEC = float(os.getenv("INDEXING_WORKER_INTERVAL_SEC", "2"))
INDEXING_WORKER_BATCH_SIZE = int(os.getenv("INDEXING_WORKER_BATCH_SIZE", "5"))
INDEXING_DEBOUNCE_SEC = int(os.getenv("INDEXING_DEBOUNCE_SEC", "5"))

# COS backup scheduler — index jobs schedule instead of uploading every SQL file
COS_BACKUP_INTERVAL_SEC = float(os.getenv("COS_BACKUP_INTERVAL_SEC", "45"))

# Tencent VectorDB (optional production backend)
TENCENT_VECTORDB_URL = os.getenv("TENCENT_VECTORDB_URL", "").strip()
TENCENT_VECTORDB_KEY = os.getenv("TENCENT_VECTORDB_KEY", "").strip()
TENCENT_VECTORDB_DATABASE = os.getenv("TENCENT_VECTORDB_DATABASE", "guazi_sql_agent").strip()
TENCENT_VECTORDB_COLLECTION = os.getenv("TENCENT_VECTORDB_COLLECTION", "sql_chunks").strip()

# LangChain agent
AGENT_CONVERSATION_HISTORY_LIMIT = int(os.getenv("AGENT_CONVERSATION_HISTORY_LIMIT", "20"))
