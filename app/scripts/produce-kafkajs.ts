import 'dotenv/config';
import fs from 'node:fs';
import { Kafka, logLevel } from 'kafkajs';

function v(name: string): string {
  return (process.env[name] ?? '').trim();
}

function parseHostPort(s: string): { host: string; port: number } {
  const t = s.trim();
  const m = t.match(/^([^:]+):(\d+)$/);
  if (!m) throw new Error(`Expected host:port but got "${s}"`);
  return { host: m[1], port: Number(m[2]) };
}

function parseServiceLike(input: string) {
  const raw = input.trim();

  // Accept:
  // - kafka+ssl://user:pass@host:port
  // - ssl://user:pass@host:port
  // - host:port   (no scheme)
  let host = '';
  let port = 9092;
  let username = '';
  let password = '';

  if (raw.includes('://')) {
    const u = new URL(raw.replace(/^kafka\+ssl:/, 'ssl:'));
    host = u.hostname;
    port = u.port ? Number(u.port) : 9092;
    username = decodeURIComponent(u.username || '');
    password = decodeURIComponent(u.password || '');
  } else {
    const hp = parseHostPort(raw);
    host = hp.host;
    port = hp.port;
  }

  return { host, port, username, password };
}

function getKafkaConfig() {
  // Prefer brokers explicitly if present (your kafka-smoke proves this works)
  const brokersRaw = v('KAFKA_BROKERS') || v('BROKERS') || v('KAFKA_BOOTSTRAP_SERVERS');
  const serviceUri = v('KAFKA_SERVICE_URI') || v('KAFKA_URI') || v('KAFKA_SERVICE_URL');

  let brokers: string[] = [];
  let username = v('KAFKA_USERNAME') || v('SASL_USERNAME');
  let password = v('KAFKA_PASSWORD') || v('SASL_PASSWORD');

  if (brokersRaw) {
    brokers = brokersRaw.split(',').map(s => s.trim()).filter(Boolean);
  } else if (serviceUri) {
    const { host, port, username: u, password: p } = parseServiceLike(serviceUri);
    brokers = [`${host}:${port}`];
    if (!username) username = u;
    if (!password) password = p;
  } else {
    throw new Error('Missing Kafka connection info: set KAFKA_BROKERS (recommended) or KAFKA_SERVICE_URI.');
  }

  if (brokers.length === 0 || brokers.some(b => b.startsWith(':'))) {
    throw new Error(`Invalid brokers list: "${brokersRaw || serviceUri}"`);
  }

  const topic = v('KAFKA_TOPIC') || v('TOPIC') || 'clickstream';

  const caPath =
    v('KAFKA_CA_PATH') ||
    v('KAFKA_SSL_CA_LOCATION') ||
    v('SSL_CA_LOCATION') ||
    './kafka-ca.pem';

  const caExists = fs.existsSync(caPath);
  const ssl = caExists ? { ca: [fs.readFileSync(caPath, 'utf8')] } : true;

  const hasSasl = Boolean(username && password);

  return { brokers, topic, ssl, hasSasl, username, password, caPath, caExists };
}

async function tryRun(mechanism: 'scram-sha-512'|'scram-sha-256'|undefined) {
  const { brokers, topic, ssl, hasSasl, username, password, caPath, caExists } = getKafkaConfig();
  const sasl = hasSasl && mechanism ? { mechanism, username, password } : undefined;

  const kafka = new Kafka({
    clientId: v('KAFKA_CLIENT_ID') || 'aiven-clickstream-producer',
    brokers,
    ssl,
    sasl,
    logLevel: v('KAFKAJS_DEBUG') ? logLevel.DEBUG : logLevel.ERROR,
  });

  const producer = kafka.producer();

  console.log('--- Kafka config ---');
  console.log('brokers:', brokers.join(', '));
  console.log('topic:', topic);
  console.log('ssl ca:', caExists ? `file:${caPath}` : '(default)');
  console.log('sasl:', sasl ? `${mechanism} (user set)` : '(none)');
  console.log('--------------------');

  await producer.connect();
  console.log(`✅ Connected. Producing to topic="${topic}"…`);

  const intervalMs = Number(v('PRODUCE_INTERVAL_MS') || '250');
  const total = Number(v('PRODUCE_COUNT') || '0'); // 0 = forever
  const keyPrefix = v('KEY_PREFIX') || 'user';
  const pagePool = (v('PAGE_POOL') || '/,/pricing,/docs,/blog,/signup,/login')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

  let i = 0;
  while (true) {
    i += 1;
    const userId = `${keyPrefix}-${(i % 250) + 1}`;
    const page = pagePool[i % pagePool.length] || '/';
    const event = {
      event_id: (globalThis.crypto as any)?.randomUUID?.() ?? `${Date.now()}-${i}`,
      ts: new Date().toISOString(),
      user_id: userId,
      session_hint: Math.floor(i / 20),
      page,
      referrer: i % 3 === 0 ? 'google' : i % 3 === 1 ? 'email' : 'direct',
      device: i % 2 === 0 ? 'mobile' : 'desktop',
    };

    await producer.send({ topic, messages: [{ key: userId, value: JSON.stringify(event) }] });

    if (i % 20 === 0) console.log(`…sent ${i} events`);

    if (total > 0 && i >= total) break;
    await new Promise(r => setTimeout(r, intervalMs));
  }

  await producer.disconnect();
  console.log('✅ Done.');
}

async function main() {
  const cfg = getKafkaConfig();
  const attempts: Array<'scram-sha-512'|'scram-sha-256'|undefined> =
    cfg.hasSasl ? ['scram-sha-512','scram-sha-256'] : [undefined];

  let lastErr: any;
  for (const mech of attempts) {
    try {
      await tryRun(mech);
      return;
    } catch (e: any) {
      lastErr = e;
      console.error(`❌ Attempt failed (${mech ?? 'no-sasl'}):`, e?.message ?? e);
    }
  }
  throw lastErr;
}

main().catch(err => {
  console.error('❌ Producer failed:', err?.message ?? err);
  process.exit(1);
});
