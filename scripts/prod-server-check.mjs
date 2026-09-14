import { accessSync, constants, existsSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { lookup } from "node:dns/promises";
import { connect } from "node:net";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const envFile = resolve(
  root,
  process.env.WAPP_ENV_FILE || "infra/pm2/production.env"
);

const errors = [];
const warnings = [];
const passes = [];

function pass(message) {
  passes.push(message);
}

function fail(message) {
  errors.push(message);
}

function warn(message) {
  warnings.push(message);
}

function commandExists(command, args = ["--version"]) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "ignore",
    shell: false
  });

  if (result.error || result.status !== 0) {
    fail(`${command} is not available in PATH.`);
    return false;
  }

  pass(`${command} is available.`);
  return true;
}

function parseUrl(name, protocols) {
  const value = process.env[name]?.trim();
  if (!value) {
    fail(`${name} is required.`);
    return null;
  }

  try {
    const parsed = new URL(value);
    if (!protocols.includes(parsed.protocol)) {
      fail(`${name} must use ${protocols.join(" or ")}.`);
      return null;
    }
    return parsed;
  } catch {
    fail(`${name} must be a valid URL.`);
    return null;
  }
}

function tcpCheck(host, port, label, timeoutMs = 5_000) {
  return new Promise(resolvePromise => {
    const socket = connect({ host, port: Number(port) });
    let settled = false;

    const finish = (ok, detail) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      if (ok) pass(`${label} reachable at ${host}:${port}.`);
      else fail(`${label} is not reachable at ${host}:${port}${detail ? ` — ${detail}` : ""}.`);
      resolvePromise();
    };

    socket.setTimeout(timeoutMs);
    socket.once("connect", () => finish(true));
    socket.once("timeout", () => finish(false, "timeout"));
    socket.once("error", error => finish(false, error.message));
  });
}

function checkReadable(path, label) {
  try {
    accessSync(path, constants.R_OK);
    pass(`${label} is readable: ${path}`);
  } catch {
    fail(`${label} is not readable: ${path}`);
  }
}

if (!existsSync(envFile)) {
  console.error(`[prod:server:check] FAIL — environment file not found: ${envFile}`);
  console.error("Run pnpm prod:init first.");
  process.exit(1);
}

process.loadEnvFile(envFile);

if (process.platform !== "linux") {
  warn(`Production target is Linux; current platform is ${process.platform}.`);
} else {
  pass("Linux host detected.");
}

const nodeMajor = Number(process.versions.node.split(".")[0]);
if (nodeMajor !== 24) {
  fail(`Node.js 24 is required. Current version: ${process.version}`);
} else {
  pass(`Node.js ${process.version} detected.`);
}

commandExists("git");
commandExists("pnpm");
const pm2Available = commandExists("pm2");

if (process.platform !== "win32") {
  try {
    const mode = statSync(envFile).mode & 0o777;
    if ((mode & 0o077) !== 0) {
      fail(`${envFile} permissions are ${mode.toString(8)}; use chmod 600.`);
    } else {
      pass(`Environment file permissions are ${mode.toString(8)}.`);
    }
  } catch (error) {
    fail(`Could not inspect environment file permissions: ${error.message}`);
  }
}

const tlsCaPath = process.env.DATABASE_TLS_CA_PATH?.trim();
if (!tlsCaPath) {
  fail("DATABASE_TLS_CA_PATH is required.");
} else if (!existsSync(tlsCaPath)) {
  fail(`MySQL CA certificate does not exist: ${tlsCaPath}`);
} else {
  checkReadable(tlsCaPath, "MySQL CA certificate");
}

