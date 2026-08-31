#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE="infra/production/docker-compose.yml"
DOCKERFILE="infra/production/api.Dockerfile"
GITIGNORE=".gitignore"
PACKAGE="package.json"
PREFLIGHT="scripts/prod-preflight.mjs"
ENV_EXAMPLE="infra/production/.env.production.example"
ENV_REAL="infra/production/.env.production"

echo "[RH1] Installing production Compose + environment hardening..."

for check in \
  "$COMPOSE|name: wapp-production" \
  "$COMPOSE|image: wapp-api:\${WAPP_IMAGE_TAG:-local}" \
  "$COMPOSE|REDIS_PASSWORD: \${REDIS_PASSWORD}" \
  "$DOCKERFILE|pnpm --filter @wapp/api db:generate" \
  "$GITIGNORE|infra/production/.env.production" \
  "$PACKAGE|\"prod:preflight\"" \
  "$PREFLIGHT|[prod:preflight]"
do
  file="${check%%|*}"
  marker="${check#*|}"

  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: RH1 prerequisite missing:"
    echo "  $file -> $marker"
    echo "RH1 made no changes."
    exit 1
  fi
done

mkdir -p infra/production docs scripts

node <<'NODE'
const fs = require("node:fs");
const path = ".gitignore";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
const realEnvRule = "infra/production/.env.production";
const exampleRule = "!infra/production/.env.production.example";

if (!content.includes(realEnvRule)) {
  throw new Error("Production env ignore rule not found.");
}

if (!content.includes(exampleRule)) {
  content = content.replace(
    `${realEnvRule}\n`,
    `${realEnvRule}\n${exampleRule}\n`
  );
}

fs.writeFileSync(path, content);
console.log("[RH1] Production env example is explicitly trackable.");
NODE

cat > "$ENV_EXAMPLE" <<'EOF'
# Wapp production environment template
#
# Copy with:
#   pnpm prod:init
#
# NEVER commit infra/production/.env.production.
# Replace every CHANGE_ME value before running prod:preflight.
#
# If a password contains URL-reserved characters, URL-encode the password
# inside DATABASE_URL / SHADOW_DATABASE_URL / REDIS_URL.

WAPP_DOMAIN=CHANGE_ME.example.com
WAPP_IMAGE_TAG=CHANGE_ME_RELEASE_TAG

MYSQL_DATABASE=wapp
MYSQL_USER=wapp
MYSQL_PASSWORD=CHANGE_ME_MYSQL_PASSWORD_AT_LEAST_16_CHARS
MYSQL_ROOT_PASSWORD=CHANGE_ME_MYSQL_ROOT_PASSWORD_AT_LEAST_16_CHARS
DATABASE_URL=mysql://wapp:CHANGE_ME_MYSQL_PASSWORD_AT_LEAST_16_CHARS@mysql:3306/wapp
SHADOW_DATABASE_URL=mysql://wapp:CHANGE_ME_MYSQL_PASSWORD_AT_LEAST_16_CHARS@mysql:3306/wapp_shadow

REDIS_PASSWORD=CHANGE_ME_REDIS_PASSWORD_AT_LEAST_16_CHARS
REDIS_URL=redis://:CHANGE_ME_REDIS_PASSWORD_AT_LEAST_16_CHARS@redis:6379/0

API_BODY_MAX_BYTES=1048576
JWT_SECRET=CHANGE_ME_JWT_SECRET_AT_LEAST_32_CHARACTERS_LONG
METRICS_TOKEN=CHANGE_ME_METRICS_TOKEN_AT_LEAST_32_CHARACTERS
ACCESS_TOKEN_TTL_SECONDS=900
REFRESH_TOKEN_TTL_DAYS=30

EVOLUTION_BASE_URL=https://CHANGE_ME_EVOLUTION_HOST
EVOLUTION_API_KEY=CHANGE_ME_EVOLUTION_API_KEY_AT_LEAST_32_CHARACTERS
EVOLUTION_WEBHOOK_SECRET=CHANGE_ME_WEBHOOK_SECRET_AT_LEAST_32_CHARACTERS
EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS=60

