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

const result = api("DescribeCloudRunBuildLog", {
  EnvId: "yzmty-d5gqs0ufzac842072",
  ServerName: "guazi-sql-agent",
  BuildId: 2601219156,
});

const logs = result?.data?.Logs || result?.data?.BuildLog || result?.data?.Log || "";
if (typeof logs === "string") {
  console.log(logs.slice(-12000));
} else {
  console.log(JSON.stringify(result, null, 2).slice(-12000));
}
