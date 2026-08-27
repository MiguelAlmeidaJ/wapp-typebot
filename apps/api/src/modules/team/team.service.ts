import type { MembershipRole } from "../../generated/prisma/client.js";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { hashPassword } from "../../lib/password.js";

type ManagedRole = "ADMIN" | "SUPERVISOR" | "AGENT";

interface TeamActor {
  companyId: string;
  membershipId: string;
  role: MembershipRole;
}

function assertManager(role: MembershipRole) {
  if (role !== "OWNER" && role !== "ADMIN") {
    throw new AppError(
      "Você não possui permissão para gerenciar a equipe.",
      403,
      "TEAM_MANAGEMENT_FORBIDDEN"
    );
  }
}

function assertAssignableRole(
  actorRole: MembershipRole,
  role: ManagedRole
) {
  if (actorRole === "ADMIN" && role === "ADMIN") {
    throw new AppError(
      "Administradores não podem promover outros administradores.",
      403,
      "ADMIN_ROLE_PROTECTED"
    );
  }
}

export async function listCompanyMemberships(
  companyId: string,
  includeInactive = false
) {
  return prisma.companyMembership.findMany({
    where: {
      companyId,
      ...(includeInactive ? {} : { isActive: true })
    },
    include: {
      user: {
        select: {
          id: true,
          name: true,
          email: true,
          isActive: true
        }
      },
      queueMemberships: {
        select: {
          queueId: true
        }
      }
    },
    orderBy: {
      createdAt: "asc"
    }
  });
}

export async function createCompanyMembership(input: {
  actor: TeamActor;
  name: string;
  email: string;
  temporaryPassword?: string;
  role: ManagedRole;
}) {
  assertManager(input.actor.role);
  assertAssignableRole(input.actor.role, input.role);

  const email = input.email.trim().toLowerCase();

  const existingUser = await prisma.user.findUnique({
    where: { email },
    include: {
      memberships: {
        where: {
          companyId: input.actor.companyId
        }
      }
    }
  });

  if (existingUser) {
    if (!existingUser.isActive) {
      throw new AppError(
        "A identidade deste usuário está desativada.",
        409,
        "USER_INACTIVE"
      );
    }

    const currentMembership = existingUser.memberships[0];

    if (currentMembership?.isActive) {
      throw new AppError(
        "Este usuário já possui acesso à empresa.",
        409,
        "MEMBERSHIP_ALREADY_EXISTS"
      );
    }

    const membership = currentMembership
      ? await prisma.companyMembership.update({
          where: { id: currentMembership.id },
          data: {
            role: input.role,
            isActive: true
          },
          include: {
            user: {
              select: {
                id: true,
                name: true,
                email: true,
                isActive: true
              }
            },
            queueMemberships: {
              select: { queueId: true }
            }
          }
        })
      : await prisma.companyMembership.create({
          data: {
            companyId: input.actor.companyId,
            userId: existingUser.id,
            role: input.role
          },
          include: {
            user: {
              select: {
                id: true,
                name: true,
                email: true,
                isActive: true
              }
            },
            queueMemberships: {
              select: { queueId: true }
            }
          }
        });

    return {
      membership,
      linkedExistingUser: true
    };
  }

  if (!input.temporaryPassword) {
    throw new AppError(
      "Informe uma senha temporária para criar um novo usuário.",
      422,
      "TEMPORARY_PASSWORD_REQUIRED"
    );
  }

  const passwordHash = await hashPassword(
    input.temporaryPassword
  );

  const membership = await prisma.$transaction(async tx => {
    const user = await tx.user.create({
      data: {
        name: input.name.trim(),
        email,
        passwordHash
      }
    });

    return tx.companyMembership.create({
      data: {
        companyId: input.actor.companyId,
        userId: user.id,
        role: input.role
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
            isActive: true
          }
        },
        queueMemberships: {
          select: { queueId: true }
        }
      }
    });
  });

  return {
    membership,
    linkedExistingUser: false
  };
}

export async function updateCompanyMembership(input: {
  actor: TeamActor;
  membershipId: string;
  role?: ManagedRole;
  isActive?: boolean;
}) {
  assertManager(input.actor.role);

  const target = await prisma.companyMembership.findFirst({
    where: {
      id: input.membershipId,
      companyId: input.actor.companyId
    }
  });

  if (!target) {
    throw new AppError(
      "Membro da equipe não encontrado.",
      404,
      "MEMBERSHIP_NOT_FOUND"
    );
  }

  if (target.id === input.actor.membershipId) {
    throw new AppError(
      "Você não pode alterar o próprio acesso por esta tela.",
      409,
      "SELF_MEMBERSHIP_PROTECTED"
    );
  }

  if (target.role === "OWNER") {
    throw new AppError(
      "O acesso OWNER é protegido.",
      403,
      "OWNER_MEMBERSHIP_PROTECTED"
    );
  }

  if (
    input.actor.role === "ADMIN" &&
    target.role === "ADMIN"
  ) {
    throw new AppError(
      "Administradores não podem alterar outro administrador.",
      403,
      "ADMIN_MEMBERSHIP_PROTECTED"
    );
  }

  if (input.role) {
    assertAssignableRole(input.actor.role, input.role);
  }

  const nextRole = input.role ?? target.role;
  const nextActive =
    input.isActive ?? target.isActive;

  return prisma.$transaction(async tx => {
    const membership = await tx.companyMembership.update({
      where: { id: target.id },
      data: {
        role: nextRole,
        isActive: nextActive
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
            isActive: true
          }
        },
        queueMemberships: {
          select: { queueId: true }
        }
      }
    });

    if (
      nextRole !== target.role ||
      nextActive !== target.isActive
    ) {
      await tx.session.updateMany({
        where: {
          membershipId: target.id,
          revokedAt: null
        },
        data: {
          revokedAt: new Date()
        }
      });
    }

    if (!nextActive) {
      await tx.queueMember.deleteMany({
        where: {
          membershipId: target.id
        }
      });

      await tx.ticket.updateMany({
        where: {
          companyId: input.actor.companyId,
          assignedMembershipId: target.id,
          status: {
            in: ["OPEN", "PENDING"]
          }
        },
        data: {
          assignedMembershipId: null,
          status: "PENDING"
        }
      });
    }

    return membership;
  });
}
