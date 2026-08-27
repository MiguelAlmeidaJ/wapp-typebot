import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

function normalizeShortcut(
  value: string
) {
  return value
    .trim()
    .toLowerCase()
    .replace(/^\/+/, "");
}

async function assertShortcutAvailable(input: {
  companyId: string;
  shortcut: string;
  excludeId?: string;
}) {
  const existing =
    await prisma.quickReply.findFirst({
      where: {
        companyId: input.companyId,
        shortcut: input.shortcut,
        ...(input.excludeId
          ? {
              id: {
                not: input.excludeId
              }
            }
          : {})
      },
      select: {
        id: true
      }
    });

  if (existing) {
    throw new AppError(
      `O atalho /${input.shortcut} já está em uso.`,
      409,
      "QUICK_REPLY_SHORTCUT_IN_USE"
    );
  }
}

export async function listQuickReplies(input: {
  companyId: string;
  search?: string;
  includeInactive?: boolean;
}) {
  const search = input.search?.trim();

  return prisma.quickReply.findMany({
    where: {
      companyId: input.companyId,
      ...(input.includeInactive
        ? {}
        : {
            isActive: true
          }),
      ...(search
        ? {
            OR: [
              {
                shortcut: {
                  contains:
                    normalizeShortcut(
                      search
                    )
                }
              },
              {
                title: {
                  contains: search
                }
              },
              {
                body: {
                  contains: search
                }
              }
            ]
          }
        : {})
    },
    include: {
      createdByMembership: {
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
    },
    orderBy: [
      {
        isActive: "desc"
      },
      {
        title: "asc"
      }
    ],
    take: 300
  });
}

export async function createQuickReply(input: {
  companyId: string;
  membershipId: string;
  shortcut: string;
  title: string;
  body: string;
}) {
  const shortcut =
    normalizeShortcut(
      input.shortcut
    );

  await assertShortcutAvailable({
    companyId: input.companyId,
    shortcut
  });

  const quickReply =
    await prisma.quickReply.create({
      data: {
        companyId:
          input.companyId,
        createdByMembershipId:
          input.membershipId,
        shortcut,
        title:
          input.title.trim(),
        body:
          input.body.trim()
      },
      include: {
        createdByMembership: {
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
    });

  publishRealtime(
    input.companyId,
    {
      type: "quick-reply.updated",
      quickReplyId:
        quickReply.id
    }
  );

  return quickReply;
}

export async function updateQuickReply(input: {
  companyId: string;
  quickReplyId: string;
  shortcut?: string;
  title?: string;
  body?: string;
  isActive?: boolean;
}) {
  const existing =
    await prisma.quickReply.findFirst({
      where: {
        id: input.quickReplyId,
        companyId: input.companyId
      }
    });

  if (!existing) {
    throw new AppError(
      "Resposta rápida não encontrada.",
      404,
      "QUICK_REPLY_NOT_FOUND"
    );
  }

  const shortcut =
    input.shortcut !== undefined
      ? normalizeShortcut(
          input.shortcut
        )
      : undefined;

  if (
    shortcut !== undefined &&
    shortcut !== existing.shortcut
  ) {
    await assertShortcutAvailable({
      companyId:
        input.companyId,
      shortcut,
      excludeId:
        existing.id
    });
  }

  const quickReply =
    await prisma.quickReply.update({
      where: {
        id: existing.id
      },
      data: {
        ...(shortcut !== undefined
          ? { shortcut }
          : {}),
        ...(input.title !== undefined
          ? {
              title:
                input.title.trim()
            }
          : {}),
        ...(input.body !== undefined
          ? {
              body:
                input.body.trim()
            }
          : {}),
        ...(input.isActive !== undefined
          ? {
              isActive:
                input.isActive
            }
          : {})
      },
      include: {
        createdByMembership: {
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
    });

  publishRealtime(
    input.companyId,
    {
      type: "quick-reply.updated",
      quickReplyId:
        quickReply.id
    }
  );

  return quickReply;
}
