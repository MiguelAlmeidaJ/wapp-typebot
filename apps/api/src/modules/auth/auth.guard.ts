import type { FastifyRequest } from "fastify";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import {
  type AccessContext,
  type WappRole,
  verifyAccessToken
} from "../../lib/tokens.js";

export interface AuthContext extends AccessContext {
  user: {
    id: string;
    name: string;
    email: string;
  };
  company: {
    id: string;
    name: string;
    slug: string;
  };
}

function getBearerToken(request: FastifyRequest): string {
  const authorization = request.headers.authorization;

  if (!authorization?.startsWith("Bearer ")) {
    throw new AppError(
      "Token de acesso não informado.",
      401,
      "UNAUTHORIZED"
    );
  }

  return authorization.slice("Bearer ".length).trim();
}

export async function requireAuth(
  request: FastifyRequest
): Promise<AuthContext> {
  let tokenContext: AccessContext;

  try {
    tokenContext = await verifyAccessToken(getBearerToken(request));
  } catch {
    throw new AppError(
      "Token de acesso inválido ou expirado.",
      401,
      "UNAUTHORIZED"
    );
  }

  const session = await prisma.session.findFirst({
    where: {
      id: tokenContext.sessionId,
      userId: tokenContext.userId,
      companyId: tokenContext.companyId,
      membershipId: tokenContext.membershipId,
      revokedAt: null,
      expiresAt: {
        gt: new Date()
      }
    },
    include: {
      user: true,
      company: true,
      membership: true
    }
  });

  if (
    !session ||
    !session.user.isActive ||
    session.company.status !== "ACTIVE" ||
    !session.membership.isActive
  ) {
    throw new AppError(
      "Sessão inválida ou revogada.",
      401,
      "SESSION_INVALID"
    );
  }

  if (session.membership.role !== tokenContext.role) {
    throw new AppError(
      "As permissões da sessão foram alteradas. Entre novamente.",
      401,
      "SESSION_ROLE_CHANGED"
    );
  }

  return {
    ...tokenContext,
    role: session.membership.role,
    user: {
      id: session.user.id,
      name: session.user.name,
      email: session.user.email
    },
    company: {
      id: session.company.id,
      name: session.company.name,
      slug: session.company.slug
    }
  };
}

export async function requireRoles(
  request: FastifyRequest,
  allowedRoles: readonly WappRole[]
): Promise<AuthContext> {
  const auth = await requireAuth(request);

  if (!allowedRoles.includes(auth.role)) {
    throw new AppError(
      "Você não possui permissão para executar esta ação.",
      403,
      "FORBIDDEN"
    );
  }

  return auth;
}
