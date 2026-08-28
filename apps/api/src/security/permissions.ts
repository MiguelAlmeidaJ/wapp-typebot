import type { WappRole } from "../lib/tokens.js";

export type WappPermission =
  | "admin.test"
  | "audit.read"
  | "observability.read"
  | "automations.read"
  | "automations.manage"
  | "contacts.read"
  | "contacts.manage"
  | "quickReplies.read"
  | "quickReplies.manage"
  | "tags.read"
  | "tags.manage"
  | "sla.read"
  | "sla.manage"
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
    "automations.manage",
    "automations.read",
    "admin.test",
    "audit.read",
    "observability.read",
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "quickReplies.manage",
    "tags.read",
    "tags.manage",
    "sla.read",
    "sla.manage",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ],
  ADMIN: [
    "automations.manage",
    "automations.read",
    "admin.test",
    "audit.read",
    "observability.read",
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "quickReplies.manage",
    "tags.read",
    "tags.manage",
    "sla.read",
    "sla.manage",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ],
  SUPERVISOR: [
    "automations.manage",
    "automations.read",
    "observability.read",
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "quickReplies.manage",
    "tags.read",
    "tags.manage",
    "sla.read",
    "sla.manage",
    "team.read",
    "queues.read",
    "whatsapp.read",
    "whatsapp.test"
  ],
  AGENT: [
    "automations.read",
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "tags.read",
    "sla.read",
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
