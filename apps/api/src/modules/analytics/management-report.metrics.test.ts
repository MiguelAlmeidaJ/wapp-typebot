import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  average,
  elapsedMinutes,
  percent,
  percentChange
} from "./management-report.metrics.js";

test(
  "report averages stay deterministic",
  () => {
    assert.equal(
      average([
        10,
        20,
        31
      ]),
      20
    );

    assert.equal(
      average([]),
      null
    );
  }
);

test(
  "report percentages handle empty samples",
  () => {
    assert.equal(
      percent(
        8,
        10
      ),
      80
    );

    assert.equal(
      percent(
        0,
        0
      ),
      null
    );
  }
);

test(
  "comparison does not invent a percentage over zero baseline",
  () => {
    assert.equal(
      percentChange(
        15,
        10
      ),
      50
    );

    assert.equal(
      percentChange(
        4,
        0
      ),
      null
    );

    assert.equal(
      percentChange(
        0,
        0
      ),
      0
    );
  }
);

test(
  "resolution minutes never become negative",
  () => {
    assert.equal(
      elapsedMinutes(
        new Date(
          "2026-08-28T15:00:00.000Z"
        ),
        new Date(
          "2026-08-28T15:42:00.000Z"
        )
      ),
      42
    );

    assert.equal(
      elapsedMinutes(
        new Date(
          "2026-08-28T16:00:00.000Z"
        ),
        new Date(
          "2026-08-28T15:42:00.000Z"
        )
      ),
      0
    );
  }
);
