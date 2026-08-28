#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.2] Installing native WhatsApp reactions..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/integrations/whatsapp/provider.ts" \
  "apps/api/src/integrations/whatsapp/evolution.client.ts" \
  "apps/api/src/modules/messages/contact-identity.ts" \
  "apps/api/src/modules/realtime/realtime.bus.ts" \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/tickets/ticket-message-history.service.ts" \
  "apps/api/src/modules/webhooks/evolution-webhook.routes.ts" \
  "apps/web/lib/realtime-types.ts" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -q "replyingTo" apps/web/app/dashboard/conversations/page.tsx; then
  echo "ERROR: P2.1 must be installed before P2.2."
  exit 1
fi

if ! grep -q "canonicalRemoteJid" apps/api/src/modules/messages/contact-identity.ts; then
  echo "ERROR: P2.1b must be installed before P2.2."
  exit 1
fi

mkdir -p \
  apps/api/src/modules/messages \
  apps/api/prisma/migrations/20260828190000_message_reactions \
  docs

# ---------------------------------------------------------------------------
# Prisma: reactions are state attached to a message, not new messages.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/prisma/schema.prisma";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !content.includes(
    "messageReactions"
  )
) {
  const membershipModelStart =
    content.indexOf(
      "model CompanyMembership {"
    );

  const membershipModelEnd =
    content.indexOf(
      "\n}",
      membershipModelStart
    );

  if (
    membershipModelStart < 0 ||
    membershipModelEnd < 0
  ) {
    throw new Error(
      "CompanyMembership model not found."
    );
  }

  const beforeClose =
    content.slice(
      membershipModelStart,
      membershipModelEnd
    );

  if (
    !beforeClose.includes(
      "messageReactions"
    )
  ) {
    content =
      content.slice(
        0,
        membershipModelEnd
      ) +
      "\n  messageReactions MessageReaction[]" +
      content.slice(
        membershipModelEnd
      );
  }
}

if (
  !content.includes(
    "reactions              MessageReaction[]"
  )
) {
  const messageModelStart =
    content.indexOf(
      "model Message {"
    );

  const messageModelEnd =
    content.indexOf(
      "\n}",
      messageModelStart
    );

  if (
    messageModelStart < 0 ||
    messageModelEnd < 0
  ) {
    throw new Error(
      "Message model not found."
    );
  }

  const beforeClose =
    content.slice(
      messageModelStart,
      messageModelEnd
    );

  if (
    !beforeClose.includes(
      "MessageReaction[]"
    )
  ) {
    content =
      content.slice(
        0,
        messageModelEnd
      ) +
      "\n  reactions              MessageReaction[]" +
      content.slice(
        messageModelEnd
      );
  }
}