MEDIA_MAX_BYTES=26214400
S3_BUCKET=CHANGE_ME_PRIVATE_BUCKET
S3_REGION=us-east-1
S3_ENDPOINT=https://CHANGE_ME_S3_ENDPOINT
S3_FORCE_PATH_STYLE=false
S3_ACCESS_KEY_ID=CHANGE_ME_S3_ACCESS_KEY_ID
S3_SECRET_ACCESS_KEY=CHANGE_ME_S3_SECRET_ACCESS_KEY

JOBS_MEDIA_CAPTURE_CONCURRENCY=4
JOBS_MEDIA_CAPTURE_ATTEMPTS=5

MAINTENANCE_ENABLED=true
MAINTENANCE_INTERVAL_HOURS=6
SESSION_RETENTION_DAYS=30
MAINTENANCE_STALE_MEDIA_MINUTES=30

TYPEBOT_URL=
EOF

node <<'NODE'
const fs = require("node:fs");
const path = "infra/production/docker-compose.yml";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("  SHADOW_DATABASE_URL: ${SHADOW_DATABASE_URL}")) {
  const anchor = "  DATABASE_URL: ${DATABASE_URL}\n";
  if (!content.includes(anchor)) {
    throw new Error("DATABASE_URL compose anchor not found.");
  }
  content = content.replace(
    anchor,
    `${anchor}  SHADOW_DATABASE_URL: \${SHADOW_DATABASE_URL}\n`
  );
}

const badRedisHealthEnvironment = `      environment:
        REDIS_PASSWORD: \${REDIS_PASSWORD}
`;

if (content.includes(badRedisHealthEnvironment)) {
  content = content.replace(badRedisHealthEnvironment, "");
}

const redisServiceAnchor = `  redis:
    image: redis:7-alpine
    restart: unless-stopped
`;

const redisEnvironment = `  redis:
    image: redis:7-alpine
    restart: unless-stopped
    environment:
      REDIS_PASSWORD: \${REDIS_PASSWORD}
`;

if (content.includes(redisServiceAnchor)) {
  content = content.replace(redisServiceAnchor, redisEnvironment);
} else if (!content.includes(redisEnvironment)) {
  throw new Error("Redis service anchor not found.");
}

const oldImage = "    image: wapp-api:${WAPP_IMAGE_TAG:-local}";
const runtimeImage = "    image: wapp-api-runtime:${WAPP_IMAGE_TAG}";
const migrateImage = "    image: wapp-api-migrate:${WAPP_IMAGE_TAG}";

function replaceServiceImage(serviceName, nextServiceName, replacement) {
  const start = content.indexOf(`  ${serviceName}:\n`);
  const end = content.indexOf(`  ${nextServiceName}:\n`, start);
  if (start < 0 || end < 0) {
    throw new Error(`${serviceName} service boundaries not found.`);
  }

  let block = content.slice(start, end);
  if (!block.includes(replacement)) {
    if (!block.includes(oldImage)) {
      throw new Error(`${serviceName} old image anchor not found.`);
    }
    block = block.replace(oldImage, replacement);
    content = content.slice(0, start) + block + content.slice(end);
  }
}

replaceServiceImage("migrate", "api", migrateImage);
replaceServiceImage("api", "worker", runtimeImage);
replaceServiceImage("worker", "web", runtimeImage);

if (content.includes("image: wapp-api:${WAPP_IMAGE_TAG:-local}")) {
  throw new Error("Legacy shared API image tag still exists.");
}

const redisStart = content.indexOf("  redis:\n");
const migrateStart = content.indexOf("  migrate:\n");
const redisBlock = content.slice(redisStart, migrateStart);
const healthIndex = redisBlock.indexOf("    healthcheck:\n");
const envIndex = redisBlock.indexOf("    environment:\n");

if (envIndex < 0 || healthIndex < 0 || envIndex > healthIndex) {
  throw new Error("Redis environment is not at service level.");
}

fs.writeFileSync(path, content);
console.log("[RH1] Production Compose structure fixed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "infra/production/api.Dockerfile";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("ARG PRISMA_BUILD_DATABASE_URL=")) {
  const anchor = `COPY packages/contracts packages/contracts

RUN pnpm --filter @wapp/contracts build \\
`;
  if (!content.includes(anchor)) {
    throw new Error("API Dockerfile build anchor not found.");
  }

  content = content.replace(
    anchor,
    `COPY packages/contracts packages/contracts

# Prisma 7 loads prisma.config.ts during client generation. These URLs are
# build-only placeholders; prisma generate does not connect to the database.
ARG PRISMA_BUILD_DATABASE_URL=mysql://build:build@127.0.0.1:3306/build
ARG PRISMA_BUILD_SHADOW_DATABASE_URL=mysql://build:build@127.0.0.1:3306/build_shadow

RUN pnpm --filter @wapp/contracts build \\
`
  );
}

