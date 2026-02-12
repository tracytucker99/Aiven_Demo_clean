import https from "https";
import { Buffer } from "buffer";
import dotenv from "dotenv";

dotenv.config();

const OS_HOST = process.env.OS_HOST;
const OS_PORT = process.env.OS_PORT;
const OS_USER = process.env.OS_USER;
const OS_PASS = process.env.OS_PASS;
const OS_INDEX = process.env.OS_INDEX || "clickstream-events";

if (!OS_HOST || !OS_PORT || !OS_USER || !OS_PASS) {
  console.error("Missing env vars. Need OS_HOST, OS_PORT, OS_USER, OS_PASS (and optionally OS_INDEX).");
  process.exit(1);
}

// Use a daily index name and rely on an alias like "clickstream-events"
function dailyIndexName(base = OS_INDEX, d = new Date()) {
  const yyyy = d.getUTCFullYear();
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${base}-${yyyy}.${mm}.${dd}`;
}

const urls = ["/", "/pricing", "/docs", "/product", "/checkout"];
const refs = ["https://search.example.com", "https://example.com", "https://news.example.com", null];

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
function pick(arr) {
  return arr[randInt(0, arr.length - 1)];
}

function makeDoc() {
  // random time within last 12 hours
  const ts = new Date(Date.now() - randInt(0, 12 * 60 * 60 * 1000)).toISOString();
  const isCheckout = Math.random() < 0.12;

  const doc = {
    ts,
    "@timestamp": ts,                // <-- IMPORTANT for Grafana time field
    received_at: ts,
    user_id: `user-${randInt(1, 50)}`,
    session_id: `sess-${randInt(1, 200)}`,
    event_name: isCheckout ? "checkout" : "page_view",
    event_type: isCheckout ? "checkout" : "page_view",
    url: pick(urls),
    referrer: pick(refs),
    revenue: isCheckout ? Math.round((10 + Math.random() * 190) * 100) / 100 : 0.0,
    user_agent: "demo",
  };

  return doc;
}

function buildBulk(n) {
  const idx = dailyIndexName(OS_INDEX, new Date()); // write to today's daily index
  const lines = [];
  for (let i = 0; i < n; i++) {
    lines.push(JSON.stringify({ index: { _index: idx } }));
    lines.push(JSON.stringify(makeDoc()));
  }
  return lines.join("\n") + "\n";
}

function postBulk(body) {
  const auth = Buffer.from(`${OS_USER}:${OS_PASS}`).toString("base64");

  const req = https.request(
    {
      hostname: OS_HOST,
      port: Number(OS_PORT),
      path: "/_bulk?refresh=true",
      method: "POST",
      headers: {
        Authorization: `Basic ${auth}`,
        "Content-Type": "application/x-ndjson",
        "Content-Length": Buffer.byteLength(body),
      },
      // You used -k with curl; equivalent here is to skip TLS verification for demo purposes:
      rejectUnauthorized: false,
    },
    (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => {
        console.log("HTTP", res.statusCode);
        console.log(data.slice(0, 800));
      });
    }
  );

  req.on("error", (e) => {
    console.error("bulk error:", e);
    process.exit(1);
  });

  req.write(body);
  req.end();
}

const n = Number(process.argv[2] || "20000");
postBulk(buildBulk(n));
