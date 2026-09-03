import assert from "node:assert/strict";
import test from "node:test";

import {
  buildBootstrapCompanySlug,
  normalizeBootstrapEmail,
  normalizeRequiredLabel,
  validateInitialOwnerPassword
} from "./first-owner-bootstrap.policy.js";

test(
  "normalizes bootstrap identity input",
  () => {
    assert.equal(
      normalizeBootstrapEmail(
        " Owner@Example.COM "
      ),
      "owner@example.com"
    );

    assert.equal(
      normalizeRequiredLabel(
        "  Wapp   Company  ",
        "Company"
      ),
      "Wapp Company"
    );

    assert.equal(
      buildBootstrapCompanySlug(
        "  ÁNOAR & Tecnologia  "
      ),
      "anoar-tecnologia"
    );
  }
);

test(
  "rejects weak initial OWNER passwords",
  () => {
    assert.throws(
      () =>
        validateInitialOwnerPassword(
          "short",
          "owner@example.com"
        )
    );

    assert.throws(
      () =>
        validateInitialOwnerPassword(
          "owner-Strong-Password-123!",
          "owner@example.com"
        )
    );

    assert.equal(
      validateInitialOwnerPassword(
        "A-Strong-Generated#Passphrase-9482",
        "owner@example.com"
      ),
      "A-Strong-Generated#Passphrase-9482"
    );
  }
);
