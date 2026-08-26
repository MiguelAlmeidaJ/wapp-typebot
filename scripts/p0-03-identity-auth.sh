#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.3] Building identity, database and authentication foundation..."

if [[ ! -f "apps/api/package.json" ]]; then
  echo "ERROR: apps/api/package.json not found. Run P0.2 first."
  exit 1
fi

mkdir -p \
  apps/api/prisma \
  apps/api/src/errors \
  apps/api/src/lib \
  apps/api/src/modules/auth \
  apps/api/src/modules/admin \
  docs

IGNORE_MARKER="# --- WAPP P0.3 ---"
if ! grep -Fq "$IGNORE_MARKER" .gitignore 2>/dev/null; then
  cat >> .gitignore <<'EOF'

# --- WAPP P0.3 ---
apps/api/src/generated/prisma/
apps/api/.runtime/
# --- /WAPP P0.3 ---
EOF
fi

cat > apps/api/prisma/schema.prisma <<'EOF'
generator client {
  provider     = "prisma-client"
  output       = "../src/generated/prisma"
  moduleFormat = "esm"
}

datasource db {
  provider = "mysql"
}

enum CompanyStatus {
  ACTIVE
  SUSPENDED
}

enum MembershipRole {
  OWNER
  ADMIN
  SUPERVISOR
  AGENT
}

model Company {
  id          String              @id @default(uuid()) @db.Char(36)
  name        String              @db.VarChar(160)
  slug        String              @unique @db.VarChar(80)
  status      CompanyStatus       @default(ACTIVE)
  memberships CompanyMembership[]
  sessions    Session[]
  createdAt   DateTime            @default(now())
  updatedAt   DateTime            @updatedAt

  @@index([status])
}

model User {
  id           String              @id @default(uuid()) @db.Char(36)
  name         String              @db.VarChar(160)
  email        String              @unique @db.VarChar(190)
  passwordHash String              @db.VarChar(255)
  isActive     Boolean             @default(true)
  memberships  CompanyMembership[]
  sessions     Session[]
  createdAt    DateTime            @default(now())
  updatedAt    DateTime            @updatedAt

  @@index([isActive])
}

model CompanyMembership {
  id        String         @id @default(uuid()) @db.Char(36)
  companyId String         @db.Char(36)
  userId    String         @db.Char(36)
  role      MembershipRole @default(AGENT)
  isActive  Boolean        @default(true)
  company   Company        @relation(fields: [companyId], references: [id], onDelete: Cascade)
  user      User           @relation(fields: [userId], references: [id], onDelete: Cascade)
  sessions  Session[]
  createdAt DateTime       @default(now())
  updatedAt DateTime       @updatedAt

  @@unique([companyId, userId])
  @@index([userId, isActive])
  @@index([companyId, role])
}

model Session {
  id               String            @id @default(uuid()) @db.Char(36)
  userId           String            @db.Char(36)
  companyId        String            @db.Char(36)
  membershipId     String            @db.Char(36)
  refreshTokenHash String            @unique @db.Char(64)
  expiresAt        DateTime
  revokedAt        DateTime?
  ipAddress        String?           @db.VarChar(64)
  userAgent        String?           @db.VarChar(500)
  user             User              @relation(fields: [userId], references: [id], onDelete: Cascade)
  company          Company           @relation(fields: [companyId], references: [id], onDelete: Cascade)
  membership       CompanyMembership @relation(fields: [membershipId], references: [id], onDelete: Cascade)
  createdAt        DateTime           @default(now())
  updatedAt        DateTime           @updatedAt

  @@index([userId, revokedAt])
  @@index([companyId, revokedAt])
  @@index([expiresAt])
}
EOF

cat > apps/api/prisma.config.ts <<'EOF'
import "dotenv/config";

import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations"
  },
  datasource: {
    url: env("DATABASE_URL")
  }
});
EOF

cat > apps/api/src/errors/app-error.ts <<'EOF'
export class AppError extends Error {
  constructor(
    message: string,
    public readonly statusCode = 400,
    public readonly code = "APP_ERROR",
    public readonly details?: unknown
  ) {
    super(message);
    this.name = "AppError";
  }
}
EOF

cat > apps/api/src/lib/password.ts <<'EOF'
import {
  randomBytes,
  scrypt as nodeScrypt,
  timingSafeEqual
} from "node:crypto";

const KEY_LENGTH = 64;
const SCRYPT_OPTIONS = {
  N: 16_384,
  r: 8,
  p: 1,
  maxmem: 64 * 1024 * 1024
};

