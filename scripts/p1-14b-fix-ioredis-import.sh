#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/modules/realtime/realtime.bus.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.14b] Fixing ioredis TypeScript import..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/realtime/realtime.bus.ts";

let content =
  fs.readFileSync(path, "utf8");

const wrong =
  'import Redis from "ioredis";';

const correct =
  'import { Redis } from "ioredis";';

if (content.includes(wrong)) {
  content =
    content.replace(
      wrong,
      correct
    );
} else if (
  content.includes(correct)
) {
  console.log(
    "ioredis named import already fixed."
  );
} else {
  throw new Error(
    "Could not find expected ioredis import."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "ioredis import normalized for NodeNext/TypeScript."
);
NODE

echo "[P1.14b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.14b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.14b] ioredis typing fixed."
echo
echo "Next:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then verify:"
echo "  http://localhost:4000/health"
echo "Expected:"
echo "  realtime.mode = redis"
echo "  realtime.redisConfigured = true"
echo "  realtime.redisReady = true"
