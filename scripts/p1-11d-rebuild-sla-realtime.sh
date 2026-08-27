#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/web/components/conversations/sla-monitor-drawer.tsx"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.11d] Rebuilding SLA realtime effect..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/components/conversations/sla-monitor-drawer.tsx";

let content =
  fs.readFileSync(path, "utf8");

const pattern =
  /  useEffect\(\(\) => \{\n    return subscribe\([\s\S]*?\n  \}, \[\n    load,\n    subscribe\n  \]\);/;

if (!pattern.test(content)) {
  throw new Error(
    "Could not find the SLA realtime useEffect block."
  );
}

const replacement = `  useEffect(() => {
    return subscribe(
      "/api/v1/realtime/events",
      event => {
        if (
          event.type ===
            "ticket.created" ||
          event.type ===
            "ticket.updated" ||
          event.type ===
            "message.created" ||
          event.type ===
            "sla.updated"
        ) {
          void load();
        }
      }
    );
  }, [
    load,
    subscribe
  ]);`;

content =
  content.replace(
    pattern,
    replacement
  );

fs.writeFileSync(
  path,
  content
);

console.log(
  "SLA realtime effect rebuilt."
);
NODE

echo "[P1.11d] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo "[P1.11d] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo
echo "[P1.11d] SLA realtime effect is valid."
echo
echo "If both typechecks passed:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name operational_sla"
echo "  pnpm --filter @wapp/api exec tsx src/scripts/backfill-ticket-sla.ts"
echo "  pnpm dev"
