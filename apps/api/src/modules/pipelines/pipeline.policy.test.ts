import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  normalizeStageNames,
  stageMoveChanged
} from "./pipeline.policy.js";

test(
  "pipeline stage names are normalized and unique",
  () => {
    assert.deepEqual(
      normalizeStageNames([
        " Novo ",
        "Em   contato",
        "novo",
        "",
        "Cliente"
      ]),
      [
        "Novo",
        "Em contato",
        "Cliente"
      ]
    );
  }
);

test(
  "pipeline movement does not create duplicate history for a no-op",
  () => {
    assert.equal(
      stageMoveChanged(
        "stage-a",
        "stage-a"
      ),
      false
    );

    assert.equal(
      stageMoveChanged(
        null,
        "stage-a"
      ),
      true
    );

    assert.equal(
      stageMoveChanged(
        "stage-a",
        null
      ),
      true
    );
  }
);
