#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/modules/media/media-storage.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.2c] Fixing strict MIME extension lookup..."

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/modules/media/media-storage.ts";
let content = fs.readFileSync(path, "utf8");

const oldBlock = `  return (
    (mimetype
      ? mimeExtensions[
          mimetype
            .split(";")[0]
            ?.trim()
            .toLowerCase()
        ]
      : undefined) ?? ".bin"
  );`;

const newBlock = `  const normalizedMime = mimetype
    ?.split(";")[0]
    ?.trim()
    .toLowerCase();

  return (
    (normalizedMime
      ? mimeExtensions[normalizedMime]
      : undefined) ?? ".bin"
  );`;

if (content.includes(oldBlock)) {
  content = content.replace(oldBlock, newBlock);
} else if (!content.includes("const normalizedMime = mimetype")) {
  throw new Error(
    "Could not find expected MIME lookup block in media-storage.ts."
  );
}

fs.writeFileSync(path, content);
console.log("Strict-safe MIME lookup installed.");
NODE

echo "[P1.2c] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.2c] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.2c] Typechecks passed."
echo
echo "Continue with:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name message_media"
echo "  pnpm dev"
