#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "==> Repo: $ROOT"

if [ ! -f ".env" ]; then
  echo "❌ .env not found in $ROOT"
  exit 1
fi

# --- helper: de-dupe env keys (keep first occurrence) ---
dedupe_keys() {
  local file="$1"
  awk '
    BEGIN { FS="=" }
    /^[A-Za-z_][A-Za-z0-9_]*=/ {
      key=$1
      if (!seen[key]++) print $0
      next
    }
    { print $0 }
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

echo "==> 1) De-dupe .env keys (keeps first occurrence)"
dedupe_keys ".env"

# --- ensure Kafka files exist (from your env) ---
echo "==> 2) Load env + verify Kafka files exist"
set -a; source .env; set +a

req_file() {
  local p="$1"
  local name="$2"
  if [ -z "${p:-}" ]; then
    echo "❌ $name is empty"
    exit 1
  fi
  if [ ! -f "$p" ]; then
    echo "❌ $name file missing: $p"
    exit 1
  fi
  echo "✅ $name: $p"
}

req_file "${KAFKA_CA_CERT_PATH:-}" "KAFKA_CA_CERT_PATH"
req_file "${KAFKA_ACCESS_CERT_PATH:-}" "KAFKA_ACCESS_CERT_PATH"
req_file "${KAFKA_ACCESS_KEY_PATH:-}" "KAFKA_ACCESS_KEY_PATH"

# --- ensure pg-ca.pem exists in repo ---
echo "==> 3) Ensure pg-ca.pem exists in repo"
if [ ! -f "./pg-ca.pem" ]; then
  if [ -f "$HOME/Downloads/ca(1).pem" ]; then
    cp -f "$HOME/Downloads/ca(1).pem" ./pg-ca.pem
    echo "✅ Copied ~/Downloads/ca(1).pem -> ./pg-ca.pem"
  elif [ -f "$HOME/Downloads/ca.pem" ]; then
    cp -f "$HOME/Downloads/ca.pem" ./pg-ca.pem
    echo "✅ Copied ~/Downloads/ca.pem -> ./pg-ca.pem"
  else
    echo "❌ Missing ./pg-ca.pem and no ca.pem / ca(1).pem found in ~/Downloads"
    echo "   Download the Aiven Postgres CA PEM and put it at: $ROOT/pg-ca.pem"
    exit 1
  fi
fi

# --- force Node to use CA + secure mode ---
echo "==> 4) Set PG_CA_CERT_PATH and remove PG_SSL_INSECURE"
# replace/add PG_CA_CERT_PATH
if grep -q '^PG_CA_CERT_PATH=' .env; then
  perl -i -pe 's|^PG_CA_CERT_PATH=.*|PG_CA_CERT_PATH="./pg-ca.pem"|' .env
else
  echo 'PG_CA_CERT_PATH="./pg-ca.pem"' >> .env
fi
# drop any PG_SSL_INSECURE lines
perl -i -ne 'print unless /^PG_SSL_INSECURE=/' .env 2>/dev/null || true

# reload env after edits
set -a; source .env; set +a

echo "PG_CA_CERT_PATH=${PG_CA_CERT_PATH:-}"
echo "PG_DSN scheme/user/host/port/db (not printing password):"
python3 - <<'PY'
import os, urllib.parse
dsn=os.environ.get("PG_DSN","")
u=urllib.parse.urlparse(dsn)
print("  scheme:", u.scheme)
print("  user:", u.username)
print("  host:", u.hostname)
print("  port:", u.port)
print("  db:", u.path.lstrip("/"))
print("  query:", u.query)
print("  has_pw_in_dsn:", bool(u.password))
print("  PGPASSWORD_set:", bool(os.environ.get("PGPASSWORD")))
PY

echo "==> 5) Verify Postgres with psql (will prompt if needed)"
psql "$PG_DSN" -c "select now(), current_database(), current_user, inet_server_port();" >/dev/null
echo "✅ psql ok"

echo "==> 6) Verify Postgres with node/pg (this is what consumer uses)"
node - <<'NODE'
const fs = require("fs");
const { Pool } = require("pg");

const dsn = process.env.PG_DSN;
if (!dsn) throw new Error("PG_DSN missing");
const caPath = (process.env.PG_CA_CERT_PATH || "").trim();
if (!caPath) throw new Error("PG_CA_CERT_PATH missing");
if (!fs.existsSync(caPath)) throw new Error("PG CA missing: " + caPath);

// If DSN has no password, node/pg needs one via config (psql can prompt; node cannot)
const password = process.env.PGPASSWORD || undefined;

const pool = new Pool({
  connectionString: dsn,
  password,
  ssl: { ca: fs.readFileSync(caPath, "utf8"), rejectUnauthorized: true },
});

(async () => {
  const r = await pool.query("select current_database() db, current_user usr, inet_server_port() port");
  console.log("✅ node pg ok:", r.rows[0]);
  await pool.end();
})().catch(async (e) => {
  console.error("❌ node pg failed:", e.message || e);
  try { await pool.end(); } catch {}
  process.exit(1);
});
NODE

echo "==> 7) Verify Kafka"
npm run -s smoke:kafka
echo "✅ kafka ok"

echo "==> 8) Ready. Run these in TWO terminals to refresh data:"
echo "   Terminal A (producer):  cd $ROOT && set -a; source .env; set +a; npm run run:producer"
echo "   Terminal B (consumer):  cd $ROOT && set -a; source .env; set +a; npm run run:consumer"

echo "==> 9) Quick check commands (run anytime):"
echo "   psql \"\$PG_DSN\" -c \"select count(*) events, max(ts) max_ts from public.clickstream_events;\""
echo "   psql \"\$PG_DSN\" -c \"select count(*) sessions, max(last_updated_at) max_upd from public.clickstream_sessions;\""
