import { randomUUID } from "node:crypto";

import { AppError } from "../../errors/app-error.js";
import type { Prisma } from "../../generated/prisma/client.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import type { WappRole } from "../../lib/tokens.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import {
  notifyTicketAssignment
} from "../notifications/notification.service.js";
import { recordTicketEvent } from "./ticket-event.service.js";
import { storeMedia } from "../media/media-storage.js";
import { persistReaction } from "../messages/message-reaction.service.js";
import { finishChatbotSessionForTicket } from "../chatbots/chatbot.service.js";

export type TicketListStatus =
  | "ACTIVE"
  | "OPEN"
  | "PENDING"
  | "CLOSED";

export interface TicketListFilters {
  q?: string;
  queueId?:
    | string
    | "NONE";
  assigneeId?:
    | string
    | "ME"
    | "NONE";
  actorMembershipId?: string;
  unreadOnly?: boolean;
  tagId?: string;
  conversationType?:
    | "ALL"
    | "DIRECT"
    | "GROUP";
}

const ticketInclude = {
  contact: true,
  whatsappConnection: {
    select: {
      id: true,
      name: true,
      status: true,
      phoneNumber: true
    }
  },
  queue: {
    select: {
      id: true,
      name: true
    }
  },
  assignedMembership: {
    include: {
      user: {
        select: {
          id: true,
          name: true,
          email: true
        }
      }
    }
  },
  tags: {
    include: {
      tag: true
    },
    orderBy: {
      createdAt: "asc"
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
} satisfies Prisma.TicketInclude;

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

function outboundSlaUpdate(
  ticket: {
    firstInboundAt: Date | null;
    firstResponseAt: Date | null;
  },
  timestamp: Date
) {
  return {
    lastOutboundAt: timestamp,
    waitingSince: null,
    ...(ticket.firstInboundAt &&
    !ticket.firstResponseAt
      ? {
          firstResponseAt:
            timestamp
        }
      : {})
  };
}

function canOverrideAssignment(role: WappRole) {
  return role === "OWNER" || role === "ADMIN" || role === "SUPERVISOR";
}

function assertCanOperateTicket(
  assignedMembershipId: string | null,
  actorMembershipId: string,
  role: WappRole
) {
  if (
    assignedMembershipId &&
    assignedMembershipId !== actorMembershipId &&
    !canOverrideAssignment(role)
  ) {
    throw new AppError(
      "Este atendimento está atribuído a outro atendente.",
      403,
      "TICKET_ASSIGNED_TO_ANOTHER_AGENT"
    );
  }
}

export async function listTickets(
  companyId: string,
  status: TicketListStatus,
  filters:
    TicketListFilters = {}
) {
  const q =
    filters.q
      ?.trim()
      .slice(
        0,
        120
      );

  const assigneeId =
    filters.assigneeId ===
      "ME"
      ? filters
          .actorMembershipId
      : filters.assigneeId ===
          "NONE"
        ? null
        : filters
            .assigneeId;

  const where:
    Prisma.TicketWhereInput = {
    companyId,
    ...(status === "ACTIVE"
      ? {
          status: {
            in: [
              "OPEN",
              "PENDING"
            ]
          }
        }
      : {
          status
        }),
    ...(q
      ? {
          OR: [
            {
              contact: {
                name: {
                  contains:
                    q
                }
              }
            },
            {
              contact: {
                whatsappName: {
                  contains:
                    q
                }
              }
            },
            {
              contact: {
                phoneNumber: {
                  contains:
                    q
                }
              }
            },
            {
              contact: {
                remoteJid: {
                  contains:
                    q
                }
              }
            },
            {
              lastMessage: {
                contains:
                  q
              }
            }
          ]
        }
      : {}),
    ...(filters.queueId
      ? filters.queueId ===
          "NONE"
        ? {
            queueId:
              null
          }
        : {
            queueId:
              filters.queueId
          }
      : {}),
    ...(filters.assigneeId
      ? {
          assignedMembershipId:
            assigneeId
        }
      : {}),
    ...(filters.unreadOnly
      ? {
          unreadCount: {
            gt: 0
          }
        }
      : {}),
    ...(filters.tagId
      ? {
          tags: {
            some: {
              tagId:
                filters.tagId
            }
          }
        }
      : {}),
    ...(filters.conversationType ===
      "DIRECT"
      ? {
          contact: {
            isGroup:
              false
          }
        }
      : filters.conversationType ===
          "GROUP"
        ? {
            contact: {
              isGroup:
                true
            }
          }
        : {})
  };

  return prisma.ticket.findMany({
    where,
    include:
      ticketInclude,
    orderBy: [
      {
        unreadCount:
          "desc"
      },
      {
        lastMessageAt:
          "desc"
      }
    ],
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
      whatsappConnection: true,
      queue: true,
      assignedMembership: {
        include: {
          user: true
        }
      }
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

async function validateMembership(
  companyId: string,
  membershipId: string
) {
  const membership = await prisma.companyMembership.findFirst({
    where: {
      id: membershipId,
      companyId,
      isActive: true,
      user: {
        isActive: true
      }
    }
  });

  if (!membership) {
    throw new AppError(
      "Atendente não encontrado na empresa ativa.",
      422,
      "INVALID_ASSIGNEE"
    );
  }

  return membership;
}

async function validateQueue(
  companyId: string,
  queueId: string
) {
  const queue = await prisma.queue.findFirst({
    where: {
      id: queueId,
      companyId,
      isActive: true
    }
  });

  if (!queue) {
    throw new AppError(
      "Fila não encontrada.",
      422,
      "INVALID_QUEUE"
    );
  }

  return queue;
}

async function validateQueueMembership(
  queueId: string,
  membershipId: string,
  allowOverride = false
) {
  const membersCount = await prisma.queueMember.count({
    where: { queueId }
  });

  if (membersCount === 0 || allowOverride) {
    return;
  }

  const link = await prisma.queueMember.findUnique({
    where: {
      queueId_membershipId: {
        queueId,
        membershipId
      }
    }
  });

  if (!link) {
    throw new AppError(
      "Você não pertence à fila deste atendimento.",
      403,
      "AGENT_NOT_IN_QUEUE"
    );
  }
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
    where: { id: ticketId },
    data: { unreadCount: 0 }
  });
}

export async function claimTicket(input: {
  companyId: string;
  ticketId: string;
  membershipId: string;
  role: WappRole;
}) {
  const ticket = await getTicket(input.companyId, input.ticketId);

  if (ticket.status === "CLOSED") {
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

  await validateMembership(input.companyId, input.membershipId);

  if (ticket.queueId) {
    await validateQueueMembership(
      ticket.queueId,
      input.membershipId,
      canOverrideAssignment(input.role)
    );
  }

  const updated = await prisma.ticket.update({
    where: { id: ticket.id },
    data: {
      assignedMembershipId: input.membershipId,
      status: "OPEN"
    },
    include: ticketInclude
  });

  await finishChatbotSessionForTicket(ticket.id, "HUMAN_TAKEOVER");

  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      updated.id,
    actorMembershipId:
      input.membershipId,
    type: "CLAIMED",
    metadata: {
      assignedMembershipId:
        updated.assignedMembershipId,
      assigneeName:
        updated.assignedMembership?.user.name ??
        null
    }
  });

  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: ticket.id
  });

  return updated;
}