const oldGenerate = `  && pnpm --filter @wapp/api db:generate \\
`;

const newGenerate =
  `  && DATABASE_URL="$PRISMA_BUILD_DATABASE_URL" SHADOW_DATABASE_URL="$PRISMA_BUILD_SHADOW_DATABASE_URL" pnpm --filter @wapp/api db:generate \\
`;

if (content.includes(oldGenerate)) {
  content = content.replace(oldGenerate, newGenerate);
} else if (!content.includes(newGenerate)) {
  throw new Error("Prisma generate Dockerfile command not found.");
}

fs.writeFileSync(path, content);
console.log("[RH1] Prisma Docker build environment hardened.");
NODE

cat > "$PREFLIGHT" <<'EOF'
import {
  stat
} from "node:fs/promises";
import {
  readFile
} from "node:fs/promises";
import {
  resolve
} from "node:path";

const envPath =
  resolve(
    process.cwd(),
    process.env.WAPP_PROD_ENV ??
      "infra/production/.env.production"
  );

const placeholderPattern =
  /CHANGE_ME|REPLACE_ME|YOUR_[A-Z0-9_]+|example\.com/i;

function fail(
  message
) {
  throw new Error(
    message
  );
}

function parseEnv(
  source
) {
  const values =
    {};

  const duplicates =
    new Set();

  for (
    const rawLine
    of source.split(
      /\r?\n/
    )
  ) {
    const line =
      rawLine.trim();

    if (
      !line ||
      line.startsWith(
        "#"
      )
    ) {
      continue;
    }

    const separator =
      line.indexOf(
        "="
      );

    if (
      separator <
      1
    ) {
      continue;
    }

    const key =
      line.slice(
        0,
        separator
      ).trim();

    let value =
      line.slice(
        separator +
          1
      ).trim();

    if (
      (
        value.startsWith(
          '"'
        ) &&
        value.endsWith(
          '"'
        )
      ) ||
      (
        value.startsWith(
          "'"
        ) &&
        value.endsWith(
          "'"
        )
      )
    ) {
      value =
        value.slice(
          1,
          -1
        );
    }

    if (
      Object.hasOwn(
        values,
        key
      )
    ) {
      duplicates.add(
        key
      );
    }

    values[
      key
    ] =
      value;
  }

  if (
    duplicates.size >
    0
  ) {
    fail(
      `Duplicate environment keys: ${[
        ...duplicates
      ].join(", ")}`
    );
  }

  return values;
}

function required(
  env,
  key
) {
  const value =
    env[
      key
    ];

  if (
    !value ||
    placeholderPattern.test(
      value
    )
  ) {
    fail(
      `${key} is missing or still contains a placeholder.`
    );
  }

  return value;
}

function strongSecret(
  env,
  key,
  minimum
) {
  const value =
    required(
      env,
      key
    );

  if (
    value.length <
    minimum
  ) {
    fail(
      `${key} must contain at least ${minimum} characters.`
    );
  }

  return value;
}

function integerInRange(
  env,
  key,
  minimum,
  maximum
) {
  const raw =
    required(
      env,
      key
    );

  if (
    !/^\d+$/.test(
      raw
    )
  ) {
    fail(
      `${key} must be an integer.`
    );
  }

  const value =
    Number(
      raw
    );

  if (
    !Number.isSafeInteger(
      value
    ) ||
    value <
      minimum ||
    value >
      maximum
  ) {
    fail(
      `${key} must be between ${minimum} and ${maximum}.`
    );
  }

  return value;
}

function booleanValue(
  env,
  key
) {
  const value =
    required(
      env,
      key
    );

  if (
    ![
      "true",
      "false"
    ].includes(
      value
    )
  ) {
    fail(
      `${key} must be true or false.`
    );
  }

  return value ===
    "true";
}

