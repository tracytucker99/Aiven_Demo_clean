import "dotenv/config";
import fs from "node:fs";
import { Client } from "pg";

export function makePgClient(): Client {
  const dsnRaw = process.env.PG_DSN || "";
  const dsn = dsnRaw.replace(/\?.*$/, ""); // strip params to avoid sslmode conflicts

  if (!dsn) throw new Error("PG_DSN missing");

  const caPath = process.env.PG_CA_PATH || "./pg-ca.pem";
  const ca = fs.readFileSync(caPath, "utf8");

  return new Client({
    connectionString: dsn,
    ssl: { ca, rejectUnauthorized: true },
  });
}
