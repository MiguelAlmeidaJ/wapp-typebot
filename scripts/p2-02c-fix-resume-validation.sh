#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET="scripts/p2-02b-resume-message-reactions.sh"

echo "[P2.2c] Fixing P2.2b literal-state validation..."

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: missing $TARGET"
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const path =
  "scripts/p2-02b-resume-message-reactions.sh";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldLine =
  '  if ! grep -q "$marker" apps/api/prisma/schema.prisma; then';

const newLine =
  '  if ! grep -Fq -- "$marker" apps/api/prisma/schema.prisma; then';

if (
  content.includes(
    oldLine
  )
) {
  content =
    content.replace(
      oldLine,
      newLine
    );
} else if (
  !content.includes(
    'grep -Fq -- "$marker" apps/api/prisma/schema.prisma'
  )
) {
  throw new Error(
    "P2.2b marker-validation line not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "P2.2b marker validation now uses literal grep."
);
NODE

echo "[P2.2c] Checking corrected installer syntax..."
bash -n "$TARGET"

echo "[P2.2c] Verifying actual partial backend state..."

grep -Fq -- \
  "model MessageReaction" \
  apps/api/prisma/schema.prisma

grep -Fq -- \
  "reactions              MessageReaction[]" \
  apps/api/prisma/schema.prisma

grep -Fq -- \
  "async sendReaction(" \
  apps/api/src/integrations/whatsapp/evolution.client.ts

grep -Fq -- \
  "message.reaction.updated" \
  apps/api/src/modules/realtime/realtime.bus.ts

echo "[P2.2c] Partial backend state confirmed."
echo
echo "[P2.2c] Resuming P2.2b..."
bash "$TARGET"
