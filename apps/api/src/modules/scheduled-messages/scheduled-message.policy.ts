import type {
  WappRole
} from "../../lib/tokens.js";

export const SCHEDULE_MIN_LEAD_MS =
  30_000;

export const SCHEDULE_MAX_AHEAD_MS =
  365 *
  24 *
  60 *
  60 *
  1_000;

export const STALE_PROCESSING_MS =
  15 *
  60 *
  1_000;

export function scheduleTimeError(
  now: Date,
  scheduledFor: Date
) {
  const delta =
    scheduledFor.getTime() -
    now.getTime();

  if (
    !Number.isFinite(
      scheduledFor.getTime()
    )
  ) {
    return "INVALID";
  }

  if (
    delta <
    SCHEDULE_MIN_LEAD_MS
  ) {
    return "TOO_SOON";
  }

  if (
    delta >
    SCHEDULE_MAX_AHEAD_MS
  ) {
    return "TOO_FAR";
  }

  return null;
}

export function scheduledMessageDelay(
  now: Date,
  scheduledFor: Date
) {
  return Math.max(
    0,
    scheduledFor.getTime() -
      now.getTime()
  );
}

export function canManageScheduledMessage(input: {
  role: WappRole;
  actorMembershipId: string;
  createdByMembershipId: string;
}) {
  return (
    input.actorMembershipId ===
      input.createdByMembershipId ||
    input.role ===
      "OWNER" ||
    input.role ===
      "ADMIN" ||
    input.role ===
      "SUPERVISOR"
  );
}
