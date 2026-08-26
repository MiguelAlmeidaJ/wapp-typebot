#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEMA="apps/api/prisma/schema.prisma"

if [[ ! -f "$SCHEMA" ]]; then
  echo "ERROR: $SCHEMA not found."
  exit 1
fi

echo "[P0.6b] Repairing WhatsAppConnection relations..."

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

const malformed = `  company      Company
  tickets      Ticket[]
  messages     Message[]                  @relation(fields: [companyId], references: [id], onDelete: Cascade)`;

const fixed = `  company      Company                  @relation(fields: [companyId], references: [id], onDelete: Cascade)
  tickets      Ticket[]
  messages     Message[]`;

if (schema.includes(malformed)) {
  schema = schema.replace(malformed, fixed);
  fs.writeFileSync(path, schema);
  console.log("Fixed malformed WhatsAppConnection relation block.");
} else if (schema.includes(fixed)) {
  console.log("WhatsAppConnection relation block is already correct.");
} else {
  const start = schema.indexOf("model WhatsAppConnection {");
  const end = start >= 0 ? schema.indexOf("\n}", start) : -1;

  if (start >= 0 && end >= 0) {
    console.error("Unexpected WhatsAppConnection model:");
    console.error(schema.slice(start, end + 2));
  }

  throw new Error(
    "Could not find the expected WhatsAppConnection relation block. No automatic changes were made."
  );
}
NODE

echo "[P0.6b] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P0.6b] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P0.6b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.6b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.6b] Repair complete."
echo
echo "Continue with:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name conversations"
