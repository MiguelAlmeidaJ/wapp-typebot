#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.1] Installing WhatsApp quoted replies..."

for required in \
  "apps/api/src/integrations/whatsapp/provider.ts" \
  "apps/api/src/integrations/whatsapp/evolution.client.ts" \
  "apps/api/src/modules/messages/evolution-message.parser.ts" \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/tickets/ticket-message-history.service.ts" \
  "apps/api/package.json" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/integrations/whatsapp \
  apps/api/src/modules/messages \
  docs

# ---------------------------------------------------------------------------
# Provider abstraction + exact Evolution 2.3.7 quoted payload.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/provider.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldInterface = `export interface SendTextInput {
  instanceName: string;
  number: string;
  text: string;
}`;

const newInterface = `export interface SendTextInput {
  instanceName: string;
  number: string;
  text: string;
  quoted?: {
    externalId: string;
  };
}`;

if (
  content.includes(
    oldInterface
  )
) {
  content =
    content.replace(
      oldInterface,
      newInterface
    );
} else if (
  !content.includes(
    "externalId: string;"
  )
) {
  throw new Error(
    "SendTextInput anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > apps/api/src/integrations/whatsapp/evolution-payloads.ts <<'EOF'
import type {
  SendTextInput
} from "./provider.js";

export function buildEvolutionTextPayload(
  input: SendTextInput
) {
  return {
    number:
      input.number,
    text:
      input.text,
    ...(input.quoted
      ? {
          /*
           * Evolution API 2.3.7 message.schema.ts accepts `quoted.key.id`
           * as the required quote locator. The provider can resolve the
           * original message from its own message store.
           */
          quoted: {
            key: {
              id:
                input
                  .quoted
                  .externalId
            }
          }
        }
      : {})
  };
}
EOF

cat > apps/api/src/integrations/whatsapp/evolution-payloads.test.ts <<'EOF'
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
EOF

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/evolution.client.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const payloadImport =
  'import { buildEvolutionTextPayload } from "./evolution-payloads.js";';

if (
  !content.includes(
    payloadImport
  )
) {
  const anchor =
    'import { AppError } from "../../errors/app-error.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Evolution client import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${payloadImport}`
    );
}

const oldBody = `        body: JSON.stringify({
          number: input.number,
          text: input.text
        })`;

const newBody = `        body: JSON.stringify(
          buildEvolutionTextPayload(
            input
          )
        )`;

