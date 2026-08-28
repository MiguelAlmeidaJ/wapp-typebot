import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  fieldKeyFromLabel,
  normalizeSelectOptions,
  validateContactFieldValue
} from "./contact-crm.policy.js";

test(
  "field keys are stable and ASCII-safe",
  () => {
    assert.equal(
      fieldKeyFromLabel(
        "Data da Renovação"
      ),
      "data_da_renovacao"
    );
  }
);

test(
  "select options are trimmed and deduplicated",
  () => {
    assert.deepEqual(
      normalizeSelectOptions([
        " Lead ",
        "Cliente",
        "Lead",
        ""
      ]),
      [
        "Lead",
        "Cliente"
      ]
    );
  }
);

test(
  "typed CRM values reject invalid data",
  () => {
    assert.equal(
      validateContactFieldValue({
        type:
          "NUMBER",
        value:
          "12.50"
      }),
      null
    );

    assert.equal(
      validateContactFieldValue({
        type:
          "NUMBER",
        value:
          "abc"
      }),
      "INVALID_NUMBER"
    );

    assert.equal(
      validateContactFieldValue({
        type:
          "DATE",
        value:
          "2026-02-31"
      }),
      "INVALID_DATE"
    );

    assert.equal(
      validateContactFieldValue({
        type:
          "SELECT",
        value:
          "Cliente",
        options: [
          "Lead",
          "Cliente"
        ]
      }),
      null
    );
  }
);
