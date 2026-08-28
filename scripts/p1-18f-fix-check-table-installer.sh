#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="scripts/backup-restore-drill.sh"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.18f] Installing portable CHECK TABLE validation..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "scripts/backup-restore-drill.sh";

let content =
  fs.readFileSync(path, "utf8");

if (
  content.includes(
    '[backup:drill] CHECK TABLE: OK'
  )
) {
  console.log(
    "Portable CHECK TABLE validation already installed."
  );
  process.exit(0);
}

const startMarker =
  'echo "[backup:drill] Executando mysqlcheck..."';

const endMarker =
  'echo "[backup:drill] mysqlcheck: OK"';

const start =
  content.indexOf(
    startMarker
  );

const end =
  content.indexOf(
    endMarker,
    start
  );

if (
  start < 0 ||
  end < 0
) {
  throw new Error(
    "Could not find current mysqlcheck block."
  );
}

const replacement = [
  'echo "[backup:drill] Executando CHECK TABLE em todas as tabelas..."',
  '',
  'TABLE_LIST="$(',
  '  docker exec \\',
  '    --env "MYSQL_PWD=$DRILL_PASSWORD" \\',
  '    "$CONTAINER" \\',
  '    mysql \\',
  '      --protocol=TCP \\',
  '      --host=127.0.0.1 \\',
  '      --batch \\',
  '      --skip-column-names \\',
  '      --user=root \\',
  '      --execute="SELECT table_name FROM information_schema.tables WHERE table_schema=\'${DRILL_DB}\' AND table_type=\'BASE TABLE\' ORDER BY table_name;"',
  ')"',
  '',
  'if [[ -z "$TABLE_LIST" ]]; then',
  '  echo "[backup:drill] Nenhuma tabela encontrada para CHECK TABLE."',
  '  exit 1',
  'fi',
  '',
  'CHECK_FAILED=false',
  '',
  'while IFS= read -r TABLE_NAME; do',
  '  [[ -z "$TABLE_NAME" ]] && continue',
  '',
  '  CHECK_OUTPUT="$(',
  '    docker exec \\',
  '      --env "MYSQL_PWD=$DRILL_PASSWORD" \\',
  '      "$CONTAINER" \\',
  '      mysql \\',
  '        --protocol=TCP \\',
  '        --host=127.0.0.1 \\',
  '        --batch \\',
  '        --skip-column-names \\',
  '        --user=root \\',
  '        "$DRILL_DB" \\',
  '        --execute="CHECK TABLE \\`${TABLE_NAME}\\`;" \\',
  '      2>&1',
  '  )"',
  '',
  '  printf \'%s\\n\' "$CHECK_OUTPUT"',
  '',
  '  if ! printf \'%s\\n\' "$CHECK_OUTPUT" |',
  '    awk -F \'\\t\' \'',
  '      $3 == "status" && $4 == "OK" {',
  '        ok = 1',
  '      }',
  '      END {',
  '        exit ok ? 0 : 1',
  '      }',
  '    \'',
  '  then',
  '    CHECK_FAILED=true',
  '  fi',
  'done <<< "$TABLE_LIST"',
  '',
  'if [[ "$CHECK_FAILED" == "true" ]]; then',
  '  echo',
  '  echo "[backup:drill] CHECK TABLE encontrou uma ou mais tabelas com problema."',
  '  exit 1',
  'fi',
  '',
  'echo "[backup:drill] CHECK TABLE: OK"'
].join("\n");

const afterEnd =
  end +
  endMarker.length;

content =
  content.slice(
    0,
    start
  ) +
  replacement +
  content.slice(
    afterEnd
  );

fs.writeFileSync(
  path,
  content
);

console.log(
  "mysqlcheck replaced with portable CHECK TABLE validation."
);
NODE

echo "[P1.18f] Shell syntax..."
bash -n "$FILE"

echo "[P1.18f] Confirming replacement..."

if grep -q 'Executando mysqlcheck' "$FILE"; then
  echo "ERROR: old mysqlcheck block still present."
  exit 1
fi

if ! grep -q 'CHECK TABLE: OK' "$FILE"; then
  echo "ERROR: CHECK TABLE validation was not installed."
  exit 1
fi

echo
echo "[P1.18f] Restore drill fixed."
echo
echo "Run:"
echo "  pnpm backup:drill -- .backups/wapp-20260828T111956Z"