function deriveKey(password: string, salt: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    nodeScrypt(
      password,
      salt,
      KEY_LENGTH,
      SCRYPT_OPTIONS,
      (error, derivedKey) => {
        if (error) {
          reject(error);
          return;
        }

        resolve(derivedKey as Buffer);
      }
    );
  });
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16).toString("hex");
  const hash = await deriveKey(password, salt);

  return `scrypt$${salt}$${hash.toString("hex")}`;
}

export async function verifyPassword(
  password: string,
  storedPassword: string
): Promise<boolean> {
  const [algorithm, salt, storedHash] = storedPassword.split("$");

  if (algorithm !== "scrypt" || !salt || !storedHash) {
    return false;
  }

  const candidate = await deriveKey(password, salt);
  const expected = Buffer.from(storedHash, "hex");

  if (candidate.length !== expected.length) {
    return false;
  }

  return timingSafeEqual(candidate, expected);
}
EOF

cat > apps/api/src/lib/database.ts <<'EOF'
import { PrismaMariaDb } from "@prisma/adapter-mariadb";

import { env } from "../config/env.js";
import { PrismaClient } from "../generated/prisma/client.js";

function createAdapter() {
  const databaseUrl = new URL(env.DATABASE_URL);

  if (databaseUrl.protocol !== "mysql:") {
    throw new Error("DATABASE_URL must use the mysql:// protocol");
  }

  return new PrismaMariaDb({
    host: databaseUrl.hostname,
    port: Number(databaseUrl.port || 3306),
    user: decodeURIComponent(databaseUrl.username),
    password: decodeURIComponent(databaseUrl.password),
    database: databaseUrl.pathname.replace(/^\//, ""),
    connectionLimit: 10
  });
}

export const prisma = new PrismaClient({
  adapter: createAdapter()
});
EOF

cat > apps/api/src/lib/tokens.ts <<'EOF'
import { createHash, randomBytes } from "node:crypto";

import { jwtVerify, SignJWT } from "jose";
import { z } from "zod";

import { env } from "../config/env.js";

export type WappRole = "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";

export interface AccessContext {
  userId: string;
  companyId: string;
  membershipId: string;
  sessionId: string;
  role: WappRole;
}

const payloadSchema = z.object({
  sub: z.string().uuid(),
  companyId: z.string().uuid(),
  membershipId: z.string().uuid(),
  sessionId: z.string().uuid(),
  role: z.enum(["OWNER", "ADMIN", "SUPERVISOR", "AGENT"])
});

const jwtSecret = new TextEncoder().encode(env.JWT_SECRET);

export async function signAccessToken(
  context: AccessContext
): Promise<string> {
  return new SignJWT({
    companyId: context.companyId,
    membershipId: context.membershipId,
    sessionId: context.sessionId,
    role: context.role
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setSubject(context.userId)
    .setIssuedAt()
    .setExpirationTime(`${env.ACCESS_TOKEN_TTL_SECONDS}s`)
    .sign(jwtSecret);
}

export async function verifyAccessToken(
  token: string
): Promise<AccessContext> {
  const { payload } = await jwtVerify(token, jwtSecret, {
    algorithms: ["HS256"]
  });

  const parsed = payloadSchema.parse(payload);

  return {
    userId: parsed.sub,
    companyId: parsed.companyId,
    membershipId: parsed.membershipId,
    sessionId: parsed.sessionId,
    role: parsed.role
  };
}

export function createRefreshToken(): string {
  return randomBytes(48).toString("base64url");
}

export function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}
EOF

cat > apps/api/src/config/env.ts <<'EOF'
import "dotenv/config";

import { z } from "zod";

const booleanFromEnv = z
  .enum(["true", "false"])
  .default("false")
  .transform(value => value === "true");

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("0.0.0.0"),
  PORT: z.coerce.number().int().positive().default(4000),
  WEB_URL: z.string().url().default("http://localhost:3000"),

  DATABASE_URL: z.string().url().startsWith("mysql://"),
  REDIS_URL: z.string().min(1).optional(),

  JWT_SECRET: z.string().min(32),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  COOKIE_SECURE: booleanFromEnv,

  WHATSAPP_SESSION_PATH: z.string().default(".runtime/whatsapp"),
  TYPEBOT_URL: z.string().url().optional().or(z.literal(""))
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error(
    "Invalid environment configuration",
    parsed.error.flatten().fieldErrors
  );
  process.exit(1);
}

export const env = parsed.data;
EOF

cat > apps/api/src/modules/auth/auth.guard.ts <<'EOF'
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
EOF

cat > apps/api/src/modules/auth/auth.service.ts <<'EOF'
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
EOF

cat > apps/api/src/modules/auth/auth.routes.ts <<'EOF'
import type { FastifyInstance, FastifyReply } from "fastify";
import { z } from "zod";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { requireAuth } from "./auth.guard.js";
import {
  login,
  logout,
  refresh
} from "./auth.service.js";

const REFRESH_COOKIE = "wapp_refresh";

const loginSchema = z.object({
  email: z.string().email().transform(value => value.trim().toLowerCase()),
  password: z.string().min(8),
  companySlug: z.string().min(1).optional()
});

function refreshCookieOptions() {
  return {
    httpOnly: true,
    secure: env.COOKIE_SECURE,
    sameSite: "lax" as const,
    path: "/api/v1/auth",
    maxAge: env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60
  };
}

function setRefreshCookie(
  reply: FastifyReply,
  token: string
) {
  reply.setCookie(
    REFRESH_COOKIE,
    token,
    refreshCookieOptions()
  );
}

export async function authRoutes(app: FastifyInstance) {
  app.post("/api/v1/auth/login", async (request, reply) => {
    const input = loginSchema.parse(request.body);

    const result = await login({
      ...input,
      ipAddress: request.ip,
      userAgent: request.headers["user-agent"]
    });

    setRefreshCookie(reply, result.refreshToken);

    return {
      accessToken: result.accessToken,
      user: result.user,
      company: result.company,
      role: result.role
    };
  });

  app.post("/api/v1/auth/refresh", async (request, reply) => {
    const token = request.cookies[REFRESH_COOKIE];

    if (!token) {
      throw new AppError(
        "Refresh token não informado.",
        401,
        "REFRESH_TOKEN_MISSING"
      );
    }

    const result = await refresh(token);

    setRefreshCookie(reply, result.refreshToken);

    return {
      accessToken: result.accessToken
    };
  });

  app.post("/api/v1/auth/logout", async (request, reply) => {
    await logout(request.cookies[REFRESH_COOKIE]);

    reply.clearCookie(REFRESH_COOKIE, {
      path: "/api/v1/auth"
    });

    return {
      success: true
    };
  });

  app.get("/api/v1/auth/me", async request => {
    const auth = await requireAuth(request);

    return {
      user: auth.user,
      company: auth.company,
      role: auth.role
    };
  });
}
EOF

cat > apps/api/src/modules/admin/admin.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";

import { requireRoles } from "../auth/auth.guard.js";

export async function adminRoutes(app: FastifyInstance) {
  app.get("/api/v1/admin/ping", async request => {
    const auth = await requireRoles(request, ["OWNER", "ADMIN"]);

    return {
      status: "ok",
      companyId: auth.companyId,
      role: auth.role,
      message: "RBAC funcionando."
    };
  });
}
EOF

cat > apps/api/src/app.ts <<'EOF'
import cookie from "@fastify/cookie";
import cors from "@fastify/cors";
import Fastify from "fastify";
import { ZodError } from "zod";

import { env } from "./config/env.js";
import { AppError } from "./errors/app-error.js";
import { prisma } from "./lib/database.js";
import { adminRoutes } from "./modules/admin/admin.routes.js";
import { authRoutes } from "./modules/auth/auth.routes.js";

export async function buildApp() {
  const app = Fastify({
    logger: {
      level: env.NODE_ENV === "production" ? "info" : "debug"
    }
  });

  await app.register(cors, {
    origin: env.WEB_URL,
    credentials: true
  });

  await app.register(cookie);

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof AppError) {
      return reply.status(error.statusCode).send({
        error: {
          code: error.code,
          message: error.message,
          details: error.details
        }
      });
    }

    if (error instanceof ZodError) {
      return reply.status(422).send({
        error: {
          code: "VALIDATION_ERROR",
          message: "Dados inválidos.",
          details: error.flatten().fieldErrors
        }
      });
    }

    request.log.error(error);

    return reply.status(500).send({
      error: {
        code: "INTERNAL_ERROR",
        message: "Erro interno do servidor."
      }
    });
  });

  app.get("/health", async () => {
    await prisma.$queryRaw`SELECT 1`;

    return {
      status: "ok",
      service: "wapp-api",
      database: "ok",
      timestamp: new Date().toISOString()
    };
  });

  app.get("/api/v1", async () => ({
    name: "Wapp API",
    version: "0.1.0"
  }));

  await app.register(authRoutes);
  await app.register(adminRoutes);

  app.addHook("onClose", async () => {
    await prisma.$disconnect();
  });

  return app;
}
EOF

