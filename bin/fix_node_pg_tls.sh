#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
echo "==> Repo: $(pwd)"

ROOTCRT="$HOME/.postgresql/root.crt"
if [ ! -f "$ROOTCRT" ]; then
  echo "❌ Missing $ROOTCRT"
  echo "   Put your Aiven Postgres CA PEM here first:"
  echo "   mkdir -p ~/.postgresql && cp ~/Downloads/ca\\(1\\).pem ~/.postgresql/root.crt && chmod 0600 ~/.postgresql/root.crt"
  exit 1
fi

echo "==> Using CA for Node: $ROOTCRT"
ls -lah "$ROOTCRT" | sed 's/^/   /'

# 1) Update .env to use the same CA as psql
if grep -q '^PG_CA_CERT_PATH=' .env 2>/dev/null; then
  perl -i -pe "s|^PG_CA_CERT_PATH=.*|PG_CA_CERT_PATH=\"$ROOTCRT\"|" .env
else
  echo "PG_CA_CERT_PATH=\"$ROOTCRT\"" >> .env
fi

# 2) Ensure insecure mode is OFF
perl -i -ne 'print unless /^PG_SSL_INSECURE=/' .env 2>/dev/null || true

# 3) Load env
set -a; source .env; set +a

echo "==> Sanity: show key vars (no secrets)"
python3 - <<'PY'
import os, urllib.parse
dsn=os.environ.get("PG_DSN","")
u=urllib.parse.urlparse(dsn)
print("PG_DSN host:", u.hostname)
print("PG_DSN port:", u.port)
print("PG_DSN db:", u.path.lstrip("/"))
print("PG_DSN query:", u.query)
print("PGPASSWORD set?:", bool(os.environ.get("PGPASSWORD")))
print("PG_CA_CERT_PATH:", os.environ.get("PG_CA_CERT_PATH"))
PY

echo "==> Test node/pg TLS (this must pass for consumer)"
node - <<'NODE'
const fs = require("fs");
const { Pool } = require("pg");

const dsn = process.env.PG_DSN;
const caPath = (process.env.PG_CA_CERT_PATH || "").trim();
const password = process.env.PGPASSWORD;

if (!dsn) throw new Error("PG_DSN missing");
if (!caPath) throw new Error("PG_CA_CERT_PATH missing");
if (!fs.existsSync(caPath)) throw new Error("CA file missing: " + caPath);
if (!password) throw new Error("PGPASSWORD missing (Node cannot prompt like psql)");

const pool = new Pool({
  connectionString: dsn,
  password,
  ssl: {
    ca: fs.readFileSync(caPath),        // Buffer is safest
    rejectUnauthorized: true,
  },
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

echo "==> ✅ Node TLS fixed. Now your consumer should run."
echo "Run:"
echo "  set -a; source .env; set +a"
echo "  npm run run:consumer"
