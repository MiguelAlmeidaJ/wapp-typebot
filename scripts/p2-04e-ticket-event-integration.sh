#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.4e] Closing automation ticket-event integration..."

EVENT_SERVICE="apps/api/src/modules/tickets/ticket-event.service.ts"
AUTOMATION_SERVICE="apps/api/src/modules/automations/automation.service.ts"
HISTORY="apps/web/components/conversations/ticket-history-drawer.tsx"
PERMISSIONS="apps/api/src/security/permissions.ts"
PERMISSIONS_TEST="apps/api/src/security/permissions.test.ts"

for required in \
  "$EVENT_SERVICE" \
  "$AUTOMATION_SERVICE" \
  "$HISTORY" \
  "$PERMISSIONS" \
  "$PERMISSIONS_TEST"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

# Validate the exact Git-backed state we are fixing.
grep -Fq -- '"AUTOMATION_APPLIED"' "$AUTOMATION_SERVICE"
grep -Fq -- '| "TAGS_UPDATED";' "$EVENT_SERVICE"
grep -Fq -- '"automations.read"' "$PERMISSIONS"
grep -Fq -- '"automations.manage"' "$PERMISSIONS"

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket-event.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldUnionEnd =
  `  | "REOPENED"
  | "TAGS_UPDATED";`;

const newUnionEnd =
  `  | "REOPENED"
  | "TAGS_UPDATED"
  | "AUTOMATION_APPLIED";`;

if (
  content.includes(
    oldUnionEnd
  )
) {
  content =
    content.replace(
      oldUnionEnd,
      newUnionEnd
    );
} else if (
  !content.includes(
    '| "AUTOMATION_APPLIED"'
  )
) {
  throw new Error(
    "TicketEventType union anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.4e] TicketEventType accepts AUTOMATION_APPLIED."
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/components/conversations/ticket-history-drawer.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const typeAnchor =
  `  | "REOPENED"
  | "TAGS_UPDATED"
  | string;`;

const typeReplacement =
  `  | "REOPENED"
  | "TAGS_UPDATED"
  | "AUTOMATION_APPLIED"
  | string;`;

if (
  content.includes(
    typeAnchor
  )
) {
  content =
    content.replace(
      typeAnchor,
      typeReplacement
    );
} else if (
  !content.includes(
    '| "AUTOMATION_APPLIED"'
  )
) {
  throw new Error(
    "Ticket history EventType anchor not found."
  );
}

const titleAnchor =
  `    case "TAGS_UPDATED":
      return "Etiquetas atualizadas";
    default:`;

const titleReplacement =
  `    case "TAGS_UPDATED":
      return "Etiquetas atualizadas";
    case "AUTOMATION_APPLIED":
      return "Automação executada";
    default:`;

if (
  content.includes(
    titleAnchor
  )
) {
  content =
    content.replace(
      titleAnchor,
      titleReplacement
    );
} else if (
  !content.includes(
    'case "AUTOMATION_APPLIED":\n      return "Automação executada";'
  )
) {
  throw new Error(
    "Ticket history eventTitle anchor not found."
  );
}

const detailAnchor =
  `    case "TAGS_UPDATED": {
      const names =
        stringList(
          metadata,
          "tagNames"
        );

      return names.length > 0
        ? \`Etiquetas atuais: \${names.join(", ")}.\`
        : "Todas as etiquetas foram removidas.";
    }

    default:`;

const detailReplacement =
  `    case "TAGS_UPDATED": {
      const names =
        stringList(
          metadata,
          "tagNames"
        );

      return names.length > 0
        ? \`Etiquetas atuais: \${names.join(", ")}.\`
        : "Todas as etiquetas foram removidas.";
    }

    case "AUTOMATION_APPLIED": {
      const ruleName =
        text(
          metadata,
          "ruleName"
        );

      const trigger =
        text(
          metadata,
          "trigger"
        );

      const triggerLabel =
        trigger ===
          "TICKET_CREATED"
          ? "novo atendimento"
          : trigger ===
              "INBOUND_MESSAGE"
            ? "mensagem recebida"
            : null;

      if (
        ruleName &&
        triggerLabel
      ) {
        return \`A regra “\${ruleName}” foi executada por \${triggerLabel}.\`;
      }

      if (ruleName) {
        return \`A regra “\${ruleName}” foi executada.\`;
      }

      return "Uma automação operacional foi executada pelo sistema.";
    }

    default:`;

if (
  content.includes(
    detailAnchor
  )
) {
  content =
    content.replace(
      detailAnchor,
      detailReplacement
    );
} else if (
  !content.includes(
    'case "AUTOMATION_APPLIED": {'
  )
) {
  throw new Error(
    "Ticket history eventDetail anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.4e] Ticket history renders automation events explicitly."
);
NODE

# Check that the previously repaired RBAC test remains structurally healthy
# before running the full toolchain.
node <<'NODE'
const fs = require("node:fs");

const permissions =
  fs.readFileSync(
    "apps/api/src/security/permissions.ts",
    "utf8"
  );

const test =
  fs.readFileSync(
    "apps/api/src/security/permissions.test.ts",
    "utf8"
  );

for (
  const permission
  of [
    "automations.read",
    "automations.manage"
  ]
) {
  if (
    !permissions.includes(
      `"${permission}"`
    )
  ) {
    throw new Error(
      `Missing permission: ${permission}`
    );
  }

  if (
    !test.includes(
      `"${permission}"`
    )
  ) {
    throw new Error(
      `Missing RBAC test coverage: ${permission}`
    );
  }
}

console.log(
  "[P2.4e] RBAC automation permissions remain present."
);
NODE

echo "[P2.4e] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P2.4e] Unit tests..."
pnpm test

echo "[P2.4e] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.4e] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.4e] P2.4 CODE VALIDATION PASS."
echo
echo "The database migration is still intentionally NOT executed here."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
