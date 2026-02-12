#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# Remove any existing PG_CA_CERT_PATH lines
if [ -f .env ]; then
  perl -i -ne 'print unless /^PG_CA_CERT_PATH=/' .env
else
  touch .env
fi

# Add a single correct value (we expand ~ in our TS)
echo 'PG_CA_CERT_PATH="~/.postgresql/root.crt"' >> .env

echo "PG_CA_CERT_PATH now:"
grep -n '^PG_CA_CERT_PATH=' .env || true

echo
echo "Checking CA file exists:"
ls -lah ~/.postgresql/root.crt

echo
echo "Node sees expanded path?"
node -e '
const fs=require("fs");
const path=require("path");
let p=process.env.PG_CA_CERT_PATH||"";
if(p.startsWith("~/")) p=path.join(process.env.HOME, p.slice(2));
console.log("PG_CA_CERT_PATH(expanded) =", p);
console.log("exists? =", fs.existsSync(p));
process.exit(fs.existsSync(p)?0:1);
'
