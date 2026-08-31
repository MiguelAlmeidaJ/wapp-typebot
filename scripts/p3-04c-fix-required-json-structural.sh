#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/modules/segments/segment.service.ts"

echo "[P3.4c] Structurally fixing required segment JSON..."

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

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

for (
  const marker
  of [
    "toPrismaJson",
    "createSegment",
    "updateSegment",
    "segmentDefinitionSchema",
    "AppError",
    "Prisma"
  ]
) {
  if (
    !content.includes(
      marker
    )
  ) {
    throw new Error(
      `Expected P3.4 marker missing: ${marker}`
    );
  }
}

const optionalDefinitionPattern =
  /toPrismaJson\s*\(\s*definition\s*\)/g;

const rawMatches =
  content.match(
    optionalDefinitionPattern
  ) ??
  [];

const alreadyFixedMatches =
  content.match(
    /requiredPrismaJson\s*\(\s*definition\s*\)/g
  ) ??
  [];

if (
  rawMatches.length ===
    0 &&
  alreadyFixedMatches.length ===
    2
) {
  console.log(
    "[P3.4c] Segment JSON writes are already fixed."
  );
} else {
  if (
    rawMatches.length !==
    2
  ) {
    throw new Error(
      `Expected exactly 2 toPrismaJson(definition) writes, found ${rawMatches.length}.`
    );
  }

  content =
    content.replace(
      optionalDefinitionPattern,
      "requiredPrismaJson(definition)"
    );

  if (
    !content.includes(
      "function requiredPrismaJson("
    )
  ) {
    const preferredAnchor =
      "async function validateReferences";

    const fallbackAnchor =
      "export function buildSegmentWhere";

    let insertAt =
      content.indexOf(
        preferredAnchor
      );

    if (
      insertAt <
      0
    ) {
      insertAt =
        content.indexOf(
          fallbackAnchor
        );
    }

    if (
      insertAt <
      0
    ) {
      throw new Error(
        "Could not find a semantic insertion point for requiredPrismaJson()."
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
        insertAt
      ) +
      helper +
      content.slice(
        insertAt
      );
  }
}

const finalRequiredMatches =
  content.match(
    /requiredPrismaJson\s*\(\s*definition\s*\)/g
  ) ??
  [];

if (
  finalRequiredMatches.length !==
  2
) {
  throw new Error(
    `Expected 2 requiredPrismaJson(definition) writes after repair, found ${finalRequiredMatches.length}.`
  );
}

if (
  /toPrismaJson\s*\(\s*definition\s*\)/.test(
    content
  )
) {
  throw new Error(
    "Raw optional toPrismaJson(definition) assignment still exists."
  );
}

if (
  !content.includes(
    "function requiredPrismaJson("
  ) ||
  !content.includes(
    "Prisma.InputJsonValue"
  ) ||
  !content.includes(
    "SEGMENT_DEFINITION_SERIALIZATION_FAILED"
  )
) {
  throw new Error(
    "Required segment JSON guard verification failed."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.4c] Required JSON guard installed and both writes verified."
);
NODE

echo "[P3.4c] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.4c] Segment smoke..."
node scripts/p3-04-segment-smoke.mjs

echo "[P3.4c] Unit tests..."
pnpm test

echo "[P3.4c] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.4c] P3.4 CODE VALIDATION PASS."
echo
echo "Migration is still NOT executed by this hotfix."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