if (
  content.includes(
    oldBody
  )
) {
  content =
    content.replace(
      oldBody,
      newBody
    );
} else if (
  !content.includes(
    "buildEvolutionTextPayload("
  )
) {
  throw new Error(
    "Evolution sendText payload anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Inbound quote parsing for text AND media messages.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/evolution-message.parser.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldQuoted = `function quotedId(message: Record<string, unknown>) {
  const extended = record(message.extendedTextMessage);
  const context = record(extended?.contextInfo);

  return string(context?.stanzaId);
}`;

const newQuoted = `function quotedId(
  message:
    Record<string, unknown>
) {
  const messageContainers = [
    message.extendedTextMessage,
    message.imageMessage,
    message.audioMessage,
    message.videoMessage,
    message.documentMessage,
    message.stickerMessage,
    message.locationMessage,
    message.contactMessage
  ];

  for (
    const container
    of messageContainers
  ) {
    const context =
      record(
        record(
          container
        )?.contextInfo
      );

    const stanzaId =
      string(
        context?.stanzaId
      );

    if (stanzaId) {
      return stanzaId;
    }
  }

  const directContext =
    record(
      message.contextInfo
    );

  return string(
    directContext?.stanzaId
  );
}`;

if (
  content.includes(
    oldQuoted
  )
) {
  content =
    content.replace(
      oldQuoted,
      newQuoted
    );
} else if (
  !content.includes(
    "const messageContainers = ["
  )
) {
  throw new Error(
    "quotedId parser anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > apps/api/src/modules/messages/evolution-message.parser.test.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# API: replyToMessageId -> validate same ticket -> Evolution -> persistence.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.routes.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldSchema = `const sendTextSchema = z.object({
  text: z.string().trim().min(1).max(4096)
});`;

const newSchema = `const sendTextSchema = z.object({
  text: z
    .string()
    .trim()
    .min(1)
    .max(4096),
  replyToMessageId:
    z.string()
      .uuid()
      .optional()
});`;

if (
  content.includes(
    oldSchema
  )
) {
  content =
    content.replace(
      oldSchema,
      newSchema
    );
} else if (
  !content.includes(
    "replyToMessageId:"
  )
) {
  throw new Error(
    "sendTextSchema anchor not found."
  );
}

const oldCall = `          role: auth.role,
          text: input.text
        })`;

const newCall = `          role: auth.role,
          text: input.text,
          replyToMessageId:
            input.replyToMessageId
        })`;

if (
  content.includes(
    oldCall
  )
) {
  content =
    content.replace(
      oldCall,
      newCall
    );
} else if (
  !content.includes(
    "replyToMessageId:\n            input.replyToMessageId"
  )
) {
  throw new Error(
    "sendTicketText route call anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const signatureOld = `  role: WappRole;
  text: string;
}) {
  let ticket = await getTicket(input.companyId, input.ticketId);`;

const signatureNew = `  role: WappRole;
  text: string;
  replyToMessageId?: string;
}) {
  let ticket = await getTicket(input.companyId, input.ticketId);`;

if (
  content.includes(
    signatureOld
  )
) {
  content =
    content.replace(
      signatureOld,
      signatureNew
    );
} else if (
  !content.includes(
    "replyToMessageId?: string;"
  )
) {
  throw new Error(
    "sendTicketText signature anchor not found."
  );
}

const sendAnchor = `  const result = await evolutionWhatsAppClient.sendText({
    instanceName: ticket.whatsappConnection.instanceName,
    number: ticket.contact.remoteJid,
    text: input.text
  });`;

const sendReplacement = `  const quotedMessage =
    input.replyToMessageId
      ? await prisma.message.findFirst({
          where: {
            id:
              input.replyToMessageId,
            companyId:
              input.companyId,
            ticketId:
              ticket.id
          },
          select: {
            id: true,
            externalId:
              true
          }
        })
      : null;

  if (
    input.replyToMessageId &&
    !quotedMessage
  ) {
    throw new AppError(
      "A mensagem citada não pertence a este atendimento.",
      422,
      "INVALID_QUOTED_MESSAGE"
    );
  }

  const result =
    await evolutionWhatsAppClient.sendText({
      instanceName:
        ticket
          .whatsappConnection
          .instanceName,
      number:
        ticket
          .contact
          .remoteJid,
      text:
        input.text,
      ...(quotedMessage
        ? {
            quoted: {
              externalId:
                quotedMessage
                  .externalId
            }
          }
        : {})
    });`;

if (
  content.includes(
    sendAnchor
  )
) {
  content =
    content.replace(
      sendAnchor,
      sendReplacement
    );
} else if (
  !content.includes(
    'code: "INVALID_QUOTED_MESSAGE"'
  )
) {
  throw new Error(
    "Evolution sendText service anchor not found."
  );
}

const createAnchor = `      deliveryStatus: "PENDING",
      body: input.text,
      timestamp,`;

const createReplacement = `      deliveryStatus: "PENDING",
      body: input.text,
      quotedExternalId:
        quotedMessage
          ?.externalId,
      timestamp,`;

if (
  content.includes(
    createAnchor
  )
) {
  content =
    content.replace(
      createAnchor,
      createReplacement
    );
} else if (
  !content.includes(
    "quotedMessage\n          ?.externalId"
  )
) {
  throw new Error(
    "outbound message create anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# API: enrich each history page with a safe quoted-message preview.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket-message-history.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldFunctionStart = `function pageResult(
  messages:`;

const newFunctionStart = `async function pageResult(
  companyId: string,
  ticketId: string,
  messages:`;

if (
  content.includes(
    oldFunctionStart
  )
) {
  content =
    content.replace(
      oldFunctionStart,
      newFunctionStart
    );
} else if (
  !content.includes(
    "async function pageResult("
  )
) {
  throw new Error(
    "pageResult function anchor not found."
  );
}

const oldReturn = `  return {
    messages,
    pagination: {`;

const newReturn = `  const quotedExternalIds =
    Array.from(
      new Set(
        messages
          .map(
            message =>
              message
                .quotedExternalId
          )
          .filter(
            (
              externalId
            ): externalId is string =>
              Boolean(
                externalId
              )
          )
      )
    );

  const quotedMessages =
    quotedExternalIds.length >
      0
      ? await prisma.message.findMany({
          where: {
            companyId,
            ticketId,
            externalId: {
              in:
                quotedExternalIds
            }
          },
          select: {
            id: true,
            externalId:
              true,
            direction:
              true,
            type: true,
            body: true,
            mediaFileName:
              true,
            timestamp:
              true
          }
        })
      : [];

  const quotedByExternalId =
    new Map(
      quotedMessages.map(
        message => [
          message.externalId,
          message
        ]
      )
    );

  return {
    messages:
      messages.map(
        message => ({
          ...message,
          quotedMessage:
            message
              .quotedExternalId
              ? quotedByExternalId.get(
                  message
                    .quotedExternalId
                ) ??
                null
              : null
        })
      ),
    pagination: {`;

if (
  content.includes(
    oldReturn
  )
) {
  content =
    content.replace(
      oldReturn,
      newReturn
    );
} else if (
  !content.includes(
    "quotedByExternalId"
  )
) {
  throw new Error(
    "pageResult return anchor not found."
  );
}

/*
 * Every pageResult invocation now needs company/ticket scope.
 * The first argument is always a message array, so inject scope ahead of it.
 */
const callPatterns = [
  "    return pageResult(\n      [",
  "    return pageResult(\n      messages,",
  "  return pageResult(\n    messages,"
];

for (
  const pattern
  of callPatterns
) {
  while (
    content.includes(
      pattern
    )
  ) {
    const indent =
      pattern.startsWith(
        "    "
      )
        ? "    "
        : "  ";

    const replacement =
      pattern.replace(
        "pageResult(\n",
        `pageResult(
${indent}  input.companyId,
${indent}  input.ticketId,
`
      );

    content =
      content.replace(
        pattern,
        replacement
      );
  }
}

if (
  content.match(
    /pageResult\(\s*(?:\[|messages)/
  )
) {
  throw new Error(
    "An unscoped pageResult call remains."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Web: quote preview, reply mode, jump-to-original, send reply id.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

function replaceOnce(
  before,
  after,
  label
) {
  if (
    content.includes(
      after
    )
  ) {
    return;
  }

  if (
    !content.includes(
      before
    )
  ) {
    throw new Error(
      `${label} anchor not found.`
    );
  }

  content =
    content.replace(
      before,
      after
    );
}

replaceOnce(
  `  sentByUserId: string | null;
}`,
  `  sentByUserId: string | null;
  quotedExternalId:
    | string
    | null;
  quotedMessage:
    | {
        id: string;
        externalId: string;
        direction:
          | "INBOUND"
          | "OUTBOUND";
        type:
          MessageType;
        body:
          | string
          | null;
        mediaFileName:
          | string
          | null;
        timestamp:
          string;
      }
    | null;
}`,
  "Message quoted fields"
);

if (
  !content.includes(
    "function quotedMessagePreview"
  )
) {
  const anchor = `function deliveryStatusPresentation(
  status: Message["deliveryStatus"]
) {`;

  const helper = `function quotedMessagePreview(
  message:
    NonNullable<
      Message[
        "quotedMessage"
      ]
    >
) {
  if (
    message.body &&
    message.body.trim()
  ) {
    return message.body;
  }

  if (
    message.mediaFileName
  ) {
    return message.mediaFileName;
  }

  return messageFallback(
    message.type
  );
}

function replyTargetPreview(
  message: Message
) {
  return (
    visibleMessageBody(
      message
    ) ??
    message.mediaFileName ??
    messageFallback(
      message.type
    )
  );
}

${anchor}`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "delivery presentation anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      helper
    );
}

replaceOnce(
  `  const [text, setText] = useState("");`,
  `  const [text, setText] = useState("");
  const [replyingTo, setReplyingTo] =
    useState<Message | null>(null);`,
  "reply state"
);

const selectedClearOld = `    if (!selectedId) {
      setMessages([]);
      setMessagePagination({`;

const selectedClearNew = `    if (!selectedId) {
      setMessages([]);
      setReplyingTo(null);
      setMessagePagination({`;

replaceOnce(
  selectedClearOld,
  selectedClearNew,
  "selected ticket reply clear"
);

const selectedLoadAnchor = `    if (
      skipNextSelectedLoadRef.current
    ) {`;

if (
  !content.includes(
    "setReplyingTo(null);\n\n    if (\n      skipNextSelectedLoadRef.current"
  )
) {
  if (
    !content.includes(
      selectedLoadAnchor
    )
  ) {
    throw new Error(
      "selected load anchor not found."
    );
  }

  content =
    content.replace(
      selectedLoadAnchor,
      `    setReplyingTo(null);

${selectedLoadAnchor}`
    );
}

if (
  !content.includes(
    "function startReply("
  )
) {
  const anchor = `  async function handleSend(
    event: FormEvent<HTMLFormElement>
  ) {`;

  const helpers = `  function startReply(
    message: Message
  ) {
    if (
      recording
    ) {
      return;
    }

    setReplyingTo(
      message
    );

    window.setTimeout(
      () => {
        composerTextRef
          .current
          ?.focus();
      },
      0
    );
  }

  async function jumpToQuotedMessage(
    message: Message
  ) {
    const target =
      message
        .quotedMessage;

    if (
      !target ||
      !selectedId
    ) {
      return;
    }

    const loaded =
      messages.some(
        item =>
          item.id ===
          target.id
      );

    if (loaded) {
      setFocusedMessageId(
        target.id
      );

      document
        .querySelector(
          \`[data-message-id="\${target.id}"]\`
        )
        ?.scrollIntoView({
          behavior:
            "smooth",
          block:
            "center"
        });

      window.setTimeout(
        () => {
          setFocusedMessageId(
            current =>
              current ===
              target.id
                ? null
                : current
          );
        },
        3_000
      );

      return;
    }

    try {
      await loadMessages(
        selectedId,
        {
          around:
            target.id
        }
      );
    } catch {
      setError(
        "Não foi possível abrir a mensagem citada."
      );
    }
  }

${anchor}`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "handleSend anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      helpers
    );
}

const textPayloadOld = `            body: JSON.stringify({
              text: text.trim()
            })`;

const textPayloadNew = `            body: JSON.stringify({
              text:
                text.trim(),
              ...(replyingTo
                ? {
                    replyToMessageId:
                      replyingTo.id
                  }
                : {})
            })`;

replaceOnce(
  textPayloadOld,
  textPayloadNew,
  "text send payload"
);

const clearTextOld = `      setText("");

      await Promise.all([`;

const clearTextNew = `      setText("");
      setReplyingTo(null);

      await Promise.all([`;

replaceOnce(
  clearTextOld,
  clearTextNew,
  "reply clear after send"
);

const closeClearOld = `      setMessages([]);
      setSelectedId(null);`;

const closeClearNew = `      setMessages([]);
      setReplyingTo(null);
      setSelectedId(null);`;

replaceOnce(
  closeClearOld,
  closeClearNew,
  "reply clear on close"
);

const mediaBodyAnchor = `                      <MessageMedia
                        fileName={message.mediaFileName}`;

if (
  !content.includes(
    "message-quoted-preview"
  )
) {
  if (
    !content.includes(
      mediaBodyAnchor
    )
  ) {
    throw new Error(
      "MessageMedia render anchor not found."
    );
  }

  const quoteRender = `                      {message.quotedExternalId && (
                        <button
                          className="message-quoted-preview"
                          disabled={
                            !message.quotedMessage
                          }
                          onClick={() =>
                            void jumpToQuotedMessage(
                              message
                            )
                          }
                          title={
                            message.quotedMessage
                              ? "Abrir mensagem citada"
                              : "Mensagem citada não está disponível no histórico local"
                          }
                          type="button"
                        >
                          <span>
                            {message.quotedMessage?.direction ===
                            "OUTBOUND"
                              ? "Você"
                              : selectedTicket.contact.name}
                          </span>
                          <p>
                            {message.quotedMessage
                              ? quotedMessagePreview(
                                  message.quotedMessage
                                )
                              : "Mensagem citada"}
                          </p>
                        </button>
                      )}

${mediaBodyAnchor}`;

  content =
    content.replace(
      mediaBodyAnchor,
      quoteRender
    );
}

const metaAnchor = `                      <div className="message-meta">
                        {message.direction === "OUTBOUND" &&`;

if (
  !content.includes(
    'className="message-reply-action"'
  )
) {
  if (
    !content.includes(
      metaAnchor
    )
  ) {
    throw new Error(
      "message-meta anchor not found."
    );
  }

  const replyAction = `                      <div className="message-meta">
                        <button
                          aria-label="Responder esta mensagem"
                          className="message-reply-action"
                          onClick={() =>
                            startReply(
                              message
                            )
                          }
                          title="Responder"
                          type="button"
                        >
                          ↩
                        </button>

                        {message.direction === "OUTBOUND" &&`;

  content =
    content.replace(
      metaAnchor,
      replyAction
    );
}

const formAnchor = `                  <input
                    accept="image/jpeg,image/png,image/webp,image/gif,audio/ogg,audio/mpeg,audio/mp4,audio/webm,audio/wav,video/mp4,video/webm,application/pdf,text/plain,application/zip,.doc,.docx,.xls,.xlsx,.ppt,.pptx"`;

if (
  !content.includes(
    "composer-reply-preview"
  )
) {
  if (
    !content.includes(
      formAnchor
    )
  ) {
    throw new Error(
      "composer input anchor not found."
    );
  }

  const replyComposer = `                  {replyingTo && (
                    <div className="composer-reply-preview">
                      <div>
                        <span>
                          Respondendo a{" "}
                          {replyingTo.direction ===
                          "OUTBOUND"
                            ? "você"
                            : selectedTicket.contact.name}
                        </span>
                        <strong>
                          {replyTargetPreview(
                            replyingTo
                          )}
                        </strong>
                      </div>

                      <button
                        aria-label="Cancelar resposta"
                        disabled={sending}
                        onClick={() =>
                          setReplyingTo(
                            null
                          )
                        }
                        title="Cancelar resposta"
                        type="button"
                      >
                        ×
                      </button>
                    </div>
                  )}

${formAnchor}`;

  content =
    content.replace(
      formAnchor,
      replyComposer
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# UI styling. Keep canonical conversation/composer layout untouched.
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P2.1 / QUOTED REPLIES" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P2.1 / QUOTED REPLIES --- */

.message-quoted-preview {
  display: block;
  width: 100%;
  margin: 0 0 8px;
  padding: 8px 10px;
  border: 0;
  border-left: 3px solid currentColor;
  border-radius: 7px;
  background: rgba(0, 0, 0, 0.045);
  color: inherit;
  text-align: left;
  cursor: pointer;
  opacity: 0.82;
}

.message-quoted-preview:disabled {
  cursor: default;
}

.message-quoted-preview span {
  display: block;
  margin-bottom: 2px;
  font-size: 11px;
  font-weight: 800;
}

.message-quoted-preview p {
  display: -webkit-box;
  overflow: hidden;
  margin: 0;
  font-size: 12px;
  line-height: 1.35;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.message-reply-action {
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  cursor: pointer;
  opacity: 0.45;
}

.message-reply-action:hover {
  opacity: 0.9;
}

.composer-reply-preview {
  grid-column: 1 / -1;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-width: 0;
  margin: 0 0 4px;
  padding: 8px 10px 8px 12px;
  border-left: 3px solid rgba(34, 126, 82, 0.72);
  border-radius: 8px;
  background: rgba(34, 126, 82, 0.065);
}

.composer-reply-preview > div {
  min-width: 0;
}

.composer-reply-preview span,
.composer-reply-preview strong {
  display: block;
}

.composer-reply-preview span {
  margin-bottom: 2px;
  font-size: 11px;
  font-weight: 800;
}

.composer-reply-preview strong {
  overflow: hidden;
  max-width: min(560px, 72vw);
  font-size: 12px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.composer-reply-preview button {
  flex: 0 0 auto;
  border: 0;
  background: transparent;
  font: inherit;
  font-size: 18px;
  cursor: pointer;
  opacity: 0.58;
}

/* --- /WAPP P2.1 --- */
EOF
fi

# ---------------------------------------------------------------------------
# Register tests without overwriting the P1 suite assembled locally.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

pkg.scripts ??= {};

const current =
  pkg.scripts.test;

if (
  typeof current !==
    "string"
) {
  throw new Error(
    "apps/api test script is missing."
  );
}

const additions = [
  "src/integrations/whatsapp/evolution-payloads.test.ts",
  "src/modules/messages/evolution-message.parser.test.ts"
];

pkg.scripts.test =
  additions.reduce(
    (
      command,
      file
    ) =>
      command.includes(
        file
      )
        ? command
        : `${command} ${file}`,
    current
  );

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);
NODE

cat > docs/P2_01_QUOTED_REPLIES.md <<'EOF'
# P2.1 WhatsApp quoted replies

P2.1 closes the end-to-end quoted/reply flow.

## Inbound

Wapp already persisted `Message.quotedExternalId`.

P2.1 expands the Evolution parser so quoted `contextInfo.stanzaId` is also
recognized on image/audio/video/document/sticker/location/contact containers,
not only `extendedTextMessage`.

## History API

Ticket message pages now include:

```json
{
  "quotedExternalId": "...",
  "quotedMessage": {
    "id": "...",
    "externalId": "...",
    "direction": "INBOUND",
    "type": "TEXT",
    "body": "...",
    "mediaFileName": null,
    "timestamp": "..."
  }
}
```

The quoted preview is resolved company + ticket scoped.

If the referenced message is not present in Wapp's local history,
`quotedMessage` is `null`; the raw external id remains stored.

## Outbound text

`POST /api/v1/tickets/:id/messages`

accepts:

```json
{
  "text": "Resposta",
  "replyToMessageId": "<Wapp Message UUID>"
}
```

The API validates that the message belongs to the same company and ticket.

Evolution API 2.3.7 receives:

```json
{
  "number": "...",
  "text": "Resposta",
  "quoted": {
    "key": {
      "id": "<WhatsApp external message id>"
    }
  }
}
```

The resulting outbound Wapp message persists the original external id in
`quotedExternalId`.

## UI

Each loaded message has a reply action.

While composing, Wapp shows a compact "Respondendo a..." strip. Sending a text
includes `replyToMessageId`; cancelling only clears reply mode.

Messages that quote another message render a compact preview. Clicking the
preview jumps to the original. If the original is outside the loaded P1.21
window, Wapp loads the page around that message first.

## Scope

P2.1 intentionally quotes outbound TEXT messages only.

Attachment/media reply transport is left for a later P2 increment because
Evolution's multipart routes have a different transport contract. Existing
media and voice-note sending behavior is not changed.

## Migration

No Prisma migration is required. `quotedExternalId` already exists.
EOF

echo "[P2.1] Unit tests..."
pnpm test

echo "[P2.1] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P2.1] Typechecking Web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.1] Quoted replies installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Live validation:"
echo "  1. receive a WhatsApp reply/quote and confirm the preview appears"
echo "  2. click the quoted preview and confirm it jumps to the original"
echo "  3. click ↩ on an inbound message"
echo "  4. type a text reply and send"
echo "  5. confirm WhatsApp renders it as a native quoted reply"
