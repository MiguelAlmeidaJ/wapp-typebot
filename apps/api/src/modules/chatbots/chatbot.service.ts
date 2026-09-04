import { randomUUID } from "node:crypto";

import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { recordAudit } from "../audit/audit.service.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import { recordTicketEvent } from "../tickets/ticket-event.service.js";

function slugify(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function stringValue(value: unknown) {
  return typeof value === "string" && value ? value : undefined;
}

function sentExternalId(result: unknown) {
  return stringValue(objectValue(objectValue(result)?.key)?.id) ??
    `wapp-chatbot-${randomUUID()}`;
}

function sentTimestamp(result: unknown) {
  const raw = objectValue(result)?.messageTimestamp;
  const seconds = typeof raw === "number"
    ? raw
    : typeof raw === "string"
      ? Number(raw)
      : NaN;

  return Number.isFinite(seconds) ? new Date(seconds * 1_000) : new Date();
}

async function assertConnection(companyId: string, connectionId: string) {
  const connection = await prisma.whatsAppConnection.findFirst({
    where: {
      id: connectionId,
      companyId
    },
    select: { id: true }
  });

  if (!connection) {
    throw new AppError(
      "Conexão WhatsApp não encontrada.",
      404,
      "WHATSAPP_CONNECTION_NOT_FOUND"
    );
  }
}

export function listChatbotFlows(companyId: string) {
  return prisma.chatbotFlow.findMany({
    where: { companyId },
    include: {
      whatsappConnection: {
        select: {
          id: true,
          name: true,
          status: true
        }
      },
      _count: {
        select: { sessions: true }
      }
    },
    orderBy: [{ isActive: "desc" }, { name: "asc" }]
  });
}

export async function createChatbotFlow(input: {
  companyId: string;
  actorMembershipId: string;
  name: string;
  whatsappConnectionId: string;
  externalId: string;
  isActive?: boolean;
}) {
  await assertConnection(input.companyId, input.whatsappConnectionId);
  const isActive = input.isActive ?? true;

  if (isActive) {
    const active = await prisma.chatbotFlow.findUnique({
      where: { activeKey: input.whatsappConnectionId },
      select: { id: true }
    });

    if (active) {
      throw new AppError(
        "Esta conexão já possui um chatbot ativo.",
        409,
        "CHATBOT_CONNECTION_ALREADY_ACTIVE"
      );
    }
  }

  const flow = await prisma.chatbotFlow.create({
    data: {
      companyId: input.companyId,
      whatsappConnectionId: input.whatsappConnectionId,
      name: input.name.trim(),
      externalId: input.externalId.trim(),
      isActive,
      activeKey: isActive ? input.whatsappConnectionId : null
    }
  });

  await recordAudit({
    companyId: input.companyId,
    actorMembershipId: input.actorMembershipId,
    action: "CHATBOT_FLOW_CREATED",
    entityType: "CHATBOT_FLOW",
    entityId: flow.id,
    after: flow
  });

  return flow;
}

export async function updateChatbotFlow(input: {
  companyId: string;
  actorMembershipId: string;
  flowId: string;
  patch: {
    name?: string;
    whatsappConnectionId?: string;
    externalId?: string;
    isActive?: boolean;
  };
}) {
  const current = await prisma.chatbotFlow.findFirst({
    where: {
      id: input.flowId,
      companyId: input.companyId
    }
  });

  if (!current) {
    throw new AppError("Chatbot não encontrado.", 404, "CHATBOT_NOT_FOUND");
  }

  const connectionId = input.patch.whatsappConnectionId ??
    current.whatsappConnectionId;
  const isActive = input.patch.isActive ?? current.isActive;

  if (input.patch.whatsappConnectionId) {
    await assertConnection(input.companyId, connectionId);
  }

  if (isActive) {
    const active = await prisma.chatbotFlow.findUnique({
      where: { activeKey: connectionId },
      select: { id: true }
    });

    if (active && active.id !== current.id) {
      throw new AppError(
        "Esta conexão já possui um chatbot ativo.",
        409,
        "CHATBOT_CONNECTION_ALREADY_ACTIVE"
      );
    }
  }

  const updated = await prisma.$transaction(async transaction => {
    const flow = await transaction.chatbotFlow.update({
      where: { id: current.id },
      data: {
        name: input.patch.name?.trim(),
        externalId: input.patch.externalId?.trim(),
        whatsappConnectionId: input.patch.whatsappConnectionId,
        isActive,
        activeKey: isActive ? connectionId : null
      }
    });

    if (!isActive) {
      await transaction.chatbotSession.updateMany({
        where: {
          flowId: current.id,
          activeKey: { not: null }
        },
        data: {
          status: "FINISHED",
          activeKey: null,
          finishedAt: new Date(),
          finishReason: "FLOW_DISABLED"
        }
      });
    }

    return flow;
  });

  await recordAudit({
    companyId: input.companyId,
    actorMembershipId: input.actorMembershipId,
    action: "CHATBOT_FLOW_UPDATED",
    entityType: "CHATBOT_FLOW",
    entityId: updated.id,
    before: current,
    after: updated
  });

  return updated;
}

export async function finishChatbotSessionForTicket(
  ticketId: string,
  reason: string
) {
  return prisma.chatbotSession.updateMany({
    where: {
      ticketId,
      activeKey: { not: null }
    },
    data: {
      status: "FINISHED",
      activeKey: null,
      finishedAt: new Date(),
      finishReason: reason
    }
  });
}

export async function sendChatbotText(input: {
  sessionId: string;
  companyId: string;
  ticketId: string;
  text: string;
}) {
  const ticket = await prisma.ticket.findFirst({
    where: {
      id: input.ticketId,
      companyId: input.companyId,
      status: { not: "CLOSED" },
      assignedMembershipId: null,
      chatbotSessions: {
        some: {
          id: input.sessionId,
          activeKey: input.ticketId
        }
      }
    },
    include: {
      contact: {
        select: { remoteJid: true }
      },
      whatsappConnection: {
        select: {
          id: true,
          instanceName: true,
          status: true
        }
      }
    }
  });

  if (!ticket) return null;

  if (ticket.whatsappConnection.status !== "CONNECTED") {
    throw new Error("WhatsApp connection is not CONNECTED.");
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
        whatsappConnectionId: ticket.whatsappConnection.id,
        externalId
      }
    },
    update: {},
    create: {
      companyId: input.companyId,
      ticketId: ticket.id,
      whatsappConnectionId: ticket.whatsappConnection.id,
      externalId,
      direction: "OUTBOUND",
      type: "TEXT",
      deliveryStatus: "PENDING",
      body: input.text,
      timestamp,
      rawPayload: toPrismaJson({
        source: "CHATBOT",
        chatbotSessionId: input.sessionId,
        providerResult: result
      })
    }
  });

  await prisma.ticket.update({
    where: { id: ticket.id },
    data: {
      lastMessage: input.text,
      lastMessageAt: timestamp,
      lastOutboundAt: timestamp,
      waitingSince: null,
      ...(ticket.firstInboundAt && !ticket.firstResponseAt
        ? { firstResponseAt: timestamp }
        : {})
    }
  });

  publishRealtime(input.companyId, {
    type: "message.created",
    ticketId: ticket.id,
    messageId: message.id
  });

  return message;
}

