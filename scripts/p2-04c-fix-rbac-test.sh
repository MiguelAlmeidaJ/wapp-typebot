#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.4c] Repairing RBAC test syntax and validating P2.4..."

PERMISSIONS="apps/api/src/security/permissions.ts"
TEST="apps/api/src/security/permissions.test.ts"

for required in \
  "$PERMISSIONS" \
  "$TEST" \
  "apps/api/src/modules/automations/automation.service.ts" \
  "apps/api/src/modules/automations/automation.routes.ts" \
  "apps/api/src/jobs/automation.worker.ts" \
  "apps/api/src/app.ts" \
  "apps/web/app/dashboard/automations/page.tsx"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

# Confirm the P2.4 tail actually persisted before repairing the test.
for check in \
  "$PERMISSIONS|automations.read" \
  "$PERMISSIONS|automations.manage" \
  "apps/api/src/app.ts|await app.register(automationRoutes);" \
  "apps/web/app/dashboard/automations/page.tsx|export default function AutomationsPage()"
do
  file="${check%%|*}"
  marker="${check#*|}"

  if ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: incomplete P2.4 state:"
    echo "  $file -> $marker"
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/security/permissions.test.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const marker =
  `const allPermissions:
  WappPermission[] = [`;

const start =
  content.indexOf(
    marker
  );

if (start < 0) {
  throw new Error(
    "allPermissions declaration not found."
  );
}

const listStart =
  content.indexOf(
    "[",
    start
  );

const listEnd =
  content.indexOf(
    "\n  ];",
    listStart
  );

if (
  listStart < 0 ||
  listEnd < 0
) {
  throw new Error(
    "allPermissions list boundary not found."
  );
}

const block =
  content.slice(
    listStart + 1,
    listEnd
  );

const permissions =
  Array.from(
    block.matchAll(
      /"([^"]+)"/g
    ),
    match =>
      match[1]
  );

for (
  const permission
  of [
    "automations.read",
    "automations.manage"
  ]
) {
  if (
    !permissions.includes(
      permission
    )
  ) {
    permissions.push(
      permission
    );
  }
}

const unique =
  Array.from(
    new Set(
      permissions
    )
  );

const rebuilt =
  unique
    .map(
      permission =>
        `    "${permission}"`
    )
    .join(",\n");

content =
  content.slice(
    0,
    listStart + 1
  ) +
  `\n${rebuilt}` +
  content.slice(
    listEnd
  );

fs.writeFileSync(
  path,
  content
);

console.log(
  `Rebuilt allPermissions with ${unique.length} valid entries.`
);
NODE

echo "[P2.4c] Syntax check..."
pnpm --filter @wapp/api exec tsc -p tsconfig.json --noEmit --pretty false

echo "[P2.4c] Unit tests..."
pnpm test

echo "[P2.4c] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.4c] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.4c] P2.4 code validation PASS."
echo
echo "Migration still has NOT been executed."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
