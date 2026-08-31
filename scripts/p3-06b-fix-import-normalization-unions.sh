#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

POLICY="apps/api/src/modules/data-quality/data-quality.policy.ts"

echo "[P3.6b] Fixing explicit import normalization unions..."

if [[ ! -f "$POLICY" ]]; then
  echo "ERROR: missing $POLICY"
  exit 1
fi

for marker in \
  'export function normalizeImportPhone(input: {' \
  'export function normalizeEmail(' \
  'INVALID_PHONE_LENGTH' \
  'INVALID_EMAIL'
do
  if ! grep -Fq -- "$marker" "$POLICY"; then
    echo "ERROR: expected P3.6 policy marker missing: $marker"
    echo "Inspect current source before applying another fix."
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/data-quality/data-quality.policy.ts";

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
    "export type NormalizedImportPhoneResult ="
  )
) {
  const anchor =
    `export function normalizeImportPhone(input: {`;

  const index =
    content.indexOf(
      anchor
    );

  if (
    index <
    0
  ) {
    throw new Error(
      "normalizeImportPhone declaration not found."
    );
  }

  const types = `export type NormalizedImportPhoneResult =
  | {
      phoneNumber: string;
      remoteJid: string;
    }
  | {
      error:
        | "INVALID_COUNTRY_CODE"
        | "PHONE_REQUIRED"
        | "INVALID_PHONE_LENGTH";
    };

export type NormalizedEmailResult =
  | {
      value: string | null;
    }
  | {
      error: "INVALID_EMAIL";
    };

`;

  content =
    content.slice(
      0,
      index
    ) +
    types +
    content.slice(
      index
    );
}

const phonePattern =
  /export function normalizeImportPhone\(input: \{\n  value:\n    string;\n  defaultCountryCode:\n    string;\n\}\) \{/;

if (
  phonePattern.test(
    content
  )
) {
  content =
    content.replace(
      phonePattern,
      `export function normalizeImportPhone(input: {
  value:
    string;
  defaultCountryCode:
    string;
}): NormalizedImportPhoneResult {`
    );
} else if (
  !content.includes(
    "}): NormalizedImportPhoneResult {"
  )
) {
  throw new Error(
    "normalizeImportPhone signature could not be normalized."
  );
}

const emailPattern =
  /export function normalizeEmail\(\n  value:\n    string\n\) \{/;

if (
  emailPattern.test(
    content
  )
) {
  content =
    content.replace(
      emailPattern,
      `export function normalizeEmail(
  value:
    string
): NormalizedEmailResult {`
    );
} else if (
  !content.includes(
    "): NormalizedEmailResult {"
  )
) {
  throw new Error(
    "normalizeEmail signature could not be normalized."
  );
}

for (
  const marker
  of [
    "export type NormalizedImportPhoneResult =",
    "export type NormalizedEmailResult =",
    "}): NormalizedImportPhoneResult {",
    "): NormalizedEmailResult {"
  ]
) {
  if (
    !content.includes(
      marker
    )
  ) {
    throw new Error(
      `P3.6b verification failed: ${marker}`
    );
  }
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.6b] Import normalization return types are now explicit."
);
NODE

echo "[P3.6b] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.6b] P3.6 unit tests..."
pnpm --filter @wapp/api test

echo "[P3.6b] P3.6 smoke..."
node scripts/p3-06-data-quality-smoke.mjs

echo "[P3.6b] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo "[P3.6b] Integration tests..."
pnpm test:integration

echo "[P3.6b] Production build..."
pnpm build

echo
echo "[P3.6b] P3.6 VALIDATION PASS."
echo
echo "No Prisma migration is required."
echo "If this passes, run pnpm dev and perform the P3.6 runtime checklist."
