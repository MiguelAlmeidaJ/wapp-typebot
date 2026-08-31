import type {
  Prisma
} from "../../generated/prisma/client.js";

import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";

export type AuditEntityType =
  | "TEAM_MEMBERSHIP"
  | "QUEUE"
  | "SLA_SETTINGS"
  | "TAG"
  | "QUICK_REPLY"
  | "WHATSAPP_CONNECTION"
  | "AUTOMATION_RULE"
  | "CONTACT_DATA";

function jsonValue(
  value: unknown
):
  | Prisma.InputJsonValue
  | undefined {
  if (
    value === null ||
    value === undefined
  ) {
    return undefined;
  }

  return toPrismaJson(
    value
  );
}

export async function recordAudit(input: {
  companyId: string;
  actorMembershipId: string;
  action: string;
  entityType: AuditEntityType;
  entityId?: string | null;
  before?: unknown;
  after?: unknown;
  metadata?: unknown;
  requestId?: string;
  ipAddress?: string;
  userAgent?: string;
}) {
  return prisma.auditLog.create({
    data: {
      companyId:
        input.companyId,
      actorMembershipId:
        input.actorMembershipId,
      action:
        input.action,
      entityType:
        input.entityType,
      entityId:
        input.entityId ??
        null,
      beforeData:
        jsonValue(
          input.before
        ),
      afterData:
        jsonValue(
          input.after
        ),
      metadata:
        jsonValue(
          input.metadata
        ),
      requestId:
        input.requestId,
      ipAddress:
        input.ipAddress,
      userAgent:
        input.userAgent
    }
  });
}

export async function snapshotAuditEntity(input: {
  companyId: string;
  entityType: AuditEntityType;
  entityId: string;
}) {
  switch (
    input.entityType
  ) {
    case "TEAM_MEMBERSHIP":
      return prisma.companyMembership.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          role: true,
          isActive:
            true,
          user: {
            select: {
              id: true,
              name: true,
              email: true,
              isActive:
                true
            }
          }
        }
      });

    case "QUEUE":
      return prisma.queue.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          name: true,
          isActive:
            true,
          members: {
            select: {
              membershipId:
                true
            },
            orderBy: {
              createdAt:
                "asc"
            }
          }
        }
      });

    case "SLA_SETTINGS":
      return prisma.company.findFirst({
        where: {
          id:
            input.companyId
        },
        select: {
          id: true,
          firstResponseSlaMinutes:
            true,
          replySlaMinutes:
            true
        }
      });

    case "TAG":
      return prisma.tag.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          name: true,
          colorKey:
            true,
          isActive:
            true
        }
      });

    case "QUICK_REPLY":
      return prisma.quickReply.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          shortcut:
            true,
          title: true,
          isActive:
            true
        }
      });

    case "WHATSAPP_CONNECTION":
      return prisma.whatsAppConnection.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          name: true,
          provider:
            true,
          status: true,
          acceptGroups:
            true,
          defaultQueueId:
            true
        }
      });
    case "CONTACT_DATA":
      return null;

    case "AUTOMATION_RULE":
      return prisma.automationRule.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        }
      });

  }
}

export async function listAuditLogs(input: {
  companyId: string;
  limit: number;
  cursor?: string;
  action?: string;
  entityType?: string;
  actorMembershipId?: string;
}) {
  let cursorWhere:
    Prisma.AuditLogWhereInput =
    {};

  if (
    input.cursor
  ) {
    const cursor =
      await prisma.auditLog.findFirst({
        where: {
          id:
            input.cursor,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          createdAt:
            true
        }
      });

    if (cursor) {
      cursorWhere = {
        OR: [
          {
            createdAt: {
              lt:
                cursor.createdAt
            }
          },
          {
            createdAt:
              cursor.createdAt,
            id: {
              lt:
                cursor.id
            }
          }
        ]
      };
    }
  }

  const rows =
    await prisma.auditLog.findMany({
      where: {
        companyId:
          input.companyId,
        ...cursorWhere,
        ...(input.action
          ? {
              action:
                input.action
            }
          : {}),
        ...(input.entityType
          ? {
              entityType:
                input.entityType
            }
          : {}),
        ...(input.actorMembershipId
          ? {
              actorMembershipId:
                input.actorMembershipId
            }
          : {})
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
      orderBy: [
        {
          createdAt:
            "desc"
        },
        {
          id:
            "desc"
        }
      ],
      take:
        input.limit +
        1
    });

  const hasMore =
    rows.length >
    input.limit;

  const items =
    rows.slice(
      0,
      input.limit
    );

  return {
    items,
    pagination: {
      hasMore,
      cursor:
        hasMore
          ? items[
              items.length -
                1
            ]?.id ??
            null
          : null
    }
  };
}