if (
  !content.includes(
    "model MessageReaction {"
  )
) {
  content += `

model MessageReaction {
  id                    String             @id @default(uuid()) @db.Char(36)
  companyId             String             @db.Char(36)
  ticketId              String             @db.Char(36)
  messageId             String             @db.Char(36)
  reactedByMembershipId String?            @db.Char(36)
  reactorKey            String             @db.VarChar(190)
  reactorJid            String?            @db.VarChar(190)
  fromMe                Boolean            @default(false)
  emoji                 String             @db.VarChar(32)
  message               Message            @relation(fields: [messageId], references: [id], onDelete: Cascade)
  reactedByMembership   CompanyMembership? @relation(fields: [reactedByMembershipId], references: [id], onDelete: SetNull)
  createdAt             DateTime           @default(now())
  updatedAt             DateTime           @updatedAt

  @@unique([messageId, reactorKey])
  @@index([companyId, ticketId])
  @@index([ticketId, updatedAt])
  @@index([reactedByMembershipId])
}
`;
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > apps/api/prisma/migrations/20260828190000_message_reactions/migration.sql <<'EOF'
CREATE TABLE `MessageReaction` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NOT NULL,
  `messageId` CHAR(36) NOT NULL,
  `reactedByMembershipId` CHAR(36) NULL,
  `reactorKey` VARCHAR(190) NOT NULL,
  `reactorJid` VARCHAR(190) NULL,
  `fromMe` BOOLEAN NOT NULL DEFAULT false,
  `emoji` VARCHAR(32) NOT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `MessageReaction_messageId_reactorKey_key` (`messageId`, `reactorKey`),
  INDEX `MessageReaction_companyId_ticketId_idx` (`companyId`, `ticketId`),
  INDEX `MessageReaction_ticketId_updatedAt_idx` (`ticketId`, `updatedAt`),
  INDEX `MessageReaction_reactedByMembershipId_idx` (`reactedByMembershipId`),

  CONSTRAINT `MessageReaction_messageId_fkey`
    FOREIGN KEY (`messageId`)
    REFERENCES `Message`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `MessageReaction_reactedByMembershipId_fkey`
    FOREIGN KEY (`reactedByMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

# ---------------------------------------------------------------------------
# Evolution 2.3.7 provider contract.
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

if (
  !content.includes(
    "export interface SendReactionInput"
  )
) {
  const anchor =
    "export type WhatsAppMediaType =";

  if (!content.includes(anchor)) {
    throw new Error(
      "provider media type anchor not found."
    );
  }

  const addition = `export interface SendReactionInput {
  instanceName: string;
  key: {
    id: string;
    remoteJid: string;
    fromMe: boolean;
  };
  reaction: string;
}

`;

  content =
    content.replace(
      anchor,
      `${addition}${anchor}`
    );
}

if (
  !content.includes(
    "sendReaction("
  )
) {
  const anchor = `  sendText(
    input: SendTextInput
  ): Promise<unknown>;`;

  if (!content.includes(anchor)) {
    throw new Error(
      "provider sendText method anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

  sendReaction(
    input: SendReactionInput
  ): Promise<unknown>;`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > apps/api/src/integrations/whatsapp/evolution-reaction-payloads.ts <<'EOF'
import type {
  SendReactionInput
} from "./provider.js";

export function buildEvolutionReactionPayload(
  input: SendReactionInput
) {
  return {
    key: {
      id:
        input.key.id,
      remoteJid:
        input.key.remoteJid,
      fromMe:
        input.key.fromMe
    },
    reaction:
      input.reaction
  };
}
EOF

cat > apps/api/src/integrations/whatsapp/evolution-reaction-payloads.test.ts <<'EOF'
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
  'import { buildEvolutionReactionPayload } from "./evolution-reaction-payloads.js";';

if (
  !content.includes(
    payloadImport
  )
) {
  const anchor =
    'import { AppError } from "../../errors/app-error.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Evolution AppError import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}\n${payloadImport}`
    );
}

if (
  !content.includes(
    "SendReactionInput,"
  )
) {
  const anchor =
    "  SendMediaInput,";

  if (!content.includes(anchor)) {
    throw new Error(
      "Evolution provider type import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}\n  SendReactionInput,`
    );
}

if (
  !content.includes(
    "async sendReaction("
  )
) {
  const anchor =
    `  async sendMedia(`;

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "Evolution sendMedia anchor not found."
    );
  }

  const method = `  async sendReaction(
    input: SendReactionInput
  ): Promise<unknown> {
    return this.request(
      \`/message/sendReaction/\${encodeURIComponent(
        input.instanceName
      )}\`,
      {
        method: "POST",
        body: JSON.stringify(
          buildEvolutionReactionPayload(
            input
          )
        )
      }
    );
  }

`;

  content =
    content.slice(
      0,
      index
    ) +
    method +
    content.slice(
      index
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Parse inbound reaction events without turning them into Message rows.
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/messages/evolution-reaction.parser.ts <<'EOF'
import {
  canonicalRemoteJid
} from "./contact-identity.js";

export interface ParsedEvolutionReaction {
  targetExternalId: string;
  emoji: string;
  fromMe: boolean;
  reactorKey: string;
  reactorJid?: string;
  rawPayload:
    Record<string, unknown>;
}

function record(
  value: unknown
):
  | Record<string, unknown>
  | undefined {
  return value &&
    typeof value ===
      "object" &&
    !Array.isArray(
      value
    )
    ? value as
        Record<
          string,
          unknown
        >
    : undefined;
}

function text(
  value: unknown
) {
  return typeof value ===
      "string" &&
    value.length > 0
    ? value
    : undefined;
}

function reactionText(
  value: unknown
) {
  return typeof value ===
    "string"
    ? value
    : undefined;
}

function actorJid(
  key:
    Record<string, unknown>,
  remoteJid: string
) {
  const participant =
    text(
      key.participant
    );

  if (participant) {
    return canonicalRemoteJid({
      remoteJid:
        participant,
      remoteJidAlt:
        text(
          key.participantAlt
        )
    });
  }

  return canonicalRemoteJid({
    remoteJid,
    remoteJidAlt:
      text(
        key.remoteJidAlt
      )
  });
}

export function parseEvolutionReaction(
  payload:
    Record<string, unknown>
):
  | ParsedEvolutionReaction
  | null {
  const data =
    record(
      payload.data
    );

  const key =
    record(
      data?.key
    );

  const message =
    record(
      data?.message
    );

  const reaction =
    record(
      message
        ?.reactionMessage
    );

  const targetKey =
    record(
      reaction?.key
    );

  const remoteJid =
    text(
      key?.remoteJid
    );

  const targetExternalId =
    text(
      targetKey?.id
    );

  const emoji =
    reactionText(
      reaction?.text
    );

  if (
    !key ||
    !remoteJid ||
    !targetExternalId ||
    emoji ===
      undefined
  ) {
    return null;
  }

  const fromMe =
    key.fromMe ===
    true;

  const reactorJid =
    fromMe
      ? undefined
      : actorJid(
          key,
          remoteJid
        );

  return {
    targetExternalId,
    emoji:
      emoji.trim(),
    fromMe,
    reactorKey:
      fromMe
        ? "SELF"
        : reactorJid ??
          remoteJid,
    reactorJid,
    rawPayload:
      payload
  };
}
EOF

cat > apps/api/src/modules/messages/evolution-reaction.parser.test.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# Reaction persistence + normalized DTO.
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/messages/message-reaction.service.ts <<'EOF'
import type {
  WhatsAppConnection
} from "../../generated/prisma/client.js";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import {
  parseEvolutionReaction
} from "./evolution-reaction.parser.js";

const reactionInclude = {
  reactedByMembership: {
    select: {
      id: true,
      user: {
        select: {
          id: true,
          name: true
        }
      }
    }
  }
} as const;

export function reactionDto(
  reaction: {
    id: string;
    reactorKey: string;
    reactorJid:
      | string
      | null;
    fromMe: boolean;
    emoji: string;
    updatedAt: Date;
    reactedByMembership:
      | {
          id: string;
          user: {
            id: string;
            name: string;
          };
        }
      | null;
  }
) {
  return {
    id:
      reaction.id,
    reactorKey:
      reaction.reactorKey,
    reactorJid:
      reaction.reactorJid,
    fromMe:
      reaction.fromMe,
    emoji:
      reaction.emoji,
    actorName:
      reaction
        .reactedByMembership
        ?.user.name ??
      null,
    updatedAt:
      reaction.updatedAt
        .toISOString()
  };
}

export async function listReactions(
  messageId: string
) {
  const rows =
    await prisma.messageReaction.findMany({
      where: {
        messageId
      },
      include:
        reactionInclude,
      orderBy: [
        {
          fromMe:
            "desc"
        },
        {
          updatedAt:
            "asc"
        }
      ]
    });

  return rows.map(
    reactionDto
  );
}

export async function listTicketMessageReactions(input: {
  companyId: string;
  ticketId: string;
  messageId: string;
}) {
  const message =
    await prisma.message.findFirst({
      where: {
        id:
          input.messageId,
        companyId:
          input.companyId,
        ticketId:
          input.ticketId
      },
      select: {
        id: true
      }
    });

  if (!message) {
    throw new AppError(
      "Mensagem não encontrada neste atendimento.",
      404,
      "TICKET_MESSAGE_NOT_FOUND"
    );
  }

  return listReactions(
    message.id
  );
}

export async function persistReaction(input: {
  companyId: string;
  ticketId: string;
  messageId: string;
  reactorKey: string;
  reactorJid?: string;
  fromMe: boolean;
  emoji: string;
  reactedByMembershipId?: string;
}) {
  const emoji =
    input.emoji.trim();

  if (!emoji) {
    await prisma.messageReaction.deleteMany({
      where: {
        messageId:
          input.messageId,
        reactorKey:
          input.reactorKey
      }
    });
  } else {
    await prisma.messageReaction.upsert({
      where: {
        messageId_reactorKey: {
          messageId:
            input.messageId,
          reactorKey:
            input.reactorKey
        }
      },
      create: {
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        messageId:
          input.messageId,
        reactorKey:
          input.reactorKey,
        reactorJid:
          input.reactorJid,
        fromMe:
          input.fromMe,
        emoji,
        reactedByMembershipId:
          input
            .reactedByMembershipId
      },
      update: {
        reactorJid:
          input.reactorJid,
        fromMe:
          input.fromMe,
        emoji,
        ...(input
          .reactedByMembershipId
          ? {
              reactedByMembershipId:
                input
                  .reactedByMembershipId
            }
          : {})
      }
    });
  }

  const reactions =
    await listReactions(
      input.messageId
    );

  publishRealtime(
    input.companyId,
    {
      type:
        "message.reaction.updated",
      ticketId:
        input.ticketId,
      messageId:
        input.messageId
    }
  );

  return reactions;
}

export async function ingestEvolutionReaction(
  payload:
    Record<string, unknown>,
  connection:
    WhatsAppConnection
) {
  const parsed =
    parseEvolutionReaction(
      payload
    );

  if (!parsed) {
    return null;
  }

  const target =
    await prisma.message.findUnique({
      where: {
        whatsappConnectionId_externalId: {
          whatsappConnectionId:
            connection.id,
          externalId:
            parsed
              .targetExternalId
        }
      },
      select: {
        id: true,
        companyId:
          true,
        ticketId:
          true
      }
    });

  if (!target) {
    return {
      handled: true,
      ignored:
        "target_message_not_found"
    };
  }

  const reactions =
    await persistReaction({
      companyId:
        target.companyId,
      ticketId:
        target.ticketId,
      messageId:
        target.id,
      reactorKey:
        parsed.reactorKey,
      reactorJid:
        parsed.reactorJid,
      fromMe:
        parsed.fromMe,
      emoji:
        parsed.emoji
    });

  return {
    handled: true,
    messageId:
      target.id,
    reactions:
      reactions.length
  };
}
EOF

# ---------------------------------------------------------------------------
# Webhook: reactions are handled before normal message ingestion.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/webhooks/evolution-webhook.routes.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const importLine =
  'import { ingestEvolutionReaction } from "../messages/message-reaction.service.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { ingestEvolutionMessage } from "../messages/message-ingestion.service.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Evolution webhook ingestion import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}\n${importLine}`
    );
}

