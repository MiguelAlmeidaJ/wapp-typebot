import assert from "node:assert/strict";
import { test } from "node:test";

import type {
  TicketListFilters
} from "./ticket.service.js";

function normalize(
  input:
    TicketListFilters
) {
  return {
    q:
      input.q
        ?.trim(),
    queueId:
      input.queueId,
    assigneeId:
      input.assigneeId,
    unreadOnly:
      Boolean(
        input.unreadOnly
      ),
    tagId:
      input.tagId,
    conversationType:
      input.conversationType ??
      "ALL"
  };
}

test(
  "ticket list filters preserve explicit operational scope",
  () => {
    assert.deepEqual(
      normalize({
        q:
          "  joao  ",
        queueId:
          "NONE",
        assigneeId:
          "ME",
        unreadOnly:
          true,
        tagId:
          "00000000-0000-4000-8000-000000000000",
        conversationType:
          "DIRECT"
      }),
      {
        q:
          "joao",
        queueId:
          "NONE",
        assigneeId:
          "ME",
        unreadOnly:
          true,
        tagId:
          "00000000-0000-4000-8000-000000000000",
        conversationType:
          "DIRECT"
      }
    );
  }
);
