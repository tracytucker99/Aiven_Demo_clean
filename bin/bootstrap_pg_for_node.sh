#!/usr/bin/env bash
set -eo pipefail  # NOTE: intentionally NOT using -u because .env may reference unset vars

cd "$(dirname "$0")/.."

echo "==> Repo: $(pwd)"

if [ ! -f .env ]; then
  echo "ERROR: .env not found in repo root"
  exit 1
fi

echo "==> Showing .env line 13 (where your error points)"
nl -ba .env | sed -n '13p' || true

# Ensure pg-ca.pem exists in repo root
if [ ! -f ./pg-ca.pem ]; then
  if [ -f "$HOME/Downloads/ca(1).pem" ]; then
    cp -f "$HOME/Downloads/ca(1).pem" ./pg-ca.pem
  elif [ -f "$HOME/Downloads/ca.pem" ]; then
    cp -f "$HOME/Downloads/ca.pem" ./pg-ca.pem
  else
    echo "ERROR: pg-ca.pem missing and no CA PEM found in ~/Downloads (ca(1).pem or ca.pem)."
    exit 1
  fi
fi

# Ensure PG_CA_CERT_PATH is set in .env
if grep -q '^PG_CA_CERT_PATH=' .env 2>/dev/null; then
  perl -i -pe 's|^PG_CA_CERT_PATH=.*|PG_CA_CERT_PATH="./pg-ca.pem"|' .env
else
  echo 'PG_CA_CERT_PATH="./pg-ca.pem"' >> .env
fi

# Make sure insecure mode is OFF for secure mode
perl -i -ne 'print unless /^PG_SSL_INSECURE=/' .env 2>/dev/null || true

# Ensure PGPASSWORD exists (Node won't prompt)
if ! grep -q '^PGPASSWORD=' .env 2>/dev/null; then
  echo "ERROR: PGPASSWORD not set in .env"
  echo 'Add: PGPASSWORD="<your_aiven_password>"'
  exit 1
fi

# Load env safely (allow unset references without aborting)
set -a
# shellcheck disable=SC1091
source .env
set +a

if [ -z "${PG_DSN:-}" ]; then
  echo "ERROR: PG_DSN is missing/empty in .env"
  exit 1
fi
if [ -z "${PGPASSWORD:-}" ]; then
  echo "ERROR: PGPASSWORD is missing/empty in .env"
  exit 1
fi
if [ -z "${PG_CA_CERT_PATH:-}" ]; then
  echo "ERROR: PG_CA_CERT_PATH is missing/empty in .env"
  exit 1
fi
if [ ! -f "${PG_CA_CERT_PATH}" ]; then
  echo "ERROR: PG_CA_CERT_PATH points to missing file: ${PG_CA_CERT_PATH}"
  exit 1
fi

echo "==> PG_DSN is set (not printing password)"
echo "==> PG_CA_CERT_PATH=${PG_CA_CERT_PATH}"
echo "==> PGPASSWORD=<set>"

# Node connectivity check using pg (same lib as consumer)
node - <<'NODE'
const fs = require("node:fs");
const { Pool } = require("pg");

const dsn = (process.env.PG_DSN || "").trim();
const caPath = (process.env.PG_CA_CERT_PATH || "").trim();
const pw = (process.env.PGPASSWORD || "");

if (!dsn) throw new Error("PG_DSN missing");
if (!caPath) throw new Error("PG_CA_CERT_PATH missing");
if (!fs.existsSync(caPath)) throw new Error("Missing CA file: " + caPath);
if (typeof pw !== "string" || pw.length === 0) throw new Error("PGPASSWORD missing/empty");

(async () => {
  const pool = new Pool({
    connectionString: dsn,
    password: pw,
    ssl: {
      ca: fs.readFileSync(caPath, "utf8"),
      rejectUnauthorized: true,
    },
  });
  const r = await pool.query("select now(), current_database(), current_user, inet_server_port()");
  console.log("✅ node pg ok:", r.rows[0]);
  await pool.end();
})().catch((e) => {
  console.error("❌ node pg failed:", e.message || e);
  process.exit(1);
});
NODE

echo "✅ Postgres is ready for Node consumer"
