const { execSync } = require("child_process");

function api(action, body) {
  const out = execSync(
    `cloudbase api tcbr ${action} --api-version 2022-02-17 --body ${JSON.stringify(JSON.stringify(body))} --json`,
    { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 },
  );
  const start = out.indexOf("{");
  const end = out.lastIndexOf("}");
  return JSON.parse(out.slice(start, end + 1));
}

const envId = "yzmty-d5gqs0ufzac842072";
const serverName = "guazi-sql-agent";

const build = api("DescribeCloudRunBuildLog", {
  EnvId: envId,
  ServerName: serverName,
  BuildId: 2601219156,
  Offset: 0,
  Limit: 200,
});
console.log("=== BUILD LOG (040) tail ===");
const buildLogs = build?.data?.Logs || build?.data?.BuildLogList || [];
for (const line of (Array.isArray(buildLogs) ? buildLogs : [buildLogs]).slice(-30)) {
  console.log(typeof line === "string" ? line : JSON.stringify(line));
}

const records = api("DescribeCloudRunDeployRecord", { EnvId: envId, ServerName: serverName });
const latest = records?.data?.DeployRecords?.slice(-1)[0];
console.log("\n=== LATEST DEPLOY ===");
console.log(JSON.stringify(latest, null, 2));

if (latest?.BuildId) {
  const b2 = api("DescribeCloudRunBuildLog", {
    EnvId: envId,
    ServerName: serverName,
    BuildId: latest.BuildId,
    Offset: 0,
    Limit: 200,
  });
  console.log("\n=== BUILD LOG (latest) tail ===");
  const logs2 = b2?.data?.Logs || b2?.data?.BuildLogList || [];
  for (const line of (Array.isArray(logs2) ? logs2 : [logs2]).slice(-20)) {
    console.log(typeof line === "string" ? line : JSON.stringify(line));
  }
}

try {
  const detail = api("DescribeCloudRunServerDetail", { EnvId: envId, ServerName: serverName });
  console.log("\n=== SERVER DETAIL (partial) ===");
  console.log(JSON.stringify({
    OnlineVersionInfos: detail?.data?.OnlineVersionInfos,
    LastDeploy: detail?.data?.LastDeploy,
    Status: detail?.data?.Status,
  }, null, 2));
} catch (e) {
  console.log("detail error", e.message);
}