const oldBranch = `      } else if (event === "MESSAGES_UPSERT") {
        const result = await ingestEvolutionMessage(
          body,
          connection
        );

        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance,
            result
          },
          "Evolution message processed"
        );`;

const newBranch = `      } else if (event === "MESSAGES_UPSERT") {
        const reaction =
          await ingestEvolutionReaction(
            body,
            connection
          );

        const result =
          reaction ??
          await ingestEvolutionMessage(
            body,
            connection
          );

        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance,
            result
          },
          reaction
            ? "Evolution reaction processed"
            : "Evolution message processed"
        );`;

if (
  content.includes(
    oldBranch
  )
) {
  content =
    content.replace(
      oldBranch,
      newBranch
    );
} else if (
  !content.includes(
    "await ingestEvolutionReaction("
  )
) {
  throw new Error(
    "Evolution MESSAGES_UPSERT branch anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Ticket operation: send/remove a native reaction.
# ---------------------------------------------------------------------------

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

const reactionImport =
  `import { persistReaction } from "../messages/message-reaction.service.js";`;

if (
  !content.includes(
    reactionImport
  )
) {
  const anchor =
    'import { storeMedia } from "../media/media-storage.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "ticket service media import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}\n${reactionImport}`
    );
}

if (
  !content.includes(
    "export async function sendTicketReaction("
  )
) {
  const anchor =
    `\n\nconst documentMimeTypes = new Set([`;

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "ticket service media descriptor anchor not found."
    );
  }

  const method = `

export async function sendTicketReaction(input: {
  companyId: string;
  ticketId: string;
  messageId: string;
  membershipId: string;
  role: WappRole;
  emoji: string;
}) {
  let ticket =
    await getTicket(
      input.companyId,
      input.ticketId
    );

  if (
    ticket.status ===
    "CLOSED"
  ) {
    throw new AppError(
      "Este atendimento já foi encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.membershipId,
    input.role
  );

  if (
    !ticket.assignedMembershipId
  ) {
    await claimTicket({
      companyId:
        input.companyId,
      ticketId:
        ticket.id,
      membershipId:
        input.membershipId,
      role:
        input.role
    });

    ticket =
      await getTicket(
        input.companyId,
        input.ticketId
      );
  }

  if (
    ticket
      .whatsappConnection
      .status !==
    "CONNECTED"
  ) {
    throw new AppError(
      "A conexão WhatsApp deste atendimento está offline.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  const message =
    await prisma.message.findFirst({
      where: {
        id:
          input.messageId,
        companyId:
          input.companyId,
        ticketId:
          ticket.id
      },
      select: {
        id: true,
        externalId:
          true,
        direction:
          true
      }
    });

  if (!message) {
    throw new AppError(
      "Mensagem não encontrada neste atendimento.",
      404,
      "TICKET_MESSAGE_NOT_FOUND"
    );
  }

  const emoji =
    input.emoji.trim();

  await evolutionWhatsAppClient.sendReaction({
    instanceName:
      ticket
        .whatsappConnection
        .instanceName,
    key: {
      id:
        message.externalId,
      remoteJid:
        ticket
          .contact
          .remoteJid,
      fromMe:
        message.direction ===
        "OUTBOUND"
    },
    reaction:
      emoji
  });

  const reactions =
    await persistReaction({
      companyId:
        input.companyId,
      ticketId:
        ticket.id,
      messageId:
        message.id,
      reactorKey:
        "SELF",
      fromMe: true,
      emoji,
      reactedByMembershipId:
        input.membershipId
    });

  return {
    messageId:
      message.id,
    reactions
  };
}`;

  content =
    content.slice(
      0,
      index
    ) +
    method +
    content.slice(
      index
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Ticket routes: GET reactions + POST replace/remove reaction.
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

const reactionImport =
  'import { listTicketMessageReactions } from "../messages/message-reaction.service.js";';

if (
  !content.includes(
    reactionImport
  )
) {
  const anchor =
    'import { requireAuth } from "../auth/auth.guard.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "ticket route auth import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}\n${reactionImport}`
    );
}

