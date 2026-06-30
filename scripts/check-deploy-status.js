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

const records = api("DescribeCloudRunDeployRecord", {
  EnvId: envId,
  ServerName: serverName,
});

console.log(JSON.stringify(records, null, 2));
