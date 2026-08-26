import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export async function listQueues(companyId: string) {
  return prisma.queue.findMany({
    where: {
      companyId,
      isActive: true
    },
    include: {
      members: {
        include: {
          membership: {
            include: {
              user: {
                select: {
                  id: true,
                  name: true,
                  email: true
                }
              }
            }
          }
        }
      },
      _count: {
        select: {
          tickets: true
        }
      }
    },
    orderBy: {
      name: "asc"
    }
  });
}

export async function createQueue(input: {
  companyId: string;
  name: string;
}) {
  const existing = await prisma.queue.findFirst({
    where: {
      companyId: input.companyId,
      name: input.name.trim()
    }
  });

  if (existing) {
    throw new AppError(
      "Já existe uma fila com este nome.",
      409,
      "QUEUE_ALREADY_EXISTS"
    );
  }

  const queue = await prisma.queue.create({
    data: {
      companyId: input.companyId,
      name: input.name.trim()
    }
  });

  publishRealtime(input.companyId, {
    type: "queue.updated",
    queueId: queue.id
  });

  return queue;
}

export async function replaceQueueMembers(input: {
  companyId: string;
  queueId: string;
  membershipIds: string[];
}) {
  const queue = await prisma.queue.findFirst({
    where: {
      id: input.queueId,
      companyId: input.companyId,
      isActive: true
    }
  });

  if (!queue) {
    throw new AppError(
      "Fila não encontrada.",
      404,
      "QUEUE_NOT_FOUND"
    );
  }

  const uniqueMembershipIds = [...new Set(input.membershipIds)];

  if (uniqueMembershipIds.length > 0) {
    const validMemberships = await prisma.companyMembership.count({
      where: {
        companyId: input.companyId,
        id: {
          in: uniqueMembershipIds
        },
        isActive: true,
        user: {
          isActive: true
        }
      }
    });

    if (validMemberships !== uniqueMembershipIds.length) {
      throw new AppError(
        "Um ou mais atendentes não pertencem à empresa ativa.",
        422,
        "INVALID_QUEUE_MEMBERS"
      );
    }
  }

  await prisma.$transaction(async tx => {
    await tx.queueMember.deleteMany({
      where: {
        queueId: queue.id
      }
    });

    if (uniqueMembershipIds.length > 0) {
      await tx.queueMember.createMany({
        data: uniqueMembershipIds.map(membershipId => ({
          queueId: queue.id,
          membershipId
        }))
      });
    }
  });

  publishRealtime(input.companyId, {
    type: "queue.updated",
    queueId: queue.id
  });

  return listQueues(input.companyId);
}
