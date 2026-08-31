#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/modules/segments/segment.service.ts"

echo "[P3.4b] Fixing required segment JSON persistence..."

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

for marker in \
  'import type {' \
  'toPrismaJson' \
  'segmentDefinitionSchema' \
  'definition:' \
  'createSegment' \
  'updateSegment'
do
  if ! grep -Fq -- "$marker" "$FILE"; then
    echo "ERROR: expected P3.4 marker missing: $marker"
    echo "Inspect $FILE before applying another fix."
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/segments/segment.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !content.includes(
    "function requiredPrismaJson("
  )
) {
  const anchor = `function jsonOptions(
  value:
    unknown
) {`;

  const index =
    content.indexOf(
      anchor
    );

  if (
    index < 0
  ) {
    throw new Error(
      "jsonOptions anchor not found in segment.service.ts."
    );
  }

  const helper = `function requiredPrismaJson(
  value:
    unknown
):
  Prisma.InputJsonValue {
  const json =
    toPrismaJson(
      value
    );

  if (
    json ===
    undefined
  ) {
    throw new AppError(
      "A definição do segmento não pôde ser serializada.",
      500,
      "SEGMENT_DEFINITION_SERIALIZATION_FAILED"
    );
  }

  return json;
}

`;

  content =
    content.slice(
      0,
      index
    ) +
    helper +
    content.slice(
      index
    );
}

const rawMatches =
  content.match(
    /toPrismaJson\(\s*definition\s*\)/g
  ) ??
  [];

if (
  rawMatches.length >
  0
) {
  content =
    content.replace(
      /toPrismaJson\(\s*definition\s*\)/g,
      "requiredPrismaJson(definition)"
    );
}

const requiredMatches =
  content.match(
    /requiredPrismaJson\(definition\)/g
  ) ??
  [];

if (
  requiredMatches.length !==
  2
) {
  throw new Error(
    `Expected exactly 2 required segment JSON writes, found ${requiredMatches.length}.`
  );
}

if (
  /definition:\s*toPrismaJson\(\s*definition\s*\)/.test(
    content
  )
) {
  throw new Error(
    "A raw optional toPrismaJson(definition) assignment still exists."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.4b] Required JSON guard installed for create/update."
);
NODE

echo "[P3.4b] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.4b] Segment smoke..."
node scripts/p3-04-segment-smoke.mjs

echo "[P3.4b] Unit tests..."
pnpm test

echo "[P3.4b] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.4b] P3.4 CODE VALIDATION PASS."
echo
echo "Migration is still NOT executed by this hotfix."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
