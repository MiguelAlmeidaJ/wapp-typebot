import assert from "node:assert/strict";
import { test } from "node:test";

import {
  parseEvolutionReaction
} from "./evolution-reaction.parser.js";

test(
  "parses inbound direct reaction",
  () => {
    const parsed =
      parseEvolutionReaction({
        data: {
          key: {
            id:
              "REACTION_ID",
            remoteJid:
              "5511999999999@s.whatsapp.net",
            fromMe:
              false
          },
          messageType:
            "reactionMessage",
          message: {
            reactionMessage: {
              key: {
                id:
                  "TARGET_ID",
                remoteJid:
                  "5511999999999@s.whatsapp.net",
                fromMe:
                  true
              },
              text:
                "❤️"
            }
          }
        }
      });

    assert.equal(
      parsed
        ?.targetExternalId,
      "TARGET_ID"
    );

    assert.equal(
      parsed?.emoji,
      "❤️"
    );

    assert.equal(
      parsed?.fromMe,
      false
    );

    assert.equal(
      parsed?.reactorKey,
      "5511999999999@s.whatsapp.net"
    );
  }
);

test(
  "empty reaction text represents removal",
  () => {
    const parsed =
      parseEvolutionReaction({
        data: {
          key: {
            remoteJid:
              "5511999999999@s.whatsapp.net",
            fromMe:
              true
          },
          message: {
            reactionMessage: {
              key: {
                id:
                  "TARGET_ID"
              },
              text: ""
            }
          }
        }
      });

    assert.equal(
      parsed?.reactorKey,
      "SELF"
    );

    assert.equal(
      parsed?.emoji,
      ""
    );
  }
);

test(
  "group reaction identifies participant instead of group JID",
  () => {
    const parsed =
      parseEvolutionReaction({
        data: {
          key: {
            remoteJid:
              "120363000000000000@g.us",
            participant:
              "123456789@lid",
            participantAlt:
              "5511888888888@s.whatsapp.net",
            fromMe:
              false
          },
          message: {
            reactionMessage: {
              key: {
                id:
                  "TARGET_GROUP_ID"
              },
              text:
                "👍"
            }
          }
        }
      });

    assert.equal(
      parsed?.reactorKey,
      "5511888888888@s.whatsapp.net"
    );
  }
);
