#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/security/permissions.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

echo "[P1.8b] Normalizing permission matrix..."

cat > "$FILE" <<'EOF'
import type { WappRole } from "../lib/tokens.js";

export type WappPermission =
  | "admin.test"
  | "contacts.read"
  | "contacts.manage"
  | "quickReplies.read"
  | "quickReplies.manage"
  | "tags.read"
  | "tags.manage"
  | "team.read"
  | "team.manage"
  | "queues.read"
  | "queues.manage"
  | "whatsapp.read"
  | "whatsapp.manage"
  | "whatsapp.test";

const permissionsByRole: Record<
  WappRole,
  readonly WappPermission[]
> = {
  OWNER: [
    "admin.test",
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "quickReplies.manage",
    "tags.read",
    "tags.manage",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ],
  ADMIN: [
    "admin.test",
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "quickReplies.manage",
    "tags.read",
    "tags.manage",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ],
  SUPERVISOR: [
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "quickReplies.manage",
    "tags.read",
    "tags.manage",
    "team.read",
    "queues.read",
    "whatsapp.read",
    "whatsapp.test"
  ],
  AGENT: [
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "tags.read",
    "team.read",
    "queues.read",
    "whatsapp.read"
  ]
};

export function roleHasPermission(
  role: WappRole,
  permission: WappPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
EOF

echo "[P1.8b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo
echo "[P1.8b] Permission matrix normalized."
echo
echo "Continue the original P1.8 script:"
echo "  bash scripts/p1-08-ticket-tags.sh"
