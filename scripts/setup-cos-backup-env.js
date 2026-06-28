const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

function loadBackendEnv() {
  const envPath = path.join(__dirname, "..", "backend", ".env");
  if (!fs.existsSync(envPath)) return {};
  const out = {};
  for (const line of fs.readFileSync(envPath, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx <= 0) continue;
    out[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
  }
  return out;
}

function api(action, body) {
  let out;
  try {
    out = execSync(
      `cloudbase api tcbr ${action} --api-version 2022-02-17 --body ${JSON.stringify(JSON.stringify(body))} --json`,
      { encoding: "utf8" },
    );
  } catch (err) {
    out = [err.stdout, err.stderr].filter(Boolean).join("\n");
    if (!out.includes("{")) throw err;
  }
  const start = out.indexOf("{");
  const end = out.lastIndexOf("}");
  if (start < 0 || end <= start) {
    throw new Error(`Unexpected API output:\n${out}`);
  }
  const parsed = JSON.parse(out.slice(start, end + 1));
  if (parsed.error) {
    const e = new Error(JSON.stringify(parsed.error));
    e.code = parsed.error.code;
    throw e;
  }
  return parsed;
}

function mergeEnvParams(currentJson, updates) {
  const current = currentJson ? JSON.parse(currentJson) : {};
  return JSON.stringify({ ...current, ...updates });
}

const localEnv = loadBackendEnv();
const envId = "yzmty-d5gqs0ufzac842072";
const serverName = "guazi-sql-agent";

const detail = api("DescribeCloudRunServerDetail", { EnvId: envId, ServerName: serverName });
const prev = detail.data?.ServerConfig;
if (!prev) {
  console.error("Could not resolve server config", detail);
  process.exit(1);
}

const envUpdates = {
  SERVE_STATIC: "true",
  AUTO_SYNC_SQL: "false",
  DATA_DIR: "/app/data",
  COS_DB_BACKUP: "true",
  COS_BUCKET: "797a-yzmty-d5gqs0ufzac842072-1325615965",
  COS_REGION: "ap-shanghai",
  // SQL + vector_chunks 同库；索引完成后批量 COS 备份（见 COS_BACKUP_INTERVAL_SEC）
  VECTOR_STORE_TYPE: "sqlite",
  INDEXING_WORKER_ENABLED: "true",
  INDEXING_WORKER_BATCH_SIZE: "5",
  EMBEDDING_PROVIDER: "fastembed",
  EMBEDDING_USE_FASTEMBED_FALLBACK: "true",
  COS_BACKUP_INTERVAL_SEC: "45",
  LLM_BASE_URL: localEnv.LLM_BASE_URL || process.env.LLM_BASE_URL || "https://api.deepseek.com",
  LLM_API_KEY: localEnv.LLM_API_KEY || process.env.LLM_API_KEY || "",
  LLM_MODEL: localEnv.LLM_MODEL || process.env.LLM_MODEL || "deepseek-chat",
  LLM_TIMEOUT: localEnv.LLM_TIMEOUT || "90",
  EMBEDDING_MODEL: localEnv.EMBEDDING_MODEL || "text-embedding-3-small",
  COS_SECRET_ID: localEnv.COS_SECRET_ID || process.env.COS_SECRET_ID || "",
  COS_SECRET_KEY: localEnv.COS_SECRET_KEY || process.env.COS_SECRET_KEY || "",
  COS_STARTUP_RESTORE_ATTEMPTS: "3",
  COS_CREDENTIAL_RETRY_ATTEMPTS: "15",
};

if (!envUpdates.LLM_API_KEY) {
  console.warn("WARN: LLM_API_KEY is empty — set it in backend/.env before running this script");
}

const serverBaseConfig = {
  EnvId: envId,
  ServerName: serverName,
  OpenAccessTypes: prev.OpenAccessTypes,
  Cpu: prev.Cpu,
  Mem: prev.Mem,
  MinNum: prev.MinNum,
  MaxNum: prev.MaxNum,
  PolicyDetails: prev.PolicyDetails,
  CustomLogs: prev.CustomLogs,
  EnvParams: mergeEnvParams(prev.EnvParams, envUpdates),
  InitialDelaySeconds: 120,
  CreateTime: prev.CreateTime,
  Port: prev.Port,
  HasDockerfile: true,
  Dockerfile: prev.Dockerfile,
  BuildDir: prev.BuildDir,
};

console.log(
  "Env updates:",
  JSON.stringify(
    {
      ...envUpdates,
      LLM_API_KEY: envUpdates.LLM_API_KEY ? "***" : "",
      COS_SECRET_ID: envUpdates.COS_SECRET_ID ? "***" : "",
      COS_SECRET_KEY: envUpdates.COS_SECRET_KEY ? "***" : "",
    },
    null,
    2,
  ),
);

const res = api("UpdateCloudRunServerConfig", {
  EnvId: envId,
  ServerBaseConfig: serverBaseConfig,
});
console.log(JSON.stringify(res, null, 2));
