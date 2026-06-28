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
  if (start < 0 || end <= start) return null;
  return JSON.parse(out.slice(start, end + 1));
}

const envId = "yzmty-d5gqs0ufzac842072";
const serverName = "guazi-sql-agent";

const actions = [
  ["DescribeCloudRunDeployRecord", { EnvId: envId, ServerName: serverName, Limit: 5, Offset: 0 }],
  ["DescribeCloudRunReleaseOrderDetail", { EnvId: envId, ServerName: serverName }],
];

for (const [action, body] of actions) {
  console.log(`\n=== ${action} ===`);
  console.log(JSON.stringify(api(action, body), null, 2));
}
