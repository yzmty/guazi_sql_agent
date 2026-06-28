const { execSync } = require("child_process");

function api(action, body) {
  const out = execSync(
    `cloudbase api tcbr ${action} --api-version 2022-02-17 --body ${JSON.stringify(JSON.stringify(body))} --json`,
    { encoding: "utf8" },
  );
  const start = out.indexOf("{");
  const end = out.lastIndexOf("}");
  return JSON.parse(out.slice(start, end + 1));
}

const envId = "yzmty-d5gqs0ufzac842072";
const serverName = "guazi-sql-agent";

const detail = api("DescribeCloudRunServerDetail", { EnvId: envId, ServerName: serverName });
const cfg = detail.data?.ServerConfig || {};
const env = cfg.EnvParams ? JSON.parse(cfg.EnvParams) : {};

console.log("=== Online Versions ===");
for (const v of detail.data?.OnlineVersionInfos || []) {
  console.log(`- ${v.VersionName} traffic=${v.FlowRatio}%`);
}

console.log("\n=== Cloud Run Resource ===");
console.log("Cpu:", cfg.Cpu);
console.log("Mem:", cfg.Mem);
console.log("InitialDelaySeconds:", cfg.InitialDelaySeconds);
console.log("MinNum:", cfg.MinNum, "MaxNum:", cfg.MaxNum);

console.log("\n=== Indexing / Embedding Env ===");
for (const k of [
  "EMBEDDING_PROVIDER",
  "EMBEDDING_MODEL",
  "EMBEDDING_USE_FASTEMBED_FALLBACK",
  "INDEXING_WORKER_BATCH_SIZE",
  "INDEXING_WORKER_INTERVAL_SEC",
  "COS_BACKUP_INTERVAL_SEC",
  "VECTOR_STORE_TYPE",
]) {
  console.log(`${k}:`, env[k] ?? "(unset)");
}
