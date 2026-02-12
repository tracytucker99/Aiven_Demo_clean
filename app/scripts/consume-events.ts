import "dotenv/config";
import fs from "node:fs";
import { Kafka, logLevel } from "kafkajs";
import { makePgClient } from "./lib/pg-client";

function v(name: string): string {
  return (process.env[name] ?? "").trim();
}
function must(name: string): string {
  const val = v(name);
  if (!val) throw new Error(`Missing env var: ${name}`);
  return val;
}

function getKafka() {
  const brokers = must("KAFKA_BROKERS").split(",").map(s => s.trim()).filter(Boolean);

  const username = v("KAFKA_USERNAME");
  const password = v("KAFKA_PASSWORD");

  const caPath = v("KAFKA_CA_PATH") || "./kafka-ca.pem";
  const ssl = fs.existsSync(caPath) ? { ca: [fs.readFileSync(caPath, "utf8")] } : true;

  const sasl = username && password
    ? { mechanism: "scram-sha-512" as const, username, password }
    : undefined;

  return new Kafka({
    clientId: v("KAFKA_CLIENT_ID") || "aiven-clickstream-consumer-events",
    brokers,
    ssl,
    sasl,
    logLevel: v("KAFKAJS_DEBUG") ? logLevel.DEBUG : logLevel.ERROR,
  });
}

type Event = {
  event_id: string;
  ts: string;
  user_id: string;
  session_hint?: number;
  page?: string;
  referrer?: string;
  device?: string;
};

async function main() {
  const topic = v("KAFKA_TOPIC") || "clickstream";
  const groupId = v("KAFKA_GROUP_ID_EVENTS") || "clickstream-events-writer";

  const kafka = getKafka();
  const consumer = kafka.consumer({ groupId });

  const pg = makePgClient();
  await pg.connect();

  await consumer.connect();
  await consumer.subscribe({ topic, fromBeginning: false });

  console.log(`✅ Consuming "${topic}" groupId="${groupId}" → Postgres clickstream_events`);

  let n = 0;

  await consumer.run({
    autoCommit: true,
    eachMessage: async ({ message }) => {
      if (!message.value) return;

      const rawStr = message.value.toString("utf8");
      let e: Event;
      try {
        e = JSON.parse(rawStr);
      } catch {
        console.error("❌ Invalid JSON, skipping:", rawStr.slice(0, 200));
        return;
      }

      if (!e.event_id || !e.ts || !e.user_id) return;

      await pg.query(
        `
        insert into clickstream_events(event_id, ts, user_id, session_hint, page, referrer, device, raw)
        values ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
        on conflict (event_id) do nothing
        `,
        [
          e.event_id,
          e.ts,
          e.user_id,
          e.session_hint ?? null,
          e.page ?? null,
          e.referrer ?? null,
          e.device ?? null,
          rawStr,
        ]
      );

      n += 1;
      if (n % 50 === 0) console.log(`…inserted ${n} events`);
    },
  });
}

main().catch((err) => {
  console.error("❌ consume:events failed:", err?.message ?? err);
  process.exit(1);
});