export async function transferTicket(input: {
  companyId: string;
  ticketId: string;
  actorMembershipId: string;
  role: WappRole;
  queueId?: string | null;
  membershipId?: string | null;
}) {
  const ticket = await getTicket(input.companyId, input.ticketId);

  if (ticket.status === "CLOSED") {
    throw new AppError(
      "Este atendimento já foi encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.actorMembershipId,
    input.role
  );

  const queueId =
    input.queueId === undefined ? ticket.queueId : input.queueId;
  const membershipId =
    input.membershipId === undefined
      ? ticket.assignedMembershipId
      : input.membershipId;

  if (queueId) {
    await validateQueue(input.companyId, queueId);
  }

  if (membershipId) {
    await validateMembership(input.companyId, membershipId);

    if (queueId) {
      const configuredMembers = await prisma.queueMember.count({
        where: { queueId }
      });

      if (configuredMembers > 0) {
        const link = await prisma.queueMember.findUnique({
          where: {
            queueId_membershipId: {
              queueId,
              membershipId
            }
          }
        });

        if (!link) {
          throw new AppError(
            "O atendente escolhido não pertence a esta fila.",
            422,
            "ASSIGNEE_NOT_IN_QUEUE"
          );
        }
      }
    }
  }

  const updated = await prisma.ticket.update({
    where: { id: ticket.id },
    data: {
      queueId,
      assignedMembershipId: membershipId,
      status: membershipId ? "OPEN" : "PENDING"
    },
    include: ticketInclude
  });

  if (updated.assignedMembershipId) {
    await finishChatbotSessionForTicket(ticket.id, "HUMAN_TAKEOVER");
  }

  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      updated.id,
    actorMembershipId:
      input.actorMembershipId,
    type: "TRANSFERRED",
    metadata: {
      fromQueueId:
        ticket.queueId,
      fromQueueName:
        ticket.queue?.name ??
        null,
      toQueueId:
        updated.queueId,
      toQueueName:
        updated.queue?.name ??
        null,
      fromMembershipId:
        ticket.assignedMembershipId,
      fromAssigneeName:
        ticket.assignedMembership?.user.name ??
        null,
      toMembershipId:
        updated.assignedMembershipId,
      toAssigneeName:
        updated.assignedMembership?.user.name ??
        null
    }
  });

  if (
    updated.assignedMembershipId &&
    updated.assignedMembershipId !==
      ticket.assignedMembershipId
  ) {
    await notifyTicketAssignment({
      companyId:
        input.companyId,
      ticketId:
        updated.id,
      membershipId:
        updated.assignedMembershipId,
      actorMembershipId:
        input.actorMembershipId
    });
  }

  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: ticket.id
  });

  return updated;
}

