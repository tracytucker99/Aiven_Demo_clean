#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

ABS_CA="${HOME}/.postgresql/root.crt"

if [ ! -f "$ABS_CA" ]; then
  echo "❌ Missing CA at: $ABS_CA"
  exit 1
fi

# Remove any existing PG_CA_CERT_PATH lines
perl -i -ne 'print unless /^PG_CA_CERT_PATH=/' .env 2>/dev/null || true

# Add a single absolute path
echo "PG_CA_CERT_PATH=\"$ABS_CA\"" >> .env

echo "✅ Set PG_CA_CERT_PATH to:"
grep -n '^PG_CA_CERT_PATH=' .env

echo
echo "✅ File exists:"
ls -lah "$ABS_CA"

echo
echo "✅ Node sees it (no ~ expansion needed):"
set -a; source .env; set +a
node -e '
const fs=require("fs");
const p=process.env.PG_CA_CERT_PATH||"";
console.log("PG_CA_CERT_PATH =", p);
console.log("exists? =", fs.existsSync(p));
process.exit(fs.existsSync(p)?0:1);
'
