#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/integrations/whatsapp/evolution.client.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.20c] Fixing Evolution 2.3.7 webhook/set payload..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/evolution.client.ts";

let content =
  fs.readFileSync(path, "utf8");

const oldBlock = `        body: JSON.stringify({
          enabled: true,
          url: input.webhookUrl,
          webhookByEvents: false,
          webhookBase64: false,
          base64: false,
          events: input.events
        })`;

const newBlock = `        body: JSON.stringify({
          webhook: {
            enabled: true,
            url: input.webhookUrl,
            byEvents: false,
            base64: false,
            events: input.events
          }
        })`;

if (content.includes(oldBlock)) {
  content =
    content.replace(
      oldBlock,
      newBlock
    );

  fs.writeFileSync(
    path,
    content
  );

  console.log(
    "Evolution webhook payload normalized."
  );
} else if (
  content.includes(
    "webhook: {\n            enabled: true,"
  )
) {
  console.log(
    "Evolution webhook payload already fixed."
  );
} else {
  throw new Error(
    "Could not find expected configureWebhook payload."
  );
}
NODE

echo "[P1.20c] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.20c] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.20c] Evolution webhook contract fixed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then:"
echo "  open /dashboard/connections"
echo "  click Atualizar status"
echo "  confirm no webhook schema error is shown"
