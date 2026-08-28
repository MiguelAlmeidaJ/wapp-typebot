#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ORIGINAL="scripts/p2-05-templates-scheduling.sh"

echo "[P2.5b] Resuming P2.5 from composer integration..."

if [[ ! -f "$ORIGINAL" ]]; then
  echo "ERROR: missing $ORIGINAL"
  exit 1
fi

# Confirm the exact partial state that should exist before the failed Web mount.
for check in \
  "apps/api/prisma/schema.prisma|model ScheduledMessage {" \
  "apps/api/src/modules/scheduled-messages/scheduled-message.service.ts|deliverScheduledMessage" \
  "apps/api/src/modules/scheduled-messages/scheduled-message.routes.ts|scheduledMessageRoutes" \
  "apps/api/src/jobs/scheduled-message.queue.ts|wapp-scheduled-messages" \
  "apps/api/src/jobs/scheduled-message.worker.ts|createScheduledMessageWorker" \
  "apps/api/src/app.ts|await app.register(scheduledMessageRoutes);" \
  "apps/api/src/jobs/job-runtime.ts|createScheduledMessageWorker()" \
  "apps/api/src/worker.ts|createScheduledMessageWorker()" \
  "apps/web/components/conversations/scheduled-message-drawer.tsx|export function ScheduledMessageDrawer" \
  "apps/api/src/modules/tickets/ticket-event.service.ts|MESSAGE_SCHEDULED"
do
  file="${check%%|*}"
  marker="${check#*|}"

  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: expected partial P2.5 state is missing:"
    echo "  $file -> $marker"
    echo "Do not retry P2.5 blindly; inspect the checkout first."
    exit 1
  fi
done

echo "[P2.5b] Partial P2.5 backend/component state confirmed."

node <<'NODE'
const fs = require("node:fs");

const path =
  "scripts/p2-05-templates-scheduling.sh";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const bad =
  "# Close scheduler when changing/closing the current ticket.";

const fixed =
  "// Close scheduler when changing/closing the current ticket.";

if (
  content.includes(
    bad
  )
) {
  content =
    content.replace(
      bad,
      fixed
    );
} else if (
  !content.includes(
    fixed
  )
) {
  throw new Error(
    "P2.5 invalid JavaScript comment marker not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.5b] Invalid shell-style comment inside Node block fixed."
);
NODE

echo "[P2.5b] Checking corrected original installer syntax..."
bash -n "$ORIGINAL"

TAIL="$(mktemp)"
cleanup() {
  rm -f "$TAIL"
}
trap cleanup EXIT

awk '
  /^# Mount scheduler in canonical composer without changing scroll ownership\.$/ {
    found=1
  }

  found {
    print
  }
' "$ORIGINAL" > "$TAIL"

if ! grep -Fq -- "[P2.5] Prisma generate..." "$TAIL"; then
  echo "ERROR: could not extract the remaining P2.5 installer tail."
  exit 1
fi

echo "[P2.5b] Continuing from composer integration only..."
bash "$TAIL"