function webUrl(
  env,
  key,
  {
    allowHttp =
      true,
    allowEmpty =
      false
  } = {}
) {
  const raw =
    env[
      key
    ] ??
    "";

  if (
    allowEmpty &&
    !raw
  ) {
    return null;
  }

  const value =
    required(
      env,
      key
    );

  let url;

  try {
    url =
      new URL(
        value
      );
  } catch {
    fail(
      `${key} must be a valid URL.`
    );
  }

  const protocols =
    allowHttp
      ? [
          "http:",
          "https:"
        ]
      : [
          "https:"
        ];

  if (
    !protocols.includes(
      url.protocol
    )
  ) {
    fail(
      `${key} must use ${allowHttp ? "http or https" : "https"}.`
    );
  }

  if (
    /localhost|127\.0\.0\.1|0\.0\.0\.0/i.test(
      url.hostname
    )
  ) {
    fail(
      `${key} must not point to localhost in production.`
    );
  }

  return url;
}

function sameBundledMysqlCredentials(
  url,
  {
    user,
    password
  }
) {
  return (
    url.protocol ===
      "mysql:" &&
    url.hostname ===
      "mysql" &&
    decodeURIComponent(
      url.username
    ) ===
      user &&
    decodeURIComponent(
      url.password
    ) ===
      password
  );
}

try {
  const source =
    await readFile(
      envPath,
      "utf8"
    );

  const env =
    parseEnv(
      source
    );

  if (
    process.platform !==
    "win32"
  ) {
    const info =
      await stat(
        envPath
      );

    if (
      (
        info.mode &
        0o077
      ) !==
      0
    ) {
      console.warn(
        "[prod:preflight] WARN: production env is readable by group/other users. Prefer chmod 600."
      );
    }
  }

  const domain =
    required(
      env,
      "WAPP_DOMAIN"
    );

  if (
    domain.includes(
      "://"
    ) ||
    domain.includes(
      "/"
    ) ||
    /\s/.test(
      domain
    ) ||
    /localhost|127\.0\.0\.1/i.test(
      domain
    ) ||
    !/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(
      domain
    )
  ) {
    fail(
      "WAPP_DOMAIN must be a real hostname without protocol or path."
    );
  }

  const imageTag =
    required(
      env,
      "WAPP_IMAGE_TAG"
    );

  if (
    !/^[A-Za-z0-9._-]+$/.test(
      imageTag
    ) ||
    /^(latest|local)$/i.test(
      imageTag
    )
  ) {
    fail(
      "WAPP_IMAGE_TAG must be an immutable release tag, not local/latest."
    );
  }

  const mysqlDatabase =
    required(
      env,
      "MYSQL_DATABASE"
    );

  const mysqlUser =
    required(
      env,
      "MYSQL_USER"
    );

  const mysqlPassword =
    strongSecret(
      env,
      "MYSQL_PASSWORD",
      16
    );

  strongSecret(
    env,
    "MYSQL_ROOT_PASSWORD",
    16
  );

  const databaseUrl =
    new URL(
      required(
        env,
        "DATABASE_URL"
      )
    );

  if (
    !sameBundledMysqlCredentials(
      databaseUrl,
      {
        user:
          mysqlUser,
        password:
          mysqlPassword
      }
    ) ||
    databaseUrl.pathname
      .replace(
        /^\/+/,
        ""
      ) !==
      mysqlDatabase
  ) {
    fail(
      "DATABASE_URL must match the bundled mysql service credentials/database."
    );
  }

  const shadowUrl =
    new URL(
      required(
        env,
        "SHADOW_DATABASE_URL"
      )
    );

  if (
    !sameBundledMysqlCredentials(
      shadowUrl,
      {
        user:
          mysqlUser,
        password:
          mysqlPassword
      }
    )
  ) {
    fail(
      "SHADOW_DATABASE_URL must use the bundled mysql service credentials."
    );
  }

  const shadowDatabase =
    shadowUrl.pathname
      .replace(
        /^\/+/,
        ""
      );

  if (
    !shadowDatabase ||
    shadowDatabase ===
      mysqlDatabase
  ) {
    fail(
      "SHADOW_DATABASE_URL must name a database different from MYSQL_DATABASE."
    );
  }

  const redisPassword =
    strongSecret(
      env,
      "REDIS_PASSWORD",
      16
    );

  const redisUrl =
    new URL(
      required(
        env,
        "REDIS_URL"
      )
    );

  if (
    ![
      "redis:",
      "rediss:"
    ].includes(
      redisUrl.protocol
    ) ||
    redisUrl.hostname !==
      "redis" ||
    decodeURIComponent(
      redisUrl.password
    ) !==
      redisPassword
  ) {
    fail(
      "REDIS_URL must match the bundled redis service password."
    );
  }

  strongSecret(
    env,
    "JWT_SECRET",
    32
  );

  strongSecret(
    env,
    "METRICS_TOKEN",
    32
  );

  integerInRange(
    env,
    "API_BODY_MAX_BYTES",
    65_536,
    52_428_800
  );

  integerInRange(
    env,
    "ACCESS_TOKEN_TTL_SECONDS",
    60,
    86_400
  );

  integerInRange(
    env,
    "REFRESH_TOKEN_TTL_DAYS",
    1,
    365
  );

  webUrl(
    env,
    "EVOLUTION_BASE_URL"
  );

  strongSecret(
    env,
    "EVOLUTION_API_KEY",
    32
  );

  strongSecret(
    env,
    "EVOLUTION_WEBHOOK_SECRET",
    32
  );

  integerInRange(
    env,
    "EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS",
    15,
    3_600
  );

  integerInRange(
    env,
    "MEDIA_MAX_BYTES",
    1_024,
    104_857_600
  );

  required(
    env,
    "S3_BUCKET"
  );

  required(
    env,
    "S3_REGION"
  );

  required(
    env,
    "S3_ACCESS_KEY_ID"
  );

  strongSecret(
    env,
    "S3_SECRET_ACCESS_KEY",
    16
  );

  webUrl(
    env,
    "S3_ENDPOINT",
    {
      allowHttp:
        true,
      allowEmpty:
        true
    }
  );

  booleanValue(
    env,
    "S3_FORCE_PATH_STYLE"
  );

  integerInRange(
    env,
    "JOBS_MEDIA_CAPTURE_CONCURRENCY",
    1,
    32
  );

  integerInRange(
    env,
    "JOBS_MEDIA_CAPTURE_ATTEMPTS",
    1,
    20
  );

  booleanValue(
    env,
    "MAINTENANCE_ENABLED"
  );

  integerInRange(
    env,
    "MAINTENANCE_INTERVAL_HOURS",
    1,
    168
  );

  integerInRange(
    env,
    "SESSION_RETENTION_DAYS",
    7,
    365
  );

  integerInRange(
    env,
    "MAINTENANCE_STALE_MEDIA_MINUTES",
    5,
    1_440
  );

  webUrl(
    env,
    "TYPEBOT_URL",
    {
      allowHttp:
        true,
      allowEmpty:
        true
    }
  );

  console.log(
    `[prod:preflight] PASS — https://${domain}`
  );

  console.log(
    "[prod:preflight] Compose credentials, Prisma URLs, auth, metrics, Evolution, S3, jobs and maintenance configuration look consistent."
  );
} catch (error) {
  console.error(
    "[prod:preflight] FAIL:",
    error instanceof Error
      ? error.message
      : error
  );

  console.error(
    "[prod:preflight] No containers were changed."
  );

  process.exitCode =
    1;
}
EOF

