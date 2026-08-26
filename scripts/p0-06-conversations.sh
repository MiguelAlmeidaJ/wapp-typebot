#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.6] Building Contacts, Tickets and Messages..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/webhooks/evolution-webhook.routes.ts" \
  "apps/api/src/integrations/whatsapp/evolution.client.ts" \
  "apps/web/components/auth-provider.tsx" \
  "apps/web/app/dashboard/page.tsx"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/contacts \
  apps/api/src/modules/tickets \
  apps/api/src/modules/messages \
  apps/web/app/dashboard/conversations \
  docs

# ---------------------------------------------------------------------------
# Prisma
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

if (!schema.includes("enum TicketStatus")) {
  const anchor = "enum MembershipRole {";
  const block = `enum TicketStatus {
  OPEN
  PENDING
  CLOSED
}

enum MessageDirection {
  INBOUND
  OUTBOUND
}

enum MessageType {
  TEXT
  IMAGE
  AUDIO
  VIDEO
  DOCUMENT
  STICKER
  LOCATION
  CONTACT
  UNKNOWN
}

`;

  if (!schema.includes(anchor)) {
    throw new Error("MembershipRole enum anchor not found.");
  }

  schema = schema.replace(anchor, block + anchor);
}

function addLineAfter(needle, line) {
  if (!schema.includes(line)) {
    if (!schema.includes(needle)) {
      throw new Error(`Schema anchor not found: ${needle}`);
    }

    schema = schema.replace(needle, `${needle}\n  ${line}`);
  }
}

addLineAfter(
  "whatsappConnections WhatsAppConnection[]",
  "contacts            Contact[]"
);
addLineAfter(
  "contacts            Contact[]",
  "tickets             Ticket[]"
);
addLineAfter(
  "tickets             Ticket[]",
  "messages            Message[]"
);

addLineAfter(
  "memberships  CompanyMembership[]",
  "sentMessages Message[]"
);

if (schema.includes("model WhatsAppConnection {")) {
  const start = schema.indexOf("model WhatsAppConnection {");
  const end = schema.indexOf("\n}", start);
  let model = schema.slice(start, end + 2);

  if (!model.includes("tickets      Ticket[]")) {
    model = model.replace(
      "company      Company",
      "company      Company\n  tickets      Ticket[]\n  messages     Message[]"
    );

    schema =
      schema.slice(0, start) +
      model +
      schema.slice(end + 2);
  }
}

if (!schema.includes("model Contact {")) {
  schema += `

model Contact {
  id          String    @id @default(uuid()) @db.Char(36)
  companyId   String    @db.Char(36)
  remoteJid   String    @db.VarChar(190)
  phoneNumber String?   @db.VarChar(32)
  name        String    @db.VarChar(190)
  isGroup     Boolean   @default(false)
  lastSeenAt  DateTime?
  company     Company   @relation(fields: [companyId], references: [id], onDelete: Cascade)
  tickets     Ticket[]
  createdAt   DateTime  @default(now())
  updatedAt   DateTime  @updatedAt

  @@unique([companyId, remoteJid])
  @@index([companyId, phoneNumber])
  @@index([companyId, name])
}

model Ticket {
  id                   String        @id @default(uuid()) @db.Char(36)
  companyId            String        @db.Char(36)
  whatsappConnectionId String        @db.Char(36)
  contactId            String        @db.Char(36)
  activeKey            String?       @unique @db.VarChar(100)
  status               TicketStatus  @default(OPEN)
  unreadCount          Int           @default(0)
  lastMessage          String?       @db.Text
  lastMessageAt        DateTime      @default(now())
  closedAt             DateTime?
  company              Company       @relation(fields: [companyId], references: [id], onDelete: Cascade)
  whatsappConnection   WhatsAppConnection @relation(fields: [whatsappConnectionId], references: [id], onDelete: Cascade)
  contact              Contact       @relation(fields: [contactId], references: [id], onDelete: Cascade)
  messages             Message[]
  createdAt            DateTime      @default(now())
  updatedAt            DateTime      @updatedAt

  @@index([companyId, status, lastMessageAt])
  @@index([whatsappConnectionId, status])
  @@index([contactId, status])
}

model Message {
  id                   String           @id @default(uuid()) @db.Char(36)
  companyId            String           @db.Char(36)
  ticketId             String           @db.Char(36)
  whatsappConnectionId String           @db.Char(36)
  sentByUserId         String?          @db.Char(36)
  externalId           String           @db.VarChar(190)
  direction            MessageDirection
  type                 MessageType      @default(TEXT)
  body                  String?          @db.Text
  mediaMimeType         String?          @db.VarChar(190)
  mediaFileName         String?          @db.VarChar(255)
  quotedExternalId      String?          @db.VarChar(190)
  timestamp             DateTime
  rawPayload            Json?
  company               Company          @relation(fields: [companyId], references: [id], onDelete: Cascade)
  ticket                Ticket           @relation(fields: [ticketId], references: [id], onDelete: Cascade)
  whatsappConnection    WhatsAppConnection @relation(fields: [whatsappConnectionId], references: [id], onDelete: Cascade)
  sentByUser            User?            @relation(fields: [sentByUserId], references: [id], onDelete: SetNull)
  createdAt             DateTime          @default(now())

  @@unique([whatsappConnectionId, externalId])
  @@index([ticketId, timestamp])
  @@index([companyId, timestamp])
}
`;
}

fs.writeFileSync(path, schema);
NODE

