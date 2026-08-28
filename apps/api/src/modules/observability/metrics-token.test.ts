import assert from "node:assert/strict";
import { test } from "node:test";

import {
  validMetricsAuthorization
} from "./metrics-token.js";

test(
  "metrics bearer token validation is strict",
  () => {
    const token =
      "metrics_token_abcdefghijklmnopqrstuvwxyz_123456";

    assert.equal(
      validMetricsAuthorization(
        token,
        `Bearer ${token}`
      ),
      true
    );

    assert.equal(
      validMetricsAuthorization(
        token,
        "Bearer wrong"
      ),
      false
    );

    assert.equal(
      validMetricsAuthorization(
        "",
        "Bearer anything"
      ),
      false
    );

    assert.equal(
      validMetricsAuthorization(
        token,
        undefined
      ),
      false
    );
  }
);
