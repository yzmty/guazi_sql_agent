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

const detail = api("DescribeCloudRunServerDetail", {
  EnvId: "yzmty-d5gqs0ufzac842072",
  ServerName: "guazi-sql-agent",
});
const env = JSON.parse(detail.data?.ServerConfig?.EnvParams || "{}");
const key = env.LLM_API_KEY || "";
console.log("LLM_API_KEY length:", key.length);
console.log("LLM_API_KEY suffix:", key.slice(-4));
console.log("LLM_BASE_URL:", env.LLM_BASE_URL);
console.log("LLM_MODEL:", env.LLM_MODEL);
