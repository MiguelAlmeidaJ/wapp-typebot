import type { WappRole } from "../lib/tokens.js";

export type WappPermission =
  | "admin.test"
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
    "admin.test",
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
    "admin.test",
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