export async function closeTicket(input: {
  companyId: string;
  ticketId: string;
  membershipId: string;
  role: WappRole;
}) {
  const current = await getTicket(input.companyId, input.ticketId);

  assertCanOperateTicket(
    current.assignedMembershipId,
    input.membershipId,
    input.role
  );

  const ticket = await prisma.ticket.update({
    where: { id: input.ticketId },
    data: {
      status: "CLOSED",
      activeKey: null,
      unreadCount: 0,
      closedAt: new Date()
    }
  });

  await finishChatbotSessionForTicket(ticket.id, "TICKET_CLOSED");

  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      ticket.id,
    actorMembershipId:
      input.membershipId,
    type: "CLOSED",
    metadata: {
      previousStatus:
        current.status
    }
  });

  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: input.ticketId
  });

  return ticket;
}

export async function reopenTicket(input: {
  companyId: string;
  ticketId: string;
  membershipId: string;
  role: WappRole;
}) {
  const current = await getTicket(
    input.companyId,
    input.ticketId
  );

  if (current.status !== "CLOSED") {
    return {
      ticket: current,
      reusedExisting: true
    };
  }

  assertCanOperateTicket(
    current.assignedMembershipId,
    input.membershipId,
    input.role
  );

  await validateMembership(
    input.companyId,
    input.membershipId
  );

  const activeKey =
    `${current.whatsappConnectionId}:${current.contactId}`;

  const existingActive =
    await prisma.ticket.findFirst({
      where: {
        companyId:
          input.companyId,
        whatsappConnectionId:
          current.whatsappConnectionId,
        contactId:
          current.contactId,
        status: {
          in: [
            "OPEN",
            "PENDING"
          ]
        }
      },
      include: ticketInclude,
      orderBy: {
        lastMessageAt: "desc"
      }
    });

  if (existingActive) {
    return {
      ticket:
        existingActive,
      reusedExisting: true
    };
  }

  try {
    const ticket =
      await prisma.ticket.update({
        where: {
          id: current.id
        },
        data: {
          activeKey,
          status: "OPEN",
          assignedMembershipId:
            input.membershipId,
          unreadCount: 0,
          closedAt: null
        },
        include: ticketInclude
      });

      await recordTicketEvent({
      companyId:
        input.companyId,
      ticketId:
        ticket.id,
      actorMembershipId:
        input.membershipId,
      type: "REOPENED",
      metadata: {
        assignedMembershipId:
          ticket.assignedMembershipId,
        assigneeName:
          ticket.assignedMembership?.user.name ??
          null
      }
    });

  publishRealtime(
      input.companyId,
      {
        type: "ticket.updated",
        ticketId:
          ticket.id
      }
    );

    return {
      ticket,
      reusedExisting: false
    };
  } catch (error) {
    /*
     * A new inbound message can race with reopen and create
     * another active ticket after the pre-check. The unique
     * activeKey remains the final safety boundary.
     */
    const racedTicket =
      await prisma.ticket.findFirst({
        where: {
          companyId:
            input.companyId,
          whatsappConnectionId:
            current.whatsappConnectionId,
          contactId:
            current.contactId,
          status: {
            in: [
              "OPEN",
              "PENDING"
            ]
          }
        },
        include: ticketInclude,
        orderBy: {
          lastMessageAt: "desc"
        }
      });

    if (racedTicket) {
      return {
        ticket:
          racedTicket,
        reusedExisting: true
      };
    }

    throw error;
  }
}

