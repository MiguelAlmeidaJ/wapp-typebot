#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/integrations/whatsapp/evolution.client.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.3b] Fixing Evolution sendMedia multipart contract..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/evolution.client.ts";

let content = fs.readFileSync(path, "utf8");

const oldBlock = `    form.append(
      "media",
      blob,
      input.fileName
    );`;

const newBlock = `    /*
     * Evolution 2.3.7 wires /message/sendMedia through
     * multer upload.single("file"). The binary multipart field
     * must therefore be named "file", not "media".
     */
    form.append(
      "file",
      blob,
      input.fileName
    );`;

if (content.includes(oldBlock)) {
  content = content.replace(
    oldBlock,
    newBlock
  );
} else if (
  !content.includes(
    'form.append(\n      "file",\n      blob,'
  )
) {
  throw new Error(
    "Could not find the P1.3 Evolution multipart media field."
  );
}

/*
 * Keep the MIME information explicit in the multipart body as well.
 * Evolution has the uploaded file metadata, but this keeps the DTO/body
 * aligned with its sendMedia contract and makes troubleshooting easier.
 */
if (
  !content.includes(
    'form.append(\n      "mimetype",\n      input.mimetype'
  )
) {
  const anchor = `    form.append(
      "fileName",
      input.fileName
    );`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find Evolution fileName multipart field."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
    form.append(
      "mimetype",
      input.mimetype
    );`
  );
}

fs.writeFileSync(path, content);

console.log('Evolution binary field normalized to "file".');
console.log("MIME field included explicitly.");
NODE

echo "[P1.3b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.3b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.3b] Evolution multipart contract fixed."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then retry the same image without changing the frontend."
