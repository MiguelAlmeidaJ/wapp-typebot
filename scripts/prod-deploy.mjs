import { mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const envFile = resolve(
  root,
  process.env.WAPP_ENV_FILE || "infra/pm2/production.env"
);
const buildOnly = process.argv.includes("--build-only");

function run(command, args, options = {}) {
  console.log(`\n[prod:deploy] $ ${command} ${args.join(" ")}`);

  const result = spawnSync(command, args, {
    cwd: root,
    env: process.env,
    stdio: "inherit",
    shell: process.platform === "win32",
    ...options
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${result.status}`);
  }
}

run(process.execPath, ["scripts/prod-preflight.mjs"], {
  env: {
    ...process.env,
    WAPP_ENV_FILE: envFile
  }
});

process.loadEnvFile(envFile);
process.env.WAPP_ENV_FILE = envFile;

if (process.env.MEDIA_STORAGE_DRIVER === "local") {
  const mediaPath = process.env.MEDIA_STORAGE_PATH?.trim();
  if (mediaPath) {
    mkdirSync(mediaPath, { recursive: true });
  }
}

run("pnpm", ["install", "--frozen-lockfile"]);
run("pnpm", ["security:scan"]);
run("pnpm", ["db:generate"]);
run("pnpm", ["typecheck"]);
run("pnpm", ["build"]);

if (buildOnly) {
  console.log("\n[prod:deploy] PASS — production build completed; PM2 was not changed.");
  process.exit(0);
}

run("pnpm", ["--filter", "@wapp/api", "db:deploy"]);

run("pm2", [
  "startOrReload",
  "ecosystem.config.cjs",
  "--update-env"
]);

run("pm2", ["save"]);
run(process.execPath, ["scripts/smoke-api.mjs"]);

console.log("\n[prod:deploy] PASS — migrations applied, PM2 reloaded and smoke checks passed.");
