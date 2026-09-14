import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const envFile = resolve(
  root,
  process.env.WAPP_ENV_FILE || "infra/pm2/production.env"
);

const scripts = {
  "first-owner-status": "src/scripts/prod-first-owner-status.ts",
  "first-owner-bootstrap": "src/scripts/prod-first-owner-bootstrap.ts",
  "first-owner-finalize": "src/scripts/prod-first-owner-finalize.ts"
};

const key = process.argv[2];
const script = scripts[key];

if (!script) {
  console.error(`[prod:api-script] Unknown command: ${key || "<missing>"}`);
  process.exit(1);
}

if (!existsSync(envFile)) {
  console.error(`[prod:api-script] Environment file not found: ${envFile}`);
  process.exit(1);
}

process.loadEnvFile(envFile);
process.env.WAPP_ENV_FILE = envFile;

const result = spawnSync(
  "pnpm",
  ["--filter", "@wapp/api", "exec", "tsx", script],
  {
    cwd: root,
    env: process.env,
    stdio: "inherit",
    shell: process.platform === "win32"
  }
);

if (result.error) throw result.error;
process.exit(result.status ?? 1);
