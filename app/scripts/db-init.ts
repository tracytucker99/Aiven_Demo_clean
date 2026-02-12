import "dotenv/config";
import fs from "node:fs";
import { Client } from "pg";

const dsnRaw = process.env.PG_DSN || "";
// Match pg-smoke: strip query params entirely so DSN sslmode/etc can't interfere
const dsn = dsnRaw.replace(/\?.*$/, "");

const caPath = process.env.PG_CA_PATH || "./pg-ca.pem";
const ca = fs.readFileSync(caPath, "utf8");

async function main() {
  if (!dsn) throw new Error("PG_DSN missing");

  const client = new Client({
    connectionString: dsn,
    ssl: { ca, rejectUnauthorized: true },
  });

  await client.connect();

  await client.query(`
    create table if not exists clickstream_events (
      event_id text primary key,
      ts timestamptz not null,
      user_id text not null,
      session_hint int,
      page text,
      referrer text,
      device text,
      raw jsonb not null,
      ingested_at timestamptz not null default now()
    );
  `);

  await client.query(`
    create index if not exists clickstream_events_user_ts
    on clickstream_events (user_id, ts desc);
  `);

  await client.query(`
    create table if not exists clickstream_sessions (
      session_id text primary key,
      user_id text not null,
      session_start timestamptz not null,
      session_end timestamptz not null,
      event_count int not null,
      pageviews int not null,
      last_page text,
      updated_at timestamptz not null default now()
    );
  `);

  await client.query(`
    create index if not exists clickstream_sessions_user_start
    on clickstream_sessions (user_id, session_start desc);
  `);

  await client.end();
  console.log("✅ DB initialized: clickstream_events, clickstream_sessions");
}

main().catch((e) => {
  console.error("❌ db:init failed:", e?.message || e);
  process.exit(1);
});
