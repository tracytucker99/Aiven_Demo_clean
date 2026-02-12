import fs from "node:fs";
import { Kafka } from "kafkajs";

const brokers = [(process.env.KAFKA_SERVICE_URI || "").trim()].filter(Boolean);

const caPath = (process.env.KAFKA_CA_CERT_PATH || "").trim();
const certPath = (process.env.KAFKA_ACCESS_CERT_PATH || "").trim();
const keyPath = (process.env.KAFKA_ACCESS_KEY_PATH || "").trim();

if (!brokers.length) throw new Error("KAFKA_SERVICE_URI missing");
if (!caPath) throw new Error("KAFKA_CA_CERT_PATH missing");
if (!certPath) throw new Error("KAFKA_ACCESS_CERT_PATH missing");
if (!keyPath) throw new Error("KAFKA_ACCESS_KEY_PATH missing");

if (!fs.existsSync(caPath)) throw new Error(`Missing ${caPath}`);
if (!fs.existsSync(certPath)) throw new Error(`Missing ${certPath}`);
if (!fs.existsSync(keyPath)) throw new Error(`Missing ${keyPath}`);

const kafka = new Kafka({
  clientId: "smoke",
  brokers,
  ssl: {
    ca: [fs.readFileSync(caPath)],
    cert: fs.readFileSync(certPath),
    key: fs.readFileSync(keyPath),
    rejectUnauthorized: true
  }
});

(async () => {
  const admin = kafka.admin();
  await admin.connect();
  const topics = await admin.listTopics();
  console.log("Connected. Topics:", topics);
  await admin.disconnect();
})().catch((e) => {
  console.error("Kafka smoke failed:", e?.message || e);
  process.exit(1);
});

