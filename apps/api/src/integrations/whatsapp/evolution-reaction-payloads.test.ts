import assert from "node:assert/strict";
import { test } from "node:test";

import {
  buildEvolutionReactionPayload
} from "./evolution-reaction-payloads.js";

test(
  "Evolution 2.3.7 reaction payload uses key + reaction",
  () => {
    assert.deepEqual(
      buildEvolutionReactionPayload({
        instanceName:
          "wapp-test",
        key: {
          id:
            "MESSAGE_ID",
          remoteJid:
            "5511999999999@s.whatsapp.net",
          fromMe:
            false
        },
        reaction:
          "👍"
      }),
      {
        key: {
          id:
            "MESSAGE_ID",
          remoteJid:
            "5511999999999@s.whatsapp.net",
          fromMe:
            false
        },
        reaction:
          "👍"
      }
    );
  }
);

test(
  "empty Evolution reaction removes the current reaction",
  () => {
    assert.equal(
      buildEvolutionReactionPayload({
        instanceName:
          "wapp-test",
        key: {
          id:
            "MESSAGE_ID",
          remoteJid:
            "5511999999999@s.whatsapp.net",
          fromMe:
            true
        },
        reaction: ""
      }).reaction,
      ""
    );
  }
);
