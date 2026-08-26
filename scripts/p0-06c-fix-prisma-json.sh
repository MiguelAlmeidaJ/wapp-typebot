#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.6c] Fixing Prisma JSON typing..."

mkdir -p apps/api/src/lib

cat > apps/api/src/lib/prisma-json.ts <<'EOF'
import type { Prisma } from "../generated/prisma/client.js";

/**
 * Prisma's JSON input type is intentionally stricter than `unknown`.
 *
 * HTTP webhook payloads are already JSON-compatible at runtime, but TypeScript
 * cannot infer that from Record<string, unknown>. Serializing once also removes
 * any accidental `undefined` values before persistence.
 */
export function toPrismaJson(
  value: unknown
): Prisma.InputJsonValue | undefined {
  if (value === undefined) {
    return undefined;
  }

  const serialized = JSON.stringify(value);

  if (serialized === undefined) {
    return undefined;
  }

  return JSON.parse(serialized) as Prisma.InputJsonValue;
}
EOF

node <<'NODE'
const fs = require("node:fs");

function updateMessageIngestion() {
  const path =
    "apps/api/src/modules/messages/message-ingestion.service.ts";

  let content = fs.readFileSync(path, "utf8");

  const importLine =
    'import { toPrismaJson } from "../../lib/prisma-json.js";';

  if (!content.includes(importLine)) {
    const anchor =
      'import { prisma } from "../../lib/database.js";';

    if (!content.includes(anchor)) {
      throw new Error(
        "Could not find prisma import in message-ingestion.service.ts"
      );
    }

    content = content.replace(
      anchor,
      `${anchor}\n${importLine}`
    );
  }

  content = content.replace(
    "rawPayload: parsed.rawPayload",
    "rawPayload: toPrismaJson(parsed.rawPayload)"
  );

  fs.writeFileSync(path, content);
}

function updateTicketService() {
  const path =
    "apps/api/src/modules/tickets/ticket.service.ts";

  let content = fs.readFileSync(path, "utf8");

  const importLine =
    'import { toPrismaJson } from "../../lib/prisma-json.js";';

  if (!content.includes(importLine)) {
    const anchor =
      'import { prisma } from "../../lib/database.js";';

    if (!content.includes(anchor)) {
      throw new Error(
        "Could not find prisma import in ticket.service.ts"
      );
    }

    content = content.replace(
      anchor,
      `${anchor}\n${importLine}`
    );
  }

  const oldBlock = `      rawPayload:
        result && typeof result === "object"
          ? (result as object)
          : undefined`;

  const newBlock = `      rawPayload: toPrismaJson(result)`;

  if (content.includes(oldBlock)) {
    content = content.replace(oldBlock, newBlock);
  } else if (!content.includes(newBlock)) {
    throw new Error(
      "Could not find rawPayload block in ticket.service.ts"
    );
  }

  fs.writeFileSync(path, content);
}

updateMessageIngestion();
updateTicketService();
NODE

echo "[P0.6c] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.6c] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.6c] JSON typing fixed."
echo
echo "Continue with:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name conversations"
