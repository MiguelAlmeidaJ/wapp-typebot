import assert from "node:assert/strict";
import {
  describe,
  it
} from "node:test";

import {
  afterCursorWhere,
  beforeCursorWhere,
  chronologicalOrder,
  reverseChronologicalOrder
} from "./message-history.cursor.js";

describe(
  "message history keyset cursor",
  () => {
    const timestamp =
      new Date(
        "2026-08-28T12:00:00.000Z"
      );

    const cursor = {
      id:
        "80000000-0000-4000-8000-000000000080",
      timestamp
    };

    it(
      "uses timestamp + id tie-breaker when paging older",
      () => {
        assert.deepEqual(
          beforeCursorWhere(
            cursor
          ),
          {
            OR: [
              {
                timestamp: {
                  lt:
                    timestamp
                }
              },
              {
                timestamp,
                id: {
                  lt:
                    cursor.id
                }
              }
            ]
          }
        );
      }
    );

    it(
      "uses timestamp + id tie-breaker when paging newer",
      () => {
        assert.deepEqual(
          afterCursorWhere(
            cursor
          ),
          {
            OR: [
              {
                timestamp: {
                  gt:
                    timestamp
                }
              },
              {
                timestamp,
                id: {
                  gt:
                    cursor.id
                }
              }
            ]
          }
        );
      }
    );

    it(
      "has deterministic chronological ordering",
      () => {
        assert.deepEqual(
          chronologicalOrder,
          [
            {
              timestamp:
                "asc"
            },
            {
              id:
                "asc"
            }
          ]
        );

        assert.deepEqual(
          reverseChronologicalOrder,
          [
            {
              timestamp:
                "desc"
            },
            {
              id:
                "desc"
            }
          ]
        );
      }
    );
  }
);
