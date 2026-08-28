#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.24] Building production deployment baseline..."

for required in \
  "package.json" \
  "pnpm-lock.yaml" \
  "pnpm-workspace.yaml" \
  "apps/api/package.json" \
  "apps/api/src/worker.ts" \
  "apps/web/package.json" \
  "apps/web/next.config.ts" \
  "packages/contracts/package.json"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  infra/production \
  scripts \
  docs

# ---------------------------------------------------------------------------
# Next.js standalone output for production container.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/next.config.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  );

if (
  !content.includes(
    'import path from "node:path";'
  )
) {
  content =
    `import path from "node:path";

${content}`;
}

if (
  !content.includes(
    'output: "standalone"'
  )
) {
  const anchor =
    `const nextConfig: NextConfig = {
  reactStrictMode: true`;

  if (!content.includes(anchor)) {
    throw new Error(
      "next.config.ts anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `const nextConfig: NextConfig = {
  reactStrictMode: true,
  output: "standalone",
  outputFileTracingRoot: path.join(
    process.cwd(),
    "../.."
  )`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Next.js standalone output enabled."
);
NODE

# ---------------------------------------------------------------------------
# Docker context security.
# ---------------------------------------------------------------------------

cat > .dockerignore <<'EOF'
.git
.github
.backups
.runtime
legacy
cookies.txt
*.cookiejar
*.cookies.txt
*.patch

**/.env
**/.env.local
**/.env.production
**/.env.*.local

node_modules
**/node_modules
**/.next
**/dist
**/coverage

infra/production/.env.production
EOF

if ! grep -q '^infra/production/\.env\.production$' .gitignore; then
  cat >> .gitignore <<'EOF'

# --- WAPP P1.24 / PRODUCTION SECRETS ---
infra/production/.env.production
# --- /WAPP P1.24 ---
EOF
fi

# ---------------------------------------------------------------------------
# API + worker + migration image.
# ---------------------------------------------------------------------------

cat > infra/production/api.Dockerfile <<'EOF'
# syntax=docker/dockerfile:1

FROM node:24-bookworm-slim AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm install --global pnpm@11.16.0

WORKDIR /app

FROM base AS build-deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install \
  --frozen-lockfile \
  --filter @wapp/api... \
  --filter @wapp/contracts...

FROM build-deps AS build

COPY tsconfig.base.json ./
COPY apps/api apps/api
COPY packages/contracts packages/contracts

RUN pnpm --filter @wapp/contracts build \
  && pnpm --filter @wapp/api db:generate \
  && pnpm --filter @wapp/api build

FROM base AS production-deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install \
  --frozen-lockfile \
  --prod \
  --filter @wapp/api...

FROM base AS runtime

ENV NODE_ENV=production

COPY --from=production-deps /app/node_modules /app/node_modules
COPY --from=production-deps /app/apps/api/node_modules /app/apps/api/node_modules
COPY --from=production-deps /app/apps/api/package.json /app/apps/api/package.json
COPY --from=production-deps /app/packages/contracts /app/packages/contracts

COPY --from=build /app/apps/api/dist /app/apps/api/dist
COPY --from=build /app/packages/contracts/dist /app/packages/contracts/dist

WORKDIR /app/apps/api

USER node

EXPOSE 4000

CMD ["node", "dist/server.js"]

FROM build AS migrate

ENV NODE_ENV=production

WORKDIR /app/apps/api

CMD ["pnpm", "db:deploy"]
EOF

# ---------------------------------------------------------------------------
# Web production image.
# ---------------------------------------------------------------------------

cat > infra/production/web.Dockerfile <<'EOF'
# syntax=docker/dockerfile:1

FROM node:24-bookworm-slim AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm install --global pnpm@11.16.0

WORKDIR /app

FROM base AS deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install \
  --frozen-lockfile \
  --filter @wapp/web... \
  --filter @wapp/contracts...

FROM deps AS build

COPY tsconfig.base.json ./
COPY apps/web apps/web
COPY packages/contracts packages/contracts

ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

RUN mkdir -p apps/web/public \
  && pnpm --filter @wapp/contracts build \
  && pnpm --filter @wapp/web build

FROM node:24-bookworm-slim AS runtime

ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

WORKDIR /app

COPY --from=build --chown=node:node \
  /app/apps/web/.next/standalone \
  /app

COPY --from=build --chown=node:node \
  /app/apps/web/.next/static \
  /app/apps/web/.next/static

COPY --from=build --chown=node:node \
  /app/apps/web/public \
  /app/apps/web/public

USER node

EXPOSE 3000

CMD ["node", "apps/web/server.js"]
EOF

# ---------------------------------------------------------------------------
# Caddy TLS + reverse proxy.
# ---------------------------------------------------------------------------

cat > infra/production/Caddyfile <<'EOF'
{$WAPP_DOMAIN} {
  encode zstd gzip

  header {
    -Server
    X-Content-Type-Options "nosniff"
    Referrer-Policy "strict-origin-when-cross-origin"
  }

  @api path /api/* /health /health/*
  handle @api {
    reverse_proxy api:4000
  }

  handle {
    reverse_proxy web:3000
  }
}
EOF

# ---------------------------------------------------------------------------
# Production Compose.
# ---------------------------------------------------------------------------

cat > infra/production/docker-compose.yml <<'EOF'
name: wapp-production

x-api-environment: &api-environment
  NODE_ENV: production
  HOST: 0.0.0.0
  PORT: "4000"
  WEB_URL: https://${WAPP_DOMAIN}
  TRUST_PROXY: "true"
  DATABASE_URL: ${DATABASE_URL}
  REDIS_URL: ${REDIS_URL}
  API_BODY_MAX_BYTES: ${API_BODY_MAX_BYTES:-1048576}
  JWT_SECRET: ${JWT_SECRET}
  ACCESS_TOKEN_TTL_SECONDS: ${ACCESS_TOKEN_TTL_SECONDS:-900}
  REFRESH_TOKEN_TTL_DAYS: ${REFRESH_TOKEN_TTL_DAYS:-30}
  COOKIE_SECURE: "true"
  EVOLUTION_BASE_URL: ${EVOLUTION_BASE_URL}
  EVOLUTION_API_KEY: ${EVOLUTION_API_KEY}
  EVOLUTION_WEBHOOK_BASE_URL: https://${WAPP_DOMAIN}
  EVOLUTION_WEBHOOK_SECRET: ${EVOLUTION_WEBHOOK_SECRET}
  EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS: ${EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS:-60}
  WHATSAPP_SESSION_PATH: .runtime/whatsapp
  MEDIA_STORAGE_DRIVER: s3
  MEDIA_STORAGE_PATH: .runtime/media
  MEDIA_MAX_BYTES: ${MEDIA_MAX_BYTES:-26214400}
  S3_BUCKET: ${S3_BUCKET}
  S3_REGION: ${S3_REGION:-us-east-1}
  S3_ENDPOINT: ${S3_ENDPOINT:-}
  S3_FORCE_PATH_STYLE: ${S3_FORCE_PATH_STYLE:-false}
  S3_ACCESS_KEY_ID: ${S3_ACCESS_KEY_ID}
  S3_SECRET_ACCESS_KEY: ${S3_SECRET_ACCESS_KEY}
  TYPEBOT_URL: ${TYPEBOT_URL:-}
  JOBS_EMBEDDED_WORKER: "false"
  JOBS_MEDIA_CAPTURE_CONCURRENCY: ${JOBS_MEDIA_CAPTURE_CONCURRENCY:-4}
  JOBS_MEDIA_CAPTURE_ATTEMPTS: ${JOBS_MEDIA_CAPTURE_ATTEMPTS:-5}

services:
  mysql:
    image: mysql:8.4
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - backend
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "MYSQL_PWD=$$MYSQL_ROOT_PASSWORD mysqladmin ping --host=127.0.0.1 --user=root --silent"
        ]
      interval: 10s
      timeout: 5s
      retries: 20
      start_period: 20s
    security_opt:
      - no-new-privileges:true

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command:
      [
        "redis-server",
        "--appendonly",
        "yes",
        "--requirepass",
        "${REDIS_PASSWORD}"
      ]
    volumes:
      - redis_data:/data
    networks:
      - backend
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "redis-cli -a \"$$REDIS_PASSWORD\" ping | grep PONG"
        ]
      environment:
        REDIS_PASSWORD: ${REDIS_PASSWORD}
      interval: 10s
      timeout: 5s
      retries: 20
      start_period: 10s
    security_opt:
      - no-new-privileges:true

  migrate:
    image: wapp-api:${WAPP_IMAGE_TAG:-local}
    build:
      context: ../..
      dockerfile: infra/production/api.Dockerfile
      target: migrate
    environment: *api-environment
    depends_on:
      mysql:
        condition: service_healthy
    networks:
      - backend
    restart: "no"
    security_opt:
      - no-new-privileges:true

  api:
    image: wapp-api:${WAPP_IMAGE_TAG:-local}
    build:
      context: ../..
      dockerfile: infra/production/api.Dockerfile
      target: runtime
    restart: unless-stopped
    environment: *api-environment
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
      migrate:
        condition: service_completed_successfully
    networks:
      - backend
      - edge
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:4000/health/ready').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
        ]
      interval: 15s
      timeout: 5s
      retries: 12
      start_period: 20s
    security_opt:
      - no-new-privileges:true

  worker:
    image: wapp-api:${WAPP_IMAGE_TAG:-local}
    build:
      context: ../..
      dockerfile: infra/production/api.Dockerfile
      target: runtime
    command:
      [
        "node",
        "dist/worker.js"
      ]
    restart: unless-stopped
    environment: *api-environment
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
      migrate:
        condition: service_completed_successfully
    networks:
      - backend
    security_opt:
      - no-new-privileges:true

  web:
    image: wapp-web:${WAPP_IMAGE_TAG:-local}
    build:
      context: ../..
      dockerfile: infra/production/web.Dockerfile
      args:
        NEXT_PUBLIC_API_URL: https://${WAPP_DOMAIN}
    restart: unless-stopped
    environment:
      NODE_ENV: production
      HOSTNAME: 0.0.0.0
      PORT: "3000"
    networks:
      - edge
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:3000/login').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
        ]
      interval: 15s
      timeout: 5s
      retries: 12
      start_period: 20s
    security_opt:
      - no-new-privileges:true

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    environment:
      WAPP_DOMAIN: ${WAPP_DOMAIN}
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      api:
        condition: service_healthy
      web:
        condition: service_healthy
    networks:
      - edge
    security_opt:
      - no-new-privileges:true

networks:
  backend:
  edge:

volumes:
  mysql_data:
  redis_data:
  caddy_data:
  caddy_config:
EOF

# ---------------------------------------------------------------------------
# Production environment template. No real credentials.
# ---------------------------------------------------------------------------

cat > infra/production/.env.production.example <<'EOF'
# Public hostname only — no https:// prefix.
WAPP_DOMAIN=app.example.com
WAPP_IMAGE_TAG=local

MYSQL_DATABASE=wapp
MYSQL_USER=wapp
MYSQL_PASSWORD=CHANGE_ME_DB_PASSWORD
MYSQL_ROOT_PASSWORD=CHANGE_ME_DB_ROOT_PASSWORD
DATABASE_URL=mysql://wapp:CHANGE_ME_DB_PASSWORD@mysql:3306/wapp

REDIS_PASSWORD=CHANGE_ME_REDIS_PASSWORD
REDIS_URL=redis://:CHANGE_ME_REDIS_PASSWORD@redis:6379/0

JWT_SECRET=CHANGE_ME_RANDOM_64_CHARACTERS
ACCESS_TOKEN_TTL_SECONDS=900
REFRESH_TOKEN_TTL_DAYS=30

EVOLUTION_BASE_URL=https://evolution.example.com
EVOLUTION_API_KEY=CHANGE_ME_EVOLUTION_API_KEY
EVOLUTION_WEBHOOK_SECRET=CHANGE_ME_RANDOM_WEBHOOK_SECRET_32_PLUS
EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS=60

# Shared/private S3-compatible storage is mandatory in this production baseline.
S3_BUCKET=CHANGE_ME_BUCKET
S3_REGION=us-east-1
S3_ENDPOINT=
S3_FORCE_PATH_STYLE=false
S3_ACCESS_KEY_ID=CHANGE_ME_S3_ACCESS_KEY
S3_SECRET_ACCESS_KEY=CHANGE_ME_S3_SECRET_KEY

MEDIA_MAX_BYTES=26214400
API_BODY_MAX_BYTES=1048576
JOBS_MEDIA_CAPTURE_CONCURRENCY=4
JOBS_MEDIA_CAPTURE_ATTEMPTS=5

TYPEBOT_URL=
EOF

# ---------------------------------------------------------------------------
# Production preflight.
# ---------------------------------------------------------------------------

cat > scripts/prod-preflight.mjs <<'EOF'
import {
  readFile
} from "node:fs/promises";
import {
  resolve
} from "node:path";

const envPath =
  resolve(
    process.cwd(),
    process.env
      .WAPP_PROD_ENV ??
      "infra/production/.env.production"
  );

function parseEnv(
  source
) {
  const values = {};

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
        separator + 1
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

    values[key] =
      value;
  }

  return values;
}

function fail(
  message
) {
  throw new Error(
    message
  );
}

function required(
  env,
  key
) {
  const value =
    env[key];

  if (
    !value ||
    /CHANGE_ME/i.test(
      value
    )
  ) {
    fail(
      `${key} is missing or still contains a placeholder.`
    );
  }

  return value;
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
    /localhost|127\.0\.0\.1/i.test(
      domain
    )
  ) {
    fail(
      "WAPP_DOMAIN must be a real hostname without protocol or path."
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
    required(
      env,
      "MYSQL_PASSWORD"
    );

  required(
    env,
    "MYSQL_ROOT_PASSWORD"
  );

  const databaseUrl =
    new URL(
      required(
        env,
        "DATABASE_URL"
      )
    );

  if (
    databaseUrl.protocol !==
      "mysql:" ||
    databaseUrl.hostname !==
      "mysql" ||
    decodeURIComponent(
      databaseUrl.username
    ) !==
      mysqlUser ||
    decodeURIComponent(
      databaseUrl.password
    ) !==
      mysqlPassword ||
    databaseUrl.pathname
      .replace(
        /^\/+/,
        ""
      ) !==
      mysqlDatabase
  ) {
    fail(
      "DATABASE_URL must match the bundled mysql service credentials."
    );
  }

  const redisPassword =
    required(
      env,
      "REDIS_PASSWORD"
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

  const jwtSecret =
    required(
      env,
      "JWT_SECRET"
    );

  if (
    jwtSecret.length <
    32
  ) {
    fail(
      "JWT_SECRET must contain at least 32 characters."
    );
  }

  const evolutionKey =
    required(
      env,
      "EVOLUTION_API_KEY"
    );

  if (
    evolutionKey.length <
    32
  ) {
    fail(
      "EVOLUTION_API_KEY must contain at least 32 characters."
    );
  }

  const webhookSecret =
    required(
      env,
      "EVOLUTION_WEBHOOK_SECRET"
    );

  if (
    webhookSecret.length <
    32
  ) {
    fail(
      "EVOLUTION_WEBHOOK_SECRET must contain at least 32 characters."
    );
  }

  new URL(
    required(
      env,
      "EVOLUTION_BASE_URL"
    )
  );

  required(
    env,
    "S3_BUCKET"
  );

  const s3Access =
    required(
      env,
      "S3_ACCESS_KEY_ID"
    );

  const s3Secret =
    required(
      env,
      "S3_SECRET_ACCESS_KEY"
    );

  if (
    !s3Access ||
    !s3Secret
  ) {
    fail(
      "S3 credentials must be configured for this baseline."
    );
  }

  if (
    env.S3_ENDPOINT
  ) {
    new URL(
      env.S3_ENDPOINT
    );
  }

  console.log(
    `[prod:preflight] PASS — https://${domain}`
  );

  console.log(
    "[prod:preflight] MySQL, Redis, auth, Evolution and S3 configuration look consistent."
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

  process.exitCode = 1;
}
EOF

# ---------------------------------------------------------------------------
# Production deployment helper.
# ---------------------------------------------------------------------------

cat > scripts/prod-deploy.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${WAPP_PROD_ENV:-infra/production/.env.production}"
COMPOSE_FILE="infra/production/docker-compose.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing $ENV_FILE"
  echo "Create it from infra/production/.env.production.example."
  exit 1
fi

echo "[prod:deploy] Preflight..."
WAPP_PROD_ENV="$ENV_FILE" node scripts/prod-preflight.mjs

echo "[prod:deploy] Building images..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  build \
  api \
  worker \
  migrate \
  web

echo "[prod:deploy] Starting MySQL + Redis..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  up \
  -d \
  --wait \
  mysql \
  redis

echo "[prod:deploy] Applying Prisma migrations..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  run \
  --rm \
  migrate

echo "[prod:deploy] Starting API + worker + web + Caddy..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  up \
  -d \
  --wait \
  api \
  worker \
  web \
  caddy

echo
echo "[prod:deploy] Stack:"
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  ps

echo
echo "[prod:deploy] Deployment started successfully."
echo "Run pnpm prod:smoke after DNS/TLS is reachable."
EOF

chmod +x scripts/prod-deploy.sh

# ---------------------------------------------------------------------------
# Root production commands.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

pkg.scripts ??= {};

Object.assign(
  pkg.scripts,
  {
    "prod:init":
      "node -e \"const fs=require('node:fs');const s='infra/production/.env.production.example';const d='infra/production/.env.production';if(fs.existsSync(d)){console.error('Production env already exists:',d);process.exit(1)}fs.copyFileSync(s,d);console.log('Created',d)\"",
    "prod:preflight":
      "node scripts/prod-preflight.mjs",
    "prod:config":
      "docker compose --env-file infra/production/.env.production -f infra/production/docker-compose.yml config",
    "prod:build":
      "docker compose --env-file infra/production/.env.production -f infra/production/docker-compose.yml build",
    "prod:deploy":
      "bash scripts/prod-deploy.sh",
    "prod:ps":
      "docker compose --env-file infra/production/.env.production -f infra/production/docker-compose.yml ps",
    "prod:logs":
      "docker compose --env-file infra/production/.env.production -f infra/production/docker-compose.yml logs -f --tail=200",
    "prod:down":
      "docker compose --env-file infra/production/.env.production -f infra/production/docker-compose.yml down",
    "prod:smoke":
      "node -e \"const fs=require('node:fs');const env=Object.fromEntries(fs.readFileSync('infra/production/.env.production','utf8').split(/\\\\r?\\\\n/).filter(l=>l&&!l.trim().startsWith('#')&&l.includes('=')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i).trim(),l.slice(i+1).trim()]}));process.env.WAPP_SMOKE_API_URL='https://'+env.WAPP_DOMAIN;import('./scripts/smoke-api.mjs')\""
  }
);

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);

console.log(
  "Production package commands registered."
);
NODE

# ---------------------------------------------------------------------------
# Runbook.
# ---------------------------------------------------------------------------

cat > docs/PRODUCTION_DEPLOYMENT.md <<'EOF'
# P1.24 Production deployment baseline

P1.24 turns the Wapp workspace into a reproducible single-host production
deployment using Docker Compose.

It is provider-neutral: any Linux host with Docker Engine + Docker Compose,
public DNS and ports 80/443 can use the baseline.

## Topology

```text
Internet
   |
80 / 443
   |
 Caddy
  /  \
Web  API
      |
      +---- MySQL 8.4
      +---- Redis 7
      +---- S3-compatible private media storage
      +---- Evolution API
      |
    Worker
```

Only Caddy publishes host ports.

MySQL, Redis, API and Web are not directly exposed to the public host network.

## Containers

### api

Fastify production build.

Healthcheck:

`GET /health/ready`

### worker

Runs:

`node dist/worker.js`

The API has:

`JOBS_EMBEDDED_WORKER=false`

so durable BullMQ jobs are consumed by the dedicated worker.

### migrate

One-shot image target running:

`prisma migrate deploy`

It completes before API/worker startup.

### web

Next.js standalone production server.

`NEXT_PUBLIC_API_URL` is baked as:

`https://<WAPP_DOMAIN>`

### caddy

Terminates TLS automatically and proxies:

- `/api/*` -> API
- `/health*` -> API
- all remaining paths -> Web

DNS must point `WAPP_DOMAIN` to the deployment host before Caddy can obtain a
public certificate.

### mysql / redis

Persistent Docker volumes are used, but volumes are still not backups. Keep the
P1.18 backup/restore policy.

Neither service publishes a host port.

## Shared media

This baseline intentionally forces:

`MEDIA_STORAGE_DRIVER=s3`

Local media storage is not accepted as a production topology because API/worker
or future API replicas must see the same objects.

The bucket must remain private. Wapp continues serving media through its
authenticated message endpoint.

## First configuration

Create the ignored runtime env:

```bash
pnpm prod:init
```

Edit:

`infra/production/.env.production`

Replace every `CHANGE_ME`.

Use strong random values. Do not commit this file.

Then:

```bash
pnpm prod:preflight
```

The preflight checks:

- real public hostname;
- consistent MySQL URL and credentials;
- consistent Redis URL and password;
- JWT length;
- Evolution URL/key/webhook secret;
- S3 bucket and credentials.

It changes no container.

## Build validation

Before first deployment:

```bash
pnpm verify
pnpm prod:preflight
pnpm prod:build
```

This proves both the source production build and Docker production images.

## First deployment

After DNS points to the host and ports 80/443 are allowed:

```bash
pnpm prod:deploy
```

The deploy helper:

1. runs preflight;
2. builds images;
3. starts and waits for MySQL + Redis;
4. executes `prisma migrate deploy`;
5. starts API + dedicated worker + Web + Caddy;
6. waits for service health;
7. prints Compose status.

Then:

```bash
pnpm prod:smoke
```

Expected:

```text
live: OK
ready: OK
health: ok
PASS
```

## Updates

Before a production update:

1. verify the candidate commit with `pnpm verify`;
2. create/verify an off-host database backup according to P1.18;
3. record the currently deployed Git commit/image tag;
4. deploy the new commit;
5. run `pnpm prod:smoke`;
6. validate login and a WhatsApp inbound/outbound message.

Do not use `docker compose down -v`.

`pnpm prod:down` intentionally does not pass `-v`; persistent data remains.

## Logs

```bash
pnpm prod:logs
```

Or isolate a service:

```bash
docker compose \
  --env-file infra/production/.env.production \
  -f infra/production/docker-compose.yml \
  logs -f api worker
```

## Status

```bash
pnpm prod:ps
```

## Evolution

P1.24 does not force Evolution into the same Compose project. It can be the
existing Evolution deployment or a dedicated service.

`EVOLUTION_BASE_URL` must be reachable from the API and worker containers.

Evolution must be able to reach:

`https://<WAPP_DOMAIN>/api/v1/webhooks/evolution/...`

using the existing Wapp webhook contract.

## Secrets

Production secrets live only in:

`infra/production/.env.production`

which is ignored by Git and excluded from Docker build context.

P1.23 `pnpm security:scan` remains part of `pnpm verify`.

## Scaling boundary

This baseline starts one API and one worker.

P1.14 Redis realtime, P1.17 shared storage and P1.19 BullMQ already remove the
main stateful blockers for additional API/worker replicas.

Before horizontal scaling, validate load-balancer/SSE behavior and capacity
under realistic traffic.
EOF

# ---------------------------------------------------------------------------
# Validation without starting/changing production containers.
# ---------------------------------------------------------------------------

echo "[P1.24] Shell syntax..."
bash -n scripts/prod-deploy.sh

echo "[P1.24] Node syntax..."
node --check scripts/prod-preflight.mjs

echo "[P1.24] Typechecking web config..."
pnpm --filter @wapp/web typecheck

echo "[P1.24] Typechecking API..."
pnpm --filter @wapp/api typecheck

if command -v docker >/dev/null 2>&1 &&
   docker compose version >/dev/null 2>&1
then
  echo "[P1.24] Validating Compose structure with example environment..."
  docker compose \
    --env-file infra/production/.env.production.example \
    -f infra/production/docker-compose.yml \
    config \
    >/dev/null
else
  echo "[P1.24] Docker Compose not available; skipped compose config validation."
fi

echo
echo "[P1.24] Production deployment baseline installed."
echo
echo "No Prisma migration is introduced by P1.24 itself."
echo
echo "Do NOT deploy yet."
echo "First validate Docker images locally with:"
echo "  pnpm prod:init"
echo "  # edit infra/production/.env.production"
echo "  pnpm prod:preflight"
echo "  pnpm prod:build"