# ---------------------------------------------------------------------------
# Message parser / ingestion
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/messages/evolution-message.parser.ts <<'EOF'
export interface ParsedEvolutionMessage {
  externalId: string;
  remoteJid: string;
  phoneNumber?: string;
  pushName?: string;
  fromMe: boolean;
  isGroup: boolean;
  type:
    | "TEXT"
    | "IMAGE"
    | "AUDIO"
    | "VIDEO"
    | "DOCUMENT"
    | "STICKER"
    | "LOCATION"
    | "CONTACT"
    | "UNKNOWN";
  body?: string;
  mediaMimeType?: string;
  mediaFileName?: string;
  quotedExternalId?: string;
  timestamp: Date;
  rawPayload: Record<string, unknown>;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : undefined;
}

function string(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0
    ? value
    : undefined;
}

function numberFromJid(jid: string | undefined) {
  if (!jid || !jid.includes("@s.whatsapp.net")) {
    return undefined;
  }

  const digits = jid.split("@")[0]?.replace(/\D/g, "");
  return digits || undefined;
}

function epochToDate(value: unknown) {
  const timestamp =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : NaN;

  if (!Number.isFinite(timestamp)) {
    return new Date();
  }

  return new Date(timestamp * 1000);
}

function textFromMessage(
  message: Record<string, unknown>,
  messageType: string | undefined
) {
  const conversation = string(message.conversation);

  if (conversation) {
    return conversation;
  }

  const extended = record(message.extendedTextMessage);
  const extendedText = string(extended?.text);

  if (extendedText) {
    return extendedText;
  }

  const image = record(message.imageMessage);
  const imageCaption = string(image?.caption);

  if (imageCaption) {
    return imageCaption;
  }

  const video = record(message.videoMessage);
  const videoCaption = string(video?.caption);

  if (videoCaption) {
    return videoCaption;
  }

  const document = record(message.documentMessage);
  const documentCaption = string(document?.caption);

  if (documentCaption) {
    return documentCaption;
  }

  const buttons = record(message.buttonsResponseMessage);
  const selectedButton = string(buttons?.selectedDisplayText);

  if (selectedButton) {
    return selectedButton;
  }

  const list = record(message.listResponseMessage);
  const title = string(list?.title);

  if (title) {
    return title;
  }

  switch (messageType) {
    case "imageMessage":
      return "[Imagem]";
    case "audioMessage":
      return "[Áudio]";
    case "videoMessage":
      return "[Vídeo]";
    case "documentMessage":
      return "[Documento]";
    case "stickerMessage":
      return "[Sticker]";
    case "locationMessage":
      return "[Localização]";
    case "contactMessage":
    case "contactsArrayMessage":
      return "[Contato]";
    default:
      return undefined;
  }
}

function mapType(
  message: Record<string, unknown>,
  messageType: string | undefined
): ParsedEvolutionMessage["type"] {
  if (
    messageType === "conversation" ||
    messageType === "extendedTextMessage" ||
    message.conversation ||
    message.extendedTextMessage
  ) {
    return "TEXT";
  }

  if (messageType === "imageMessage" || message.imageMessage) {
    return "IMAGE";
  }

  if (messageType === "audioMessage" || message.audioMessage) {
    return "AUDIO";
  }

  if (messageType === "videoMessage" || message.videoMessage) {
    return "VIDEO";
  }

  if (messageType === "documentMessage" || message.documentMessage) {
    return "DOCUMENT";
  }

  if (messageType === "stickerMessage" || message.stickerMessage) {
    return "STICKER";
  }

  if (messageType === "locationMessage" || message.locationMessage) {
    return "LOCATION";
  }

  if (
    messageType === "contactMessage" ||
    messageType === "contactsArrayMessage" ||
    message.contactMessage ||
    message.contactsArrayMessage
  ) {
    return "CONTACT";
  }

  return "UNKNOWN";
}

function mediaInfo(
  message: Record<string, unknown>,
  type: ParsedEvolutionMessage["type"]
) {
  let media: Record<string, unknown> | undefined;

  switch (type) {
    case "IMAGE":
      media = record(message.imageMessage);
      break;
    case "AUDIO":
      media = record(message.audioMessage);
      break;
    case "VIDEO":
      media = record(message.videoMessage);
      break;
    case "DOCUMENT":
      media = record(message.documentMessage);
      break;
  }

  return {
    mediaMimeType: string(media?.mimetype),
    mediaFileName: string(media?.fileName)
  };
}

function quotedId(message: Record<string, unknown>) {
  const extended = record(message.extendedTextMessage);
  const context = record(extended?.contextInfo);

  return string(context?.stanzaId);
}

export function parseEvolutionMessage(
  payload: Record<string, unknown>
): ParsedEvolutionMessage | null {
  const data = record(payload.data);

  if (!data) {
    return null;
  }

  const key = record(data.key);
  const remoteJid = string(key?.remoteJid);
  const externalId = string(key?.id);

  if (!remoteJid || !externalId) {
    return null;
  }

  if (
    remoteJid === "status@broadcast" ||
    remoteJid.endsWith("@broadcast")
  ) {
    return null;
  }

  const message = record(data.message);

  if (!message) {
    return null;
  }

  const messageType = string(data.messageType);
  const type = mapType(message, messageType);
  const body = textFromMessage(message, messageType);

  // Ignore synchronization/protocol payloads that are not visible messages.
  if (type === "UNKNOWN" && !body) {
    return null;
  }

  const senderPn = string(key?.senderPn);
  const isGroup = remoteJid.endsWith("@g.us");
  const phoneNumber = isGroup
    ? undefined
    : numberFromJid(senderPn) ?? numberFromJid(remoteJid);

  const media = mediaInfo(message, type);

  return {
    externalId,
    remoteJid,
    phoneNumber,
    pushName: string(data.pushName),
    fromMe: key?.fromMe === true,
    isGroup,
    type,
    body,
    mediaMimeType: media.mediaMimeType,
    mediaFileName: media.mediaFileName,
    quotedExternalId: quotedId(message),
    timestamp: epochToDate(data.messageTimestamp),
    rawPayload: payload
  };
}
EOF

