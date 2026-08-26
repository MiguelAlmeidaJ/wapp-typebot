#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/web/app/dashboard/conversations/page.tsx"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: $FILE not found."
  exit 1
fi

echo "[P0.7c] Repairing conversations presence state..."

node <<'NODE'
const fs = require("node:fs");

const path = "apps/web/app/dashboard/conversations/page.tsx";
let content = fs.readFileSync(path, "utf8");

if (
  content.includes(
    "const [onlineMembershipIds, setOnlineMembershipIds]"
  )
) {
  console.log("Presence state already exists.");
  process.exit(0);
}

const anchor = `  const [error, setError] = useState("");`;

if (!content.includes(anchor)) {
  throw new Error(
    "Could not find conversations state anchor. No changes were made."
  );
}

content = content.replace(
  anchor,
  `${anchor}
  const [onlineMembershipIds, setOnlineMembershipIds] = useState<string[]>([]);`
);

fs.writeFileSync(path, content);
console.log("Added onlineMembershipIds presence state.");
NODE

echo "[P0.7c] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7c] Frontend presence state repaired."
echo
echo "Continue with:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name queues_assignment_realtime"
