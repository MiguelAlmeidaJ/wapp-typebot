import {
  readFile
} from "node:fs/promises";

const compose =
  await readFile(
    "infra/production/docker-compose.yml",
    "utf8"
  );

const dockerfile =
  await readFile(
    "infra/production/api.Dockerfile",
    "utf8"
  );

const gitignore =
  await readFile(
    ".gitignore",
    "utf8"
  );

const preflight =
  await readFile(
    "scripts/prod-preflight.mjs",
    "utf8"
  );

const packageJson =
  JSON.parse(
    await readFile(
      "package.json",
      "utf8"
    )
  );

for (
  const marker
  of [
    "SHADOW_DATABASE_URL: ${SHADOW_DATABASE_URL}",
    "image: wapp-api-runtime:${WAPP_IMAGE_TAG}",
    "image: wapp-api-migrate:${WAPP_IMAGE_TAG}",
    "environment:\n      REDIS_PASSWORD: ${REDIS_PASSWORD}"
  ]
) {
  if (
    !compose.includes(
      marker
    )
  ) {
    throw new Error(
      `RH1 compose marker missing: ${marker}`
    );
  }
}

const redisStart =
  compose.indexOf(
    "  redis:\n"
  );

const migrateStart =
  compose.indexOf(
    "  migrate:\n"
  );

const redisBlock =
  compose.slice(
    redisStart,
    migrateStart
  );

const redisHealth =
  redisBlock.indexOf(
    "    healthcheck:\n"
  );

const redisEnvironment =
  redisBlock.indexOf(
    "    environment:\n"
  );

if (
  redisEnvironment <
    0 ||
  redisHealth <
    0 ||
  redisEnvironment >
    redisHealth
) {
  throw new Error(
    "Redis environment is still nested under/after healthcheck."
  );
}

if (
  compose.includes(
    "image: wapp-api:${WAPP_IMAGE_TAG:-local}"
  )
) {
  throw new Error(
    "Runtime/migrate image collision still exists."
  );
}

for (
  const marker
  of [
    "ARG PRISMA_BUILD_DATABASE_URL=",
    "ARG PRISMA_BUILD_SHADOW_DATABASE_URL=",
    'DATABASE_URL="$PRISMA_BUILD_DATABASE_URL" SHADOW_DATABASE_URL="$PRISMA_BUILD_SHADOW_DATABASE_URL"'
  ]
) {
  if (
    !dockerfile.includes(
      marker
    )
  ) {
    throw new Error(
      `RH1 Dockerfile marker missing: ${marker}`
    );
  }
}

if (
  !gitignore.includes(
    "!infra/production/.env.production.example"
  )
) {
  throw new Error(
    "Production env example is still ignored by Git."
  );
}

for (
  const marker
  of [
    '"METRICS_TOKEN"',
    '"SHADOW_DATABASE_URL"',
    '"MAINTENANCE_ENABLED"',
    '"SESSION_RETENTION_DAYS"',
    '"WAPP_IMAGE_TAG"'
  ]
) {
  if (
    !preflight.includes(
      marker
    )
  ) {
    throw new Error(
      `RH1 preflight marker missing: ${marker}`
    );
  }
}

if (
  packageJson.scripts[
    "prod:config"
  ] !==
    "bash scripts/prod-config.sh"
) {
  throw new Error(
    "prod:config does not use the hardened config script."
  );
}

console.log(
  "[RH1] production config smoke PASS"
);