cat > apps/api/src/modules/messages/message-ingestion.service.ts <<'EOF'
import type { WhatsAppConnection } from "../../generated/prisma/client.js";
import { prisma } from "../../lib/database.js";
import {
  parseEvolutionMessage,
  type ParsedEvolutionMessage
} from "./evolution-message.parser.js";

function activeTicketKey(
  connectionId: string,
  contactId: string
) {
  return `${connectionId}:${contactId}`;
}

function displayName(message: ParsedEvolutionMessage) {
  if (message.isGroup) {
    return `Grupo ${message.remoteJid.split("@")[0]}`;
  }

  return (
    message.pushName ??
    message.phoneNumber ??
    message.remoteJid.split("@")[0] ??
    "Contato"
  );
}

function preview(message: ParsedEvolutionMessage) {
  return message.body ?? `[${message.type.toLowerCase()}]`;
}

export async function ingestEvolutionMessage(
  payload: Record<string, unknown>,
  connection: WhatsAppConnection
) {
  const parsed = parseEvolutionMessage(payload);

  if (!parsed) {
    return {
      ignored: true,
      reason: "unsupported_or_non_message"
    };
  }

  const existing = await prisma.message.findUnique({
    where: {
      whatsappConnectionId_externalId: {
        whatsappConnectionId: connection.id,
        externalId: parsed.externalId
      }
    }
  });

  if (existing) {
    return {
      ignored: true,
      reason: "duplicate",
      messageId: existing.id
    };
  }

  const contact = await prisma.contact.upsert({
    where: {
      companyId_remoteJid: {
        companyId: connection.companyId,
        remoteJid: parsed.remoteJid
      }
    },
    update: {
      ...(parsed.pushName && !parsed.isGroup
        ? { name: parsed.pushName }
        : {}),
      ...(parsed.phoneNumber
        ? { phoneNumber: parsed.phoneNumber }
        : {}),
      lastSeenAt: parsed.fromMe ? undefined : parsed.timestamp
    },
    create: {
      companyId: connection.companyId,
      remoteJid: parsed.remoteJid,
      phoneNumber: parsed.phoneNumber,
      name: displayName(parsed),
      isGroup: parsed.isGroup,
      lastSeenAt: parsed.fromMe ? undefined : parsed.timestamp
    }
  });

  const ticket = await prisma.ticket.upsert({
    where: {
      activeKey: activeTicketKey(connection.id, contact.id)
    },
    update: {},
    create: {
      companyId: connection.companyId,
      whatsappConnectionId: connection.id,
      contactId: contact.id,
      activeKey: activeTicketKey(connection.id, contact.id),
      status: "OPEN",
      lastMessageAt: parsed.timestamp
    }
  });

  const message = await prisma.message.create({
    data: {
      companyId: connection.companyId,
      ticketId: ticket.id,
      whatsappConnectionId: connection.id,
      externalId: parsed.externalId,
      direction: parsed.fromMe ? "OUTBOUND" : "INBOUND",
      type: parsed.type,
      body: parsed.body,
      mediaMimeType: parsed.mediaMimeType,
      mediaFileName: parsed.mediaFileName,
      quotedExternalId: parsed.quotedExternalId,
      timestamp: parsed.timestamp,
      rawPayload: parsed.rawPayload
    }
  });

  await prisma.ticket.update({
    where: {
      id: ticket.id
    },
    data: {
      lastMessage: preview(parsed),
      lastMessageAt: parsed.timestamp,
      ...(parsed.fromMe
        ? {}
        : {
            unreadCount: {
              increment: 1
            }
          })
    }
  });

  return {
    ignored: false,
    ticketId: ticket.id,
    contactId: contact.id,
    messageId: message.id
  };
}
EOF

# ---------------------------------------------------------------------------
# Ticket service and routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tickets/ticket.service.ts <<'EOF'
import { randomUUID } from "node:crypto";

import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";

function getObject(value: unknown) {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : undefined;
}

function getString(value: unknown) {
  return typeof value === "string" && value.length > 0
    ? value
    : undefined;
}

function sentExternalId(result: unknown) {
  const body = getObject(result);
  const key = getObject(body?.key);

  return getString(key?.id) ?? `wapp-local-${randomUUID()}`;
}

function sentTimestamp(result: unknown) {
  const body = getObject(result);
  const raw = body?.messageTimestamp;

  const seconds =
    typeof raw === "number"
      ? raw
      : typeof raw === "string"
        ? Number(raw)
        : NaN;

  return Number.isFinite(seconds)
    ? new Date(seconds * 1000)
    : new Date();
}

export async function listTickets(
  companyId: string,
  status: "OPEN" | "PENDING" | "CLOSED"
) {
  return prisma.ticket.findMany({
    where: {
      companyId,
      status
    },
    include: {
      contact: true,
      whatsappConnection: {
        select: {
          id: true,
          name: true,
          status: true,
          phoneNumber: true
        }
      },
      messages: {
        orderBy: {
          timestamp: "desc"
        },
        take: 1,
        select: {
          id: true,
          direction: true,
          type: true,
          body: true,
          timestamp: true
        }
      }
    },
    orderBy: {
      lastMessageAt: "desc"
    },
    take: 200
  });
}

