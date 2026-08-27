import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export type TicketEventType =
  | "CREATED"
  | "CLAIMED"
  | "TRANSFERRED"
  | "CLOSED"
  | "REOPENED"
  | "TAGS_UPDATED";

export async function recordTicketEvent(input: {
  companyId: string;
  ticketId: string;
  type: TicketEventType;
  actorMembershipId?: string | null;
  metadata?: Record<string, unknown> | null;
}) {
  const event =
    await prisma.ticketEvent.create({
      data: {
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        type:
          input.type,
        actorMembershipId:
          input.actorMembershipId ??
          null,
        metadata:
          input.metadata
            ? toPrismaJson(
                input.metadata
              )
            : undefined
      }
    });

  publishRealtime(
    input.companyId,
    {
      type:
        "ticket.event.created",
      ticketId:
        input.ticketId,
      eventId:
        event.id
    }
  );

  return event;
}

export async function listTicketEvents(input: {
  companyId: string;
  ticketId: string;
}) {
  const ticket =
    await prisma.ticket.findFirst({
      where: {
        id: input.ticketId,
        companyId:
          input.companyId
      },
      select: {
        id: true
      }
    });

  if (!ticket) {
    throw new AppError(
      "Atendimento não encontrado.",
      404,
      "TICKET_NOT_FOUND"
    );
  }

  return prisma.ticketEvent.findMany({
    where: {
      companyId:
        input.companyId,
      ticketId:
        input.ticketId
    },
    include: {
      actorMembership: {
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
      createdAt: "desc"
    },
    take: 300
  });
}
