const fs = require("node:fs");
const path = require("node:path");
const { parseEnv } = require("node:util");

const root = __dirname;

const defaultEnvPaths = [
  path.join(root, "infra/pm2/production.env"),
  path.join(root, ".env"),
  path.join(root, "apps/api/.env")
];

const envPath = process.env.WAPP_ENV_FILE
  ? path.resolve(root, process.env.WAPP_ENV_FILE)
  : defaultEnvPaths.find(candidate => fs.existsSync(candidate));

if (!envPath || !fs.existsSync(envPath)) {
  throw new Error(
    "Environment file not found. Run pnpm prod:init or set WAPP_ENV_FILE."
  );
}

Object.assign(process.env, parseEnv(fs.readFileSync(envPath, "utf8")));

const apiPort = String(process.env.PORT || 4401);
const webPort = String(process.env.WEB_PORT || 3301);

function definedEnv(values) {
  return Object.fromEntries(
    Object.entries(values).filter(([, value]) => value !== undefined)
  );
}

const apiEnvKeys = [
  "WEB_URL",
  "TRUST_PROXY",
  "DATABASE_URL",
  "DATABASE_TLS_CA_PATH",
  "REDIS_URL",
  "JOBS_MEDIA_CAPTURE_CONCURRENCY",
  "JOBS_MEDIA_CAPTURE_ATTEMPTS",
  "MAINTENANCE_ENABLED",
  "MAINTENANCE_INTERVAL_HOURS",
  "SESSION_RETENTION_DAYS",
  "MAINTENANCE_STALE_MEDIA_MINUTES",
  "API_BODY_MAX_BYTES",
  "JWT_SECRET",
  "METRICS_TOKEN",
  "ACCESS_TOKEN_TTL_SECONDS",
  "REFRESH_TOKEN_TTL_DAYS",
  "COOKIE_SECURE",
  "EVOLUTION_BASE_URL",
  "EVOLUTION_API_KEY",
  "EVOLUTION_WEBHOOK_BASE_URL",
  "EVOLUTION_WEBHOOK_SECRET",
  "EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS",
  "WHATSAPP_SESSION_PATH",
  "MEDIA_STORAGE_DRIVER",
  "MEDIA_STORAGE_PATH",
  "S3_BUCKET",
  "S3_REGION",
  "S3_ENDPOINT",
  "S3_FORCE_PATH_STYLE",
  "S3_ACCESS_KEY_ID",
  "S3_SECRET_ACCESS_KEY",
  "MEDIA_MAX_BYTES",
  "TYPEBOT_URL",
  "TYPEBOT_ENABLED",
  "TYPEBOT_API_URL",
  "TYPEBOT_API_TOKEN",
  "TYPEBOT_WEBHOOK_SECRET",
  "TYPEBOT_REQUEST_TIMEOUT_MS"
];

const sharedEnv = definedEnv({
  ...Object.fromEntries(apiEnvKeys.map(key => [key, process.env[key]])),
  NODE_ENV: process.env.NODE_ENV || "production",
  JOBS_EMBEDDED_WORKER: "false"
});

const standaloneCandidates = [
  path.join(root, "apps/web/.next/standalone/apps/web/server.js"),
  path.join(root, "apps/web/.next/standalone/server.js")
];

const webServer = standaloneCandidates.find(candidate => fs.existsSync(candidate));

if (!webServer) {
  throw new Error("Next standalone server not found. Run pnpm prod:build first.");
}

const common = {
  instances: 1,
  exec_mode: "fork",
  autorestart: true,
  watch: false,
  restart_delay: 2000,
  max_restarts: 10,
  min_uptime: "10s",
  kill_timeout: 15000,
  time: true,
  merge_logs: true
};

module.exports = {
  apps: [
    {
      ...common,
      name: "wapp-api",
      cwd: root,
      script: path.join(root, "apps/api/dist/server.js"),
      interpreter: "node",
      max_memory_restart: "1G",
      env: {
        ...sharedEnv,
        HOST: process.env.HOST || "127.0.0.1",
        PORT: apiPort,
        JOBS_EMBEDDED_WORKER: "false"
      }
    },
    {
      ...common,
      name: "wapp-worker",
      cwd: root,
      script: path.join(root, "apps/api/dist/worker.js"),
      interpreter: "node",
      max_memory_restart: "768M",
      env: {
        ...sharedEnv,
        JOBS_EMBEDDED_WORKER: "false"
      }
    },
    {
      ...common,
      name: "wapp-web",
      cwd: path.dirname(webServer),
      script: webServer,
      interpreter: "node",
      max_memory_restart: "1G",
      env: definedEnv({
        NODE_ENV: "production",
        PORT: webPort,
        HOSTNAME: process.env.WEB_HOST || "127.0.0.1",
        NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL,
        API_INTERNAL_URL: process.env.API_INTERNAL_URL
      })
    }
  ]
};
