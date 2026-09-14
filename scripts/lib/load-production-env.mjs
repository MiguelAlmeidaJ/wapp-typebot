import { readFileSync } from "node:fs";
import { parseEnv } from "node:util";

export function loadProductionEnv(path) {
  const parsed = parseEnv(readFileSync(path, "utf8"));

  for (const [key, value] of Object.entries(parsed)) {
    process.env[key] = value;
  }

  return parsed;
}
