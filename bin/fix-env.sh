#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${AVN_AUTH_TOKEN:?missing AVN_AUTH_TOKEN}"

if [ -f .env ]; then
  cp -f .env ".env.bad.$(date +%Y%m%d_%H%M%S)" || true
fi

PROJECT="$(terraform -chdir=terraform output -raw project 2>/dev/null || terraform -chdir=terraform output -raw project_name)"
CLOUD="$(terraform -chdir=terraform output -raw cloud 2>/dev/null || true)"
TOPIC="$(terraform -chdir=terraform output -raw topic_name 2>/dev/null || echo clickstream.events)"

KAFKA_HOST="$(terraform -chdir=terraform output -raw kafka_host)"
KAFKA_PORT="$(terraform -chdir=terraform output -raw kafka_port)"
KAFKA_USER="$(terraform -chdir=terraform output -raw kafka_username)"
KAFKA_PASS="$(terraform -chdir=terraform output -raw kafka_password)"

PG_HOST="$(terraform -chdir=terraform output -raw pg_host)"
PG_PORT="$(terraform -chdir=terraform output -raw pg_port)"
PG_USER="$(terraform -chdir=terraform output -raw pg_username)"
PG_PASS="$(terraform -chdir=terraform output -raw pg_password)"
PG_DB="$(terraform -chdir=terraform output -raw pg_dbname 2>/dev/null || echo defaultdb)"

avn --auth-token "$AVN_AUTH_TOKEN" project switch "$PROJECT" >/dev/null
avn --auth-token "$AVN_AUTH_TOKEN" project ca-get --target-filepath ./pg-ca.pem >/dev/null
cp -f ./pg-ca.pem ./kafka-ca.pem
chmod 600 ./pg-ca.pem ./kafka-ca.pem

cat > .env <<EOV
KAFKA_BROKERS=${KAFKA_HOST}:${KAFKA_PORT}
KAFKA_USERNAME=${KAFKA_USER}
KAFKA_PASSWORD=${KAFKA_PASS}
KAFKA_CA_PATH=./kafka-ca.pem
PG_DSN=postgres://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DB}
PG_CA_PATH=./pg-ca.pem
TOPIC_CLICKSTREAM=${TOPIC}
SESSION_TIMEOUT_MIN=30
DLQ_TOPIC=clickstream.dlq
MAX_BATCH_EVENTS=300
EOV

perl -pi -e 's/\r$//; s/\$+$//' .env

echo "WROTE_ENV=1"
