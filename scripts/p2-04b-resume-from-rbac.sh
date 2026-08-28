#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ORIGINAL="scripts/p2-04-operational-automations.sh"

echo "[P2.4b] Resuming P2.4 from RBAC..."

if [[ ! -f "$ORIGINAL" ]]; then
  echo "ERROR: missing $ORIGINAL"
  exit 1
fi

# Confirm the exact partial state created before the RBAC failure.
for check in \
  "apps/api/prisma/schema.prisma|model AutomationRule {" \
  "apps/api/prisma/schema.prisma|model AutomationAction {" \
  "apps/api/prisma/schema.prisma|model AutomationRun {" \
  "apps/api/src/modules/automations/automation.service.ts|evaluateAutomationEvent" \
  "apps/api/src/modules/automations/automation.routes.ts|automationRoutes" \
  "apps/api/src/jobs/automation.worker.ts|createAutomationWorker" \
  "apps/api/src/jobs/automation.queue.ts|wapp-automations" \
  "apps/api/src/modules/messages/message-ingestion.service.ts|scheduleAutomationEvaluation" \
  "apps/api/src/jobs/job-runtime.ts|createAutomationWorker()" \
  "apps/api/src/worker.ts|createAutomationWorker()"
do
  file="${check%%|*}"
  marker="${check#*|}"

  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: expected partial P2.4 state is missing:"
    echo "  $file -> $marker"
    echo "Do not retry P2.4 blindly; inspect the checkout first."
    exit 1
  fi
done

echo "[P2.4b] Partial P2.4 foundation confirmed."

# Fix the original RBAC block so the final AGENT array can end with `]`
# instead of requiring the comma form used by earlier object properties.
node <<'NODE'
const fs = require("node:fs");

const path =
  "scripts/p2-04-operational-automations.sh";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldBlock = `  const end =
    content.indexOf(
      "\\n  ],",
      start
    );

  if (end < 0) {
    throw new Error(
      \`\${role} permission block end not found.\`
    );
  }`;

const newBlock = `  const commaEnd =
    content.indexOf(
      "\\n  ],",
      start
    );

  const finalEnd =
    content.indexOf(
      "\\n  ]\\n};",
      start
    );

  const end =
    commaEnd >= 0
      ? commaEnd
      : finalEnd;

  if (end < 0) {
    throw new Error(
      \`\${role} permission block end not found.\`
    );
  }`;

if (
  content.includes(
    oldBlock
  )
) {
  content =
    content.replace(
      oldBlock,
      newBlock
    );
} else if (
  !content.includes(
    "const commaEnd ="
  )
) {
  throw new Error(
    "P2.4 RBAC parser block not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "P2.4 RBAC parser now supports the final AGENT property."
);
NODE

echo "[P2.4b] Checking corrected original installer syntax..."
bash -n "$ORIGINAL"

TAIL="$(mktemp)"
cleanup() {
  rm -f "$TAIL"
}
trap cleanup EXIT

# Execute only the remaining portion of P2.4. Everything before RBAC has
# already been persisted by the failed first run.
awk '
  /^# RBAC$/ {
    found=1
  }

  found {
    print
  }
' "$ORIGINAL" > "$TAIL"

if ! grep -Fq -- "[P2.4] Generating Prisma client..." "$TAIL"; then
  echo "ERROR: could not extract the remaining P2.4 installer tail."
  exit 1
fi

echo "[P2.4b] Continuing from RBAC only..."
bash "$TAIL"