if (process.env.MEDIA_STORAGE_DRIVER === "local") {
  const mediaPath = process.env.MEDIA_STORAGE_PATH?.trim();
  if (!mediaPath) {
    fail("MEDIA_STORAGE_PATH is required when MEDIA_STORAGE_DRIVER=local.");
  } else if (!mediaPath.startsWith("/")) {
    fail("MEDIA_STORAGE_PATH must be absolute in production.");
  } else if (!existsSync(mediaPath)) {
    fail(`Local media directory does not exist: ${mediaPath}`);
  } else {
    try {
      accessSync(mediaPath, constants.R_OK | constants.W_OK | constants.X_OK);
      pass(`Local media directory is readable and writable: ${mediaPath}`);
    } catch {
      fail(`Local media directory is not readable/writable by the deploy user: ${mediaPath}`);
    }
  }
}

const databaseUrl = parseUrl("DATABASE_URL", ["mysql:"]);
const redisUrl = parseUrl("REDIS_URL", ["redis:", "rediss:"]);
const evolutionUrl = parseUrl("EVOLUTION_BASE_URL", ["http:", "https:"]);
const webUrl = parseUrl("WEB_URL", ["https:"]);

const checks = [];

if (databaseUrl) {
  checks.push(tcpCheck(databaseUrl.hostname, databaseUrl.port || 3306, "MySQL"));
}

if (redisUrl) {
  checks.push(tcpCheck(redisUrl.hostname, redisUrl.port || 6379, "Redis"));
}

if (evolutionUrl) {
  checks.push(
    tcpCheck(
      evolutionUrl.hostname,
      evolutionUrl.port || (evolutionUrl.protocol === "https:" ? 443 : 80),
      "Evolution API"
    )
  );
}

if (process.env.TYPEBOT_ENABLED === "true") {
  const typebotUrl = parseUrl("TYPEBOT_API_URL", ["http:", "https:"]);
  if (typebotUrl) {
    checks.push(
      tcpCheck(
        typebotUrl.hostname,
        typebotUrl.port || (typebotUrl.protocol === "https:" ? 443 : 80),
        "Typebot API"
      )
    );
  }
}

if (webUrl) {
  try {
    const addresses = await lookup(webUrl.hostname, { all: true });
    if (addresses.length === 0) {
      warn(`DNS lookup returned no address for ${webUrl.hostname}.`);
    } else {
      pass(`DNS resolves ${webUrl.hostname} to ${addresses.map(item => item.address).join(", ")}.`);
    }
  } catch (error) {
    warn(`DNS does not resolve ${webUrl.hostname} yet — ${error.message}`);
  }
}

await Promise.all(checks);

await new Promise(resolvePromise => {
  const socket = connect({ host: "127.0.0.1", port: 443 });
  let settled = false;
  const finish = ok => {
    if (settled) return;
    settled = true;
    socket.destroy();
    if (ok) pass("A reverse proxy appears to be listening on 127.0.0.1:443.");
    else warn("Nothing is listening on 127.0.0.1:443 yet. Configure the HTTPS reverse proxy before the final smoke test.");
    resolvePromise();
  };
  socket.setTimeout(1_500);
  socket.once("connect", () => finish(true));
  socket.once("timeout", () => finish(false));
  socket.once("error", () => finish(false));
});

if (pm2Available && process.platform === "linux" && process.env.USER) {
  const service = `pm2-${process.env.USER}`;
  const result = spawnSync("systemctl", ["is-enabled", service], {
    stdio: "ignore",
    shell: false
  });

  if (result.status === 0) {
    pass(`PM2 startup service is enabled: ${service}`);
  } else {
    warn(`PM2 startup persistence is not enabled for ${process.env.USER}. Run pm2 startup, execute the command it prints, then pm2 save.`);
  }
}

for (const message of passes) {
  console.log(`[prod:server:check] PASS — ${message}`);
}

for (const message of warnings) {
  console.warn(`[prod:server:check] WARN — ${message}`);
}

if (errors.length > 0) {
  for (const message of errors) {
    console.error(`[prod:server:check] FAIL — ${message}`);
  }
  console.error(`[prod:server:check] ${errors.length} blocking issue(s) found.`);
  process.exit(1);
}

console.log(`[prod:server:check] PASS — server prerequisites are ready for deployment.`);
