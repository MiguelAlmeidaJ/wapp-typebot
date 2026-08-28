import assert from "node:assert/strict";
import { test } from "node:test";
import {
  canAssignTaskTo,
  canMutateTask,
  taskTimeError
} from "./task.policy.js";

test("agents self-assign while managers may delegate", () => {
  assert.equal(canAssignTaskTo({
    role: "AGENT",
    actorMembershipId: "a",
    assigneeMembershipId: "a"
  }), true);
  assert.equal(canAssignTaskTo({
    role: "AGENT",
    actorMembershipId: "a",
    assigneeMembershipId: "b"
  }), false);
  assert.equal(canAssignTaskTo({
    role: "SUPERVISOR",
    actorMembershipId: "a",
    assigneeMembershipId: "b"
  }), true);
});

test("task creator or assignee may operate the task", () => {
  assert.equal(canMutateTask({
    role: "AGENT",
    actorMembershipId: "creator",
    assigneeMembershipId: "other",
    createdByMembershipId: "creator"
  }), true);
});

test("reminder must be future and before due date", () => {
  const now = new Date("2026-08-29T10:00:00.000Z");
  assert.equal(taskTimeError({
    now,
    dueAt: new Date("2026-08-29T12:00:00.000Z"),
    reminderAt: new Date("2026-08-29T11:00:00.000Z")
  }), null);
  assert.equal(taskTimeError({
    now,
    dueAt: new Date("2026-08-29T12:00:00.000Z"),
    reminderAt: new Date("2026-08-29T13:00:00.000Z")
  }), "REMINDER_AFTER_DUE");
});
