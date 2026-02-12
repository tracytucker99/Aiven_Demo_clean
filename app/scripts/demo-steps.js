console.log(`
=== Aiven Clickstream Demo Run Order (app/) ===

Terminal A (Reset + Consumer):
  set -a; source .env; set +a
  npm run demo:reset
  npm run demo:consumer

Terminal B (Producer burst):
  set -a; source .env; set +a
  npm run demo:burst

Proof / Talk Track Queries (any terminal):
  set -a; source .env; set +a
  npm run demo:proof

Notes:
- demo:consumer runs continuously; leave it running during the demo.
- demo:burst is a fixed burst (500 events @ 50ms). Adjust in package.json if desired.
- demo:proof prints: counts/users/time-range, top pages, and last 10 events.
`);
