const { execSync } = require("child_process");

function api(action, body) {
  const out = execSync(
    `cloudbase api tcbr ${action} --api-version 2022-02-17 --body ${JSON.stringify(JSON.stringify(body))} --json`,
    { encoding: "utf8" },
  );
  const start = out.indexOf("{");
  return JSON.parse(out.slice(start));
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function main() {
  const base = "https://guazi-sql-agent-273429-4-1325615965.sh.run.tcloudbase.com";
  for (let i = 1; i <= 25; i++) {
    const records = api("DescribeCloudRunDeployRecord", {
      EnvId: "yzmty-d5gqs0ufzac842072",
      ServerName: "guazi-sql-agent",
    });
    const last = records.data.DeployRecords.slice(-1)[0];
    console.log(`poll ${i}: ${last.DeployId} ${last.Status} flow=${last.FlowRatio}`);
    if (last.Status === "normal" && last.FlowRatio === 100 && last.DeployId >= "042") {
      console.log("SUCCESS");
      try {
        const resp = await fetch(`${base}/api/health`);
        const text = await resp.text();
        console.log("health:", text.slice(0, 400));
        const shared = await fetch(`${base}/api/shared-group/status`);
        console.log("shared-group status:", shared.status, await shared.text());
      } catch (e) {
        console.log("probe error", e.message);
      }
      return;
    }
    if (last.Status === "build_failed" || last.Status === "deploy_failed") {
      console.log("FAILED", JSON.stringify(last, null, 2));
      process.exit(1);
    }
    await sleep(45000);
  }
  console.log("TIMEOUT waiting for deploy");
  process.exit(2);
}

main();
