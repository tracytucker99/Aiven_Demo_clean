#!/usr/bin/env bash
set -euo pipefail

: "${PG_DSN:?PG_DSN must be set (do not store it in git)}"

echo "Testing Postgres connectivity..."
psql "$PG_DSN" -c "select now();"

echo "Done."
