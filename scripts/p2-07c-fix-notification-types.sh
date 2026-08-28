#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

INGESTION="apps/api/src/modules/messages/message-ingestion.service.ts"
ROUTES="apps/api/src/modules/notifications/notification.routes.ts"

echo "[P2.7c] Fixing notification type contracts..."

for required in "$INGESTION" "$ROUTES"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

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

const oldBlock = `      preview:
        parsed.body,
      fallbackPreview:`;

const newBlock = `      preview:
        parsed.body ??
        null,
      fallbackPreview:`;

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
  !content.includes(
    `preview:
        parsed.body ??
        null,`
  )
) {
  throw new Error(
    "Inbound notification preview anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.7c] parsed.body normalized to string | null."
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/notifications/notification.routes.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldBlock = `    unreadOnly:
      z.enum([
        "true",
        "false"
      ])
        .transform(
          value =>
            value ===
            "true"
        )
        .default(
          "false"
        )`;

const newBlock = `    unreadOnly:
      z.enum([
        "true",
        "false"
      ])
        .default(
          "false"
        )
        .transform(
          value =>
            value ===
            "true"
        )`;

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
  !content.includes(
    `.default(
          "false"
        )
        .transform(`
  )
) {
  throw new Error(
    "Notification unreadOnly schema anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.7c] unreadOnly default now applies before boolean transform."
);
NODE

echo "[P2.7c] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.7c] Unit tests..."
pnpm test

echo "[P2.7c] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.7c] P2.7 CODE VALIDATION PASS."
echo
echo "Migration is still NOT executed by this hotfix."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
