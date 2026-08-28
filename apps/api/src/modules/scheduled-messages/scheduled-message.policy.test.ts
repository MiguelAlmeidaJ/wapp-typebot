import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  canManageScheduledMessage,
  scheduleTimeError,
  scheduledMessageDelay
} from "./scheduled-message.policy.js";

test(
  "scheduled time must have a safe future lead",
  () => {
    const now =
      new Date(
        "2026-08-28T15:00:00.000Z"
      );

    assert.equal(
      scheduleTimeError(
        now,
        new Date(
          "2026-08-28T15:00:10.000Z"
        )
      ),
      "TOO_SOON"
    );

    assert.equal(
      scheduleTimeError(
        now,
        new Date(
          "2026-08-28T15:10:00.000Z"
        )
      ),
      null
    );
  }
);

test(
  "BullMQ delay never becomes negative",
  () => {
    const now =
      new Date(
        "2026-08-28T15:00:00.000Z"
      );

    assert.equal(
      scheduledMessageDelay(
        now,
        new Date(
          "2026-08-28T14:59:00.000Z"
        )
      ),
      0
    );
  }
);

test(
  "agents can cancel their own schedules but not another agent schedule",
  () => {
    assert.equal(
      canManageScheduledMessage({
        role:
          "AGENT",
        actorMembershipId:
          "a",
        createdByMembershipId:
          "a"
      }),
      true
    );

    assert.equal(
      canManageScheduledMessage({
        role:
          "AGENT",
        actorMembershipId:
          "a",
        createdByMembershipId:
          "b"
      }),
      false
    );

    assert.equal(
      canManageScheduledMessage({
        role:
          "SUPERVISOR",
        actorMembershipId:
          "a",
        createdByMembershipId:
          "b"
      }),
      true
    );
  }
);