export async function sendTicketText(input: {
  companyId: string;
  ticketId: string;
  userId: string;
  membershipId: string;
  role: WappRole;
  text: string;
  replyToMessageId?: string;
}) {
  let ticket = await getTicket(input.companyId, input.ticketId);

  if (ticket.status === "CLOSED") {
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

  if (!ticket.assignedMembershipId) {
    await claimTicket({
      companyId: input.companyId,
      ticketId: ticket.id,
      membershipId: input.membershipId,
      role: input.role
    });

    ticket = await getTicket(input.companyId, input.ticketId);
  }

  if (ticket.whatsappConnection.status !== "CONNECTED") {
    throw new AppError(
      "A conexão WhatsApp deste atendimento está offline.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  const quotedMessage =
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
      deliveryStatus: "PENDING",
      body: input.text,
      quotedExternalId:
        quotedMessage
          ?.externalId,
      timestamp,
      rawPayload: toPrismaJson(result)
    }
  });

  await prisma.ticket.update({
    where: { id: ticket.id },
    data: {
      lastMessage: input.text,
      lastMessageAt: timestamp,
      ...outboundSlaUpdate(
        ticket,
        timestamp
      )
    }
  });

  publishRealtime(input.companyId, {
    type: "message.created",
    ticketId: ticket.id,
    messageId: message.id
  });

  return message;
}


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
}

const documentMimeTypes = new Set([
  "application/pdf",
  "text/plain",
  "application/zip",
  "application/x-zip-compressed",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-powerpoint",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "application/octet-stream"
]);

const imageMimeTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif"
]);

const audioMimeTypes = new Set([
  "audio/ogg",
  "audio/mpeg",
  "audio/mp4",
  "audio/webm",
  "audio/wav",
  "audio/x-wav"
]);

const videoMimeTypes = new Set([
  "video/mp4",
  "video/webm"
]);

function outboundMediaDescriptor(
  mimetype: string
): {
  providerType:
    | "image"
    | "video"
    | "audio"
    | "document";
  messageType:
    | "IMAGE"
    | "VIDEO"
    | "AUDIO"
    | "DOCUMENT";
  preview: string;
} {
  const normalized = mimetype
    .split(";")[0]
    ?.trim()
    .toLowerCase();

  if (
    normalized &&
    imageMimeTypes.has(normalized)
  ) {
    return {
      providerType: "image",
      messageType: "IMAGE",
      preview: "[Imagem]"
    };
  }

  if (
    normalized &&
    audioMimeTypes.has(normalized)
  ) {
    return {
      providerType: "audio",
      messageType: "AUDIO",
      preview: "[Áudio]"
    };
  }

  if (
    normalized &&
    videoMimeTypes.has(normalized)
  ) {
    return {
      providerType: "video",
      messageType: "VIDEO",
      preview: "[Vídeo]"
    };
  }

  if (
    normalized &&
    documentMimeTypes.has(normalized)
  ) {
    return {
      providerType: "document",
      messageType: "DOCUMENT",
      preview: "[Documento]"
    };
  }

  throw new AppError(
    "Este tipo de arquivo não é suportado para envio.",
    422,
    "UNSUPPORTED_MEDIA_TYPE",
    {
      mimetype
    }
  );
}

function safeOutboundFileName(
  value: string
) {
  const sanitized = value
    .replace(/[\\/\0\r\n]/g, "_")
    .trim()
    .slice(0, 180);

  return sanitized || "arquivo";
}

