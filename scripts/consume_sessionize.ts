import fs from "node:fs";
import path from "node:path";
import os from "node:os";
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

function expandHome(p: string) {
  if (!p) return p;
  if (p === "~") return os.homedir();
  if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2));
  return p;
}

function mustFile(p: string, name: string) {
  if (!p) throw new Error(`${name} missing`);
  if (!fs.existsSync(p)) throw new Error(`Missing ${name} file: ${p}`);
}

const brokers = parseBrokers(
  (process.env.KAFKA_BROKERS || process.env.KAFKA_SERVICE_URI || "").trim()
);
if (!brokers.length) throw new Error("KAFKA_BROKERS (or KAFKA_SERVICE_URI) missing");

const topic = (process.env.KAFKA_TOPIC || "clickstream").trim();
const groupId = (process.env.KAFKA_GROUP_ID || "sessionizer").trim();
const fromBeginning = (process.env.KAFKA_FROM_BEGINNING || "0").trim() === "1";

const caPath = expandHome((process.env.KAFKA_CA_CERT_PATH || "").trim());
const certPath = expandHome((process.env.KAFKA_ACCESS_CERT_PATH || "").trim());
const keyPath = expandHome((process.env.KAFKA_ACCESS_KEY_PATH || "").trim());

mustFile(caPath, "KAFKA_CA_CERT_PATH");
mustFile(certPath, "KAFKA_ACCESS_CERT_PATH");
mustFile(keyPath, "KAFKA_ACCESS_KEY_PATH");

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

const pgDsn = (process.env.PG_DSN || "").trim();
if (!pgDsn) throw new Error("PG_DSN missing");

const pgCaPath = expandHome((process.env.PG_CA_CERT_PATH || "").trim());
mustFile(pgCaPath, "PG_CA_CERT_PATH");

const insecurePg = (process.env.PG_SSL_INSECURE || "").trim() === "1";

// Ensure TLS servername matches host in DSN
const pgHost = new URL(pgDsn).hostname;

// If DSN doesn't embed a password, use PGPASSWORD (Node won't prompt)
const hasPwInDsn = Boolean(new URL(pgDsn).password);
const pgPassword = hasPwInDsn ? undefined : (process.env.PGPASSWORD || undefined);

const u = new URL(pgDsn);
const pgHost2 = u.hostname;
const pool = new Pool({
  host: pgHost2,
  port: Number(u.port || 5432),
  database: u.pathname.replace(/^\//, ""),
  user: decodeURIComponent(u.username || ""),
  password: (u.password ? decodeURIComponent(u.password) : (process.env.PGPASSWORD || undefined)),
  ssl: insecurePg
    ? { rejectUnauthorized: false, servername: pgHost2 }
    : {
        ca: [fs.readFileSync(pgCaPath)],
        rejectUnauthorized: true,
        servername: pgHost2,
      },
});
let consumer: any = null;

async function postgresIdentityCheck() {
  const id = await pool.query(
    "select current_database() as db, current_user as usr, inet_server_port() as port"
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
      from public.clickstream_events
      where session_id = $1
    )
    insert into public.clickstream_sessions(
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
  console.log(`Consuming topic=${topic} groupId=${groupId} fromBeginning=${fromBeginning}`);
  await postgresIdentityCheck();

  consumer = kafka.consumer({ groupId });
  await consumer.connect();
  console.log("✅ connected to kafka");

  await consumer.subscribe({ topic, fromBeginning });
  console.log("✅ subscribed, waiting for messages…");

  let inserted = 0;
  let shuttingDown = false;
await consumer.run({
    eachMessage: async ({ message }) => {
      if (shuttingDown) return;
if (!message.value) return;

      let evt: ClickEvent;
      try {
        evt = JSON.parse(message.value.toString("utf8"));
      } catch {
        return;
      }

      await pool.query(
        `insert into public.clickstream_events
           (ts, user_id, event_type, url, referrer, user_agent, session_id, event_name, revenue)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [
          evt.ts,
          evt.user_id,
          evt.event_name, // event_type for legacy dashboards
          evt.url ?? null,
          evt.referrer ?? null,
          evt.user_agent ?? null,
          evt.session_id,
          evt.event_name,
          evt.revenue ?? null,
        ]
      );

      await upsertSession(evt.session_id, evt.user_id);

      inserted += 1;
      if (inserted % 25 === 0) process.stdout.write("+");
      if (inserted % 250 === 0) {
        const c = await pool.query("select count(*)::int as c from public.clickstream_events");
        console.log(`\n✅ inserted=${inserted} total_events=${c.rows[0].c}`);
      }
    },
  });

  await new Promise(() => {});
})().catch((e) => {
  console.error("Consumer failed:", e?.message || e);
  process.exit(1);
});

process.on("SIGINT", async () => {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log("\nSIGINT received, shutting down…");
  try { if (consumer) { await consumer.stop(); await consumer.disconnect(); } } catch {}
  try { await pool.end(); } catch {}
  process.exit(0);
});
