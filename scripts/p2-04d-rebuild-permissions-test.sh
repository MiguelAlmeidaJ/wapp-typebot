#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PERMISSIONS="apps/api/src/security/permissions.ts"
TEST="apps/api/src/security/permissions.test.ts"

echo "[P2.4d] Rebuilding the corrupted allPermissions declaration..."

for required in "$PERMISSIONS" "$TEST"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");

const permissionsPath =
  "apps/api/src/security/permissions.ts";

const testPath =
  "apps/api/src/security/permissions.test.ts";

const permissionsSource =
  fs.readFileSync(
    permissionsPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

let testSource =
  fs.readFileSync(
    testPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const typeStart =
  permissionsSource.indexOf(
    "export type WappPermission"
  );

if (typeStart < 0) {
  throw new Error(
    "WappPermission declaration not found."
  );
}

const typeEnd =
  permissionsSource.indexOf(
    ";",
    typeStart
  );

if (typeEnd < 0) {
  throw new Error(
    "WappPermission declaration end not found."
  );
}

const typeBlock =
  permissionsSource.slice(
    typeStart,
    typeEnd
  );

const permissions =
  Array.from(
    typeBlock.matchAll(
      /"([^"]+)"/g
    ),
    match =>
      match[1]
  );

if (
  permissions.length === 0
) {
  throw new Error(
    "No WappPermission values were parsed."
  );
}

const uniquePermissions =
  Array.from(
    new Set(
      permissions
    )
  );

const declarationStart =
  testSource.indexOf(
    "const allPermissions:"
  );

if (declarationStart < 0) {
  throw new Error(
    "allPermissions declaration start not found."
  );
}

const firstDescribe =
  testSource.indexOf(
    "describe(",
    declarationStart
  );

if (firstDescribe < 0) {
  throw new Error(
    "First describe block not found after allPermissions."
  );
}

const declaration = `const allPermissions:
  WappPermission[] = [
${uniquePermissions
  .map(
    permission =>
      `    "${permission}"`
  )
  .join(",\n")}
  ];

`;

testSource =
  testSource.slice(
    0,
    declarationStart
  ) +
  declaration +
  testSource.slice(
    firstDescribe
  );

fs.writeFileSync(
  testPath,
  testSource
);

console.log(
  `[P2.4d] allPermissions rebuilt with ${uniquePermissions.length} permissions.`
);

console.log(
  `[P2.4d] Includes automations.read: ${uniquePermissions.includes("automations.read")}`
);

console.log(
  `[P2.4d] Includes automations.manage: ${uniquePermissions.includes("automations.manage")}`
);
NODE

echo "[P2.4d] Verifying repaired test syntax..."
pnpm --filter @wapp/api exec tsc -p tsconfig.json --noEmit --pretty false

echo "[P2.4d] Unit tests..."
pnpm test

echo "[P2.4d] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.4d] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.4d] P2.4 code validation PASS."
echo
echo "Migration has still NOT been executed by this hotfix."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
