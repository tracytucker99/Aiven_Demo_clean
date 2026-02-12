import fs from "node:fs";
import { Kafka } from "kafkajs";

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
const partitions = Number(process.env.KAFKA_TOPIC_PARTITIONS || "3");
const replicationFactor = Number(process.env.KAFKA_TOPIC_RF || "2");

const caPath = (process.env.KAFKA_CA_CERT_PATH || "").trim();
const certPath = (process.env.KAFKA_ACCESS_CERT_PATH || "").trim();
const keyPath = (process.env.KAFKA_ACCESS_KEY_PATH || "").trim();

function must(path: string, name: string) {
  if (!path) throw new Error(`${name} missing`);
  if (!fs.existsSync(path)) throw new Error(`Missing ${path}`);
}

must(caPath, "KAFKA_CA_CERT_PATH");
must(certPath, "KAFKA_ACCESS_CERT_PATH");
must(keyPath, "KAFKA_ACCESS_KEY_PATH");

const kafka = new Kafka({
  clientId: "topic-admin",
  brokers,
  ssl: {
    ca: [fs.readFileSync(caPath)],
    cert: fs.readFileSync(certPath),
    key: fs.readFileSync(keyPath),
    rejectUnauthorized: true,
  },
});

(async () => {
  const admin = kafka.admin();
  await admin.connect();

  const existing = await admin.listTopics();
  if (existing.includes(topic)) {
    console.log(`Topic already exists: ${topic}`);
  } else {
    console.log(`Creating topic=${topic} partitions=${partitions} rf=${replicationFactor}`);
    await admin.createTopics({
      waitForLeaders: true,
      topics: [{ topic, numPartitions: partitions, replicationFactor }],
    });
    console.log("Topic created.");
  }

  await admin.disconnect();
})().catch((e) => {
  console.error("Create topic failed:", e?.message || e);
  console.error("If you see a replication-factor error, rerun with: export KAFKA_TOPIC_RF=1");
  process.exit(1);
});
