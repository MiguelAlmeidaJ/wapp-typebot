import type { WappRole } from "../lib/tokens.js";

export type WappPermission =
  | "admin.test"
  | "audit.read"
  | "observability.read"
  | "automations.read"
  | "automations.manage"
  | "reports.read"
  | "contacts.read"
  | "contacts.manage"
  | "contactFields.manage"
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
  | "whatsapp.test"
  | "pipelines.read"
  | "pipelines.move"
  | "pipelines.manage"
  | "tasks.read"
  | "tasks.manage"
  | "tasks.admin"
  | "segments.read"
  | "segments.manage"
  | "campaigns.read"
  | "campaigns.manage"
  | "campaigns.send";

const permissionsByRole: Record<
  WappRole,
  readonly WappPermission[]
> = {
  OWNER: [
    "contactFields.manage",
    "reports.read",
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
    "whatsapp.test",
    "pipelines.read",
    "pipelines.move",
    "pipelines.manage",
    "tasks.read",
    "tasks.manage",
    "tasks.admin",
    "segments.read",
    "segments.manage",
    "campaigns.read",
    "campaigns.manage",
    "campaigns.send"
  ],
  ADMIN: [
    "contactFields.manage",
    "reports.read",
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
    "whatsapp.test",
    "pipelines.read",
    "pipelines.move",
    "pipelines.manage",
    "tasks.read",
    "tasks.manage",
    "tasks.admin",
    "segments.read",
    "segments.manage",
    "campaigns.read",
    "campaigns.manage",
    "campaigns.send"
  ],
  SUPERVISOR: [
    "contactFields.manage",
    "reports.read",
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
    "whatsapp.test",
    "pipelines.read",
    "pipelines.move",
    "pipelines.manage",
    "tasks.read",
    "tasks.manage",
    "tasks.admin",
    "segments.read",
    "segments.manage",
    "campaigns.read",
    "campaigns.manage"
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
    "whatsapp.read",
    "pipelines.read",
    "pipelines.move",
    "tasks.read",
    "tasks.manage",
    "segments.read",
    "campaigns.read"
  ]
};

export function roleHasPermission(
  role: WappRole,
  permission: WappPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
