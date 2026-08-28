#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.2b] Resuming native WhatsApp reactions after frontend anchor failure..."

PAGE="apps/web/app/dashboard/conversations/page.tsx"
CSS="apps/web/app/globals.css"
API_PACKAGE="apps/api/package.json"

for required in \
  "$PAGE" \
  "$CSS" \
  "$API_PACKAGE" \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/integrations/whatsapp/evolution.client.ts" \
  "apps/api/src/modules/messages/evolution-reaction.parser.ts" \
  "apps/api/src/modules/messages/message-reaction.service.ts" \
  "apps/api/src/modules/realtime/realtime.bus.ts" \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/webhooks/evolution-webhook.routes.ts" \
  "apps/web/lib/realtime-types.ts"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

# We intentionally resume the partial P2.2 state instead of replaying it.
for marker in \
  "model MessageReaction" \
  "reactions              MessageReaction[]"
do
  if ! grep -Fq -- "$marker" apps/api/prisma/schema.prisma; then
    echo "ERROR: partial P2.2 backend state is incomplete: missing '$marker'."
    echo "Do not rerun P2.2. Inspect the current checkout first."
    exit 1
  fi
done

if ! grep -q "async sendReaction(" apps/api/src/integrations/whatsapp/evolution.client.ts; then
  echo "ERROR: partial P2.2 Evolution client change is missing."
  exit 1
fi

if ! grep -q "message.reaction.updated" apps/api/src/modules/realtime/realtime.bus.ts; then
  echo "ERROR: partial P2.2 realtime backend change is missing."
  exit 1
fi

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

/* P2.2d frontend bootstrap */
if (
  !content.includes(
    "interface MessageReaction"
  )
) {
  const anchor =
    "interface Message {";

  if (!content.includes(anchor)) {
    throw new Error(
      "Message interface anchor not found."
    );
  }

  const type = `interface MessageReaction {
  id: string;
  reactorKey: string;
  reactorJid:
    | string
    | null;
  fromMe: boolean;
  emoji: string;
  actorName:
    | string
    | null;
  updatedAt: string;
}

`;

  content =
    content.replace(
      anchor,
      `${type}${anchor}`
    );
}

if (
  !content.includes(
    "reactions: MessageReaction[];"
  )
) {
  const start =
    content.indexOf(
      "interface Message {"
    );

  const end =
    content.indexOf(
      "\n}",
      start
    );

  if (
    start < 0 ||
    end < 0
  ) {
    throw new Error(
      "Message interface boundary not found."
    );
  }

  content =
    content.slice(
      0,
      end
    ) +
    "\n  reactions: MessageReaction[];" +
    content.slice(
      end
    );
}

function insertBefore(
  anchor,
  addition,
  already,
  label
) {
  if (
    already &&
    content.includes(
      already
    )
  ) {
    return;
  }

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      `${label} anchor not found.`
    );
  }

  content =
    content.slice(
      0,
      index
    ) +
    addition +
    content.slice(
      index
    );
}

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

/*
 * Original P2.2 assumed a MAX_ATTACHMENT_BYTES constant that does not exist
 * in this conversations page. ConversationsPage itself is the stable anchor.
 */
insertBefore(
  "export default function ConversationsPage() {",
  `const REACTION_OPTIONS = [
  "👍",
  "❤️",
  "😂",
  "😮",
  "😢",
  "🙏"
] as const;

`,
  "const REACTION_OPTIONS = [",
  "ConversationsPage"
);

insertBefore(
  "function quotedMessagePreview(",
  `function groupedReactions(
  reactions:
    MessageReaction[]
) {
  const groups =
    new Map<
      string,
      {
        emoji: string;
        count: number;
        fromMe: boolean;
      }
    >();

  for (
    const reaction
    of reactions
  ) {
    const current =
      groups.get(
        reaction.emoji
      );

    groups.set(
      reaction.emoji,
      {
        emoji:
          reaction.emoji,
        count:
          (current?.count ?? 0) +
          1,
        fromMe:
          Boolean(
            current?.fromMe ||
            reaction.fromMe
          )
      }
    );
  }

  return Array.from(
    groups.values()
  );
}

function ownReaction(
  message: Message
) {
  return message.reactions.find(
    reaction =>
      reaction.fromMe
  );
}

`,
  "function groupedReactions(",
  "quoted message helper"
);

replaceOnce(
  `  const [replyingTo, setReplyingTo] =
    useState<Message | null>(null);`,
  `  const [replyingTo, setReplyingTo] =
    useState<Message | null>(null);
  const [reactionPickerMessageId, setReactionPickerMessageId] =
    useState<string | null>(null);
  const [reactingMessageId, setReactingMessageId] =
    useState<string | null>(null);`,
  "P2.1 reply state"
);

