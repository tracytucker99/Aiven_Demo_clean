import "dotenv/config";
import fs from "node:fs";
import { Client } from "pg";

const dsnRaw = process.env.PG_DSN || "";
const dsn = dsnRaw.replace(/\?.*$/, "");
const caPath = process.env.PG_CA_PATH || "./pg-ca.pem";
const ca = fs.readFileSync(caPath, "utf8");

async function main() {
  if (!dsn) throw new Error("PG_DSN missing");
  const client = new Client({
    connectionString: dsn,
    ssl: { ca, rejectUnauthorized: true }
  });
  await client.connect();
  const r = await client.query("select now() as now");
  console.log("PG OK:", r.rows[0].now);
  await client.end();
}

main().catch((e) => {
  console.error("PG FAIL:", e?.message || e);
  process.exit(1);
});
