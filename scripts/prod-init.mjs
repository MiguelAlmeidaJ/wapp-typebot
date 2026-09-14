import { randomBytes } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = resolve(root, "infra/pm2/production.env.example");
const target = resolve(
  root,
  process.env.WAPP_ENV_FILE || "infra/pm2/production.env"
);

if (!existsSync(source)) {
  throw new Error(`Production env template not found: ${source}`);
}

if (existsSync(target)) {
  console.log(`[prod:init] SKIP — ${target} already exists.`);
  process.exit(0);
}

function secret() {
  return randomBytes(32).toString("hex");
}

let content = readFileSync(source, "utf8");
content = content
  .replace("JWT_SECRET=CHANGE_ME_AT_LEAST_32_CHARACTERS", `JWT_SECRET=${secret()}`)
  .replace("METRICS_TOKEN=CHANGE_ME_AT_LEAST_32_CHARACTERS", `METRICS_TOKEN=${secret()}`)
  .replace(
    "EVOLUTION_WEBHOOK_SECRET=CHANGE_ME_AT_LEAST_32_CHARACTERS",
    `EVOLUTION_WEBHOOK_SECRET=${secret()}`
  );

mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, content, { encoding: "utf8", mode: 0o600 });

try {
  chmodSync(target, 0o600);
} catch {
  // chmod may not be supported on every development filesystem.
}

console.log(`[prod:init] PASS — created ${target}`);
console.log("[prod:init] Generated JWT_SECRET, METRICS_TOKEN and EVOLUTION_WEBHOOK_SECRET.");
console.log("[prod:init] Replace every remaining CHANGE_ME value before running pnpm prod:preflight.");
