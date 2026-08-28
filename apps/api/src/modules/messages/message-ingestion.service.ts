import type { WhatsAppConnection } from "../../generated/prisma/client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import {
  scheduleAutomationEvaluation
} from "../../jobs/automation.dispatch.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import { recordTicketEvent } from "../tickets/ticket-event.service.js";
import { scheduleMessageMediaCapture } from "../media/media-capture.service.js";
import {
  parseEvolutionMessage,
  type ParsedEvolutionMessage
} from "./evolution-message.parser.js";
import {
  canUsePushName,
  contactCreationName,
  shouldPromoteWhatsappName
} from "./contact-identity.js";

function activeTicketKey(
  connectionId: string,
  contactId: string
) {
  return `${connectionId}:${contactId}`;
}

function displayName(
  message:
    ParsedEvolutionMessage
) {
  return contactCreationName({
    fromMe:
      message.fromMe,
    isGroup:
      message.isGroup,
    pushName:
      message.pushName,
    phoneNumber:
      message.phoneNumber,
    remoteJid:
      message.remoteJid
  });
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

  const existingContact =
    await prisma.contact.findUnique({
      where: {
        companyId_remoteJid: {
          companyId:
            connection.companyId,
          remoteJid:
            parsed.remoteJid
        }
      },
      select: {
        name: true,
        whatsappName:
          true,
        phoneNumber:
          true,
        remoteJid:
          true
      }
    });

  const validPushName =
    canUsePushName({
      fromMe:
        parsed.fromMe,
      isGroup:
        parsed.isGroup,
      pushName:
        parsed.pushName
    });

  const promoteWhatsappName =
    Boolean(
      validPushName &&
      parsed.pushName &&
      existingContact &&
      shouldPromoteWhatsappName({
        currentName:
          existingContact.name,
        currentWhatsappName:
          existingContact
            .whatsappName,
        remoteJid:
          existingContact
            .remoteJid,
        phoneNumber:
          existingContact
            .phoneNumber,
        incomingPushName:
          parsed.pushName
      })
    );

  const contact = await prisma.contact.upsert({
    where: {
      companyId_remoteJid: {
        companyId: connection.companyId,
        remoteJid: parsed.remoteJid
      }
    },
    update: {
      ...(validPushName
        ? {
            whatsappName:
              parsed.pushName,
            ...(promoteWhatsappName
              ? {
                  name:
                    parsed.pushName
                }
              : {})
          }
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
      whatsappName:
        canUsePushName({
          fromMe:
            parsed.fromMe,
          isGroup:
            parsed.isGroup,
          pushName:
            parsed.pushName
        })
          ? parsed.pushName
          : undefined,
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
      lastMessageAt: parsed.timestamp,
      ...(parsed.fromMe
        ? {
            lastOutboundAt:
              parsed.timestamp
          }
        : {
            firstInboundAt:
              parsed.timestamp,
            lastInboundAt:
              parsed.timestamp,
            waitingSince:
              parsed.timestamp
          })
    }
  });

  const hasMedia = [
    "IMAGE",
    "AUDIO",
    "VIDEO",
    "DOCUMENT",
    "STICKER"
  ].includes(parsed.type);

  const message = await prisma.message.create({
    data: {
      companyId: connection.companyId,
      ticketId: ticket.id,
      whatsappConnectionId: connection.id,
      externalId: parsed.externalId,
      direction: parsed.fromMe ? "OUTBOUND" : "INBOUND",
      type: parsed.type,
      body: parsed.body,
      mediaStatus: hasMedia
        ? "PENDING"
        : "NONE",
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
        ? {
            lastOutboundAt:
              parsed.timestamp,
            waitingSince:
              null,
            ...(ticket.firstInboundAt &&
            !ticket.firstResponseAt
              ? {
                  firstResponseAt:
                    parsed.timestamp
                }
              : {})
          }
        : {
            firstInboundAt:
              ticket.firstInboundAt ??
              parsed.timestamp,
            lastInboundAt:
              parsed.timestamp,
            waitingSince:
              parsed.timestamp,
            unreadCount: {
              increment: 1
            }
          })
    }
  });

  if (!before) {
    await recordTicketEvent({
      companyId:
        connection.companyId,
      ticketId:
        ticket.id,
      type: "CREATED",
      metadata: {
        source: "WHATSAPP",
        initialDirection:
          parsed.fromMe
            ? "OUTBOUND"
            : "INBOUND"
      }
    });

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

  if (hasMedia) {
    scheduleMessageMediaCapture(
      message.id
    );
  }

  if (!parsed.fromMe) {
    if (!before) {
      scheduleAutomationEvaluation({
        companyId:
          connection.companyId,
        ticketId:
          ticket.id,
        sourceMessageId:
          message.id,
        trigger:
          "TICKET_CREATED"
      });
    }

    scheduleAutomationEvaluation({
      companyId:
        connection.companyId,
      ticketId:
        ticket.id,
      sourceMessageId:
        message.id,
      trigger:
        "INBOUND_MESSAGE"
    });
  }

  return {
    ignored: false,
    ticketId: ticket.id,
    contactId: contact.id,
    messageId: message.id
  };
}
