#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# find helper
pick() { for f in "$@"; do [ -f "$f" ] && { echo "$f"; return 0; }; done; return 1; }
find_first() { find . -maxdepth 3 -type f -name "$1" 2>/dev/null | head -n 1; }

# detect files
CA="$(pick ./kafka-ca.pem ./app/kafka-ca.pem ./ca.pem ./app/ca.pem || true)"
[ -z "${CA:-}" ] && CA="$(find_first 'kafka-ca.pem' || true)"
[ -z "${CA:-}" ] && CA="$(find_first 'ca.pem' || true)"

CERT="$(pick ./service.cert ./app/service.cert || true)"
[ -z "${CERT:-}" ] && CERT="$(find_first 'service.cert' || true)"

KEY="$(pick ./service.key ./app/service.key || true)"
[ -z "${KEY:-}" ] && KEY="$(find_first 'service.key' || true)"

# hard fail if missing
for name in CA CERT KEY; do
  val="${!name:-}"
  if [ -z "$val" ] || [ ! -f "$val" ]; then
    echo "ERROR: missing $name file."
    echo "Looked for:"
    echo "  CA:   kafka-ca.pem or ca.pem in ./ or ./app/"
    echo "  CERT: service.cert in ./ or ./app/"
    echo "  KEY:  service.key in ./ or ./app/"
    echo
    echo "Run these and paste output if stuck:"
    echo "  ls -la"
    echo "  ls -la app 2>/dev/null || true"
    exit 1
  fi
done

echo "Detected:"
echo "  KAFKA_CA_CERT_PATH=$CA"
echo "  KAFKA_ACCESS_CERT_PATH=$CERT"
echo "  KAFKA_ACCESS_KEY_PATH=$KEY"
echo

# prompt for service uri
read -r -p "Paste KAFKA_SERVICE_URI (host:port, e.g. demo-kafka-...:21769): " URI
URI="$(echo "$URI" | tr -d '[:space:]')"

if ! echo "$URI" | grep -Eq '^[^:/]+:[0-9]+$'; then
  echo "ERROR: KAFKA_SERVICE_URI must be host:port (no kafka+ssl:// prefix). Got: $URI"
  exit 1
fi

read -r -p "KAFKA_TOPIC [clickstream]: " TOPIC
TOPIC="${TOPIC:-clickstream}"

# remove old kafka vars then append clean ones
perl -i -ne 'print unless /^KAFKA_(SERVICE_URI|BROKERS|TOPIC|GROUP_ID|FROM_BEGINNING|CA_CERT_PATH|ACCESS_CERT_PATH|ACCESS_KEY_PATH)=/' .env 2>/dev/null || true

cat >> .env <<EOF

# --- Kafka (bootstrap) ---
KAFKA_SERVICE_URI="$URI"
KAFKA_BROKERS="$URI"
KAFKA_TOPIC="$TOPIC"
KAFKA_GROUP_ID="sessionizer"
KAFKA_FROM_BEGINNING=0
KAFKA_CA_CERT_PATH="$CA"
KAFKA_ACCESS_CERT_PATH="$CERT"
KAFKA_ACCESS_KEY_PATH="$KEY"
EOF

echo
echo "✅ Wrote Kafka config to .env"
echo "==> Current values:"
grep -E '^KAFKA_(SERVICE_URI|BROKERS|TOPIC|GROUP_ID|FROM_BEGINNING|CA_CERT_PATH|ACCESS_CERT_PATH|ACCESS_KEY_PATH)=' .env
