import fs from "node:fs";
import { Kafka } from "kafkajs";

function parseBrokers(s: string) {
  return s
    .split(/[,\s]+/)
    .map((x) => x.trim())
    .filter(Boolean)
    .map((x) => x.replace(/^kafka\+ssl:\/\//, "").replace(/^ssl:\/\//, "").replace(/^kafka:\/\//, ""));
}

const brokers = parseBrokers((process.env.KAFKA_SERVICE_URI || "").trim());
if (!brokers.length) throw new Error("KAFKA_SERVICE_URI missing");

const topic = (process.env.KAFKA_TOPIC || "clickstream").trim();
const caPath = (process.env.KAFKA_CA_CERT_PATH || "").trim();
const certPath = (process.env.KAFKA_ACCESS_CERT_PATH || "").trim();
const keyPath = (process.env.KAFKA_ACCESS_KEY_PATH || "").trim();

for (const [p, n] of [[caPath,"KAFKA_CA_CERT_PATH"],[certPath,"KAFKA_ACCESS_CERT_PATH"],[keyPath,"KAFKA_ACCESS_KEY_PATH"]] as any) {
  if (!p) throw new Error(`${n} missing`);
  if (!fs.existsSync(p)) throw new Error(`Missing ${p}`);
}

const kafka = new Kafka({
  clientId: "peek",
  brokers,
  ssl: {
    ca: [fs.readFileSync(caPath)],
    cert: fs.readFileSync(certPath),
    key: fs.readFileSync(keyPath),
    rejectUnauthorized: true,
  },
});

(async () => {
  const gid = `peek-${Date.now()}`;
  console.log(`Peeking topic=${topic} groupId=${gid} fromBeginning=true`);

  const consumer = kafka.consumer({ groupId: gid });
  await consumer.connect();
  await consumer.subscribe({ topic, fromBeginning: true });

  let seen = 0;
  await consumer.run({
    eachMessage: async ({ partition, message }) => {
      if (!message.value) return;
      const raw = message.value.toString("utf8");
      let obj: any = null;
      try { obj = JSON.parse(raw); } catch {}
      console.log(`msg#${seen+1} p=${partition} offset=${message.offset}`);
      console.log(obj ?? raw);
      seen += 1;
      if (seen >= 5) {
        await consumer.stop();
        await consumer.disconnect();
        process.exit(0);
      }
    },
  });

  setTimeout(async () => {
    console.log("No messages seen in 10s.");
    try { await consumer.stop(); await consumer.disconnect(); } catch {}
    process.exit(2);
  }, 10000);
})();
