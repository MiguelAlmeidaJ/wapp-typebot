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
