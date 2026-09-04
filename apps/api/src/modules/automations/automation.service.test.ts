import assert from "node:assert/strict";
import { test } from "node:test";

import { automationActionDecision } from "./automation-chatbot.policy.js";

function matches(input: {
  keyword?: string;
  onlyIfUnassigned?: boolean;
  assigned?: boolean;
  type?:
    | "ALL"
    | "DIRECT"
    | "GROUP";
  isGroup?: boolean;
  body?: string;
}) {
  if (
    input.onlyIfUnassigned &&
    input.assigned
  ) {
    return false;
  }

  if (
    input.type ===
      "DIRECT" &&
    input.isGroup
  ) {
    return false;
  }

  if (
    input.type ===
      "GROUP" &&
    !input.isGroup
  ) {
    return false;
  }

  if (
    input.keyword &&
    !input.body
      ?.toLowerCase()
      .includes(
        input.keyword
          .toLowerCase()
      )
  ) {
    return false;
  }

  return true;
}

test(
  "automation keyword matching is case insensitive",
  () => {
    assert.equal(
      matches({
        keyword:
          "segunda via",
        body:
          "Preciso da SEGUNDA VIA da fatura"
      }),
      true
    );
  }
);

test(
  "chatbot-owned messages suppress only automation text",
  () => {
    assert.equal(
      automationActionDecision({
        actionType: "SEND_TEXT",
        chatbotHandledSourceMessage: true,
        hasActiveChatbotSession: false
      }),
      "SKIP_CHATBOT_TEXT"
    );

    for (const actionType of [
      "ADD_TAG",
      "SET_QUEUE",
      "ASSIGN_MEMBERSHIP"
    ] as const) {
      assert.equal(
        automationActionDecision({
          actionType,
          chatbotHandledSourceMessage: true,
          hasActiveChatbotSession: true
        }),
        "EXECUTE"
      );
    }
  }
);

test(
  "an active chatbot suppresses text from legacy queued jobs",
  () => {
    assert.equal(
      automationActionDecision({
        actionType: "SEND_TEXT",
        chatbotHandledSourceMessage: false,
        hasActiveChatbotSession: true
      }),
      "SKIP_CHATBOT_TEXT"
    );
  }
);

test(
  "only-if-unassigned prevents reassignment rules",
  () => {
    assert.equal(
      matches({
        onlyIfUnassigned:
          true,
        assigned:
          true
      }),
      false
    );
  }
);

test(
  "direct/group conditions stay explicit",
  () => {
    assert.equal(
      matches({
        type:
          "DIRECT",
        isGroup:
          true
      }),
      false
    );

    assert.equal(
      matches({
        type:
          "GROUP",
        isGroup:
          true
      }),
      true
    );
  }
);
