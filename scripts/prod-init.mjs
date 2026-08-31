import {
  chmod,
  copyFile,
  stat
} from "node:fs/promises";

const source =
  "infra/production/.env.production.example";

const destination =
  "infra/production/.env.production";

try {
  await stat(
    destination
  );

  console.error(
    `[prod:init] REFUSED — ${destination} already exists.`
  );

  process.exitCode =
    1;
} catch (error) {
  if (
    error &&
    typeof error ===
      "object" &&
    "code" in error &&
    error.code !==
      "ENOENT"
  ) {
    throw error;
  }

  await copyFile(
    source,
    destination
  );

  if (
    process.platform !==
    "win32"
  ) {
    await chmod(
      destination,
      0o600
    );
  }

  console.log(
    `[prod:init] Created ${destination}.`
  );

  console.log(
    "[prod:init] Replace every CHANGE_ME value, then run pnpm prod:preflight."
  );
}
