#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="scripts/backup-restore-drill.sh"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.18d] Improving restore-drill mysqlcheck diagnostics..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "scripts/backup-restore-drill.sh";

let content =
  fs.readFileSync(path, "utf8");

const oldBlock = `echo "[backup:drill] Executando mysqlcheck..."

docker exec \\
  --env "MYSQL_PWD=$DRILL_PASSWORD" \\
  "$CONTAINER" \\
  mysqlcheck \\
    --user=root \\
    --check \\
    "$DRILL_DB" \\
    >/dev/null

echo "[backup:drill] mysqlcheck: OK"`;

const newBlock = `echo "[backup:drill] Executando mysqlcheck..."

set +e

MYSQLCHECK_OUTPUT="$(
  docker exec \\
    --env "MYSQL_PWD=$DRILL_PASSWORD" \\
    "$CONTAINER" \\
    mysqlcheck \\
      --protocol=TCP \\
      --host=127.0.0.1 \\
      --user=root \\
      --check \\
      "$DRILL_DB" \\
      2>&1
)"

MYSQLCHECK_STATUS=$?

set -e

if [[ -n "$MYSQLCHECK_OUTPUT" ]]; then
  printf '%s\\n' "$MYSQLCHECK_OUTPUT"
fi

if [[ "$MYSQLCHECK_STATUS" -ne 0 ]]; then
  echo
  echo "[backup:drill] mysqlcheck FALHOU com exit code $MYSQLCHECK_STATUS."
  echo "[backup:drill] O restore SQL foi concluído, mas a validação estrutural ainda não foi aprovada."
  exit "$MYSQLCHECK_STATUS"
fi

echo "[backup:drill] mysqlcheck: OK"`;

if (
  content.includes(
    oldBlock
  )
) {
  content =
    content.replace(
      oldBlock,
      newBlock
    );
} else if (
  content.includes(
    "MYSQLCHECK_OUTPUT="
  )
) {
  console.log(
    "mysqlcheck diagnostics already installed."
  );
} else {
  throw new Error(
    "Could not find expected mysqlcheck block."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "mysqlcheck output is now preserved and TCP connection is explicit."
);
NODE

echo "[P1.18d] Shell syntax..."
bash -n "$FILE"

echo
echo "[P1.18d] Diagnostic fix installed."
echo
echo "Run again:"
echo "  pnpm backup:drill -- .backups/wapp-20260828T111956Z"
