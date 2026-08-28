import type {
  Prisma
} from "../../generated/prisma/client.js";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { getTicket } from "./ticket.service.js";
import {
  afterCursorWhere,
  beforeCursorWhere,
  chronologicalOrder,
  reverseChronologicalOrder,
  type MessageCursor
} from "./message-history.cursor.js";

interface MessagePageInput {
  companyId: string;
  ticketId: string;
  limit: number;
  before?: string;
  after?: string;
  around?: string;
}

async function messageCursor(
  input: {
    companyId: string;
    ticketId: string;
    messageId: string;
  }
): Promise<MessageCursor> {
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
        id: true,
        timestamp: true
      }
    });

  if (!message) {
    throw new AppError(
      "Mensagem não encontrada neste atendimento.",
      404,
      "TICKET_MESSAGE_NOT_FOUND"
    );
  }

  return message;
}

async function pageResult(
  companyId: string,
  ticketId: string,
  messages:
    Awaited<
      ReturnType<
        typeof prisma.message.findMany
      >
    >,
  input: {
    hasMoreBefore: boolean;
    hasMoreAfter: boolean;
  }
) {
  const quotedExternalIds =
    Array.from(
      new Set(
        messages
          .map(
            message =>
              message
                .quotedExternalId
          )
          .filter(
            (
              externalId
            ): externalId is string =>
              Boolean(
                externalId
              )
          )
      )
    );

  const quotedMessages =
    quotedExternalIds.length >
      0
      ? await prisma.message.findMany({
          where: {
            companyId,
            ticketId,
            externalId: {
              in:
                quotedExternalIds
            }
          },
          select: {
            id: true,
            externalId:
              true,
            direction:
              true,
            type: true,
            body: true,
            mediaFileName:
              true,
            timestamp:
              true
          }
        })
      : [];

  const quotedByExternalId =
    new Map(
      quotedMessages.map(
        message => [
          message.externalId,
          message
        ]
      )
    );

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
  }

  return {
    messages:
      messages.map(
        message => ({
          ...message,
          quotedMessage:
            message
              .quotedExternalId
              ? quotedByExternalId.get(
                  message
                    .quotedExternalId
                ) ??
                null
              : null,
          reactions:
            reactionsByMessageId.get(
              message.id
            ) ?? []
        })
      ),
    pagination: {
      hasMoreBefore:
        input.hasMoreBefore,
      olderCursor:
        input.hasMoreBefore
          ? messages[0]?.id ??
            null
          : null,
      hasMoreAfter:
        input.hasMoreAfter,
      newerCursor:
        input.hasMoreAfter
          ? messages[
              messages.length -
                1
            ]?.id ??
            null
          : null
    }
  };
}

export async function listTicketMessagePage(
  input: MessagePageInput
) {
  await getTicket(
    input.companyId,
    input.ticketId
  );

  const baseWhere:
    Prisma.MessageWhereInput =
    {
      companyId:
        input.companyId,
      ticketId:
        input.ticketId
    };

  if (input.around) {
    const anchor =
      await messageCursor({
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        messageId:
          input.around
      });

    const olderLimit =
      Math.ceil(
        input.limit /
          2
      );

    const newerLimit =
      input.limit -
      olderLimit;

    const olderRaw =
      await prisma.message.findMany({
        where: {
          ...baseWhere,
          OR: [
            {
              timestamp: {
                lt:
                  anchor.timestamp
              }
            },
            {
              timestamp:
                anchor.timestamp,
              id: {
                lte:
                  anchor.id
              }
            }
          ]
        },
        orderBy:
          reverseChronologicalOrder,
        take:
          olderLimit +
          1
      });

    const newerRaw =
      newerLimit > 0
        ? await prisma.message.findMany({
            where: {
              ...baseWhere,
              ...afterCursorWhere(
                anchor
              )
            },
            orderBy:
              chronologicalOrder,
            take:
              newerLimit +
              1
          })
        : [];

    const hasMoreBefore =
      olderRaw.length >
      olderLimit;

    const hasMoreAfter =
      newerRaw.length >
      newerLimit;

    const older =
      olderRaw
        .slice(
          0,
          olderLimit
        )
        .reverse();

    const newer =
      newerRaw.slice(
        0,
        newerLimit
      );

    return pageResult(
      input.companyId,
      input.ticketId,
      [
        ...older,
        ...newer
      ],
      {
        hasMoreBefore,
        hasMoreAfter
      }
    );
  }

  if (input.before) {
    const cursor =
      await messageCursor({
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        messageId:
          input.before
      });

    const raw =
      await prisma.message.findMany({
        where: {
          ...baseWhere,
          ...beforeCursorWhere(
            cursor
          )
        },
        orderBy:
          reverseChronologicalOrder,
        take:
          input.limit +
          1
      });

    const hasMoreBefore =
      raw.length >
      input.limit;

    const messages =
      raw
        .slice(
          0,
          input.limit
        )
        .reverse();

    return pageResult(
      input.companyId,
      input.ticketId,
      messages,
      {
        hasMoreBefore,
        hasMoreAfter:
          false
      }
    );
  }

  if (input.after) {
    const cursor =
      await messageCursor({
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        messageId:
          input.after
      });

    const raw =
      await prisma.message.findMany({
        where: {
          ...baseWhere,
          ...afterCursorWhere(
            cursor
          )
        },
        orderBy:
          chronologicalOrder,
        take:
          input.limit +
          1
      });

    const hasMoreAfter =
      raw.length >
      input.limit;

    const messages =
      raw.slice(
        0,
        input.limit
      );

    return pageResult(
      input.companyId,
      input.ticketId,
      messages,
      {
        hasMoreBefore:
          false,
        hasMoreAfter
      }
    );
  }

  /*
   * Initial conversation load intentionally fetches the newest page.
   * The previous implementation sorted ASC + take(200), which returned
   * the oldest 200 messages of a long ticket.
   */
  const raw =
    await prisma.message.findMany({
      where:
        baseWhere,
      orderBy:
        reverseChronologicalOrder,
      take:
        input.limit +
        1
    });

  const hasMoreBefore =
    raw.length >
    input.limit;

  const messages =
    raw
      .slice(
        0,
        input.limit
      )
      .reverse();

  return pageResult(
    input.companyId,
    input.ticketId,
    messages,
    {
      hasMoreBefore,
      hasMoreAfter:
        false
    }
  );
}