cat > apps/api/prisma/seed.ts <<'EOF'
import "dotenv/config";

import { prisma } from "../src/lib/database.js";
import { hashPassword } from "../src/lib/password.js";

function required(name: string): string {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`${name} is required to seed the database.`);
  }

  return value;
}

async function main() {
  const companyName = required("SEED_COMPANY_NAME");
  const companySlug = required("SEED_COMPANY_SLUG").toLowerCase();
  const adminName = required("SEED_ADMIN_NAME");
  const adminEmail = required("SEED_ADMIN_EMAIL").toLowerCase();
  const adminPassword = required("SEED_ADMIN_PASSWORD");

  if (
    adminPassword.toLowerCase().includes("change-me") ||
    adminPassword.length < 12
  ) {
    throw new Error(
      "SEED_ADMIN_PASSWORD must be changed and contain at least 12 characters."
    );
  }

  const company = await prisma.company.upsert({
    where: {
      slug: companySlug
    },
    update: {
      name: companyName,
      status: "ACTIVE"
    },
    create: {
      name: companyName,
      slug: companySlug
    }
  });

  const existingUser = await prisma.user.findUnique({
    where: {
      email: adminEmail
    }
  });

  const user = existingUser
    ? await prisma.user.update({
        where: {
          id: existingUser.id
        },
        data: {
          name: adminName,
          isActive: true
        }
      })
    : await prisma.user.create({
        data: {
          name: adminName,
          email: adminEmail,
          passwordHash: await hashPassword(adminPassword)
        }
      });

  await prisma.companyMembership.upsert({
    where: {
      companyId_userId: {
        companyId: company.id,
        userId: user.id
      }
    },
    update: {
      role: "OWNER",
      isActive: true
    },
    create: {
      companyId: company.id,
      userId: user.id,
      role: "OWNER"
    }
  });

  console.log(`Seed complete: ${adminEmail} -> ${company.slug} (OWNER)`);
}

