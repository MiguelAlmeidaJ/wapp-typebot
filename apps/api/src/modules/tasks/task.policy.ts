import type { WappRole } from "../../lib/tokens.js";

export const TASK_MIN_LEAD_MS = 30_000;
export const TASK_REMINDER_STALE_MS = 15 * 60 * 1_000;

export function isTaskManager(role: WappRole) {
  return role === "OWNER" || role === "ADMIN" || role === "SUPERVISOR";
}

export function canAssignTaskTo(input: {
  role: WappRole;
  actorMembershipId: string;
  assigneeMembershipId: string;
}) {
  return isTaskManager(input.role) ||
    input.actorMembershipId === input.assigneeMembershipId;
}

export function canMutateTask(input: {
  role: WappRole;
  actorMembershipId: string;
  assigneeMembershipId: string;
  createdByMembershipId: string;
}) {
  return isTaskManager(input.role) ||
    input.actorMembershipId === input.assigneeMembershipId ||
    input.actorMembershipId === input.createdByMembershipId;
}

export function taskTimeError(input: {
  now: Date;
  dueAt: Date;
  reminderAt: Date | null;
}) {
  if (!Number.isFinite(input.dueAt.getTime())) return "INVALID_DUE";
  if (input.dueAt.getTime() - input.now.getTime() < TASK_MIN_LEAD_MS) return "DUE_TOO_SOON";
  if (!input.reminderAt) return null;
  if (!Number.isFinite(input.reminderAt.getTime())) return "INVALID_REMINDER";
  if (input.reminderAt.getTime() - input.now.getTime() < TASK_MIN_LEAD_MS) return "REMINDER_TOO_SOON";
  if (input.reminderAt > input.dueAt) return "REMINDER_AFTER_DUE";
  return null;
}
