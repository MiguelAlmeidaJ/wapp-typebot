import type { Role } from "./auth-types";

export type UiPermission =
  | "dashboard.view"
  | "conversations.view"
  | "reports.view"
  | "contacts.view"
  | "queues.manage"
  | "connections.manage"
  | "team.manage"
  | "admin.test"
  | "pipeline.view"
  | "pipeline.manage"
  | "tasks.view"
  | "tasks.admin";

const permissionsByRole: Record<
  Role,
  readonly UiPermission[]
> = {
  OWNER: [
    "reports.view",
    "dashboard.view",
    "conversations.view",
    "contacts.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test",
    "pipeline.view",
    "pipeline.manage",
    "tasks.view",
    "tasks.admin"
  ],
  ADMIN: [
    "reports.view",
    "dashboard.view",
    "conversations.view",
    "contacts.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test",
    "pipeline.view",
    "pipeline.manage",
    "tasks.view",
    "tasks.admin"
  ],
  SUPERVISOR: [
    "reports.view",
    "dashboard.view",
    "conversations.view",
    "contacts.view",
    "pipeline.view",
    "pipeline.manage",
    "tasks.view",
    "tasks.admin"
  ],
  AGENT: [
    "dashboard.view",
    "conversations.view",
    "contacts.view",
    "pipeline.view",
    "tasks.view"
  ]
};

export function roleCan(
  role: Role,
  permission: UiPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
