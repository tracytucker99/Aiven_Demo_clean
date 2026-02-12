import fs from "node:fs";
import crypto from "node:crypto";
import { Kafka } from "kafkajs";

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

const brokers = parseBrokers(
  (process.env.KAFKA_BROKERS || process.env.KAFKA_SERVICE_URI || "").trim()
);
if (!brokers.length) throw new Error("KAFKA_BROKERS (or KAFKA_SERVICE_URI) missing");

const topic = (process.env.KAFKA_TOPIC || "clickstream").trim();

const caPath = (process.env.KAFKA_CA_CERT_PATH || "").trim();
const certPath = (process.env.KAFKA_ACCESS_CERT_PATH || "").trim();
const keyPath = (process.env.KAFKA_ACCESS_KEY_PATH || "").trim();

const ratePerSec = Number(process.env.PRODUCER_RATE_PER_SEC || "20");
const users = Number(process.env.PRODUCER_USERS || "50");

function must(path: string, name: string) {
  if (!path) throw new Error(`${name} missing`);
  if (!fs.existsSync(path)) throw new Error(`Missing ${path}`);
}

must(caPath, "KAFKA_CA_CERT_PATH");
must(certPath, "KAFKA_ACCESS_CERT_PATH");
must(keyPath, "KAFKA_ACCESS_KEY_PATH");

const kafka = new Kafka({
  clientId: "clickstream-producer",
  brokers,
  ssl: {
    ca: [fs.readFileSync(caPath)],
    cert: fs.readFileSync(certPath),
    key: fs.readFileSync(keyPath),
    rejectUnauthorized: true,
  },
});

const urls = ["/", "/pricing", "/docs", "/product", "/checkout"];
const events = ["page_view", "page_view", "page_view", "add_to_cart", "checkout"];

function pick<T>(arr: T[]) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function makeEvent(): ClickEvent {
  const user_id = `user_${1 + Math.floor(Math.random() * users)}`;
  const session_id = crypto.createHash("sha1").update(user_id).update("demo").digest("hex").slice(0, 16);
  const event_name = pick(events);
  const url = pick(urls);
  const revenue = event_name === "checkout" ? Number((20 + Math.random() * 200).toFixed(2)) : undefined;

  return {
    ts: new Date().toISOString(),
    user_id,
    session_id,
    event_name,
    url,
    referrer: "https://search.example.com",
    user_agent: "Mozilla/5.0 demo",
    revenue,
  };
}

(async () => {
  const producer = kafka.producer();
  await producer.connect();
  console.log(`Producing to topic=${topic} rate=${ratePerSec}/sec users=${users}`);

  const intervalMs = Math.max(1, Math.floor(1000 / Math.max(1, ratePerSec)));

  setInterval(async () => {
    const evt = makeEvent();
    await producer.send({
      topic,
      messages: [{ key: evt.user_id, value: JSON.stringify(evt) }],
    });
    process.stdout.write(".");
  }, intervalMs);
})().catch((e) => {
  console.error("Producer failed:", e?.message || e);
  process.exit(1);
});