export async function getTicket(
  companyId: string,
  ticketId: string
) {
  const ticket = await prisma.ticket.findFirst({
    where: {
      id: ticketId,
      companyId
    },
    include: {
      contact: true,
      whatsappConnection: true
    }
  });

  if (!ticket) {
    throw new AppError(
      "Atendimento não encontrado.",
      404,
      "TICKET_NOT_FOUND"
    );
  }

  return ticket;
}

export async function listTicketMessages(
  companyId: string,
  ticketId: string
) {
  await getTicket(companyId, ticketId);

  return prisma.message.findMany({
    where: {
      companyId,
      ticketId
    },
    orderBy: {
      timestamp: "asc"
    },
    take: 200
  });
}

export async function markTicketRead(
  companyId: string,
  ticketId: string
) {
  await getTicket(companyId, ticketId);

  return prisma.ticket.update({
    where: {
      id: ticketId
    },
    data: {
      unreadCount: 0
    }
  });
}

export async function closeTicket(
  companyId: string,
  ticketId: string
) {
  await getTicket(companyId, ticketId);

  return prisma.ticket.update({
    where: {
      id: ticketId
    },
    data: {
      status: "CLOSED",
      activeKey: null,
      unreadCount: 0,
      closedAt: new Date()
    }
  });
}