cat > scripts/prod-env-template-check.mjs <<'EOF'
import {
  readFile
} from "node:fs/promises";

const path =
  "infra/production/.env.production.example";

const requiredKeys =
  [
    "WAPP_DOMAIN",
    "WAPP_IMAGE_TAG",
    "MYSQL_DATABASE",
    "MYSQL_USER",
    "MYSQL_PASSWORD",
    "MYSQL_ROOT_PASSWORD",
    "DATABASE_URL",
    "SHADOW_DATABASE_URL",
    "REDIS_PASSWORD",
    "REDIS_URL",
    "API_BODY_MAX_BYTES",
    "JWT_SECRET",
    "METRICS_TOKEN",
    "ACCESS_TOKEN_TTL_SECONDS",
    "REFRESH_TOKEN_TTL_DAYS",
    "EVOLUTION_BASE_URL",
    "EVOLUTION_API_KEY",
    "EVOLUTION_WEBHOOK_SECRET",
    "EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS",
    "MEDIA_MAX_BYTES",
    "S3_BUCKET",
    "S3_REGION",
    "S3_ENDPOINT",
    "S3_FORCE_PATH_STYLE",
    "S3_ACCESS_KEY_ID",
    "S3_SECRET_ACCESS_KEY",
    "JOBS_MEDIA_CAPTURE_CONCURRENCY",
    "JOBS_MEDIA_CAPTURE_ATTEMPTS",
    "MAINTENANCE_ENABLED",
    "MAINTENANCE_INTERVAL_HOURS",
    "SESSION_RETENTION_DAYS",
    "MAINTENANCE_STALE_MEDIA_MINUTES",
    "TYPEBOT_URL"
  ];

