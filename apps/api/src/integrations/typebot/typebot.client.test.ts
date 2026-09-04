import assert from "node:assert/strict";
import test from "node:test";

import { TypebotClient } from "./typebot.client.js";
import { TypebotApiError } from "./typebot.types.js";

test("Typebot client starts a chat with auth, variables and text input", async () => {
  let requestUrl = "";
  let requestInit: RequestInit | undefined;
  const fetchMock = (async (input: string | URL | Request, init?: RequestInit) => {
    requestUrl = String(input);
    requestInit = init;
    return new Response(JSON.stringify({
      sessionId: "session-1",
      messages: []
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  }) as typeof fetch;

  const output = await new TypebotClient(
    "https://typebot.example/api/",
    "secret-token",
    15_000,
    fetchMock
  ).start({
    externalId: "welcome/bot",
    message: "Oi",
    variables: { nome: "Miguel" }
  });

  assert.equal(requestUrl, "https://typebot.example/api/v1/typebots/welcome%2Fbot/startChat");
  assert.equal(new Headers(requestInit?.headers).get("Authorization"), "Bearer secret-token");
  assert.deepEqual(JSON.parse(String(requestInit?.body)), {
    message: { type: "text", text: "Oi" },
    prefilledVariables: { nome: "Miguel" },
    textBubbleContentFormat: "markdown"
  });
  assert.equal(output.externalSessionId, "session-1");
});

test("Typebot client surfaces provider status without leaking a large body", async () => {
  const fetchMock = (async () => new Response("not allowed", { status: 403 })) as typeof fetch;
  const client = new TypebotClient("https://typebot.example/api", "token", 15_000, fetchMock);

  await assert.rejects(
    () => client.continue("session-1", "Olá"),
    (error: unknown) => {
      assert.ok(error instanceof TypebotApiError);
      assert.equal(error.status, 403);
      assert.equal(error.responseBody, "not allowed");
      return true;
    }
  );
});
