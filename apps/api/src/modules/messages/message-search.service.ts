import type { Prisma } from "../../generated/prisma/client.js";

import { prisma } from "../../lib/database.js";

export async function searchMessageHistory(input: {
  companyId: string;
  query: string;
  ticketId?: string;
  page: number;
  limit: number;
}) {
  const query = input.query.trim();

  const where: Prisma.MessageWhereInput = {
    companyId: input.companyId,
    ...(input.ticketId
      ? {
          ticketId: input.ticketId
        }
      : {}),
    OR: [
      {
        body: {
          contains: query
        }
      },
      {
        mediaFileName: {
          contains: query
        }
      },
      {
        ticket: {
          contact: {
            name: {
              contains: query
            }
          }
        }
      },
      {
        ticket: {
          contact: {
            phoneNumber: {
              contains: query
            }
          }
        }
      }
    ]
  };

  const [total, messages] =
    await prisma.$transaction([
      prisma.message.count({
        where
      }),
      prisma.message.findMany({
        where,
        select: {
          id: true,
          ticketId: true,
          direction: true,
          type: true,
          body: true,
          mediaFileName: true,
          mediaMimeType: true,
          timestamp: true,
          ticket: {
            select: {
              id: true,
              status: true,
              lastMessageAt: true,
              contact: {
                select: {
                  id: true,
                  name: true,
                  phoneNumber: true,
                  isGroup: true
                }
              },
              queue: {
                select: {
                  id: true,
                  name: true
                }
              },
              assignedMembership: {
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
            }
          }
        },
        orderBy: [
          {
            timestamp: "desc"
          },
          {
            createdAt: "desc"
          }
        ],
        skip:
          (input.page - 1) *
          input.limit,
        take:
          input.limit
      })
    ]);

  return {
    messages,
    pagination: {
      page:
        input.page,
      limit:
        input.limit,
      total,
      pages:
        Math.max(
          1,
          Math.ceil(
            total / input.limit
          )
        )
    }
  };
}
