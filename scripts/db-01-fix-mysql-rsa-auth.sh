#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/lib/database.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[DB.1] Fixing MySQL 8.4 caching_sha2_password authentication..."

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/lib/database.ts";
let content = fs.readFileSync(path, "utf8");

if (!content.includes("allowPublicKeyRetrieval:")) {
  const anchor = `    database: databaseUrl.pathname.replace(/^\\//, ""),
    connectionLimit: 10`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find PrismaMariaDb connection configuration."
    );
  }

  content = content.replace(
    anchor,
    `    database: databaseUrl.pathname.replace(/^\\//, ""),
    connectionLimit: 10,

    /*
     * MySQL 8.x defaults to caching_sha2_password.
     * MariaDB Connector/Node does not retrieve the server RSA key unless
     * explicitly allowed.
     *
     * Local development runs without TLS, so allow key retrieval here.
     * Production must use TLS and/or an explicitly configured server key.
     */
    allowPublicKeyRetrieval:
      env.NODE_ENV !== "production"`
  );
}

fs.writeFileSync(path, content);
console.log("MySQL RSA authentication compatibility enabled for non-production.");
NODE

echo "[DB.1] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo
echo "[DB.1] Fix applied."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then test:"
echo "  http://localhost:4000/health"