insertBefore(
  "  const refreshLatestMessages = useCallback(",
  `  const refreshMessageReactions = useCallback(
    async (
      ticketId: string,
      messageId: string
    ) => {
      const payload =
        await request<{
          reactions:
            MessageReaction[];
        }>(
          \`/api/v1/tickets/\${ticketId}/messages/\${messageId}/reactions\`
        );

      setMessages(
        current =>
          current.map(
            message =>
              message.id ===
              messageId
                ? {
                    ...message,
                    reactions:
                      payload.reactions
                  }
                : message
          )
      );
    },
    [request]
  );

`,
  "const refreshMessageReactions = useCallback(",
  "refreshLatestMessages"
);

insertBefore(
  "  function startReply(",
  `  async function reactToMessage(
    message: Message,
    emoji: string
  ) {
    if (
      !selectedId ||
      reactingMessageId
    ) {
      return;
    }

    const current =
      ownReaction(
        message
      );

    const nextEmoji =
      current?.emoji ===
      emoji
        ? ""
        : emoji;

    setReactingMessageId(
      message.id
    );

    setReactionPickerMessageId(
      null
    );

    try {
      const payload =
        await request<{
          messageId: string;
          reactions:
            MessageReaction[];
        }>(
          \`/api/v1/tickets/\${selectedId}/messages/\${message.id}/reaction\`,
          {
            method:
              "POST",
            body:
              JSON.stringify({
                emoji:
                  nextEmoji
              })
          }
        );

      setMessages(
        currentMessages =>
          currentMessages.map(
            item =>
              item.id ===
              message.id
                ? {
                    ...item,
                    reactions:
                      payload.reactions
                  }
                : item
          )
      );
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : "Não foi possível reagir à mensagem."
      );
    } finally {
      setReactingMessageId(
        null
      );
    }
  }

`,
  "async function reactToMessage(",
  "P2.1 startReply"
);

if (
  !content.includes(
    'event.type ===\n          "message.reaction.updated"'
  ) &&
  !content.includes(
    'event.type === "message.reaction.updated"'
  )
) {
  const anchor = `      if (
        event.type === "note.created" &&`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "realtime note branch anchor not found."
    );
  }

  const branch = `      if (
        event.type ===
          "message.reaction.updated" &&
        selectedId &&
        event.ticketId ===
          selectedId &&
        event.messageId
      ) {
        void refreshMessageReactions(
          selectedId,
          event.messageId
        ).catch(() => {
          // The target can be outside the currently loaded P1.21 window.
        });
      }

`;

  content =
    content.replace(
      anchor,
      `${branch}${anchor}`
    );

  const depAnchor = `    refreshLatestMessages,
    selectedId,`;

  if (
    !content.includes(
      depAnchor
    )
  ) {
    throw new Error(
      "realtime dependency anchor not found."
    );
  }

  content =
    content.replace(
      depAnchor,
      `    refreshLatestMessages,
    refreshMessageReactions,
    selectedId,`
    );
}

if (
  !content.includes(
    'className="message-reactions"'
  )
) {
  const anchor = `                      <div className="message-meta">`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "message meta render anchor not found."
    );
  }

  const reactionBadges = `                      {message.reactions.length > 0 && (
                        <div className="message-reactions">
                          {groupedReactions(
                            message.reactions
                          ).map(
                            reaction => (
                              <button
                                className={
                                  reaction.fromMe
                                    ? "message-reaction-badge message-reaction-badge--mine"
                                    : "message-reaction-badge"
                                }
                                disabled={
                                  reactingMessageId ===
                                  message.id
                                }
                                key={
                                  reaction.emoji
                                }
                                onClick={() =>
                                  void reactToMessage(
                                    message,
                                    reaction.emoji
                                  )
                                }
                                title={
                                  reaction.fromMe
                                    ? "Sua reação — clique para remover"
                                    : "Reagir também"
                                }
                                type="button"
                              >
                                <span>
                                  {reaction.emoji}
                                </span>
                                {reaction.count > 1 && (
                                  <small>
                                    {reaction.count}
                                  </small>
                                )}
                              </button>
                            )
                          )}
                        </div>
                      )}

${anchor}`;

  content =
    content.replace(
      anchor,
      reactionBadges
    );
}

