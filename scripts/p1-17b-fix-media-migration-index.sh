#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/scripts/migrate-local-media-to-s3.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.17b] Fixing strict indexed access in media migration..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/scripts/migrate-local-media-to-s3.ts";

let content =
  fs.readFileSync(path, "utf8");

const wrong =
  `    const absolute =
      files[index];`;

const correct =
  `    const absolute =
      files[index]!;`;

if (content.includes(wrong)) {
  content =
    content.replace(
      wrong,
      correct
    );
} else if (
  content.includes(
    `const absolute =
      files[index]!;`
  )
) {
  console.log(
    "Strict indexed access already fixed."
  );
} else {
  throw new Error(
    "Could not find expected files[index] assignment."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Media migration indexed access fixed."
);
NODE

echo "[P1.17b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.17b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.17b] Media migration typing fixed."
echo
echo "No Prisma migration is required."
echo
echo "Next:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Keep locally:"
echo "  MEDIA_STORAGE_DRIVER=local"
