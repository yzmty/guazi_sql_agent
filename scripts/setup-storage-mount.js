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
    if (!out.includes("{")) throw err;
  }
  const start = out.indexOf("{");
  const end = out.lastIndexOf("}");
  const parsed = JSON.parse(out.slice(start, end + 1));
  if (parsed.error) throw new Error(JSON.stringify(parsed.error));
  return parsed;
}

const envId = "yzmty-d5gqs0ufzac842072";
const serverName = "guazi-sql-agent";
const bucket = "797a-yzmty-d5gqs0ufzac842072-1325615965";

const detail = api("DescribeCloudRunServerDetail", { EnvId: envId, ServerName: serverName });
const imageUrl = detail.data?.OnlineVersionInfos?.[0]?.ImageUrl;
const prev = detail.data?.ServerConfig;
if (!imageUrl || !prev) {
  console.error("Missing server detail", detail);
  process.exit(1);
}

const envParams = JSON.parse(prev.EnvParams || "{}");
envParams.COS_VOLUME_MOUNTED = "true";
envParams.DATA_DIR = "/app/data";
envParams.COS_DB_BACKUP = "true";
envParams.COS_BUCKET = bucket;
envParams.COS_REGION = "ap-shanghai";

const payload = {
  EnvId: envId,
  ServerName: serverName,
  Business: "tcb",
  DeployInfo: {
    DeployType: "image",
    ImageUrl: imageUrl,
    ReleaseType: "FULL",
  },
  Items: [
    {
      Key: "VolumesConf",
      VolumesConf: [
        {
          Type: "COS",
          BucketName: bucket,
          Endpoint: "https://cos.ap-shanghai.myqcloud.com",
          DstPath: "/app/data",
          SrcPath: "/sql-agent-data",
          ReadOnly: false,
        },
      ],
    },
    { Key: "EnvParam", Value: JSON.stringify(envParams) },
    { Key: "MinNum", IntValue: 1 },
    { Key: "MaxNum", IntValue: 1 },
  ],
};

console.log("Mount COS /sql-agent-data -> /app/data");
console.log("Image:", imageUrl);
const res = api("UpdateCloudRunServer", payload);
console.log(JSON.stringify(res, null, 2));
