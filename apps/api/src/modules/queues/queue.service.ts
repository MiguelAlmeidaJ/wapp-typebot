import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

function queueSlug(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72) || "fila";
}

async function availableQueueSlug(companyId: string, name: string) {
  const base = queueSlug(name);
  const matches = await prisma.queue.findMany({
    where: {
      companyId,
      OR: [
        { slug: base },
        { slug: { startsWith: `${base}-` } }
      ]
    },
    select: { slug: true }
  });
  const used = new Set(matches.map(queue => queue.slug));

  if (!used.has(base)) return base;

  for (let suffix = 2; suffix < 10_000; suffix += 1) {
    const candidate = `${base}-${suffix}`;
    if (!used.has(candidate)) return candidate;
  }

  throw new AppError("Não foi possível gerar o slug da fila.", 409, "QUEUE_SLUG_EXHAUSTED");
}

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
      name: input.name.trim(),
      slug: await availableQueueSlug(input.companyId, input.name)
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
