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
