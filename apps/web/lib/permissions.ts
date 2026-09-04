import type { Role } from "./auth-types";

export type UiPermission =
  | "dashboard.view"
  | "conversations.view"
  | "chatbots.view"
  | "chatbots.manage"
  | "reports.view"
  | "contacts.view"
  | "queues.manage"
  | "connections.manage"
  | "team.manage"
  | "admin.test"
  | "pipeline.view"
  | "pipeline.manage"
  | "tasks.view"
  | "tasks.admin"
  | "segments.view"
  | "segments.manage"
  | "campaigns.view"
  | "campaigns.manage"
  | "campaigns.send"
  | "dataQuality.view"
  | "dataQuality.manage";

const permissionsByRole: Record<
  Role,
  readonly UiPermission[]
> = {
  OWNER: [
    "reports.view",
    "dashboard.view",
    "conversations.view",
    "chatbots.view",
    "chatbots.manage",
    "contacts.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test",
    "pipeline.view",
    "pipeline.manage",
    "tasks.view",
    "tasks.admin",
    "segments.view",
    "segments.manage",
    "campaigns.view",
    "campaigns.manage",
    "campaigns.send",
    "dataQuality.view",
    "dataQuality.manage"
  ],
  ADMIN: [
    "reports.view",
    "dashboard.view",
    "conversations.view",
    "chatbots.view",
    "chatbots.manage",
    "contacts.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test",
    "pipeline.view",
    "pipeline.manage",
    "tasks.view",
    "tasks.admin",
    "segments.view",
    "segments.manage",
    "campaigns.view",
    "campaigns.manage",
    "campaigns.send",
    "dataQuality.view",
    "dataQuality.manage"
  ],
  SUPERVISOR: [
    "reports.view",
    "dashboard.view",
    "conversations.view",
    "chatbots.view",
    "chatbots.manage",
    "contacts.view",
    "pipeline.view",
    "pipeline.manage",
    "tasks.view",
    "tasks.admin",
    "segments.view",
    "segments.manage",
    "campaigns.view",
    "campaigns.manage",
    "dataQuality.view",
    "dataQuality.manage"
  ],
  AGENT: [
    "dashboard.view",
    "conversations.view",
    "chatbots.view",
    "contacts.view",
    "pipeline.view",
    "tasks.view",
    "segments.view",
    "campaigns.view"
  ]
};

export function roleCan(
  role: Role,
  permission: UiPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
