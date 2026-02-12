#!/usr/bin/env bash
set -euo pipefail

echo "==> 0) Sanity: in repo root?"
pwd
test -f package.json || { echo "ERROR: package.json not found. Run from repo root."; exit 1; }

echo "==> 1) Ensure Postgres env is loaded"
if [ ! -f .env ]; then
  echo "ERROR: .env missing. Run ./bootstrap_pg.sh first."
  exit 1
fi

set -a
source .env
set +a

: "${PG_DSN:?PG_DSN missing in .env}"

echo "==> 2) Install node deps"
npm ci

echo "==> 3) Kafka env prompts (paste EXACT values from Aiven service page)"
read -r -p "KAFKA_SERVICE_URI (host:port, e.g. demo-kafka-...:21769): " KAFKA_SERVICE_URI
read -r -p "KAFKA_TOPIC [clickstream]: " KAFKA_TOPIC
KAFKA_TOPIC="${KAFKA_TOPIC:-clickstream}"

read -r -p "Path to Kafka CA cert PEM (e.g. ./kafka-ca.pem or ./app/kafka-ca.pem): " KAFKA_CA_CERT_PATH
read -r -p "Path to Kafka access cert PEM (service.cert): " KAFKA_ACCESS_CERT_PATH
read -r -p "Path to Kafka access key PEM (service.key): " KAFKA_ACCESS_KEY_PATH

# Basic file checks
for f in "$KAFKA_CA_CERT_PATH" "$KAFKA_ACCESS_CERT_PATH" "$KAFKA_ACCESS_KEY_PATH"; do
  [ -f "$f" ] || { echo "ERROR: missing file $f"; exit 1; }
done

echo "==> 4) Write/merge vars into .env (preserving existing PG_DSN)"
# remove any existing kafka vars (clean)
perl -i -ne 'print unless /^KAFKA_(SERVICE_URI|BROKERS|TOPIC|GROUP_ID|FROM_BEGINNING|CA_CERT_PATH|ACCESS_CERT_PATH|ACCESS_KEY_PATH)=/' .env

# write kafka vars
cat >> .env <<EOF

# --- Kafka ---
KAFKA_SERVICE_URI="$KAFKA_SERVICE_URI"
KAFKA_BROKERS="$KAFKA_SERVICE_URI"
KAFKA_TOPIC="$KAFKA_TOPIC"
KAFKA_GROUP_ID="sessionizer"
KAFKA_FROM_BEGINNING=0
KAFKA_CA_CERT_PATH="$KAFKA_CA_CERT_PATH"
KAFKA_ACCESS_CERT_PATH="$KAFKA_ACCESS_CERT_PATH"
KAFKA_ACCESS_KEY_PATH="$KAFKA_ACCESS_KEY_PATH"

# --- Postgres ---
PG_SSL_INSECURE=0
EOF

echo "==> 5) Smoke test Kafka connectivity"
set -a; source .env; set +a
npm run smoke:kafka || { echo "ERROR: kafka smoke failed"; exit 1; }

echo "==> 6) Ensure DB schema exists (safe idempotent)"
DSN_REQ="$(echo "$PG_DSN" | perl -pe 's/([?&])sslmode=[^&]+&?/$1/g; s/[?&]$//; $_ .= (index($_,"?")>-1 ? "&" : "?") . "sslmode=verify-full";')"

psql "$DSN_REQ" <<'SQL'
create extension if not exists pgcrypto;

create table if not exists public.clickstream_events (
  id          uuid primary key default gen_random_uuid(),
  ts          timestamptz not null,
  user_id     text not null,
  event_type  text not null default 'event',
  url         text,
  referrer    text,
  user_agent  text,
  session_id  text not null,
  event_name  text not null,
  revenue     numeric(12,2),
  received_at timestamptz not null default now()
);

create index if not exists ix_clickstream_events_ts on public.clickstream_events(ts);
create index if not exists ix_clickstream_events_user_ts on public.clickstream_events(user_id, ts desc);
create index if not exists ix_clickstream_events_session_ts on public.clickstream_events(session_id, ts desc);

create table if not exists public.clickstream_sessions (
  session_id      text primary key,
  user_id         text not null,
  session_start   timestamptz not null,
  session_end     timestamptz not null,
  event_count     int not null,
  pageviews       int not null,
  conversions     int not null,
  revenue_total   numeric(12,2) not null,
  last_updated_at timestamptz not null default now()
);

create index if not exists ix_clickstream_sessions_user_end
  on public.clickstream_sessions(user_id, session_end desc);
SQL

echo
echo "✅ Bootstrap complete."
echo
echo "NEXT:"
echo "  Terminal A:  set -a; source .env; set +a; npm run run:producer"
echo "  Terminal B:  set -a; source .env; set +a; npm run run:consumer"
echo
echo "VERIFY:"
echo "  psql \"$DSN_REQ\" -c \"select count(*) as events, max(ts) as max_ts from public.clickstream_events;\""
echo "  psql \"$DSN_REQ\" -c \"select count(*) as sessions, max(session_end) as max_end from public.clickstream_sessions;\""
