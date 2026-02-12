#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"

echo "This will append Kafka connection settings to $ENV_FILE"
echo "You can find these values in your Aiven Kafka service connection info."
echo

read -rp "Bootstrap host (example: kafka-xyz.aivencloud.com): " KAFKA_HOST
read -rp "Bootstrap port (example: 12345): " KAFKA_PORT
read -rp "SASL username: " KAFKA_USERNAME
read -rsp "SASL password (will not echo): " KAFKA_PASSWORD; echo
read -rp "Topic name [clickstream]: " KAFKA_TOPIC
KAFKA_TOPIC="${KAFKA_TOPIC:-clickstream}"

# Optional CA path (you already have kafka-ca.pem)
read -rp "CA path [./kafka-ca.pem]: " KAFKA_CA_PATH
KAFKA_CA_PATH="${KAFKA_CA_PATH:-./kafka-ca.pem}"

# Append (do not overwrite)
{
  echo
  echo "# --- Kafka (Aiven) ---"
  echo "KAFKA_BROKERS=${KAFKA_HOST}:${KAFKA_PORT}"
  echo "KAFKA_USERNAME=${KAFKA_USERNAME}"
  echo "KAFKA_PASSWORD=${KAFKA_PASSWORD}"
  echo "KAFKA_TOPIC=${KAFKA_TOPIC}"
  echo "KAFKA_CA_PATH=${KAFKA_CA_PATH}"
} >> "$ENV_FILE"

echo
echo "✅ Wrote Kafka settings to $ENV_FILE"
echo "   Brokers: ${KAFKA_HOST}:${KAFKA_PORT}"
echo "   Topic:   ${KAFKA_TOPIC}"
echo "   CA:      ${KAFKA_CA_PATH}"
