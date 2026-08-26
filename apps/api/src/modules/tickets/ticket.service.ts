import { randomUUID } from "node:crypto";

import { AppError } from "../../errors/app-error.js";
import type { Prisma } from "../../generated/prisma/client.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import type { WappRole } from "../../lib/tokens.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export type TicketListStatus =
  | "ACTIVE"
  | "OPEN"
  | "PENDING"
  | "CLOSED";

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
  status: TicketListStatus
) {
  const where: Prisma.TicketWhereInput = {
    companyId,
    ...(status === "ACTIVE"
      ? {
          status: {
            in: ["OPEN", "PENDING"]
          }
        }
      : { status })
  };

  return prisma.ticket.findMany({
    where,
    include: ticketInclude,
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

  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: input.ticketId
  });

  return ticket;
}

export async function sendTicketText(input: {
  companyId: string;
  ticketId: string;
  userId: string;
  membershipId: string;
  role: WappRole;
  text: string;
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
      rawPayload: toPrismaJson(result)
    }
  });

  await prisma.ticket.update({
    where: { id: ticket.id },
    data: {
      lastMessage: input.text,
      lastMessageAt: timestamp
    }
  });

  publishRealtime(input.companyId, {
    type: "message.created",
    ticketId: ticket.id,
    messageId: message.id
  });

  return message;
}
