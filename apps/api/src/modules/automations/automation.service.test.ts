import assert from "node:assert/strict";
import { test } from "node:test";

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
