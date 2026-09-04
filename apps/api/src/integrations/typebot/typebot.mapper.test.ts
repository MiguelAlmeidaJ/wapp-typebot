import assert from "node:assert/strict";
import test from "node:test";

import {
  mapTypebotAnswer,
  mapTypebotOutput
} from "./typebot.mapper.js";

test("maps markdown bubbles and choice inputs to WhatsApp text", () => {
  const input = {
    type: "choice input",
    items: [
      { content: "Comercial", value: "sales" },
      { content: "Suporte", value: "support" }
    ]
  };

  const messages = mapTypebotOutput({
    messages: [
      {
        id: "bubble-1",
        type: "text",
        content: {
          type: "markdown",
          markdown: "Como posso ajudar?"
        }
      }
    ],
    input,
    raw: {}
  });

  assert.deepEqual(messages, [
    "Como posso ajudar?",
    "1 — Comercial\n2 — Suporte"
  ]);
  assert.equal(mapTypebotAnswer("2", input), "support");
  assert.equal(mapTypebotAnswer("outro", input), "outro");
});

test("maps rich text and media URLs", () => {
  const messages = mapTypebotOutput({
    messages: [
      {
        id: "bubble-1",
        type: "text",
        content: {
          type: "richText",
          richText: [
            { children: [{ text: "Olá " }, { text: "Miguel" }] },
            { children: [{ text: "Tudo bem?" }] }
          ]
        }
      },
      {
        id: "bubble-2",
        type: "image",
        content: { url: "https://example.com/image.png" }
      }
    ],
    raw: {}
  });

  assert.deepEqual(messages, [
    "Olá Miguel\nTudo bem?",
    "https://example.com/image.png"
  ]);
});
