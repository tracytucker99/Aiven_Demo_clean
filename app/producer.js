const Kafka = require("node-rdkafka");
const fs = require("fs");

const TOPIC_NAME = process.env.TOPIC_NAME || "clickstream.events";
const BROKERS = process.env.KAFKA_BROKERS || "demo-kafka-avien-project.g.aivencloud.com:21780";
const USER = process.env.KAFKA_USERNAME || "avnadmin";
const PASS = process.env.KAFKA_PASSWORD || "";
const CA_PATH = process.env.KAFKA_CA_PATH || "./ca.pem"; // or ./kafka-ca.pem

if (!fs.existsSync(CA_PATH)) throw new Error(`Missing CA file: ${CA_PATH}`);

const producer = new Kafka.Producer({
  "metadata.broker.list": BROKERS,
  "security.protocol": "sasl_ssl",
  "sasl.mechanism": "SCRAM-SHA-256",
  "sasl.username": USER,
  "sasl.password": PASS,
  "ssl.ca.location": CA_PATH,
  "dr_cb": true,
  "socket.keepalive.enable": true,
});

producer.on("event.error", (err) => console.error("Producer error:", err));

producer.on("delivery-report", (err, report) => {
  if (err) console.error("Delivery error:", err);
  else console.log("Delivered:", report.topic, report.partition, report.offset);
});

producer.on("ready", async () => {
  console.log("✅ Producer ready. Sending messages...");

  let i = 0;
  const interval = setInterval(() => {
    i += 1;
    const message = `Hello from Node using SASL ${i}!`;

    try {
      producer.produce(TOPIC_NAME, null, Buffer.from(message), null, Date.now());
      console.log("Sent:", message);
    } catch (e) {
      console.error("Produce failed:", e);
    }

    if (i >= 20) { // keep it shorter while testing
      clearInterval(interval);
      producer.flush(10_000, () => producer.disconnect());
    }
  }, 1000);

  producer.setPollInterval(100);
});

producer.connect();
