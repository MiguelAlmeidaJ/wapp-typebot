import { chmodSync, copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";

const root = resolve(new URL("..", import.meta.url).pathname);
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

mkdirSync(dirname(target), { recursive: true });
copyFileSync(source, target);

try {
  chmodSync(target, 0o600);
} catch {
  // chmod may not be supported on every development filesystem.
}

console.log(`[prod:init] PASS — created ${target}`);
console.log("[prod:init] Replace every CHANGE_ME value before running pnpm prod:preflight.");