if (
  !content.includes(
    "sendTicketReaction,"
  )
) {
  const anchor =
    "  sendTicketText,";

  if (!content.includes(anchor)) {
    throw new Error(
      "ticket route sendTicketText import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}\n  sendTicketReaction,`
    );
}

if (
  !content.includes(
    "const messageReactionParamsSchema"
  )
) {
  const anchor = `const ticketIdSchema = z.object({
  id: z.string().uuid()
});`;

  if (!content.includes(anchor)) {
    throw new Error(
      "ticketIdSchema anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

const messageReactionParamsSchema = z.object({
  id: z.string().uuid(),
  messageId:
    z.string().uuid()
});

const reactionSchema = z.object({
  emoji: z
    .string()
    .max(16)
});`
    );
}

if (
  !content.includes(
    '"/api/v1/tickets/:id/messages/:messageId/reactions"'
  )
) {
  const anchor =
    `  app.get(
    "/api/v1/tickets/:id/messages",`;

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "ticket messages route anchor not found."
    );
  }

  const routes = `  app.get(
    "/api/v1/tickets/:id/messages/:messageId/reactions",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        messageReactionParamsSchema.parse(
          request.params
        );

      return {
        reactions:
          await listTicketMessageReactions({
            companyId:
              auth.companyId,
            ticketId:
              params.id,
            messageId:
              params.messageId
          })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/messages/:messageId/reaction",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        messageReactionParamsSchema.parse(
          request.params
        );

      const input =
        reactionSchema.parse(
          request.body
        );

      return sendTicketReaction({
        companyId:
          auth.companyId,
        ticketId:
          params.id,
        messageId:
          params.messageId,
        membershipId:
          auth.membershipId,
        role:
          auth.role,
        emoji:
          input.emoji
      });
    }
  );

`;

  content =
    content.slice(
      0,
      index
    ) +
    routes +
    content.slice(
      index
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Message history pages include reactions in one batch query.
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

if (
  !content.includes(
    "reactionsByMessageId"
  )
) {
  const anchor = `  const quotedByExternalId =
    new Map(
      quotedMessages.map(
        message => [
          message.externalId,
          message
        ]
      )
    );`;

  if (!content.includes(anchor)) {
    throw new Error(
      "P2.1 quoted history anchor not found."
    );
  }

  const addition = `${anchor}

  const reactions =
    messages.length > 0
      ? await prisma.messageReaction.findMany({
          where: {
            messageId: {
              in:
                messages.map(
                  message =>
                    message.id
                )
            }
          },
          include: {
            reactedByMembership: {
              select: {
                user: {
                  select: {
                    name: true
                  }
                }
              }
            }
          },
          orderBy: {
            updatedAt:
              "asc"
          }
        })
      : [];

  const reactionsByMessageId =
    new Map<
      string,
      Array<{
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
      }>
    >();

  for (
    const reaction
    of reactions
  ) {
    const current =
      reactionsByMessageId.get(
        reaction.messageId
      ) ?? [];

    current.push({
      id:
        reaction.id,
      reactorKey:
        reaction.reactorKey,
      reactorJid:
        reaction.reactorJid,
      fromMe:
        reaction.fromMe,
      emoji:
        reaction.emoji,
      actorName:
        reaction
          .reactedByMembership
          ?.user.name ??
        null,
      updatedAt:
        reaction.updatedAt
          .toISOString()
    });

    reactionsByMessageId.set(
      reaction.messageId,
      current
    );
  }`;

  content =
    content.replace(
      anchor,
      addition
    );

  const messageMapAnchor = `          quotedMessage:
            message
              .quotedExternalId
              ? quotedByExternalId.get(
                  message
                    .quotedExternalId
                ) ??
                null
              : null`;

  if (!content.includes(messageMapAnchor)) {
    throw new Error(
      "P2.1 quoted message map anchor not found."
    );
  }

  content =
    content.replace(
      messageMapAnchor,
      `${messageMapAnchor},
          reactions:
            reactionsByMessageId.get(
              message.id
            ) ?? []`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Realtime event type.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

for (
  const path
  of [
    "apps/api/src/modules/realtime/realtime.bus.ts",
    "apps/web/lib/realtime-types.ts"
  ]
) {
  let content =
    fs.readFileSync(
      path,
      "utf8"
    ).replace(
      /\r\n/g,
      "\n"
    );

  if (
    !content.includes(
      '| "message.reaction.updated"'
    )
  ) {
    const anchor =
      '  | "message.updated"';

    if (!content.includes(anchor)) {
      throw new Error(
        `Realtime message.updated anchor not found in ${path}.`
      );
    }

    content =
      content.replace(
        anchor,
        `${anchor}\n  | "message.reaction.updated"`
      );
  }

  fs.writeFileSync(
    path,
    content
  );
}
NODE

# ---------------------------------------------------------------------------
# Web: reaction badges, picker, replace/remove, realtime refresh.
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
  const messageStart =
    content.indexOf(
      "interface Message {"
    );

  const messageEnd =
    content.indexOf(
      "\n}",
      messageStart
    );

  if (
    messageStart < 0 ||
    messageEnd < 0
  ) {
    throw new Error(
      "Message interface boundary not found."
    );
  }

  content =
    content.slice(
      0,
      messageEnd
    ) +
    "\n  reactions: MessageReaction[];" +
    content.slice(
      messageEnd
    );
}

if (
  !content.includes(
    "const REACTION_OPTIONS"
  )
) {
  const anchor =
    `const MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024;`;

  if (!content.includes(anchor)) {
    throw new Error(
      "attachment size constant anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

const REACTION_OPTIONS = [
  "👍",
  "❤️",
  "😂",
  "😮",
  "😢",
  "🙏"
] as const;`
    );
}

if (
  !content.includes(
    "function groupedReactions("
  )
) {
  const anchor =
    `function quotedMessagePreview(`;

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "P2.1 quoted helper anchor not found."
    );
  }

  const helpers = `function groupedReactions(
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

`;

  content =
    content.slice(
      0,
      index
    ) +
    helpers +
    content.slice(
      index
    );
}

