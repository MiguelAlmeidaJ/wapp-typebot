#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/modules/tasks/task.routes.ts"

echo "[P3.3b] Fixing task update date normalization..."

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

for marker in \
  "const input =" \
  "await updateTask({" \
  "dueAt:" \
  "reminderAt:"
do
  if ! grep -Fq -- "$marker" "$FILE"; then
    echo "ERROR: expected P3.3 route marker missing: $marker"
    echo "Do not retry blindly; inspect $FILE first."
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tasks/task.routes.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldBlock = `      const input =
        updateSchema.parse(
          request.body
        );

      const task =
        await updateTask({
          companyId:
            auth.companyId,
          taskId:
            params.id,
          actorMembershipId:
            auth.membershipId,
          role:
            auth.role,
          ...input,
          ...(input.dueAt
            ? {
                dueAt:
                  new Date(
                    input.dueAt
                  )
              }
            : {}),
          ...(input.reminderAt !==
          undefined
            ? {
                reminderAt:
                  input.reminderAt
                    ? new Date(
                        input.reminderAt
                      )
                    : null
              }
            : {})
        });`;

const newBlock = `      const input =
        updateSchema.parse(
          request.body
        );

      const {
        dueAt,
        reminderAt,
        ...taskChanges
      } =
        input;

      const task =
        await updateTask({
          companyId:
            auth.companyId,
          taskId:
            params.id,
          actorMembershipId:
            auth.membershipId,
          role:
            auth.role,
          ...taskChanges,
          ...(dueAt
            ? {
                dueAt:
                  new Date(
                    dueAt
                  )
              }
            : {}),
          ...(reminderAt !==
          undefined
            ? {
                reminderAt:
                  reminderAt
                    ? new Date(
                        reminderAt
                      )
                    : null
              }
            : {})
        });`;

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
  content.includes(
    "const {\n        dueAt,\n        reminderAt,\n        ...taskChanges"
  )
) {
  console.log(
    "[P3.3b] Route already uses normalized taskChanges."
  );
} else {
  throw new Error(
    "Expected P3.3 updateTask route block was not found. Inspect current source before applying another fix."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.3b] dueAt/reminderAt removed from raw spread and normalized explicitly."
);
NODE

echo "[P3.3b] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.3b] Unit tests..."
pnpm test

echo "[P3.3b] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.3b] P3.3 CODE VALIDATION PASS."
echo
echo "Migration is still NOT executed by this hotfix."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