export async function sendTicketText(input: {
  companyId: string;
  ticketId: string;
  userId: string;
  text: string;
}) {
  const ticket = await getTicket(
    input.companyId,
    input.ticketId
  );

  if (ticket.status === "CLOSED") {
    throw new AppError(
      "Este atendimento já foi encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  if (ticket.whatsappConnection.status !== "CONNECTED") {
    throw new AppError(
      "A conexão WhatsApp deste atendimento está offline.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  const result = await evolutionWhatsAppClient.sendText({
    instanceName: ticket.whatsappConnection.instanceName,
    number: ticket.contact.remoteJid,
    text: input.text
  });

  const timestamp = sentTimestamp(result);
  const externalId = sentExternalId(result);

  const message = await prisma.message.upsert({
    where: {
      whatsappConnectionId_externalId: {
        whatsappConnectionId: ticket.whatsappConnectionId,
        externalId
      }
    },
    update: {},
    create: {
      companyId: input.companyId,
      ticketId: ticket.id,
      whatsappConnectionId: ticket.whatsappConnectionId,
      sentByUserId: input.userId,
      externalId,
      direction: "OUTBOUND",
      type: "TEXT",
      body: input.text,
      timestamp,
      rawPayload:
        result && typeof result === "object"
          ? (result as object)
          : undefined
    }
  });

  await prisma.ticket.update({
    where: {
      id: ticket.id
    },
    data: {
      lastMessage: input.text,
      lastMessageAt: timestamp
    }
  });

  return message;
}
EOF

cat > apps/api/src/modules/tickets/ticket.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../auth/auth.guard.js";
import {
  closeTicket,
  listTicketMessages,
  listTickets,
  markTicketRead,
  sendTicketText
} from "./ticket.service.js";

const ticketIdSchema = z.object({
  id: z.string().uuid()
});

const listSchema = z.object({
  status: z
    .enum(["OPEN", "PENDING", "CLOSED"])
    .default("OPEN")
});

const sendTextSchema = z.object({
  text: z.string().trim().min(1).max(4096)
});

export async function ticketRoutes(app: FastifyInstance) {
  app.get("/api/v1/tickets", async request => {
    const auth = await requireAuth(request);
    const query = listSchema.parse(request.query);

    return {
      tickets: await listTickets(auth.companyId, query.status)
    };
  });

  app.get(
    "/api/v1/tickets/:id/messages",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        messages: await listTicketMessages(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/read",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        ticket: await markTicketRead(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/close",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        ticket: await closeTicket(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/messages",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);
      const input = sendTextSchema.parse(request.body);

      return {
        message: await sendTicketText({
          companyId: auth.companyId,
          ticketId: params.id,
          userId: auth.userId,
          text: input.text
        })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Evolution webhook: persist messages
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/webhooks/evolution-webhook.routes.ts <<'EOF'
import { timingSafeEqual } from "node:crypto";

import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { ingestEvolutionMessage } from "../messages/message-ingestion.service.js";

const paramsSchema = z.object({
  secret: z.string().min(1)
});

function secretsMatch(received: string, expected: string) {
  const receivedBuffer = Buffer.from(received);
  const expectedBuffer = Buffer.from(expected);

  return (
    receivedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(receivedBuffer, expectedBuffer)
  );
}

function normalizeEvent(value: unknown) {
  return String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/[.\-\s]+/g, "_");
}

function getInstanceName(body: Record<string, unknown>) {
  if (typeof body.instance === "string") {
    return body.instance;
  }

  if (typeof body.instanceName === "string") {
    return body.instanceName;
  }

  const data = body.data;

  if (data && typeof data === "object") {
    const dataRecord = data as Record<string, unknown>;

    if (typeof dataRecord.instance === "string") {
      return dataRecord.instance;
    }

    if (typeof dataRecord.instanceName === "string") {
      return dataRecord.instanceName;
    }
  }

  return undefined;
}

function connectionState(body: Record<string, unknown>) {
  const data = body.data;

  if (!data || typeof data !== "object") {
    return undefined;
  }

  const record = data as Record<string, unknown>;

  if (typeof record.state === "string") {
    return record.state;
  }

  if (typeof record.status === "string") {
    return record.status;
  }

  return undefined;
}

function mapState(state: string | undefined) {
  switch (state?.toLowerCase()) {
    case "open":
    case "connected":
      return "CONNECTED" as const;
    case "connecting":
      return "CONNECTING" as const;
    case "close":
    case "closed":
    case "disconnected":
      return "DISCONNECTED" as const;
    default:
      return undefined;
  }
}

export async function evolutionWebhookRoutes(
  app: FastifyInstance
) {
  app.post(
    "/api/v1/webhooks/evolution/:secret",
    async (request, reply) => {
      const params = paramsSchema.parse(request.params);

      if (
        !secretsMatch(
          params.secret,
          env.EVOLUTION_WEBHOOK_SECRET
        )
      ) {
        throw new AppError(
          "Webhook não autorizado.",
          401,
          "WEBHOOK_UNAUTHORIZED"
        );
      }

      if (!request.body || typeof request.body !== "object") {
        return reply.status(204).send();
      }

      const body = request.body as Record<string, unknown>;
      const event = normalizeEvent(body.event);
      const instance = getInstanceName(body);

      if (!instance) {
        request.log.warn(
          { event },
          "Evolution webhook without instance name"
        );

        return reply.status(204).send();
      }

      const connection = await prisma.whatsAppConnection.findUnique({
        where: {
          instanceName: instance
        }
      });

      if (!connection) {
        request.log.warn(
          { event, instance },
          "Evolution webhook for unknown instance"
        );

        return reply.status(204).send();
      }

      if (event === "CONNECTION_UPDATE") {
        const mappedState = mapState(connectionState(body));

        if (mappedState) {
          const data =
            body.data && typeof body.data === "object"
              ? (body.data as Record<string, unknown>)
              : {};

          const owner =
            typeof data.wuid === "string"
              ? data.wuid
              : typeof data.number === "string"
                ? data.number
                : undefined;

          await prisma.whatsAppConnection.update({
            where: {
              id: connection.id
            },
            data: {
              status: mappedState,
              phoneNumber: owner?.replace(/\D/g, "") || undefined,
              lastError: null,
              lastEventAt: new Date()
            }
          });
        }
      } else if (event === "MESSAGES_UPSERT") {
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
        );
      } else {
        await prisma.whatsAppConnection.update({
          where: {
            id: connection.id
          },
          data: {
            lastEventAt: new Date()
          }
        });
      }

      return {
        received: true
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register ticket routes in API
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8");

const importLine =
  'import { ticketRoutes } from "./modules/tickets/ticket.routes.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { whatsappRoutes } from "./modules/whatsapp/whatsapp.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error("whatsappRoutes import anchor not found.");
  }

  content = content.replace(
    anchor,
    `${anchor}\n${importLine}`
  );
}

if (!content.includes("await app.register(ticketRoutes);")) {
  const anchor = "await app.register(whatsappRoutes);";

  if (!content.includes(anchor)) {
    throw new Error("whatsappRoutes register anchor not found.");
  }

  content = content.replace(
    anchor,
    `${anchor}\n  await app.register(ticketRoutes);`
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Conversations UI
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/conversations/page.tsx <<'EOF'
"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

interface Contact {
  id: string;
  name: string;
  remoteJid: string;
  phoneNumber: string | null;
  isGroup: boolean;
}

interface Connection {
  id: string;
  name: string;
  status: string;
  phoneNumber: string | null;
}

interface TicketMessagePreview {
  id: string;
  direction: "INBOUND" | "OUTBOUND";
  type: MessageType;
  body: string | null;
  timestamp: string;
}

interface Ticket {
  id: string;
  status: "OPEN" | "PENDING" | "CLOSED";
  unreadCount: number;
  lastMessage: string | null;
  lastMessageAt: string;
  contact: Contact;
  whatsappConnection: Connection;
  messages: TicketMessagePreview[];
}

type MessageType =
  | "TEXT"
  | "IMAGE"
  | "AUDIO"
  | "VIDEO"
  | "DOCUMENT"
  | "STICKER"
  | "LOCATION"
  | "CONTACT"
  | "UNKNOWN";

interface Message {
  id: string;
  externalId: string;
  direction: "INBOUND" | "OUTBOUND";
  type: MessageType;
  body: string | null;
  mediaMimeType: string | null;
  mediaFileName: string | null;
  timestamp: string;
  sentByUserId: string | null;
}

interface TicketsResponse {
  tickets: Ticket[];
}

interface MessagesResponse {
  messages: Message[];
}

function messageFallback(type: MessageType) {
  const labels: Record<MessageType, string> = {
    TEXT: "Mensagem",
    IMAGE: "Imagem",
    AUDIO: "Áudio",
    VIDEO: "Vídeo",
    DOCUMENT: "Documento",
    STICKER: "Sticker",
    LOCATION: "Localização",
    CONTACT: "Contato",
    UNKNOWN: "Mensagem"
  };

  return `[${labels[type]}]`;
}

function ticketPreview(ticket: Ticket) {
  return (
    ticket.lastMessage ??
    ticket.messages[0]?.body ??
    (ticket.messages[0]
      ? messageFallback(ticket.messages[0].type)
      : "Nova conversa")
  );
}

function timeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

export default function ConversationsPage() {
  const router = useRouter();
  const { session, loading, request } = useAuth();

  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [closing, setClosing] = useState(false);
  const [error, setError] = useState("");
  const bottomRef = useRef<HTMLDivElement | null>(null);

  const selectedTicket = useMemo(
    () => tickets.find(ticket => ticket.id === selectedId) ?? null,
    [selectedId, tickets]
  );

  const loadTickets = useCallback(async () => {
    const payload = await request<TicketsResponse>(
      "/api/v1/tickets?status=OPEN"
    );

    setTickets(payload.tickets);

    setSelectedId(current => {
      if (
        current &&
        payload.tickets.some(ticket => ticket.id === current)
      ) {
        return current;
      }

      return payload.tickets[0]?.id ?? null;
    });
  }, [request]);

  const loadMessages = useCallback(
    async (ticketId: string) => {
      const payload = await request<MessagesResponse>(
        `/api/v1/tickets/${ticketId}/messages`
      );

      setMessages(payload.messages);

      await request(`/api/v1/tickets/${ticketId}/read`, {
        method: "POST"
      });
    },
    [request]
  );

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void loadTickets().catch(() => {
        setError("Não foi possível carregar os atendimentos.");
      });
    }
  }, [loading, loadTickets, router, session]);

  useEffect(() => {
    if (!selectedId) {
      setMessages([]);
      return;
    }

    void loadMessages(selectedId).catch(() => {
      setError("Não foi possível carregar as mensagens.");
    });
  }, [loadMessages, selectedId]);

  useEffect(() => {
    if (!session) {
      return;
    }

    const timer = window.setInterval(() => {
      void loadTickets();

      if (selectedId) {
        void loadMessages(selectedId);
      }
    }, 3000);

    return () => window.clearInterval(timer);
  }, [loadMessages, loadTickets, selectedId, session]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({
      behavior: "smooth",
      block: "end"
    });
  }, [messages]);

  async function handleSend(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!selectedId || !text.trim()) {
      return;
    }

    setSending(true);
    setError("");

    try {
      await request(`/api/v1/tickets/${selectedId}/messages`, {
        method: "POST",
        body: JSON.stringify({
          text: text.trim()
        })
      });

      setText("");
      await Promise.all([
        loadMessages(selectedId),
        loadTickets()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível enviar a mensagem."
      );
    } finally {
      setSending(false);
    }
  }

  async function handleClose() {
    if (!selectedId) {
      return;
    }

    setClosing(true);

    try {
      await request(`/api/v1/tickets/${selectedId}/close`, {
        method: "POST"
      });

      setMessages([]);
      setSelectedId(null);
      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível encerrar o atendimento."
      );
    } finally {
      setClosing(false);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando conversas…</main>;
  }

  return (
    <main className="inbox-screen">
      <header className="inbox-topbar">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">Atendimento</span>
          <h1>Conversas</h1>
        </div>

        <div className="inbox-topbar__right">
          <span>{session.company.name}</span>
          <button
            className="ghost-button"
            onClick={() => router.push("/dashboard/connections")}
            type="button"
          >
            Conexões
          </button>
        </div>
      </header>

      {error && <div className="inbox-error">{error}</div>}

      <section className="inbox">
        <aside className="ticket-list">
          <div className="ticket-list__heading">
            <strong>Em atendimento</strong>
            <span>{tickets.length}</span>
          </div>

          <div className="ticket-list__items">
            {tickets.length === 0 ? (
              <div className="ticket-list__empty">
                <strong>Nenhuma conversa aberta.</strong>
                <p>
                  Envie uma mensagem para o número conectado no WhatsApp.
                </p>
              </div>
            ) : (
              tickets.map(ticket => (
                <button
                  className={
                    ticket.id === selectedId
                      ? "ticket-item ticket-item--active"
                      : "ticket-item"
                  }
                  key={ticket.id}
                  onClick={() => setSelectedId(ticket.id)}
                  type="button"
                >
                  <div className="ticket-avatar">
                    {ticket.contact.name.slice(0, 1).toUpperCase()}
                  </div>

                  <div className="ticket-item__body">
                    <div className="ticket-item__row">
                      <strong>{ticket.contact.name}</strong>
                      <time>{timeLabel(ticket.lastMessageAt)}</time>
                    </div>

                    <div className="ticket-item__row">
                      <span className="ticket-item__preview">
                        {ticketPreview(ticket)}
                      </span>

                      {ticket.unreadCount > 0 && (
                        <span className="unread-badge">
                          {ticket.unreadCount}
                        </span>
                      )}
                    </div>

                    <small>{ticket.whatsappConnection.name}</small>
                  </div>
                </button>
              ))
            )}
          </div>
        </aside>

        <section className="chat-panel">
          {!selectedTicket ? (
            <div className="chat-empty">
              <div className="chat-empty__mark">W</div>
              <strong>Suas conversas vão aparecer aqui.</strong>
              <p>
                A primeira mensagem recebida já cria contato, atendimento e
                histórico automaticamente.
              </p>
            </div>
          ) : (
            <>
              <header className="chat-header">
                <div className="chat-header__contact">
                  <div className="ticket-avatar">
                    {selectedTicket.contact.name.slice(0, 1).toUpperCase()}
                  </div>
                  <div>
                    <strong>{selectedTicket.contact.name}</strong>
                    <span>
                      {selectedTicket.contact.phoneNumber ??
                        selectedTicket.contact.remoteJid}
                    </span>
                  </div>
                </div>

                <div className="chat-header__actions">
                  <span className="connection-status connection-status--connected">
                    {selectedTicket.whatsappConnection.name}
                  </span>
                  <button
                    className="ghost-button"
                    disabled={closing}
                    onClick={handleClose}
                    type="button"
                  >
                    {closing ? "Encerrando…" : "Encerrar"}
                  </button>
                </div>
              </header>

              <div className="message-list">
                {messages.map(message => (
                  <div
                    className={
                      message.direction === "OUTBOUND"
                        ? "message-row message-row--out"
                        : "message-row message-row--in"
                    }
                    key={message.id}
                  >
                    <article className="message-bubble">
                      {message.type !== "TEXT" && (
                        <span className="message-kind">
                          {messageFallback(message.type)}
                        </span>
                      )}

                      <p>
                        {message.body ?? messageFallback(message.type)}
                      </p>

                      {message.mediaFileName && (
                        <small className="message-file">
                          {message.mediaFileName}
                        </small>
                      )}

                      <time>{dateTimeLabel(message.timestamp)}</time>
                    </article>
                  </div>
                ))}
                <div ref={bottomRef} />
              </div>

              <form className="composer" onSubmit={handleSend}>
                <textarea
                  maxLength={4096}
                  onChange={event => setText(event.target.value)}
                  onKeyDown={event => {
                    if (
                      event.key === "Enter" &&
                      !event.shiftKey
                    ) {
                      event.preventDefault();
                      event.currentTarget.form?.requestSubmit();
                    }
                  }}
                  placeholder="Digite uma mensagem…"
                  rows={1}
                  value={text}
                />
                <button
                  className="composer__send"
                  disabled={sending || !text.trim()}
                  type="submit"
                >
                  {sending ? "…" : "→"}
                </button>
              </form>
            </>
          )}
        </section>
      </section>
    </main>
  );
}
EOF

cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P0.6 / Inbox -------------------------------------------------- */

.inbox-screen {
  min-height: 100vh;
  background: var(--background);
  padding: 28px clamp(18px, 4vw, 54px) 42px;
}

.inbox-topbar {
  display: flex;
  max-width: 1480px;
  align-items: flex-end;
  justify-content: space-between;
  gap: 30px;
  margin: 0 auto 22px;
}

.inbox-topbar .connections-back {
  margin-bottom: 20px;
}

.inbox-topbar h1 {
  margin: 7px 0 0;
  font-size: 44px;
  font-weight: 640;
  letter-spacing: -0.05em;
}

.inbox-topbar__right {
  display: flex;
  align-items: center;
  gap: 12px;
  color: var(--muted);
  font-size: 12px;
}

.inbox-error {
  max-width: 1480px;
  margin: 0 auto 12px;
  border: 1px solid #eccdcd;
  border-radius: 10px;
  background: var(--danger-soft);
  color: var(--danger);
  padding: 10px 14px;
  font-size: 12px;
}

.inbox {
  display: grid;
  max-width: 1480px;
  height: calc(100vh - 160px);
  min-height: 620px;
  grid-template-columns: minmax(300px, 360px) 1fr;
  overflow: hidden;
  margin: 0 auto;
  border: 1px solid var(--line);
  border-radius: 20px;
  background: white;
  box-shadow: 0 18px 60px rgba(24, 33, 27, 0.045);
}

.ticket-list {
  min-width: 0;
  border-right: 1px solid var(--line);
  background: #fbfcfa;
}

.ticket-list__heading {
  display: flex;
  height: 66px;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--line);
  padding: 0 20px;
}

.ticket-list__heading strong {
  font-size: 13px;
}

.ticket-list__heading span {
  display: grid;
  min-width: 26px;
  height: 26px;
  place-items: center;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 10px;
  font-weight: 800;
}

.ticket-list__items {
  height: calc(100% - 66px);
  overflow-y: auto;
}

.ticket-list__empty {
  padding: 44px 24px;
  text-align: center;
}

.ticket-list__empty strong {
  font-size: 13px;
}

.ticket-list__empty p {
  margin: 8px 0 0;
  color: var(--muted);
  font-size: 11px;
  line-height: 1.55;
}

.ticket-item {
  display: flex;
  width: 100%;
  gap: 11px;
  border: 0;
  border-bottom: 1px solid #edf0ed;
  background: transparent;
  padding: 15px 16px;
  text-align: left;
}

.ticket-item:hover {
  background: #f5f7f4;
}

.ticket-item--active {
  background: #eef4ef;
}

.ticket-avatar {
  display: grid;
  width: 40px;
  height: 40px;
  flex: 0 0 40px;
  place-items: center;
  border-radius: 13px;
  background: #dcebe1;
  color: #245f42;
  font-size: 13px;
  font-weight: 800;
}

.ticket-item__body {
  min-width: 0;
  flex: 1;
}

.ticket-item__row {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.ticket-item__row strong {
  overflow: hidden;
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ticket-item__row time {
  flex: 0 0 auto;
  color: #9aa19c;
  font-size: 9px;
}

.ticket-item__preview {
  overflow: hidden;
  color: var(--muted);
  font-size: 10px;
  line-height: 1.7;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ticket-item__body small {
  display: block;
  margin-top: 4px;
  color: #a1a8a3;
  font-size: 9px;
}

.unread-badge {
  display: grid;
  min-width: 20px;
  height: 20px;
  flex: 0 0 auto;
  place-items: center;
  border-radius: 999px;
  background: var(--accent);
  color: white;
  padding: 0 6px;
  font-size: 9px;
  font-weight: 800;
}

.chat-panel {
  display: grid;
  min-width: 0;
  grid-template-rows: 66px minmax(0, 1fr) auto;
  background:
    linear-gradient(rgba(247, 248, 245, 0.91), rgba(247, 248, 245, 0.91)),
    radial-gradient(circle at 30% 40%, #dce3dd 1px, transparent 1px);
  background-size: auto, 20px 20px;
}

.chat-empty {
  display: grid;
  grid-row: 1 / -1;
  max-width: 400px;
  place-self: center;
  place-items: center;
  padding: 30px;
  text-align: center;
}

.chat-empty__mark {
  display: grid;
  width: 58px;
  height: 58px;
  place-items: center;
  margin-bottom: 20px;
  border-radius: 18px;
  background: var(--sidebar);
  color: white;
  font-size: 22px;
  font-weight: 800;
}

.chat-empty strong {
  font-size: 16px;
}

.chat-empty p {
  margin: 9px 0 0;
  color: var(--muted);
  font-size: 11px;
  line-height: 1.6;
}

.chat-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  border-bottom: 1px solid var(--line);
  background: rgba(255, 255, 255, 0.94);
  padding: 0 18px;
}

.chat-header__contact {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.chat-header__contact > div:last-child {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.chat-header__contact strong {
  overflow: hidden;
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.chat-header__contact span {
  overflow: hidden;
  color: var(--muted);
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.chat-header__actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.message-list {
  min-height: 0;
  overflow-y: auto;
  padding: 26px clamp(20px, 5vw, 70px);
}

.message-row {
  display: flex;
  margin: 7px 0;
}

.message-row--in {
  justify-content: flex-start;
}

.message-row--out {
  justify-content: flex-end;
}

.message-bubble {
  width: fit-content;
  max-width: min(620px, 76%);
  border: 1px solid var(--line);
  border-radius: 6px 16px 16px 16px;
  background: white;
  box-shadow: 0 4px 12px rgba(22, 32, 25, 0.025);
  padding: 10px 12px 7px;
}

.message-row--out .message-bubble {
  border-color: #cfe3d6;
  border-radius: 16px 6px 16px 16px;
  background: #e5f2e9;
}

.message-kind {
  display: block;
  margin-bottom: 5px;
  color: var(--accent-dark);
  font-size: 9px;
  font-weight: 800;
  text-transform: uppercase;
}

.message-bubble p {
  margin: 0;
  white-space: pre-wrap;
  font-size: 12px;
  line-height: 1.55;
  word-break: break-word;
}

.message-bubble time {
  display: block;
  margin-top: 5px;
  color: #909892;
  font-size: 8px;
  text-align: right;
}

.message-file {
  display: block;
  margin-top: 6px;
  color: var(--muted);
  font-size: 9px;
}

.composer {
  display: grid;
  grid-template-columns: 1fr 46px;
  gap: 10px;
  border-top: 1px solid var(--line);
  background: white;
  padding: 13px 16px;
}

.composer textarea {
  min-height: 46px;
  max-height: 140px;
  resize: none;
  border: 1px solid var(--line);
  border-radius: 13px;
  outline: none;
  background: var(--surface-subtle);
  padding: 13px 14px;
  font-size: 12px;
  line-height: 1.5;
}

.composer textarea:focus {
  border-color: var(--accent);
  background: white;
}

.composer__send {
  width: 46px;
  height: 46px;
  align-self: end;
  border: 0;
  border-radius: 13px;
  background: var(--sidebar);
  color: white;
  font-size: 20px;
}

.composer__send:disabled {
  opacity: 0.35;
}

@media (max-width: 820px) {
  .inbox-screen {
    padding: 18px 12px;
  }

  .inbox-topbar {
    align-items: flex-start;
    flex-direction: column;
  }

  .inbox {
    height: calc(100vh - 190px);
    grid-template-columns: 130px 1fr;
  }

  .ticket-item {
    padding: 12px 9px;
  }

  .ticket-avatar {
    width: 34px;
    height: 34px;
    flex-basis: 34px;
  }

  .ticket-item__body small,
  .ticket-item__preview,
  .ticket-item__row time {
    display: none;
  }

  .ticket-item__row {
    display: block;
  }

  .message-list {
    padding: 18px 12px;
  }

  .message-bubble {
    max-width: 88%;
  }

  .chat-header__actions .connection-status {
    display: none;
  }
}
EOF

# ---------------------------------------------------------------------------
# Make dashboard navigation functional
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/web/app/dashboard/page.tsx";
let content = fs.readFileSync(path, "utf8");

const oldButton = `              <button
                className={index === 0 ? "nav-item nav-item--active" : "nav-item"}
                key={item}
                type="button"
              >`;

const newButton = `              <button
                className={index === 0 ? "nav-item nav-item--active" : "nav-item"}
                key={item}
                onClick={() => {
                  if (item === "Conversas") {
                    router.push("/dashboard/conversations");
                  }

                  if (item === "Conexões") {
                    router.push("/dashboard/connections");
                  }
                }}
                type="button"
              >`;

if (content.includes(oldButton)) {
  content = content.replace(oldButton, newButton);
} else if (!content.includes('router.push("/dashboard/conversations")')) {
  console.warn(
    "[P0.6] Dashboard nav snippet changed; Conversations page is still available by URL."
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/CONVERSATIONS.md <<'EOF'
# Conversations domain

P0.6 introduces the first operational Wapp domain.

```text
Evolution MESSAGES_UPSERT
          |
          v
       Contact
          |
          v
        Ticket
          |
          v
       Message
```

## Contact

A contact is unique by `companyId + remoteJid`.

The same contact can have multiple tickets over time.

## Ticket

Only one active ticket may exist for the same WhatsApp connection and contact.

This is guaranteed by the nullable unique `activeKey`:

```text
<whatsappConnectionId>:<contactId>
```

When the ticket is closed, `activeKey` becomes `NULL`. A later inbound message
can therefore create a new ticket.

## Message

Messages are deduplicated with:

```text
whatsappConnectionId + externalId
```

This protects the application from webhook retries.

P0.6 persists:

- text
- captions for common media messages
- media type
- MIME type when Evolution supplies it
- file name when Evolution supplies it
- raw webhook payload

Actual media download/storage is intentionally deferred to the next media
milestone.

## Realtime

The first inbox polls the API every 3 seconds. This is intentional for the
vertical slice.

After the domain is proven, polling will be replaced by realtime events without
changing the Contact/Ticket/Message model.
EOF

echo "[P0.6] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P0.6] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.6] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.6] Code generated successfully."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name conversations"
echo "  pnpm dev"
echo
echo "Open:"
echo "  http://localhost:3000/dashboard/conversations"
echo
echo "Then send a WhatsApp message TO the connected number."
