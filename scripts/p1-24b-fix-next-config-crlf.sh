#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NEXT_CONFIG="apps/web/next.config.ts"
ORIGINAL_INSTALLER="scripts/p1-24-production-deployment.sh"

for required in \
  "$NEXT_CONFIG" \
  "$ORIGINAL_INSTALLER"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

echo "[P1.24b] Normalizing Next.js production config..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/next.config.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  )
    .replace(
      /\r\n/g,
      "\n"
    );

const nextImport =
  'import type { NextConfig } from "next";';

const pathImport =
  'import path from "node:path";';

if (
  !content.includes(
    pathImport
  )
) {
  if (
    !content.includes(
      nextImport
    )
  ) {
    throw new Error(
      "NextConfig import not found."
    );
  }

  content =
    content.replace(
      nextImport,
      `${pathImport}
${nextImport}`
    );
}

if (
  !content.includes(
    'output: "standalone"'
  )
) {
  const declaration =
    "const nextConfig: NextConfig = {";

  const index =
    content.indexOf(
      declaration
    );

  if (
    index <
    0
  ) {
    throw new Error(
      "nextConfig declaration not found."
    );
  }

  const insertAt =
    index +
    declaration.length;

  content =
    content.slice(
      0,
      insertAt
    ) +
    `
  output: "standalone",
  outputFileTracingRoot: path.join(
    process.cwd(),
    "../.."
  ),` +
    content.slice(
      insertAt
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Next.js standalone config installed."
);
NODE

echo "[P1.24b] Checking Next.js config..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.24b] Resuming original P1.24 installer..."
bash "$ORIGINAL_INSTALLER"
