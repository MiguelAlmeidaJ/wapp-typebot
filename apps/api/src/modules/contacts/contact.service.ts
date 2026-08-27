import type { Prisma } from "../../generated/prisma/client.js";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";

export type ContactTypeFilter =
  | "ALL"
  | "PEOPLE"
  | "GROUPS";

export async function listContacts(input: {
  companyId: string;
  search?: string;
  type: ContactTypeFilter;
  page: number;
  limit: number;
}) {
  const search = input.search?.trim();

  const where: Prisma.ContactWhereInput = {
    companyId: input.companyId,
    ...(input.type === "PEOPLE"
      ? { isGroup: false }
      : input.type === "GROUPS"
        ? { isGroup: true }
        : {}),
    ...(search
      ? {
          OR: [
            {
              name: {
                contains: search
              }
            },
            {
              whatsappName: {
                contains: search
              }
            },
            {
              phoneNumber: {
                contains: search
              }
            },
            {
              remoteJid: {
                contains: search
              }
            },
            {
              email: {
                contains: search
              }
            }
          ]
        }
      : {})
  };

  const [total, contacts] = await prisma.$transaction([
    prisma.contact.count({
      where
    }),
    prisma.contact.findMany({
      where,
      include: {
        _count: {
          select: {
            tickets: true
          }
        },
        tickets: {
          orderBy: {
            lastMessageAt: "desc"
          },
          take: 1,
          select: {
            id: true,
            status: true,
            lastMessage: true,
            lastMessageAt: true,
            whatsappConnection: {
              select: {
                id: true,
                name: true
              }
            }
          }
        }
      },
      orderBy: {
        updatedAt: "desc"
      },
      skip: (input.page - 1) * input.limit,
      take: input.limit
    })
  ]);

  return {
    contacts,
    pagination: {
      page: input.page,
      limit: input.limit,
      total,
      pages: Math.max(
        1,
        Math.ceil(total / input.limit)
      )
    }
  };
}

export async function getContact(
  companyId: string,
  contactId: string
) {
  const contact = await prisma.contact.findFirst({
    where: {
      id: contactId,
      companyId
    },
    include: {
      tickets: {
        orderBy: {
          lastMessageAt: "desc"
        },
        take: 50,
        include: {
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
          },
          whatsappConnection: {
            select: {
              id: true,
              name: true,
              phoneNumber: true
            }
          }
        }
      }
    }
  });

  if (!contact) {
    throw new AppError(
      "Contato não encontrado.",
      404,
      "CONTACT_NOT_FOUND"
    );
  }

  const [ticketCount, openTicketCount, messageCount] =
    await prisma.$transaction([
      prisma.ticket.count({
        where: {
          companyId,
          contactId
        }
      }),
      prisma.ticket.count({
        where: {
          companyId,
          contactId,
          status: {
            in: ["OPEN", "PENDING"]
          }
        }
      }),
      prisma.message.count({
        where: {
          companyId,
          ticket: {
            contactId
          }
        }
      })
    ]);

  return {
    contact,
    stats: {
      ticketCount,
      openTicketCount,
      messageCount
    }
  };
}

export async function updateContact(input: {
  companyId: string;
  contactId: string;
  name?: string;
  email?: string | null;
  notes?: string | null;
}) {
  const existing = await prisma.contact.findFirst({
    where: {
      id: input.contactId,
      companyId: input.companyId
    },
    select: {
      id: true
    }
  });

  if (!existing) {
    throw new AppError(
      "Contato não encontrado.",
      404,
      "CONTACT_NOT_FOUND"
    );
  }

  return prisma.contact.update({
    where: {
      id: input.contactId
    },
    data: {
      ...(input.name !== undefined
        ? { name: input.name.trim() }
        : {}),
      ...(input.email !== undefined
        ? {
            email:
              input.email?.trim() || null
          }
        : {}),
      ...(input.notes !== undefined
        ? {
            notes:
              input.notes?.trim() || null
          }
        : {})
    }
  });
}
