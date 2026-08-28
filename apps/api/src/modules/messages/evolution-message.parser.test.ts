import assert from "node:assert/strict";
import { test } from "node:test";

import {
  parseEvolutionMessage
} from "./evolution-message.parser.js";

function basePayload(
  message:
    Record<
      string,
      unknown
    >,
  messageType: string
) {
  return {
    instance:
      "wapp-test",
    data: {
      key: {
        remoteJid:
          "5511999999999@s.whatsapp.net",
        id:
          "MESSAGE_NEW",
        fromMe:
          false
      },
      pushName:
        "Cliente",
      messageTimestamp:
        1_777_000_000,
      messageType,
      message
    }
  };
}

test(
  "parser captures quoted stanza from extended text",
  () => {
    const parsed =
      parseEvolutionMessage(
        basePayload(
          {
            extendedTextMessage: {
              text:
                "Resposta",
              contextInfo: {
                stanzaId:
                  "MESSAGE_ORIGINAL"
              }
            }
          },
          "extendedTextMessage"
        )
      );

    assert.equal(
      parsed
        ?.quotedExternalId,
      "MESSAGE_ORIGINAL"
    );
  }
);

test(
  "parser captures quoted stanza from media context",
  () => {
    const parsed =
      parseEvolutionMessage(
        basePayload(
          {
            imageMessage: {
              mimetype:
                "image/jpeg",
              caption:
                "Veja",
              contextInfo: {
                stanzaId:
                  "IMAGE_ORIGINAL"
              }
            }
          },
          "imageMessage"
        )
      );

    assert.equal(
      parsed
        ?.quotedExternalId,
      "IMAGE_ORIGINAL"
    );
  }
);