replaceOnce(
  `  const [replyingTo, setReplyingTo] =
    useState<Message | null>(null);`,
  `  const [replyingTo, setReplyingTo] =
    useState<Message | null>(null);
  const [reactionPickerMessageId, setReactionPickerMessageId] =
    useState<string | null>(null);
  const [reactingMessageId, setReactingMessageId] =
    useState<string | null>(null);`,
  "reaction state"
);

if (
  !content.includes(
    "const refreshMessageReactions = useCallback("
  )
) {
  const anchor =
    `  const refreshLatestMessages = useCallback(`;

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "refreshLatestMessages anchor not found."
    );
  }

  const helper = `  const refreshMessageReactions = useCallback(
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

`;

  content =
    content.slice(
      0,
      index
    ) +
    helper +
    content.slice(
      index
    );
}

if (
  !content.includes(
    "async function reactToMessage("
  )
) {
  const anchor =
    `  function startReply(`;

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "P2.1 startReply anchor not found."
    );
  }

  const helper = `  async function reactToMessage(
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

`;

  content =
    content.slice(
      0,
      index
    ) +
    helper +
    content.slice(
      index
    );
}

if (
  !content.includes(
    'event.type === "message.reaction.updated"'
  )
) {
  const anchor = `      if (
        event.type === "note.created" &&`;

  if (!content.includes(anchor)) {
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
        event.messageId &&
        messages.some(
          message =>
            message.id ===
            event.messageId
        )
      ) {
        void refreshMessageReactions(
          selectedId,
          event.messageId
        );
      }

`;

  content =
    content.replace(
      anchor,
      `${branch}${anchor}`
    );

  const depsAnchor = `    refreshLatestMessages,
    selectedId,`;

  if (!content.includes(depsAnchor)) {
    throw new Error(
      "realtime dependency anchor not found."
    );
  }

  content =
    content.replace(
      depsAnchor,
      `    refreshLatestMessages,
    refreshMessageReactions,
    messages,
    selectedId,`
    );
}

if (
  !content.includes(
    "message-reactions"
  )
) {
  const anchor = `                      <div className="message-meta">`;

  if (!content.includes(anchor)) {
    throw new Error(
      "message-meta render anchor not found."
    );
  }

  const reactions = `                      {message.reactions.length > 0 && (
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
      reactions
    );
}

if (
  !content.includes(
    "message-reaction-picker"
  )
) {
  const replyActionAnchor = `                        <button
                          aria-label="Responder esta mensagem"
                          className="message-reply-action"`;

  if (!content.includes(replyActionAnchor)) {
    throw new Error(
      "P2.1 reply action anchor not found."
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

${replyActionAnchor}`;

  content =
    content.replace(
      replyActionAnchor,
      picker
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Scoped visual treatment.
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P2.2 / MESSAGE REACTIONS" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

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

# ---------------------------------------------------------------------------
# Register tests without replacing existing P1/P2 tests.
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

const current =
  pkg.scripts?.test;

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

P2.2 adds reaction state without treating reactions as chat messages.

## Data model

`MessageReaction` stores one current reaction per reactor/message pair.

A reactor changing emoji replaces the previous row. Empty reaction text removes
that row.

Stored fields include:

- company/ticket/message scope;
- reactor key and optional JID;
- whether the reaction came from the connected WhatsApp account (`fromMe`);
- Wapp membership responsible for an outbound reaction when known;
- current emoji and timestamps.

Reactions do not alter:

- Ticket.lastMessage;
- unreadCount;
- SLA clocks;
- Message delivery state.

## Evolution 2.3.7 outbound contract

Wapp calls:

`POST /message/sendReaction/:instance`

with:

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

Sending `reaction: ""` removes the connected account's current reaction.

## Inbound

`MESSAGES_UPSERT` payloads containing `message.reactionMessage` are intercepted
before normal message ingestion.

The target is resolved by the existing unique
`(whatsappConnectionId, externalId)` message key.

For group messages, the reacting participant is stored when Evolution provides
`participant`/`participantAlt`.

If the target message is not in Wapp history, the reaction event is safely
ignored and does not create an `UNKNOWN` Message row.

## API

Read:

`GET /api/v1/tickets/:ticketId/messages/:messageId/reactions`

React/replace/remove:

`POST /api/v1/tickets/:ticketId/messages/:messageId/reaction`

```json
{ "emoji": "❤️" }
```

Remove:

```json
{ "emoji": "" }
```

The same ticket operation/assignment rules used by outbound messaging apply.
Reacting to an unassigned active ticket claims it first.

## UI

Each message has a compact reaction trigger and the common picker:

`👍 ❤️ 😂 😮 😢 🙏`

Existing reactions appear under the message bubble. Clicking your own reaction
removes it; clicking another reaction adds/replaces the connected account's
reaction.

Realtime event:

`message.reaction.updated`

Only the affected loaded message refreshes its reaction list, so old P1.21
pages are not discarded.
EOF

echo "[P2.2] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P2.2] Unit tests..."
pnpm test

echo "[P2.2] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P2.2] Typechecking Web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.2] Native reactions installed."
echo
echo "Migration required before restart:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
echo
echo "Live validation:"
echo "  1. react to an inbound message from Wapp"
echo "  2. confirm the native reaction appears in WhatsApp"
echo "  3. react from WhatsApp to a Wapp message"
echo "  4. confirm it appears in realtime in Wapp"
echo "  5. change the reaction and confirm it replaces the old emoji"
echo "  6. click your active emoji again and confirm it is removed"
