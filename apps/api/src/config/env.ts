import "dotenv/config";

import { z } from "zod";

const booleanFromEnv = z
  .enum(["true", "false"])
  .default("false")
  .transform(value => value === "true");

const booleanTrueFromEnv = z
  .enum(["true", "false"])
  .default("true")
  .transform(value => value === "true");

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("0.0.0.0"),
  PORT: z.coerce.number().int().positive().default(4000),
  WEB_URL: z.string().url().default("http://localhost:3000"),
  TRUST_PROXY: booleanFromEnv,

  DATABASE_URL: z.string().url().startsWith("mysql://"),
  DATABASE_TLS_CA_PATH: z.string().min(1).optional().or(z.literal("")),
  REDIS_URL: z.string().min(1).optional(),
  JOBS_EMBEDDED_WORKER: booleanTrueFromEnv,
  JOBS_MEDIA_CAPTURE_CONCURRENCY: z.coerce
    .number()
    .int()
    .positive()
    .max(32)
    .default(4),
  JOBS_MEDIA_CAPTURE_ATTEMPTS: z.coerce
    .number()
    .int()
    .min(1)
    .max(20)
    .default(5),
  MAINTENANCE_ENABLED: booleanTrueFromEnv,
  MAINTENANCE_INTERVAL_HOURS: z.coerce
    .number()
    .int()
    .min(1)
    .max(168)
    .default(6),
  SESSION_RETENTION_DAYS: z.coerce
    .number()
    .int()
    .min(7)
    .max(365)
    .default(30),
  MAINTENANCE_STALE_MEDIA_MINUTES: z.coerce
    .number()
    .int()
    .min(5)
    .max(1_440)
    .default(30),
  API_BODY_MAX_BYTES: z.coerce
    .number()
    .int()
    .positive()
    .default(1_048_576),

  JWT_SECRET: z.string().min(32),
  METRICS_TOKEN: z
    .string()
    .min(32)
    .optional()
    .or(z.literal("")),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  COOKIE_SECURE: booleanFromEnv,

  EVOLUTION_BASE_URL: z.string().url().default("http://localhost:8080"),
  EVOLUTION_API_KEY: z.string().min(32),
  EVOLUTION_WEBHOOK_BASE_URL: z.string().url(),
  EVOLUTION_WEBHOOK_SECRET: z.string().min(32),
  EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS: z.coerce
    .number()
    .int()
    .min(15)
    .max(3_600)
    .default(60),

  WHATSAPP_SESSION_PATH: z.string().default(".runtime/whatsapp"),
  MEDIA_STORAGE_DRIVER: z
    .enum(["local", "s3"])
    .default("local"),
  MEDIA_STORAGE_PATH: z.string().default(".runtime/media"),
  S3_BUCKET: z.string().min(1).optional().or(z.literal("")),
  S3_REGION: z.string().min(1).default("us-east-1"),
  S3_ENDPOINT: z.string().url().optional().or(z.literal("")),
  S3_FORCE_PATH_STYLE: booleanFromEnv,
  S3_ACCESS_KEY_ID: z.string().min(1).optional().or(z.literal("")),
  S3_SECRET_ACCESS_KEY: z.string().min(1).optional().or(z.literal("")),
  MEDIA_MAX_BYTES: z.coerce
    .number()
    .int()
    .positive()
    .default(26_214_400),
  TYPEBOT_URL: z.string().url().optional().or(z.literal("")),
  TYPEBOT_ENABLED: booleanFromEnv,
  TYPEBOT_API_URL: z.string().url().optional().or(z.literal("")),
  TYPEBOT_API_TOKEN: z.string().min(1).optional().or(z.literal("")),
  TYPEBOT_WEBHOOK_SECRET: z.string().min(32).optional().or(z.literal("")),
  TYPEBOT_REQUEST_TIMEOUT_MS: z.coerce
    .number()
    .int()
    .min(1_000)
    .max(60_000)
    .default(15_000)
}).superRefine((value, context) => {
  if (!value.TYPEBOT_ENABLED) return;

  if (!value.TYPEBOT_API_URL) {
    context.addIssue({
      code: "custom",
      path: ["TYPEBOT_API_URL"],
      message: "TYPEBOT_API_URL is required when TYPEBOT_ENABLED=true"
    });
  }

  if (!value.TYPEBOT_API_TOKEN) {
    context.addIssue({
      code: "custom",
      path: ["TYPEBOT_API_TOKEN"],
      message: "TYPEBOT_API_TOKEN is required when TYPEBOT_ENABLED=true"
    });
  }

  if (!value.TYPEBOT_WEBHOOK_SECRET) {
    context.addIssue({
      code: "custom",
      path: ["TYPEBOT_WEBHOOK_SECRET"],
      message: "TYPEBOT_WEBHOOK_SECRET is required when TYPEBOT_ENABLED=true"
    });
  }
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