const placeholderKeys =
  [
    "WAPP_DOMAIN",
    "WAPP_IMAGE_TAG",
    "MYSQL_PASSWORD",
    "MYSQL_ROOT_PASSWORD",
    "DATABASE_URL",
    "SHADOW_DATABASE_URL",
    "REDIS_PASSWORD",
    "REDIS_URL",
    "JWT_SECRET",
    "METRICS_TOKEN",
    "EVOLUTION_BASE_URL",
    "EVOLUTION_API_KEY",
    "EVOLUTION_WEBHOOK_SECRET",
    "S3_BUCKET",
    "S3_ENDPOINT",
    "S3_ACCESS_KEY_ID",
    "S3_SECRET_ACCESS_KEY"
  ];

const source =
  await readFile(
    path,
    "utf8"
  );

const values =
  new Map();

const duplicates =
  new Set();

for (
  const rawLine
  of source.split(
    /\r?\n/
  )
) {
  const line =
    rawLine.trim();

  if (
    !line ||
    line.startsWith(
      "#"
    )
  ) {
    continue;
  }

  const separator =
    line.indexOf(
      "="
    );

  if (
    separator <
    1
  ) {
    throw new Error(
      `Malformed template line: ${line}`
    );
  }

  const key =
    line.slice(
      0,
      separator
    ).trim();

  const value =
    line.slice(
      separator +
        1
    ).trim();

  if (
    values.has(
      key
    )
  ) {
    duplicates.add(
      key
    );
  }

  values.set(
    key,
    value
  );
}

if (
  duplicates.size >
  0
) {
  throw new Error(
    `Duplicate template keys: ${[
      ...duplicates
    ].join(", ")}`
  );
}

const missing =
  requiredKeys.filter(
    key =>
      !values.has(
        key
      )
  );

if (
  missing.length >
  0
) {
  throw new Error(
    `Missing template keys: ${missing.join(", ")}`
  );
}

for (
  const key
  of placeholderKeys
) {
  if (
    !/CHANGE_ME/i.test(
      values.get(
        key
      ) ??
      ""
    )
  ) {
    throw new Error(
      `${key} must remain an obvious CHANGE_ME placeholder in the tracked template.`
    );
  }
}

if (
  values.get(
    "TYPEBOT_URL"
  ) !==
  ""
) {
  throw new Error(
    "TYPEBOT_URL must remain empty in the production template until Typebot is formally enabled."
  );
}

console.log(
  `[prod:template] PASS — ${requiredKeys.length} keys present; tracked secrets remain placeholders.`
);
EOF

cat > scripts/prod-init.mjs <<'EOF'
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
EOF

cat > scripts/prod-config.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${WAPP_PROD_ENV:-infra/production/.env.production}"
COMPOSE_FILE="infra/production/docker-compose.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing $ENV_FILE"
  echo "Run pnpm prod:init or provide WAPP_PROD_ENV."
  exit 1
fi

echo "[prod:config] Preflight..."
WAPP_PROD_ENV="$ENV_FILE" node scripts/prod-preflight.mjs

echo "[prod:config] Compose config..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  config \
  --quiet

echo "[prod:config] PASS — production Compose is structurally valid."
EOF

chmod +x scripts/prod-config.sh

node <<'NODE'
const fs = require("node:fs");
const path = "package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));

pkg.scripts ??= {};
pkg.scripts["prod:init"] = "node scripts/prod-init.mjs";
pkg.scripts["prod:template"] = "node scripts/prod-env-template-check.mjs";
pkg.scripts["prod:preflight"] = "node scripts/prod-preflight.mjs";
pkg.scripts["prod:config"] = "bash scripts/prod-config.sh";

fs.writeFileSync(
  path,
  `${JSON.stringify(pkg, null, 2)}\n`
);

console.log("[RH1] Production package scripts synchronized.");
NODE

