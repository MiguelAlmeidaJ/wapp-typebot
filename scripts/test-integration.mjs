import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const suffix = `${process.pid}-${Date.now()}`;
const mysqlName = `wapp-it-mysql-${suffix}`;
const redisName = `wapp-it-redis-${suffix}`;
const mediaDir = mkdtempSync(join(tmpdir(), "wapp-it-media-"));
const mysqlRoot = randomBytes(18).toString("hex");
const mysqlToken = randomBytes(18).toString("hex");
const redisToken = randomBytes(18).toString("hex");

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "inherit",
    env: process.env,
    ...options
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${result.status}`);
  }
}

function output(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${result.status}`);
  }
  return result.stdout.trim();
}

function cleanup() {
  spawnSync("docker", ["rm", "-f", mysqlName, redisName], { stdio: "ignore" });
  rmSync(mediaDir, { recursive: true, force: true });
}

async function waitFor(check, label, attempts) {
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const result = spawnSync(check.command, check.args, { stdio: "ignore" });
    if (result.status === 0) return;
    await new Promise(resolvePromise => setTimeout(resolvePromise, 1000));
  }
  throw new Error(`${label} did not become ready.`);
}

try {
  run("docker", ["version"]);
  run("docker", [
    "run", "-d", "--rm", "--name", mysqlName,
    "-e", `MYSQL_ROOT_PASSWORD=${mysqlRoot}`,
    "-e", "MYSQL_DATABASE=wapp_integration",
    "-e", "MYSQL_USER=wapp",
    "-e", `MYSQL_PASSWORD=${mysqlToken}`,
    "-p", "127.0.0.1::3306",
    "mysql:8.4"
  ]);
  run("docker", [
    "run", "-d", "--rm", "--name", redisName,
    "-p", "127.0.0.1::6379",
    "redis:7-alpine", "redis-server", "--requirepass", redisToken
  ]);

  await waitFor({
    command: "docker",
    args: ["exec", mysqlName, "mysqladmin", "ping", "-uroot", `-p${mysqlRoot}`, "--silent"]
  }, "MySQL", 60);

  await waitFor({
    command: "docker",
    args: ["exec", redisName, "redis-cli", "-a", redisToken, "ping"]
  }, "Redis", 30);

  run("docker", [
    "exec", mysqlName, "mysql", "-uroot", `-p${mysqlRoot}`,
    "-e", "CREATE DATABASE IF NOT EXISTS wapp_integration_shadow; GRANT ALL PRIVILEGES ON wapp_integration_shadow.* TO 'wapp'@'%'; FLUSH PRIVILEGES;"
  ]);

  const mysqlPort = output("docker", ["port", mysqlName, "3306/tcp"]).split(":").at(-1);
  const redisPort = output("docker", ["port", redisName, "6379/tcp"]).split(":").at(-1);

  Object.assign(process.env, {
    NODE_ENV: "test",
    HOST: "127.0.0.1",
    PORT: "4401",
    WEB_URL: "http://localhost:3301",
    TRUST_PROXY: "false",
    DATABASE_URL: `mysql://wapp:${mysqlToken}@127.0.0.1:${mysqlPort}/wapp_integration`,
    SHADOW_DATABASE_URL: `mysql://wapp:${mysqlToken}@127.0.0.1:${mysqlPort}/wapp_integration_shadow`,
    DATABASE_TLS_CA_PATH: "",
    REDIS_URL: `redis://:${redisToken}@127.0.0.1:${redisPort}/0`,
    JOBS_EMBEDDED_WORKER: "false",
    MAINTENANCE_ENABLED: "false",
    COOKIE_SECURE: "false",
    JWT_SECRET: randomBytes(32).toString("hex"),
    METRICS_TOKEN: randomBytes(32).toString("hex"),
    EVOLUTION_BASE_URL: "http://127.0.0.1:65530",
    EVOLUTION_API_KEY: randomBytes(32).toString("hex"),
    EVOLUTION_WEBHOOK_BASE_URL: "http://localhost:4401",
    EVOLUTION_WEBHOOK_SECRET: randomBytes(32).toString("hex"),
    MEDIA_STORAGE_DRIVER: "local",
    MEDIA_STORAGE_PATH: mediaDir,
    TYPEBOT_ENABLED: "false"
  });

  run("pnpm", ["db:generate"]);
  run("pnpm", ["--filter", "@wapp/api", "db:deploy"]);
  run("pnpm", [
    "--filter", "@wapp/api", "exec", "tsx", "--test",
    "src/integration/critical.integration.test.ts",
    "src/integration/data-quality.integration.test.ts"
  ]);

  console.log("[integration] PASS");
} finally {
  cleanup();
}
