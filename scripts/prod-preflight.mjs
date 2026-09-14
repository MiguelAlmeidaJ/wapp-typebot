import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const envFile = resolve(
  root,
  process.env.WAPP_ENV_FILE || "infra/pm2/production.env"
);

const errors = [];
const warnings = [];

function fail(message) {
  errors.push(message);
}

function warn(message) {
  warnings.push(message);
}

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    fail(`${name} is required.`);
    return "";
  }
  return value;
}

function strongSecret(name, min = 32) {
  const value = required(name);
  if (value && value.length < min) {
    fail(`${name} must contain at least ${min} characters.`);
  }
  if (value.includes("CHANGE_ME")) {
    fail(`${name} still contains CHANGE_ME.`);
  }
}

function validUrl(name, protocols) {
  const value = required(name);
  if (!value) return null;

  try {
    const parsed = new URL(value);
    if (protocols && !protocols.includes(parsed.protocol)) {
      fail(`${name} must use ${protocols.join(" or ")}.`);
    }
    if (parsed.hostname.includes("CHANGE_ME")) {
      fail(`${name} still contains CHANGE_ME.`);
    }
    return parsed;
  } catch {
    fail(`${name} must be a valid URL.`);
    return null;
  }
}

function commandExists(command, args = ["--version"]) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "ignore",
    shell: false
  });

  if (result.error || result.status !== 0) {
    fail(`${command} is not available in PATH.`);
  }
}

if (!existsSync(envFile)) {
  console.error(`[prod:preflight] FAIL — environment file not found: ${envFile}`);
  console.error("Run pnpm prod:init first.");
  process.exit(1);
}

process.loadEnvFile(envFile);

if (process.env.NODE_ENV !== "production") {
  fail("NODE_ENV must be production.");
}

const nodeMajor = Number(process.versions.node.split(".")[0]);
if (nodeMajor !== 24) {
  fail(`Node.js 24 is required. Current version: ${process.version}`);
}

commandExists("pnpm");
commandExists("pm2");

const webUrl = validUrl("WEB_URL", ["https:"]);
const publicApiUrl = validUrl("NEXT_PUBLIC_API_URL", ["https:"]);
validUrl("API_INTERNAL_URL", ["http:", "https:"]);
const databaseUrl = validUrl("DATABASE_URL", ["mysql:"]);
validUrl("SHADOW_DATABASE_URL", ["mysql:"]);
validUrl("REDIS_URL", ["redis:", "rediss:"]);
validUrl("EVOLUTION_BASE_URL", ["http:", "https:"]);
const webhookBaseUrl = validUrl("EVOLUTION_WEBHOOK_BASE_URL", ["https:"]);

if (webUrl && publicApiUrl && webUrl.origin !== publicApiUrl.origin) {
  warn("WEB_URL and NEXT_PUBLIC_API_URL use different origins. Confirm this is intentional.");
}

if (webUrl && webhookBaseUrl && webUrl.origin !== webhookBaseUrl.origin) {
  warn("EVOLUTION_WEBHOOK_BASE_URL differs from WEB_URL. Confirm the reverse proxy routes webhooks to this Wapp instance.");
}

if (databaseUrl && databaseUrl.hostname === "127.0.0.1") {
  warn("DATABASE_URL points to localhost. This is valid for a single-host deployment, but the database must not be exposed publicly.");
}

strongSecret("JWT_SECRET");
strongSecret("EVOLUTION_API_KEY");
strongSecret("EVOLUTION_WEBHOOK_SECRET");

const metricsToken = process.env.METRICS_TOKEN?.trim();
if (metricsToken && metricsToken.length < 32) {
  fail("METRICS_TOKEN must contain at least 32 characters when configured.");
}

if (process.env.TRUST_PROXY !== "true") {
  fail("TRUST_PROXY must be true behind the production reverse proxy.");
}

if (process.env.COOKIE_SECURE !== "true") {
  fail("COOKIE_SECURE must be true in production.");
}

if (process.env.JOBS_EMBEDDED_WORKER !== "false") {
  fail("JOBS_EMBEDDED_WORKER must be false because PM2 runs a dedicated worker.");
}

const tlsCaPath = required("DATABASE_TLS_CA_PATH");
if (tlsCaPath) {
  if (!existsSync(tlsCaPath)) {
    fail(`DATABASE_TLS_CA_PATH does not exist: ${tlsCaPath}`);
  } else {
    const pem = readFileSync(tlsCaPath, "utf8");
    if (!pem.includes("-----BEGIN CERTIFICATE-----")) {
      fail("DATABASE_TLS_CA_PATH does not contain a PEM certificate.");
    }
  }
}

const storageDriver = required("MEDIA_STORAGE_DRIVER");
if (storageDriver === "s3") {
  required("S3_BUCKET");
  required("S3_REGION");
  required("S3_ACCESS_KEY_ID");
  required("S3_SECRET_ACCESS_KEY");
} else if (storageDriver === "local") {
  const mediaPath = required("MEDIA_STORAGE_PATH");
  if (mediaPath && !mediaPath.startsWith("/")) {
    warn("MEDIA_STORAGE_PATH is relative. Prefer an absolute path outside the repository in production.");
  }
} else if (storageDriver) {
  fail("MEDIA_STORAGE_DRIVER must be local or s3.");
}

if (process.env.TYPEBOT_ENABLED === "true") {
  validUrl("TYPEBOT_API_URL", ["http:", "https:"]);
  required("TYPEBOT_API_TOKEN");
  strongSecret("TYPEBOT_WEBHOOK_SECRET");
}

for (const [name, value] of Object.entries(process.env)) {
  if (name.startsWith("WAPP_") || name.startsWith("npm_")) continue;
  if (typeof value === "string" && value.includes("CHANGE_ME")) {
    fail(`${name} still contains CHANGE_ME.`);
  }
}

for (const path of [
  "package.json",
  "pnpm-lock.yaml",
  "ecosystem.config.cjs",
  "apps/api/prisma/schema.prisma",
  "apps/web/next.config.ts"
]) {
  if (!existsSync(resolve(root, path))) {
    fail(`Required project file is missing: ${path}`);
  }
}

for (const message of warnings) {
  console.warn(`[prod:preflight] WARN — ${message}`);
}

if (errors.length > 0) {
  for (const message of errors) {
    console.error(`[prod:preflight] FAIL — ${message}`);
  }
  console.error(`[prod:preflight] ${errors.length} blocking issue(s) found.`);
  process.exit(1);
}

console.log(`[prod:preflight] PASS — ${envFile}`);
