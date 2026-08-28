import assert from "node:assert/strict";
import { test } from "node:test";

import {
  buildEvolutionTextPayload
} from "./evolution-payloads.js";

test(
  "Evolution 2.3.7 text payload remains unchanged without quote",
  () => {
    assert.deepEqual(
      buildEvolutionTextPayload({
        instanceName:
          "wapp-test",
        number:
          "5511999999999",
        text:
          "Olá"
      }),
      {
        number:
          "5511999999999",
        text:
          "Olá"
      }
    );
  }
);

test(
  "Evolution 2.3.7 quoted reply uses quoted.key.id",
  () => {
    assert.deepEqual(
      buildEvolutionTextPayload({
        instanceName:
          "wapp-test",
        number:
          "5511999999999",
        text:
          "Respondendo",
        quoted: {
          externalId:
            "3EB012345678"
        }
      }),
      {
        number:
          "5511999999999",
        text:
          "Respondendo",
        quoted: {
          key: {
            id:
              "3EB012345678"
          }
        }
      }
    );
  }
);
