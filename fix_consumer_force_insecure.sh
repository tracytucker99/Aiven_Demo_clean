#!/usr/bin/env bash
set -euo pipefail
cd /Users/tracyjenkins/aiven-clickstream-demo

# Force insecure mode in .env
if grep -q '^PG_SSL_INSECURE=' .env 2>/dev/null; then
  perl -i -pe 's/^PG_SSL_INSECURE=.*/PG_SSL_INSECURE=1/' .env
else
  echo 'PG_SSL_INSECURE=1' >> .env
fi

# Rewrite consumer: if insecure, strip sslmode/sslrootcert from PG_DSN and set rejectUnauthorized=false
cat > scripts/consume_sessionize.ts <<'TS'
import fs from "node:fs";
import { Kafka } from "kafkajs";
import { Pool } from "pg";

type ClickEvent = {
  ts: string;
  user_id: string;
  session_id: string;
  event_name: string;
  url?: string;
  referrer?: string;
  user_agent?: string;
  revenue?: number;
};

function parseBrokers(s: string) {
  return s
    .split(/[,\s]+/)
    .map((x) => x.trim())
    .filter(Boolean)
    .map((x) =>
      x
        .replace(/^kafka\+ssl:\/\//, "")
        .replace(/^ssl:\/\//, "")
        .replace(/^kafka:\/\//, "")
    );
}

function must(path: string, name: string) {
  if (!path) throw new Error(`${name} missing`);
  if (!fs.existsSync(path)) throw new Error(`Missing ${path}`);
}

function stripQueryParam(uri: string, key: string) {
  // remove key=... from query string (works for ?key= and &key=)
  const re = new RegExp(`([?&])${key}=[^&]+&?`, "g");
  let out = uri.replace(re, "$1");
  out = out.replace(/[?&]$/, "");
  out = out.replace(/\?&/, "?");
  return out;
}

const brokers = parseBrokers(
  (process.env.KAFKA_BROKERS || process.env.KAFKA_SERVICE_URI || "").trim()
);
if (!brokers.length) throw new Error("KAFKA_BROKERS (or KAFKA_SERVICE_URI) missing");

const topic = (process.env.KAFKA_TOPIC || "clickstream").trim();
const groupId = (process.env.KAFKA_GROUP_ID || "sessionizer").trim();

const caPath = (process.env.KAFKA_CA_CERT_PATH || "").trim();
const certPath = (process.env.KAFKA_ACCESS_CERT_PATH || "").trim();
const keyPath = (process.env.KAFKA_ACCESS_KEY_PATH || "").trim();

must(caPath, "KAFKA_CA_CERT_PATH");
must(certPath, "KAFKA_ACCESS_CERT_PATH");
must(keyPath, "KAFKA_ACCESS_KEY_PATH");

const pgDsnRaw = (process.env.PG_DSN || "").trim();
if (!pgDsnRaw) throw new Error("PG_DSN missing");

const insecurePg = (process.env.PG_SSL_INSECURE || "").trim() === "1";

// If insecure, strip sslmode/sslrootcert/etc from DSN so they can't override our ssl settings.
let pgDsn = pgDsnRaw;
if (insecurePg) {
  pgDsn = stripQueryParam(pgDsn, "sslmode");
  pgDsn = stripQueryParam(pgDsn, "sslrootcert");
  pgDsn = stripQueryParam(pgDsn, "sslcert");
  pgDsn = stripQueryParam(pgDsn, "sslkey");
}

const pool = new Pool({
  connectionString: pgDsn,
  ssl: {
    rejectUnauthorized: !insecurePg,
  },
});

const kafka = new Kafka({
  clientId: "clickstream-consumer",
  brokers,
  ssl: {
    ca: [fs.readFileSync(caPath)],
    cert: fs.readFileSync(certPath),
    key: fs.readFileSync(keyPath),
    rejectUnauthorized: true,
  },
});

async function postgresIdentityCheck() {
  const id = await pool.query(
    "select current_database() as db, current_user as usr, inet_server_addr() as host, inet_server_port() as port"
  );
  console.log("✅ postgres:", id.rows[0], insecurePg ? "(INSECURE TLS MODE)" : "");
}

async function upsertSession(session_id: string, user_id: string) {
  const q = `
    with s as (
      select
        $1::text as session_id,
        $2::text as user_id,
        min(ts) as session_start,
        max(ts) as session_end,
        count(*)::int as event_count,
        sum(case when event_name = 'page_view' then 1 else 0 end)::int as pageviews,
        sum(case when event_name = 'checkout' then 1 else 0 end)::int as conversions,
        coalesce(sum(coalesce(revenue,0)),0)::numeric(12,2) as revenue_total
      from clickstream_events
      where session_id = $1
    )
    insert into clickstream_sessions(
      session_id, user_id, session_start, session_end,
      event_count, pageviews, conversions, revenue_total, last_updated_at
    )
    select
      session_id, user_id, session_start, session_end,
      event_count, pageviews, conversions, revenue_total, now()
    from s
    on conflict (session_id) do update
      set session_end = excluded.session_end,
          event_count = excluded.event_count,
          pageviews = excluded.pageviews,
          conversions = excluded.conversions,
          revenue_total = excluded.revenue_total,
          last_updated_at = now();
  `;
  await pool.query(q, [session_id, user_id]);
}

(async () => {
  console.log(`Consuming topic=${topic} groupId=${groupId}`);
  console.log(`PG_SSL_INSECURE=${process.env.PG_SSL_INSECURE || ""}`);

  await postgresIdentityCheck();

  const consumer = kafka.consumer({ groupId });
  await consumer.connect();
  console.log("✅ connected to kafka");

  await consumer.subscribe({ topic, fromBeginning: false });
  console.log("✅ subscribed, waiting for messages…");

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) return;

      let evt: ClickEvent;
      try {
        evt = JSON.parse(message.value.toString("utf8"));
      } catch {
        console.error("Bad JSON message, skipping");
        return;
      }

      console.log("📩 kafka msg:", evt.event_name, evt.user_id, evt.session_id, evt.ts);

      await pool.query(
        `insert into clickstream_events(ts, user_id, session_id, event_name, url, referrer, user_agent, revenue)
         values ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [
          evt.ts,
          evt.user_id,
          evt.session_id,
          evt.event_name,
          evt.url ?? null,
          evt.referrer ?? null,
          evt.user_agent ?? null,
          evt.revenue ?? null,
        ]
      );

      await upsertSession(evt.session_id, evt.user_id);
      process.stdout.write("+");
    },
  });

  await new Promise(() => {});
})().catch((e) => {
  console.error("Consumer failed:", e?.message || e);
  console.error(e);
  process.exit(1);
});
TS

echo "✅ Forced PG_SSL_INSECURE=1 and rewrote consumer to strip ssl params from PG_DSN"
