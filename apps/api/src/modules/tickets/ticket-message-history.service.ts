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

function pageResult(
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
  return {
    messages,
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
    messages,
    {
      hasMoreBefore,
      hasMoreAfter:
        false
    }
  );
}
