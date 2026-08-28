#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/config/env.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.20b] Fixing optional S3 environment validation..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/config/env.ts";

let content =
  fs.readFileSync(path, "utf8");

const replacements = [
  [
    'S3_BUCKET: z.string().min(1).optional(),',
    'S3_BUCKET: z.string().min(1).optional().or(z.literal("")),'
  ],
  [
    'S3_ACCESS_KEY_ID: z.string().min(1).optional(),',
    'S3_ACCESS_KEY_ID: z.string().min(1).optional().or(z.literal("")),'
  ],
  [
    'S3_SECRET_ACCESS_KEY: z.string().min(1).optional(),',
    'S3_SECRET_ACCESS_KEY: z.string().min(1).optional().or(z.literal("")),'
  ]
];

let changed = 0;

for (const [before, after] of replacements) {
  if (content.includes(before)) {
    content = content.replace(
      before,
      after
    );
    changed += 1;
    continue;
  }

  if (!content.includes(after)) {
    throw new Error(
      `Expected S3 env schema anchor not found: ${before}`
    );
  }
}

fs.writeFileSync(
  path,
  content
);

console.log(
  changed > 0
    ? `Updated ${changed} optional S3 env fields.`
    : "Optional S3 env fields were already fixed."
);
NODE

echo "[P1.20b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.20b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.20b] Optional S3 validation fixed."
echo
echo "Keep local S3 values empty while using:"
echo "  MEDIA_STORAGE_DRIVER=local"
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
