import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { verifyPassword } from "../../lib/password.js";
import {
  createRefreshToken,
  hashRefreshToken,
  signAccessToken
} from "../../lib/tokens.js";

interface LoginInput {
  email: string;
  password: string;
  companySlug?: string;
  ipAddress?: string;
  userAgent?: string;
}

function refreshExpirationDate(): Date {
  const expiresAt = new Date();
  expiresAt.setDate(
    expiresAt.getDate() + env.REFRESH_TOKEN_TTL_DAYS
  );
  return expiresAt;
}

function publicMembership(membership: {
  id: string;
  role: "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";
  company: {
    id: string;
    name: string;
    slug: string;
  };
}) {
  return {
    membershipId: membership.id,
    role: membership.role,
    company: membership.company
  };
}

export async function login(input: LoginInput) {
  const user = await prisma.user.findUnique({
    where: {
      email: input.email.trim().toLowerCase()
    },
    include: {
      memberships: {
        where: {
          isActive: true,
          company: {
            status: "ACTIVE"
          }
        },
        include: {
          company: true
        }
      }
    }
  });

  if (
    !user ||
    !user.isActive ||
    !(await verifyPassword(input.password, user.passwordHash))
  ) {
    throw new AppError(
      "E-mail ou senha inválidos.",
      401,
      "INVALID_CREDENTIALS"
    );
  }

  const memberships = user.memberships;

  if (memberships.length === 0) {
    throw new AppError(
      "Usuário sem acesso a uma empresa ativa.",
      403,
      "NO_ACTIVE_COMPANY"
    );
  }

  let membership: (typeof memberships)[number] | undefined;

  if (input.companySlug) {
    membership = memberships.find(
      item => item.company.slug === input.companySlug
    );

    if (!membership) {
      throw new AppError(
        "Empresa não encontrada para este usuário.",
        403,
        "COMPANY_ACCESS_DENIED"
      );
    }
  } else if (memberships.length === 1) {
    membership = memberships[0];
  } else {
    throw new AppError(
      "Escolha a empresa para continuar.",
      409,
      "COMPANY_REQUIRED",
      {
        companies: memberships.map(publicMembership)
      }
    );
  }

  if (!membership) {
    throw new AppError(
      "Não foi possível determinar a empresa da sessão.",
      403,
      "COMPANY_ACCESS_DENIED"
    );
  }

  const refreshToken = createRefreshToken();

  const session = await prisma.session.create({
    data: {
      userId: user.id,
      companyId: membership.companyId,
      membershipId: membership.id,
      refreshTokenHash: hashRefreshToken(refreshToken),
      expiresAt: refreshExpirationDate(),
      ipAddress: input.ipAddress,
      userAgent: input.userAgent
    }
  });

  const accessToken = await signAccessToken({
    userId: user.id,
    companyId: membership.companyId,
    membershipId: membership.id,
    sessionId: session.id,
    role: membership.role
  });

  return {
    accessToken,
    refreshToken,
    user: {
      id: user.id,
      name: user.name,
      email: user.email
    },
    company: membership.company,
    role: membership.role
  };
}

export async function refresh(refreshToken: string) {
  const refreshTokenHash = hashRefreshToken(refreshToken);

  const session = await prisma.session.findUnique({
    where: {
      refreshTokenHash
    },
    include: {
      user: true,
      company: true,
      membership: true
    }
  });

  if (
    !session ||
    session.revokedAt ||
    session.expiresAt <= new Date() ||
    !session.user.isActive ||
    session.company.status !== "ACTIVE" ||
    !session.membership.isActive
  ) {
    throw new AppError(
      "Sessão expirada ou inválida.",
      401,
      "REFRESH_TOKEN_INVALID"
    );
  }

  const rotatedRefreshToken = createRefreshToken();

  await prisma.session.update({
    where: {
      id: session.id
    },
    data: {
      refreshTokenHash: hashRefreshToken(rotatedRefreshToken),
      expiresAt: refreshExpirationDate()
    }
  });

  const accessToken = await signAccessToken({
    userId: session.userId,
    companyId: session.companyId,
    membershipId: session.membershipId,
    sessionId: session.id,
    role: session.membership.role
  });

  return {
    accessToken,
    refreshToken: rotatedRefreshToken
  };
}

export async function logout(refreshToken?: string) {
  if (!refreshToken) {
    return;
  }

  await prisma.session.updateMany({
    where: {
      refreshTokenHash: hashRefreshToken(refreshToken),
      revokedAt: null
    },
    data: {
      revokedAt: new Date()
    }
  });
}