cat > scripts/rh1-production-config-smoke.mjs <<'EOF'
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
EOF

cat > scripts/rh1-preflight-smoke.mjs <<'EOF'
import {
  mkdtemp,
  readFile,
  rm,
  writeFile
} from "node:fs/promises";
import {
  tmpdir
} from "node:os";
import {
  join
} from "node:path";
import {
  spawnSync
} from "node:child_process";

const template =
  await readFile(
    "infra/production/.env.production.example",
    "utf8"
  );

const values =
  new Map();

for (
  const rawLine
  of template.split(
    /\r?\n/
  )
) {
  const line =
    rawLine.trim();

  if (
    !line ||
    line.startsWith(
      "#"
    )
  ) {
    continue;
  }

  const separator =
    line.indexOf(
      "="
    );

  const key =
    line.slice(
      0,
      separator
    );

  const value =
    line.slice(
      separator +
        1
    );

  values.set(
    key,
    value
  );
}

const synthetic = {
  WAPP_DOMAIN:
    "wapp.test.invalid",
  WAPP_IMAGE_TAG:
    "rh1-smoke-0ad52c6",
  MYSQL_PASSWORD:
    "SyntheticMysqlPassword123!",
  MYSQL_ROOT_PASSWORD:
    "SyntheticMysqlRootPassword123!",
  DATABASE_URL:
    "mysql://wapp:SyntheticMysqlPassword123!@mysql:3306/wapp",
  SHADOW_DATABASE_URL:
    "mysql://wapp:SyntheticMysqlPassword123!@mysql:3306/wapp_shadow",
  REDIS_PASSWORD:
    "SyntheticRedisPassword123!",
  REDIS_URL:
    "redis://:SyntheticRedisPassword123!@redis:6379/0",
  JWT_SECRET:
    "SyntheticJwtSecret_123456789012345678901234567890",
  METRICS_TOKEN:
    "SyntheticMetricsToken_123456789012345678901234567",
  EVOLUTION_BASE_URL:
    "https://evolution.test.invalid",
  EVOLUTION_API_KEY:
    "SyntheticEvolutionKey_12345678901234567890123456",
  EVOLUTION_WEBHOOK_SECRET:
    "SyntheticWebhookSecret_12345678901234567890123456",
  S3_BUCKET:
    "synthetic-private-bucket",
  S3_ENDPOINT:
    "https://s3.test.invalid",
  S3_ACCESS_KEY_ID:
    "synthetic-access-key",
  S3_SECRET_ACCESS_KEY:
    "SyntheticS3Secret_1234567890",
  TYPEBOT_URL:
    ""
};

for (
  const [
    key,
    value
  ]
  of Object.entries(
    synthetic
  )
) {
  values.set(
    key,
    value
  );
}

const directory =
  await mkdtemp(
    join(
      tmpdir(),
      "wapp-rh1-"
    )
  );

const envPath =
  join(
    directory,
    ".env.production"
  );

try {
  const source =
    [
      ...values.entries()
    ]
      .map(
        (
          [
            key,
            value
          ]
        ) =>
          `${key}=${value}`
      )
      .join(
        "\n"
      ) +
    "\n";

  await writeFile(
    envPath,
    source,
    {
      encoding:
        "utf8",
      mode:
        0o600
    }
  );

  const result =
    spawnSync(
      process.execPath,
      [
        "scripts/prod-preflight.mjs"
      ],
      {
        cwd:
          process.cwd(),
        env: {
          ...process.env,
          WAPP_PROD_ENV:
            envPath
        },
        encoding:
          "utf8"
      }
    );

  if (
    result.status !==
    0
  ) {
    throw new Error(
      [
        "Synthetic production preflight failed.",
        result.stdout,
        result.stderr
      ]
        .filter(
          Boolean
        )
        .join(
          "\n"
        )
    );
  }

  if (
    !result.stdout.includes(
      "[prod:preflight] PASS"
    )
  ) {
    throw new Error(
      "Synthetic preflight did not report PASS."
    );
  }

  console.log(
    "[RH1] synthetic prod:preflight PASS"
  );
} finally {
  await rm(
    directory,
    {
      recursive:
        true,
      force:
        true
    }
  );
}
EOF

cat > docs/RH1_PRODUCTION_COMPOSE_ENVIRONMENT.md <<'EOF'
# RH1 — Production Compose and environment hardening