if (
  !content.includes(
    'className="message-reaction-picker"'
  )
) {
  const anchor = `                        <button
                          aria-label="Responder esta mensagem"
                          className="message-reply-action"`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "P2.1 reply action render anchor not found."
    );
  }

  const picker = `                        <div className="message-reaction-action">
                          <button
                            aria-label="Reagir à mensagem"
                            className="message-reaction-trigger"
                            disabled={
                              reactingMessageId ===
                              message.id
                            }
                            onClick={() =>
                              setReactionPickerMessageId(
                                current =>
                                  current ===
                                  message.id
                                    ? null
                                    : message.id
                              )
                            }
                            title="Reagir"
                            type="button"
                          >
                            ☺
                          </button>

                          {reactionPickerMessageId ===
                            message.id && (
                            <div className="message-reaction-picker">
                              {REACTION_OPTIONS.map(
                                emoji => (
                                  <button
                                    className={
                                      ownReaction(
                                        message
                                      )?.emoji ===
                                      emoji
                                        ? "message-reaction-option message-reaction-option--active"
                                        : "message-reaction-option"
                                    }
                                    key={emoji}
                                    onClick={() =>
                                      void reactToMessage(
                                        message,
                                        emoji
                                      )
                                    }
                                    title={
                                      ownReaction(
                                        message
                                      )?.emoji ===
                                      emoji
                                        ? "Remover reação"
                                        : \`Reagir com \${emoji}\`
                                    }
                                    type="button"
                                  >
                                    {emoji}
                                  </button>
                                )
                              )}
                            </div>
                          )}
                        </div>

${anchor}`;

  content =
    content.replace(
      anchor,
      picker
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "P2.2 frontend continuation applied."
);
NODE

if ! grep -q "WAPP P2.2 / MESSAGE REACTIONS" "$CSS"; then
  cat >> "$CSS" <<'EOF'

/* --- WAPP P2.2 / MESSAGE REACTIONS ------------------------------------ */

.message-reactions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin: 6px 0 2px;
}

.message-reaction-badge {
  display: inline-flex;
  height: 25px;
  align-items: center;
  gap: 3px;
  border: 1px solid rgba(20, 31, 25, 0.1);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.7);
  padding: 0 7px;
  font-size: 13px;
  line-height: 1;
}

.message-reaction-badge--mine {
  border-color: rgba(31, 122, 80, 0.3);
  background: rgba(31, 122, 80, 0.09);
}

.message-reaction-badge small {
  color: var(--muted);
  font-size: 9px;
  font-weight: 800;
}

.message-reaction-action {
  position: relative;
  display: inline-flex;
}

.message-reaction-trigger {
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  font-size: 13px;
  cursor: pointer;
  opacity: 0.42;
}

.message-reaction-trigger:hover {
  opacity: 0.9;
}

.message-reaction-picker {
  position: absolute;
  z-index: 40;
  bottom: calc(100% + 7px);
  left: 50%;
  display: flex;
  gap: 2px;
  border: 1px solid var(--line);
  border-radius: 999px;
  background: white;
  padding: 5px;
  box-shadow: 0 12px 35px rgba(20, 31, 25, 0.16);
  transform: translateX(-50%);
}

.message-row--out .message-reaction-picker {
  right: 0;
  left: auto;
  transform: none;
}

.message-reaction-option {
  display: grid;
  width: 31px;
  height: 31px;
  place-items: center;
  border: 0;
  border-radius: 50%;
  background: transparent;
  font-size: 17px;
  transition:
    transform 120ms ease,
    background 120ms ease;
}

.message-reaction-option:hover {
  background: var(--surface-subtle);
  transform: scale(1.1);
}

.message-reaction-option--active {
  background: var(--accent-soft);
}

/* --- /WAPP P2.2 ------------------------------------------------------- */
EOF
fi

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
    "API test command is missing."
  );
}

const additions = [
  "src/integrations/whatsapp/evolution-reaction-payloads.test.ts",
  "src/modules/messages/evolution-reaction.parser.test.ts"
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

cat > docs/P2_02_MESSAGE_REACTIONS.md <<'EOF'
# P2.2 Native WhatsApp message reactions

P2.2 stores reactions separately from chat messages.

A reaction does not change ticket unread count, SLA clocks or last-message
preview.

## Evolution 2.3.7

Outbound endpoint:

`POST /message/sendReaction/:instance`

Payload:

```json
{
  "key": {
    "id": "<target external id>",
    "remoteJid": "<conversation jid>",
    "fromMe": false
  },
  "reaction": "👍"
}
```

An empty reaction removes the connected account's current reaction.

Inbound `MESSAGES_UPSERT` events containing `message.reactionMessage` are
handled before ordinary message ingestion.

## Persistence

`MessageReaction` keeps one current reaction for each message/reactor key.

Changing emoji replaces the existing reaction. Removing it deletes that
message/reactor state.

## Realtime

`message.reaction.updated` refreshes only the reaction state of the affected
message and preserves the P1.21 paginated message window.

## UI

The picker contains:

`👍 ❤️ 😂 😮 😢 🙏`

Click the active reaction again to remove it.
EOF

echo "[P2.2b] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P2.2b] Unit tests..."
pnpm test

echo "[P2.2b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P2.2b] Typechecking Web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.2b] P2.2 installation resumed successfully."
echo
echo "Migration has NOT been executed by this installer."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
