import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  inboundNotificationKey,
  notificationPreview,
  uniqueMembershipIds
} from "./notification.policy.js";

test(
  "notification preview is compact and whitespace-normalized",
  () => {
    assert.equal(
      notificationPreview(
        "  Olá\n\npreciso   de ajuda  "
      ),
      "Olá preciso de ajuda"
    );

    assert.equal(
      notificationPreview(
        null,
        "[imagem]"
      ),
      "[imagem]"
    );
  }
);

test(
  "inbound activity coalesces by ticket",
  () => {
    assert.equal(
      inboundNotificationKey(
        "ticket-1",
        false
      ),
      "inbound:ticket-1"
    );

    assert.equal(
      inboundNotificationKey(
        "ticket-1",
        true
      ),
      "new-ticket:ticket-1"
    );
  }
);

test(
  "recipient ids are unique",
  () => {
    assert.deepEqual(
      uniqueMembershipIds([
        "a",
        "b",
        "a",
        null,
        undefined
      ]),
      [
        "a",
        "b"
      ]
    );
  }
);
