import type { Role } from "./auth-types";

export type UiPermission =
  | "dashboard.view"
  | "conversations.view"
  | "contacts.view"
  | "queues.manage"
  | "connections.manage"
  | "team.manage"
  | "admin.test";

const permissionsByRole: Record<
  Role,
  readonly UiPermission[]
> = {
  OWNER: [
    "dashboard.view",
    "conversations.view",
    "contacts.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test"
  ],
  ADMIN: [
    "dashboard.view",
    "conversations.view",
    "contacts.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test"
  ],
  SUPERVISOR: [
    "dashboard.view",
    "conversations.view",
    "contacts.view"
  ],
  AGENT: [
    "dashboard.view",
    "conversations.view",
    "contacts.view"
  ]
};

export function roleCan(
  role: Role,
  permission: UiPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