main()
  .catch(error => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
EOF

cat > apps/api/.env.example <<'EOF'
NODE_ENV=development
HOST=0.0.0.0
PORT=4000
WEB_URL=http://localhost:3000

DATABASE_URL=mysql://wapp:wapp_local@127.0.0.1:3306/wapp
REDIS_URL=redis://127.0.0.1:6379

JWT_SECRET=change-me-generate-a-long-random-secret
ACCESS_TOKEN_TTL_SECONDS=900
REFRESH_TOKEN_TTL_DAYS=30
COOKIE_SECURE=false

WHATSAPP_SESSION_PATH=.runtime/whatsapp
TYPEBOT_URL=

SEED_COMPANY_NAME=Wapp
SEED_COMPANY_SLUG=wapp
SEED_ADMIN_NAME=Miguel Almeida
SEED_ADMIN_EMAIL=miguel@anoar.com.br
SEED_ADMIN_PASSWORD=change-me-before-seeding
EOF

cat > docs/IDENTITY.md <<'EOF'
# Identity and tenancy

The new Wapp identity model separates the user identity from company access.

```text
User
  |
  +-- CompanyMembership -- Company
              |
              +-- role
              +-- active/inactive
```

This lets one user participate in more than one company without duplicating
credentials.

## Roles

- OWNER
- ADMIN
- SUPERVISOR
- AGENT

Authorization always runs inside the company selected by the current session.

## Sessions

Access tokens are short-lived JWTs. Refresh tokens are opaque random values;
only their SHA-256 hashes are persisted. Refresh tokens rotate on every use.

Each session is linked to a user, company and membership. Revoking a session
immediately blocks protected routes.
EOF

node <<'NODE'
const fs = require("node:fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function writeJson(path, value) {
  fs.writeFileSync(path, JSON.stringify(value, null, 2) + "\n");
}

const apiPath = "apps/api/package.json";
const api = readJson(apiPath);
api.scripts = {
  ...api.scripts,
  "db:generate": "prisma generate",
  "db:migrate": "prisma migrate dev",
  "db:deploy": "prisma migrate deploy",
  "db:seed": "tsx prisma/seed.ts",
  "db:studio": "prisma studio"
};
writeJson(apiPath, api);

const rootPath = "package.json";
const root = readJson(rootPath);
root.scripts = {
  ...root.scripts,
  "db:generate": "pnpm --filter @wapp/api db:generate",
  "db:migrate": "pnpm --filter @wapp/api db:migrate",
  "db:seed": "pnpm --filter @wapp/api db:seed",
  "db:studio": "pnpm --filter @wapp/api db:studio"
};
writeJson(rootPath, root);
NODE

echo "[P0.3] Installing dependencies..."

pnpm --filter @wapp/api add \
  @fastify/cookie \
  @prisma/client@7.9.1 \
  @prisma/adapter-mariadb@7.9.1 \
  jose

pnpm --filter @wapp/api add -D prisma@7.9.1

echo "[P0.3] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo
echo "[P0.3] Foundation created."
echo
echo "Update apps/api/.env using apps/api/.env.example, then run:"
echo
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name init_identity"
echo "  pnpm db:seed"
echo "  pnpm dev"
echo
