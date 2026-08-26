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
