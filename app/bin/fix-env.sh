#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

cp -f .env ".env.bad.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

PROJECT="$(terraform -chdir=terraform output -raw project_name)"
KAFKA_SVC="$(terraform -chdir=terraform output -raw kafka_service_name)"
PG_URI="$(terraform -chdir=terraform output -raw pg_uri)"
KAFKA_USER="$(terraform -chdir=terraform output -raw kafka_username)"
KAFKA_PASS="$(terraform -chdir=terraform output -raw kafka_password)"

avn --auth-token "${AVN_AUTH_TOKEN:?set AVN_AUTH_TOKEN}" project switch "$PROJECT" >/dev/null
avn --auth-token "$AVN_AUTH_TOKEN" project ca-get --target-filepath ./pg-ca.pem >/dev/null
cp -f ./pg-ca.pem ./kafka-ca.pem
chmod 600 ./pg-ca.pem ./kafka-ca.pem

KAFKA_BROKERS="$(
  avn --auth-token "$AVN_AUTH_TOKEN" service get "$KAFKA_SVC" --project "$PROJECT" --json \
  | python3 - <<'PY'
import json,sys

j=json.load(sys.stdin)
ci=j.get("connection_info") or {}

def items(x):
  if x is None: return []
  if isinstance(x, list): return x
  return [x]

def pick_component(ci, want):
  if isinstance(ci, list):
    for e in ci:
      if isinstance(e, dict) and e.get("component")==want:
        h=e.get("host")
        p=e.get("port")
        if h and p: return [f"{h}:{p}"]
    return []
  if isinstance(ci, dict):
    v=ci.get(want)
    out=[]
    for e in items(v):
      if isinstance(e, dict):
        h=e.get("host")
        p=e.get("port")
        if h and p: out.append(f"{h}:{p}")
      elif isinstance(e, str):
        out.append(e)
    return out
  return []

brokers = pick_component(ci, "kafka_sasl")
if not brokers:
  brokers = pick_component(ci, "kafka_sasl_ssl")
if not brokers:
  brokers = pick_component(ci, "kafka_sasl_ssl_auth")
if not brokers:
  raise SystemExit("no kafka_sasl endpoint found in connection_info")

print(",".join(brokers))
PY
)"

cat > .env <<EOF
KAFKA_BROKERS=$KAFKA_BROKERS
KAFKA_USERNAME=$KAFKA_USER
KAFKA_PASSWORD=$KAFKA_PASS
KAFKA_CA_PATH=./kafka-ca.pem
KAFKA_SASL_MECHANISM=scram-sha-256
PG_DSN=$PG_URI
PG_CA_PATH=./pg-ca.pem
TOPIC_CLICKSTREAM=clickstream.events
SESSION_TIMEOUT_MIN=30
DLQ_TOPIC=clickstream.dlq
MAX_BATCH_EVENTS=300
EOF

perl -pi -e 's/\r$//; s/\$+$//' .env
printf "WROTE .env\n"
nl -ba .env | sed -n '1,120p'
