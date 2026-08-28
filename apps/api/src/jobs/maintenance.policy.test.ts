import assert from "node:assert/strict";
import { test } from "node:test";

import {
  retentionCutoff,
  staleMediaCutoff
} from "./maintenance.policy.js";

test(
  "maintenance retention cutoffs are deterministic",
  () => {
    const now =
      new Date(
        "2026-08-28T12:00:00.000Z"
      );

    assert.equal(
      retentionCutoff(
        now,
        30
      ).toISOString(),
      "2026-07-29T12:00:00.000Z"
    );

    assert.equal(
      staleMediaCutoff(
        now,
        30
      ).toISOString(),
      "2026-08-28T11:30:00.000Z"
    );
  }
);