export async function transferChatbotToQueue(input: {
  ticketId: string;
  chatbotSessionId: string;
  queueSlug: string;
  externalSessionId?: string;
}) {
  const session = await prisma.chatbotSession.findFirst({
    where: {
      id: input.chatbotSessionId,
      ticketId: input.ticketId,
      activeKey: input.ticketId,
      ...(input.externalSessionId
        ? { externalSessionId: input.externalSessionId }
        : {})
    },
    include: {
      ticket: {
        select: {
          id: true,
          companyId: true,
          assignedMembershipId: true,
          status: true,
          queueId: true
        }
      }
    }
  });

  if (!session || session.ticket.status === "CLOSED") {
    throw new AppError(
      "Sessão de chatbot ativa não encontrada.",
      404,
      "CHATBOT_SESSION_NOT_FOUND"
    );
  }

  if (session.ticket.assignedMembershipId) {
    throw new AppError(
      "O atendimento já foi assumido por uma pessoa.",
      409,
      "CHATBOT_HUMAN_TAKEOVER"
    );
  }

  const queue = await prisma.queue.findFirst({
    where: {
      companyId: session.companyId,
      slug: slugify(input.queueSlug),
      isActive: true
    },
    select: { id: true, name: true, slug: true }
  });

  if (!queue) {
    throw new AppError("Fila não encontrada.", 404, "CHATBOT_QUEUE_NOT_FOUND");
  }

  await prisma.$transaction([
    prisma.ticket.update({
      where: { id: session.ticketId },
      data: {
        queueId: queue.id,
        assignedMembershipId: null,
        status: "PENDING"
      }
    }),
    prisma.chatbotSession.update({
      where: { id: session.id },
      data: {
        status: "FINISHED",
        activeKey: null,
        finishedAt: new Date(),
        finishReason: "TRANSFER_QUEUE"
      }
    })
  ]);

  await recordTicketEvent({
    companyId: session.companyId,
    ticketId: session.ticketId,
    type: "CHATBOT_TRANSFERRED",
    metadata: {
      chatbotSessionId: session.id,
      fromQueueId: session.ticket.queueId,
      toQueueId: queue.id,
      toQueueSlug: queue.slug
    }
  });

  publishRealtime(session.companyId, {
    type: "ticket.updated",
    ticketId: session.ticketId
  });

  return {
    ticketId: session.ticketId,
    queue,
    chatbotSessionId: session.id
  };
}
