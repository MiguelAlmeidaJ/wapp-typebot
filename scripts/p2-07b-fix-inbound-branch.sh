#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/modules/messages/message-ingestion.service.ts"

echo "[P2.7b] Repairing duplicated inbound notification branch..."

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

if ! grep -Fq -- "notifyInboundTicketActivity({" "$FILE"; then
  echo "ERROR: P2.7 inbound notification integration was not found."
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/message-ingestion.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const duplicated = `    if (!before) {
    if (!before) {`;

const corrected = `    if (!before) {`;

const occurrences =
  content
    .split(
      duplicated
    )
    .length -
  1;

if (
  occurrences ===
  1
) {
  content =
    content.replace(
      duplicated,
      corrected
    );
} else if (
  occurrences ===
    0 &&
  content.includes(
    "notifyInboundTicketActivity({"
  )
) {
  /*
   * Do not guess if the source differs from the known P2.7 failure.
   * A zero match here means somebody may already have edited this area.
   */
  throw new Error(
    "Expected duplicated if (!before) block was not found. Inspect the current source before applying another fix."
  );
} else {
  throw new Error(
    `Expected exactly one duplicated if (!before) block, found ${occurrences}.`
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.7b] Duplicate if (!before) removed."
);
NODE

echo "[P2.7b] API syntax/typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.7b] Unit tests..."
pnpm test

echo "[P2.7b] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.7b] P2.7 CODE VALIDATION PASS."
echo
echo "Migration is still NOT executed by this hotfix."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