RH1 is a release-hardening milestone. It does not deploy Wapp and does not
modify Docker volumes.

## What RH1 fixes

### Redis Compose structure

`REDIS_PASSWORD` is declared at the Redis service level instead of being nested
under `healthcheck.environment`.

This makes the production Compose structurally valid under `config --quiet`.

### Runtime vs migration images

The API runtime/worker and Prisma migration target no longer publish to the
same image tag.

- runtime + worker: `wapp-api-runtime:${WAPP_IMAGE_TAG}`
- migration target: `wapp-api-migrate:${WAPP_IMAGE_TAG}`

This prevents a multi-target build from overwriting the runtime tag with the
migration image.

`WAPP_IMAGE_TAG` is mandatory in the production preflight and must not be
`local` or `latest`.

### Prisma build configuration

Prisma 7 loads `prisma.config.ts` during `prisma generate`, so both
`DATABASE_URL` and `SHADOW_DATABASE_URL` must exist even during image build.

The API Dockerfile provides non-secret build-only placeholder URLs around
`prisma generate`. They are not production credentials and client generation
does not connect to MySQL.

Runtime/migration containers receive the actual values from the production env.

### Production environment template

`infra/production/.env.production.example` is tracked.

`infra/production/.env.production` remains ignored and must never be committed.

Create the real file with:

```bash
pnpm prod:init
```

The initializer refuses to overwrite an existing production env. On POSIX it
creates the file with mode `600`.

The tracked template deliberately contains `CHANGE_ME` values for every
hostname/credential/secret.

### Production preflight

`pnpm prod:preflight` validates:

- public hostname;
- immutable image tag;
- MySQL credentials and `DATABASE_URL`;
- distinct Prisma `SHADOW_DATABASE_URL`;
- Redis credentials and URL;
- JWT and metrics secrets;
- API/session bounds;
- Evolution URL/secrets/health interval;
- S3 bucket, endpoint, credentials and path-style mode;
- worker concurrency/attempts;
- maintenance/retention ranges;
- optional Typebot URL only when configured.

The preflight never starts or changes containers.

`pnpm prod:config` runs preflight and only then executes Compose
`config --quiet`. It also never starts or removes containers.

## Typebot

RH1 does not enable Typebot.

`TYPEBOT_URL` remains empty in the tracked production template until Typebot is
formally included in the release scope.

## RH1 does not solve yet

RH1 intentionally does not:

- update vulnerable Prisma/transitive dependencies;
- implement MySQL TLS;
- replace development backup scripts with production backup/restore;
- create the first OWNER bootstrap;
- run staging or production deployment.

Those remain subsequent Release Hardening milestones.
EOF

echo "[RH1] Checking tracked env template..."
node scripts/prod-env-template-check.mjs

echo "[RH1] File-level production smoke..."
node scripts/rh1-production-config-smoke.mjs

echo "[RH1] Synthetic production preflight..."
node scripts/rh1-preflight-smoke.mjs

echo "[RH1] Confirming env example is not ignored..."
if git check-ignore -q "$ENV_EXAMPLE"; then
  echo "ERROR: $ENV_EXAMPLE is still ignored by Git."
  exit 1
fi

echo "[RH1] Docker Compose structural validation..."
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker command is required for RH1 Compose validation."
  exit 1
fi

docker compose \
  --env-file "$ENV_EXAMPLE" \
  -f "$COMPOSE" \
  config \
  --quiet

echo "[RH1] Node syntax validation..."
node --check scripts/prod-preflight.mjs
node --check scripts/prod-env-template-check.mjs
node --check scripts/prod-init.mjs
node --check scripts/rh1-production-config-smoke.mjs
node --check scripts/rh1-preflight-smoke.mjs

echo "[RH1] Bash syntax validation..."
bash -n scripts/prod-config.sh
bash -n scripts/prod-deploy.sh

echo
echo "[RH1] PRODUCTION COMPOSE + ENVIRONMENT PASS."
echo
echo "No containers were started, stopped or removed."
echo "No Docker volumes were modified."
echo "No Prisma migration was executed."

if [[ -f "$ENV_REAL" ]]; then
  echo "Existing $ENV_REAL was left untouched."
else
  echo "No real production env exists yet. Create it later with: pnpm prod:init"
fi

echo
echo "Next release-hardening milestone: RH2 dependency security."
