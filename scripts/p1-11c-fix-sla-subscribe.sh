#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/web/components/conversations/sla-monitor-drawer.tsx"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.11c] Fixing SLA realtime subscription..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/components/conversations/sla-monitor-drawer.tsx";

let content =
  fs.readFileSync(path, "utf8");

const wrong =
  `    return subscribe(event => {`;

const correct =
  `    return subscribe(
      "/api/v1/realtime/events",
      event => {`;

if (
  content.includes(wrong)
) {
  content =
    content.replace(
      wrong,
      correct
    );

  /*
   * The original block closes subscribe with `});`.
   * After adding the first argument, it must close as `});`
   * only if the callback closure and function call are balanced.
   * We normalize the exact effect tail below.
   */
  const oldTail = `      }
    });
  }, [
    load,
    subscribe
  ]);`;

  const newTail = `      }
    );
  }, [
    load,
    subscribe
  ]);`;

  if (
    content.includes(oldTail)
  ) {
    content =
      content.replace(
        oldTail,
        newTail
      );
  } else {
    throw new Error(
      "SLA subscribe effect tail did not match expected source."
    );
  }
} else if (
  content.includes(
    `return subscribe(
      "/api/v1/realtime/events",`
  )
) {
  console.log(
    "SLA realtime subscription already fixed."
  );
} else {
  throw new Error(
    "Could not find SLA realtime subscription call."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "SLA realtime subscription fixed."
);
NODE

echo "[P1.11c] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo "[P1.11c] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo
echo "[P1.11c] Realtime subscription fixed."
echo
echo "If both typechecks passed, continue with:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name operational_sla"
echo "  pnpm --filter @wapp/api exec tsx src/scripts/backfill-ticket-sla.ts"
echo "  pnpm dev"
