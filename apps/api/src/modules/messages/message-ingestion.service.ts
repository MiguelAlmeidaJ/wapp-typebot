import type { WhatsAppConnection } from "../../generated/prisma/client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
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

  if (parsed.isGroup && !connection.acceptGroups) {
    return {
      ignored: true,
      reason: "groups_disabled_for_connection"
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

  const key = activeTicketKey(connection.id, contact.id);
  const before = await prisma.ticket.findUnique({
    where: {
      activeKey: key
    },
    select: {
      id: true
    }
  });

  const ticket = await prisma.ticket.upsert({
    where: {
      activeKey: key
    },
    update: {},
    create: {
      companyId: connection.companyId,
      whatsappConnectionId: connection.id,
      contactId: contact.id,
      queueId: connection.defaultQueueId,
      activeKey: key,
      status: parsed.fromMe ? "OPEN" : "PENDING",
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
      rawPayload: toPrismaJson(parsed.rawPayload)
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

  if (!before) {
    publishRealtime(connection.companyId, {
      type: "ticket.created",
      ticketId: ticket.id
    });
  }

  publishRealtime(connection.companyId, {
    type: "message.created",
    ticketId: ticket.id,
    messageId: message.id
  });

  return {
    ignored: false,
    ticketId: ticket.id,
    contactId: contact.id,
    messageId: message.id
  };
}