export async function sendTicketMedia(input: {
  companyId: string;
  ticketId: string;
  userId: string;
  membershipId: string;
  role: WappRole;
  buffer: Buffer;
  mimetype: string;
  fileName: string;
  caption?: string;
  voiceNote?: boolean;
}) {
  let ticket = await getTicket(
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

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.membershipId,
    input.role
  );

  if (!ticket.assignedMembershipId) {
    await claimTicket({
      companyId: input.companyId,
      ticketId: ticket.id,
      membershipId: input.membershipId,
      role: input.role
    });

    ticket = await getTicket(
      input.companyId,
      input.ticketId
    );
  }

  if (
    ticket.whatsappConnection.status !==
    "CONNECTED"
  ) {
    throw new AppError(
      "A conexão WhatsApp deste atendimento está offline.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  const descriptor =
    outboundMediaDescriptor(
      input.mimetype
    );

  const fileName =
    safeOutboundFileName(
      input.fileName
    );

  const caption =
    input.caption?.trim() || null;

  const isVoiceNote =
    input.voiceNote === true &&
    descriptor.messageType === "AUDIO";

  if (
    input.voiceNote === true &&
    descriptor.messageType !== "AUDIO"
  ) {
    throw new AppError(
      "Voice note precisa ser um arquivo de áudio.",
      422,
      "VOICE_NOTE_INVALID_MEDIA"
    );
  }

  if (isVoiceNote && caption) {
    throw new AppError(
      "Mensagem de voz não aceita legenda.",
      422,
      "VOICE_NOTE_CAPTION_NOT_SUPPORTED"
    );
  }

  const result = isVoiceNote
    ? await evolutionWhatsAppClient.sendWhatsAppAudio({
        instanceName:
          ticket.whatsappConnection.instanceName,
        number:
          ticket.contact.remoteJid,
        mimetype:
          input.mimetype,
        fileName,
        buffer:
          input.buffer
      })
    : await evolutionWhatsAppClient.sendMedia({
      instanceName:
        ticket.whatsappConnection.instanceName,
      number:
        ticket.contact.remoteJid,
      mediaType:
        descriptor.providerType,
      mimetype:
        input.mimetype,
      fileName,
      buffer:
        input.buffer,
      caption:
        caption ?? ""
    });

  const timestamp =
    sentTimestamp(result);

  const externalId =
    sentExternalId(result);

  const message =
    await prisma.message.upsert({
      where: {
        whatsappConnectionId_externalId: {
          whatsappConnectionId:
            ticket.whatsappConnectionId,
          externalId
        }
      },
      update: {
        sentByUserId:
          input.userId,
        direction: "OUTBOUND",
        type:
          descriptor.messageType,
        deliveryStatus: "PENDING",
        body: isVoiceNote ? null : caption,
        mediaMimeType:
          input.mimetype,
        mediaFileName:
          fileName,
        mediaStatus: "PENDING",
        mediaError: null
      },
      create: {
        companyId:
          input.companyId,
        ticketId:
          ticket.id,
        whatsappConnectionId:
          ticket.whatsappConnectionId,
        sentByUserId:
          input.userId,
        externalId,
        direction: "OUTBOUND",
        type:
          descriptor.messageType,
        body: isVoiceNote ? null : caption,
        mediaMimeType:
          input.mimetype,
        mediaFileName:
          fileName,
        mediaStatus: "PENDING",
        timestamp,
        rawPayload:
          toPrismaJson(result)
      }
    });

  let readyMessage = message;

  try {
    const stored = await storeMedia({
      companyId:
        input.companyId,
      messageId:
        message.id,
      buffer:
        input.buffer,
      mimetype:
        input.mimetype,
      fileName
    });

    readyMessage =
      await prisma.message.update({
        where: {
          id: message.id
        },
        data: {
          mediaStatus: "READY",
          mediaStorageKey:
            stored.storageKey,
          mediaSize:
            stored.size,
          mediaError: null
        }
      });
  } catch (error) {
    readyMessage =
      await prisma.message.update({
        where: {
          id: message.id
        },
        data: {
          mediaStatus: "FAILED",
          mediaError:
            (
              error instanceof Error
                ? error.message
                : "Falha ao armazenar a cópia local da mídia."
            ).slice(0, 2_000)
        }
      });
  }

  await prisma.ticket.update({
    where: {
      id: ticket.id
    },
    data: {
      lastMessage:
        isVoiceNote
          ? "[Áudio]"
          : caption ??
            descriptor.preview,
      lastMessageAt:
        timestamp,
      ...outboundSlaUpdate(
        ticket,
        timestamp
      )
    }
  });

  publishRealtime(
    input.companyId,
    {
      type: "message.created",
      ticketId:
        ticket.id,
      messageId:
        readyMessage.id
    }
  );

  return readyMessage;
}

export async function listTicketNotes(
  companyId: string,
  ticketId: string
) {
  await getTicket(companyId, ticketId);

  return prisma.ticketNote.findMany({
    where: {
      companyId,
      ticketId
    },
    include: {
      authorMembership: {
        select: {
          id: true,
          role: true,
          user: {
            select: {
              id: true,
              name: true,
              email: true
            }
          }
        }
      }
    },
    orderBy: {
      createdAt: "asc"
    },
    take: 200
  });
}

export async function createTicketNote(input: {
  companyId: string;
  ticketId: string;
  authorMembershipId: string;
  role: WappRole;
  body: string;
}) {
  const ticket = await getTicket(
    input.companyId,
    input.ticketId
  );

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.authorMembershipId,
    input.role
  );

  const membership =
    await validateMembership(
      input.companyId,
      input.authorMembershipId
    );

  const note = await prisma.ticketNote.create({
    data: {
      companyId: input.companyId,
      ticketId: input.ticketId,
      authorMembershipId: membership.id,
      body: input.body.trim()
    },
    include: {
      authorMembership: {
        select: {
          id: true,
          role: true,
          user: {
            select: {
              id: true,
              name: true,
              email: true
            }
          }
        }
      }
    }
  });

  publishRealtime(input.companyId, {
    type: "note.created",
    ticketId: input.ticketId,
    noteId: note.id
  });

  return note;
}


export async function replaceTicketTags(input: {
  companyId: string;
  ticketId: string;
  actorMembershipId: string;
  role: WappRole;
  tagIds: string[];
}) {
  const ticket = await getTicket(
    input.companyId,
    input.ticketId
  );

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.actorMembershipId,
    input.role
  );

  const uniqueTagIds =
    [...new Set(input.tagIds)];

  if (uniqueTagIds.length > 20) {
    throw new AppError(
      "Um atendimento pode ter no máximo 20 etiquetas.",
      422,
      "TOO_MANY_TICKET_TAGS"
    );
  }

  if (uniqueTagIds.length > 0) {
    const validCount =
      await prisma.tag.count({
        where: {
          companyId:
            input.companyId,
          id: {
            in: uniqueTagIds
          },
          isActive: true
        }
      });

    if (
      validCount !==
      uniqueTagIds.length
    ) {
      throw new AppError(
        "Uma ou mais etiquetas são inválidas ou estão inativas.",
        422,
        "INVALID_TICKET_TAG"
      );
    }
  }

  await prisma.$transaction(async tx => {
    await tx.ticketTag.deleteMany({
      where: {
        ticketId:
          ticket.id
      }
    });

    if (uniqueTagIds.length > 0) {
      await tx.ticketTag.createMany({
        data:
          uniqueTagIds.map(tagId => ({
            ticketId:
              ticket.id,
            tagId,
            createdByMembershipId:
              input.actorMembershipId
          })),
        skipDuplicates: true
      });
    }
  });

  const updated =
    await prisma.ticket.findFirst({
      where: {
        id: ticket.id,
        companyId:
          input.companyId
      },
      include: ticketInclude
    });

  if (updated) {
    await recordTicketEvent({
      companyId:
        input.companyId,
      ticketId:
        ticket.id,
      actorMembershipId:
        input.actorMembershipId,
      type: "TAGS_UPDATED",
      metadata: {
        tagIds:
          updated.tags.map(
            link =>
              link.tag.id
          ),
        tagNames:
          updated.tags.map(
            link =>
              link.tag.name
          )
      }
    });
  }

  publishRealtime(
    input.companyId,
    {
      type: "ticket.updated",
      ticketId:
        ticket.id
    }
  );

  return updated;
}
