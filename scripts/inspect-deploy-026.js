const { execSync } = require("child_process");

function api(action, body) {
  let out;
  try {
    out = execSync(
      `cloudbase api tcbr ${action} --api-version 2022-02-17 --body ${JSON.stringify(JSON.stringify(body))} --json`,
      { encoding: "utf8" },
    );
  } catch (err) {
    out = [err.stdout, err.stderr].filter(Boolean).join("\n");
  }
  const start = out.indexOf("{");
  const end = out.lastIndexOf("}");
  if (start < 0 || end <= start) {
    console.log(out);
    return null;
  }
  return JSON.parse(out.slice(start, end + 1));
}

const envId = "yzmty-d5gqs0ufzac842072";
const serverName = "guazi-sql-agent";

for (const action of [
  "DescribeCloudRunServerDetail",
  "DescribeCloudRunVersionDetail",
  "DescribeCloudRunDeployRecord",
]) {
  console.log(`\n=== ${action} ===`);
  const body =
    action === "DescribeCloudRunServerDetail"
      ? { EnvId: envId, ServerName: serverName }
      : { EnvId: envId, ServerName: serverName, VersionName: "guazi-sql-agent-026" };
  const res = api(action, body);
  console.log(JSON.stringify(res, null, 2));
}
