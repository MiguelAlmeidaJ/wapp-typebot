import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const envFile = resolve(
  root,
  process.env.WAPP_ENV_FILE || "infra/pm2/production.env"
);

if (existsSync(envFile)) {
  process.loadEnvFile(envFile);
}

const baseUrl = (
  process.env.WAPP_SMOKE_API_URL ||
  process.env.NEXT_PUBLIC_API_URL ||
  process.env.WEB_URL ||
  ""
).replace(/\/$/, "");

if (!baseUrl) {
  console.error("[prod:smoke] FAIL — no base URL configured.");
  process.exit(1);
}

const timeoutMs = Number(process.env.WAPP_SMOKE_TIMEOUT_MS || 10_000);

async function request(path, expectedStatus = 200) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${baseUrl}${path}`, {
      signal: controller.signal,
      redirect: "follow",
      headers: {
        "User-Agent": "wapp-production-smoke/1.0"
      }
    });

    if (response.status !== expectedStatus) {
      throw new Error(`HTTP ${response.status}, expected ${expectedStatus}`);
    }

    return response;
  } finally {
    clearTimeout(timeout);
  }
}

const checks = [
  ["live", "/health/live"],
  ["ready", "/health/ready"],
  ["health", "/health"],
  ["web", "/login"]
];

let failed = false;

for (const [name, path] of checks) {
  try {
    const response = await request(path);
    let detail = "OK";

    if (path.startsWith("/health")) {
      const body = await response.json();
      if (name === "ready" && body.ready !== true) {
        throw new Error(`readiness returned ready=${String(body.ready)}`);
      }
      if (name === "live" && body.status !== "ok") {
        throw new Error(`liveness returned status=${String(body.status)}`);
      }
      detail = body.status || detail;
    }

    console.log(`[prod:smoke] ${name}: ${detail}`);
  } catch (error) {
    failed = true;
    console.error(
      `[prod:smoke] ${name}: FAIL — ${error instanceof Error ? error.message : String(error)}`
    );
  }
}

if (failed) {
  process.exit(1);
}

console.log(`[prod:smoke] PASS — ${baseUrl}`);
