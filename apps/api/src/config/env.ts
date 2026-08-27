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

  EVOLUTION_BASE_URL: z.string().url().default("http://localhost:8080"),
  EVOLUTION_API_KEY: z.string().min(32),
  EVOLUTION_WEBHOOK_BASE_URL: z.string().url(),
  EVOLUTION_WEBHOOK_SECRET: z.string().min(32),

  WHATSAPP_SESSION_PATH: z.string().default(".runtime/whatsapp"),
  MEDIA_STORAGE_PATH: z.string().default(".runtime/media"),
  MEDIA_MAX_BYTES: z.coerce
    .number()
    .int()
    .positive()
    .default(26_214_400),
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
