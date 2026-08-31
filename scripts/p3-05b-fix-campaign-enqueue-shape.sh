#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/modules/campaigns/campaign.routes.ts"

echo "[P3.5b] Fixing campaign enqueue payload shape..."

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/campaigns/campaign.routes.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const alreadyFixed =
  /enqueueCampaignRecipient\s*\(\s*\{\s*recipientId\s*:\s*recipient\.id\s*,\s*plannedFor\s*:\s*recipient\.plannedFor\s*\}\s*\)/m
    .test(
      content
    );

if (
  alreadyFixed
) {
  console.log(
    "[P3.5b] Campaign enqueue payload is already normalized."
  );
} else {
  const rawPattern =
    /enqueueCampaignRecipient\s*\(\s*recipient\s*\)/g;

  const matches =
    content.match(
      rawPattern
    ) ??
    [];

  if (
    matches.length !==
    1
  ) {
    throw new Error(
      `Expected exactly one enqueueCampaignRecipient(recipient) call, found ${matches.length}.`
    );
  }

  content =
    content.replace(
      rawPattern,
      `enqueueCampaignRecipient({
          recipientId:
            recipient.id,
          plannedFor:
            recipient.plannedFor
        })`
    );

  console.log(
    "[P3.5b] recipient.id mapped to recipientId."
  );
}

const finalPattern =
  /enqueueCampaignRecipient\s*\(\s*\{\s*recipientId\s*:\s*recipient\.id\s*,\s*plannedFor\s*:\s*recipient\.plannedFor\s*\}\s*\)/m;

if (
  !finalPattern.test(
    content
  )
) {
  throw new Error(
    "Campaign enqueue payload verification failed."
  );
}

if (
  /enqueueCampaignRecipient\s*\(\s*recipient\s*\)/.test(
    content
  )
) {
  throw new Error(
    "Raw recipient enqueue call still exists."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

echo "[P3.5b] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.5b] Campaign smoke..."
node scripts/p3-05-campaign-smoke.mjs

echo "[P3.5b] Unit tests..."
pnpm test

echo "[P3.5b] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.5b] P3.5 CODE VALIDATION PASS."
echo
echo "Migration is still NOT executed by this hotfix."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
