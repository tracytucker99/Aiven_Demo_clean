#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
set -a; source .env; set +a

OPENSSL_BIN="openssl"
if [ -x /opt/homebrew/opt/openssl@3/bin/openssl ]; then
  OPENSSL_BIN="/opt/homebrew/opt/openssl@3/bin/openssl"
elif [ -x /usr/local/opt/openssl@3/bin/openssl ]; then
  OPENSSL_BIN="/usr/local/opt/openssl@3/bin/openssl"
fi

if ! "$OPENSSL_BIN" s_client -help 2>/dev/null | grep -q -- "-starttls"; then
  echo "Need OpenSSL that supports: -starttls postgres"
  echo "Install it, then re-run:"
  echo "  brew install openssl@3"
  echo "  ./bin/inspect_pg_tls.sh"
  exit 2
fi

read -r PGHOST PGPORT <<EOF
$(python3 - <<'PY'
import os, urllib.parse
dsn=os.environ.get("PG_DSN","")
u=urllib.parse.urlparse(dsn)
print(u.hostname or "", u.port or "")
PY
)
EOF

CA="$HOME/.postgresql/root.crt"

echo "OPENSSL_BIN=$OPENSSL_BIN"
echo "PGHOST=$PGHOST"
echo "PGPORT=$PGPORT"
echo "CA_FILE=$CA"
echo
echo "== Local CA subject/issuer =="
"$OPENSSL_BIN" x509 -in "$CA" -noout -subject -issuer -fingerprint -sha256
echo
echo "== Fetching server cert chain via STARTTLS postgres =="
OUT=/tmp/pg_sclient.txt
"$OPENSSL_BIN" s_client -starttls postgres -connect "${PGHOST}:${PGPORT}" -servername "${PGHOST}" -showcerts < /dev/null > "$OUT" 2>&1 || true

if ! grep -q "BEGIN CERTIFICATE" "$OUT"; then
  echo "No PEM certs captured. First 80 lines:"
  sed -n '1,80p' "$OUT"
  exit 3
fi

rm -f /tmp/pg_cert_*.pem
awk '
  /BEGIN CERTIFICATE/{i++; fn=sprintf("/tmp/pg_cert_%02d.pem", i)}
  { if (fn) print > fn }
  /END CERTIFICATE/{fn=""}
' "$OUT"

echo "== Server chain certs (subject/issuer) =="
for f in /tmp/pg_cert_*.pem; do
  echo "--- $f ---"
  "$OPENSSL_BIN" x509 -in "$f" -noout -subject -issuer -fingerprint -sha256
done
