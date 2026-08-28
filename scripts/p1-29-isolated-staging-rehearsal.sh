#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.29] Installing isolated staging rehearsal..."

for required in \
  "infra/production/api.Dockerfile" \
  "infra/production/web.Dockerfile" \
  "scripts/smoke-api.mjs" \
  "apps/api/src/modules/observability/metrics.service.ts" \
  "apps/api/src/jobs/maintenance.service.ts" \
  "package.json"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  infra/staging \
  docs

cat > infra/staging/Caddyfile <<'EOF'
:8080 {
  encode zstd gzip

  @api path /api/* /health /health/* /metrics
  handle @api {
    reverse_proxy api:4000
  }

  handle {
    reverse_proxy web:3000
  }
}
EOF

cat > infra/staging/docker-compose.yml <<'EOF'
name: wapp-staging-rehearsal

x-api-environment: &api-environment
  NODE_ENV: production
  HOST: 0.0.0.0
  PORT: "4000"
  WEB_URL: http://127.0.0.1:${WAPP_STAGING_PORT:-18080}
  TRUST_PROXY: "true"
  DATABASE_URL: mysql://wapp_stage:wapp_stage_password@mysql:3306/wapp_stage
  REDIS_URL: redis://:wapp_stage_redis_password@redis:6379/0
  API_BODY_MAX_BYTES: "1048576"
  JWT_SECRET: staging_jwt_secret_abcdefghijklmnopqrstuvwxyz_123456789
  METRICS_TOKEN: staging_metrics_token_abcdefghijklmnopqrstuvwxyz_123456
  ACCESS_TOKEN_TTL_SECONDS: "900"
  REFRESH_TOKEN_TTL_DAYS: "30"
  COOKIE_SECURE: "false"
  EVOLUTION_BASE_URL: http://evolution-stub:8080
  EVOLUTION_API_KEY: staging_evolution_api_key_abcdefghijklmnopqrstuvwxyz
  EVOLUTION_WEBHOOK_BASE_URL: http://127.0.0.1:${WAPP_STAGING_PORT:-18080}
  EVOLUTION_WEBHOOK_SECRET: staging_webhook_secret_abcdefghijklmnopqrstuvwxyz
  EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS: "3600"
  WHATSAPP_SESSION_PATH: .runtime/whatsapp
  MEDIA_STORAGE_DRIVER: s3
  MEDIA_STORAGE_PATH: .runtime/media
  MEDIA_MAX_BYTES: "26214400"
  S3_BUCKET: wapp-stage
  S3_REGION: us-east-1
  S3_ENDPOINT: http://minio:9000
  S3_FORCE_PATH_STYLE: "true"
  S3_ACCESS_KEY_ID: minioadmin
  S3_SECRET_ACCESS_KEY: minioadmin123
  TYPEBOT_URL: ""
  JOBS_EMBEDDED_WORKER: "false"
  JOBS_MEDIA_CAPTURE_CONCURRENCY: "2"
  JOBS_MEDIA_CAPTURE_ATTEMPTS: "3"
  MAINTENANCE_ENABLED: "true"
  MAINTENANCE_INTERVAL_HOURS: "6"
  SESSION_RETENTION_DAYS: "30"
  MAINTENANCE_STALE_MEDIA_MINUTES: "30"

services:
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_DATABASE: wapp_stage
      MYSQL_USER: wapp_stage
      MYSQL_PASSWORD: wapp_stage_password
      MYSQL_ROOT_PASSWORD: wapp_stage_root_password
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "MYSQL_PWD=$$MYSQL_ROOT_PASSWORD mysqladmin ping --host=127.0.0.1 --user=root --silent"
        ]
      interval: 3s
      timeout: 3s
      retries: 40
      start_period: 10s

  redis:
    image: redis:7-alpine
    command:
      [
        "redis-server",
        "--appendonly",
        "no",
        "--requirepass",
        "wapp_stage_redis_password"
      ]
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "redis-cli -a wapp_stage_redis_password ping | grep PONG"
        ]
      interval: 3s
      timeout: 3s
      retries: 30

  minio:
    image: minio/minio:latest
    command:
      [
        "server",
        "/data"
      ]
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin123

  minio-init:
    image: minio/mc:latest
    depends_on:
      minio:
        condition: service_started
    entrypoint:
      - /bin/sh
      - -c
    command:
      - >
        until mc alias set local http://minio:9000 minioadmin minioadmin123;
        do sleep 2; done;
        mc mb --ignore-existing local/wapp-stage;
        mc anonymous set none local/wapp-stage;
    restart: "no"

  migrate:
    image: wapp-stage-api:local
    build:
      context: ../..
      dockerfile: infra/production/api.Dockerfile
      target: migrate
    environment: *api-environment
    depends_on:
      mysql:
        condition: service_healthy
    restart: "no"

  api:
    image: wapp-stage-api:local
    build:
      context: ../..
      dockerfile: infra/production/api.Dockerfile
      target: runtime
    environment: *api-environment
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_started
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:4000/health/ready').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
        ]
      interval: 5s
      timeout: 4s
      retries: 30
      start_period: 10s

  worker:
    image: wapp-stage-api:local
    build:
      context: ../..
      dockerfile: infra/production/api.Dockerfile
      target: runtime
    command:
      [
        "node",
        "dist/worker.js"
      ]
    environment: *api-environment
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_started

  web:
    image: wapp-stage-web:local
    build:
      context: ../..
      dockerfile: infra/production/web.Dockerfile
      args:
        NEXT_PUBLIC_API_URL: http://127.0.0.1:${WAPP_STAGING_PORT:-18080}
    environment:
      NODE_ENV: production
      HOSTNAME: 0.0.0.0
      PORT: "3000"
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:3000/login').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
        ]
      interval: 5s
      timeout: 4s
      retries: 30
      start_period: 10s

  proxy:
    image: caddy:2-alpine
    ports:
      - "127.0.0.1:${WAPP_STAGING_PORT:-18080}:8080"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    depends_on:
      api:
        condition: service_healthy
      web:
        condition: service_healthy
EOF

cat > scripts/staging-rehearsal.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE="infra/staging/docker-compose.yml"
PROJECT="wapp-rehearsal-${RANDOM}-$$"
PORT="${WAPP_STAGING_PORT:-18080}"
KEEP="${WAPP_STAGING_KEEP:-0}"

if ! docker version >/dev/null 2>&1; then
  echo "ERROR: Docker is required for the staging rehearsal."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose is required for the staging rehearsal."
  exit 1
fi

if ! node - "$PORT" <<'NODE'
const net=require("node:net");
const port=Number(process.argv[2]);
const server=net.createServer();
server.once("error",()=>process.exit(1));
server.listen(port,"127.0.0.1",()=>server.close(()=>process.exit(0)));
NODE
then
  echo "ERROR: staging port $PORT is already in use."
  echo "Use another port, for example:"
  echo "  WAPP_STAGING_PORT=18081 pnpm staging:rehearsal"
  exit 1
fi

compose() {
  WAPP_STAGING_PORT="$PORT" \
    docker compose \
    -p "$PROJECT" \
    -f "$COMPOSE_FILE" \
    "$@"
}

cleanup() {
  if [[ "$KEEP" == "1" ]]; then
    echo
    echo "[staging] Keeping rehearsal stack:"
    echo "  project: $PROJECT"
    echo "  url: http://127.0.0.1:$PORT"
    echo
    echo "Stop it with:"
    echo "  WAPP_STAGING_PORT=$PORT docker compose -p $PROJECT -f $COMPOSE_FILE down --remove-orphans"
    return
  fi

  compose \
    down \
    --remove-orphans \
    >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

echo "[staging] Quality gate..."
pnpm verify

echo "[staging] Building production images..."
compose build \
  api \
  worker \
  migrate \
  web

echo "[staging] Starting disposable dependencies..."
compose up \
  -d \
  --wait \
  mysql \
  redis

compose up \
  -d \
  minio

echo "[staging] Creating private MinIO bucket..."
compose run \
  --rm \
  minio-init

echo "[staging] Applying Prisma migrations inside production image..."
compose run \
  --rm \
  migrate

echo "[staging] Starting API + worker + Web + proxy..."
compose up \
  -d \
  --wait \
  api \
  worker \
  web \
  proxy

echo "[staging] Running maintenance through compiled production image..."
compose run \
  --rm \
  api \
  node \
  dist/scripts/maintenance-run.js

echo "[staging] API smoke through reverse proxy..."
WAPP_SMOKE_API_URL="http://127.0.0.1:${PORT}" \
  node scripts/smoke-api.mjs

echo "[staging] Web smoke..."
node - "$PORT" <<'NODE'
const port=Number(process.argv[2]);
const url=`http://127.0.0.1:${port}/login`;
const response=await fetch(url);
if(!response.ok){
  console.error(`[staging] Web FAIL: ${response.status}`);
  process.exit(1);
}
console.log(`[staging] Web PASS: ${response.status}`);
NODE

echo "[staging] Prometheus metrics auth + scrape..."
node - "$PORT" <<'NODE'
const port=Number(process.argv[2]);
const token="staging_metrics_token_abcdefghijklmnopqrstuvwxyz_123456";
const response=await fetch(
  `http://127.0.0.1:${port}/metrics`,
  {
    headers:{
      authorization:`Bearer ${token}`
    }
  }
);
const text=await response.text();
if(!response.ok || !text.includes("wapp_http_requests_total")){
  console.error(`[staging] Metrics FAIL: ${response.status}`);
  process.exit(1);
}
console.log("[staging] Metrics PASS");
NODE

echo
echo "[staging] Final Compose status:"
compose ps

echo
echo "[staging] REHEARSAL PASS"
echo "No production environment was contacted."
EOF

chmod +x scripts/staging-rehearsal.sh

node <<'NODE'
const fs=require("node:fs");
const path="package.json";
const p=JSON.parse(fs.readFileSync(path,"utf8"));
p.scripts ??= {};
p.scripts["staging:rehearsal"]="bash scripts/staging-rehearsal.sh";
p.scripts["staging:config"]="docker compose -f infra/staging/docker-compose.yml config";
fs.writeFileSync(path,`${JSON.stringify(p,null,2)}\n`);
NODE

cat > .github/workflows/staging-rehearsal.yml <<'EOF'
name: Staging Rehearsal

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  rehearsal:
    runs-on: ubuntu-latest
    timeout-minutes: 45

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 11.16.0
          run_install: false

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: pnpm

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Full isolated staging rehearsal
        run: pnpm staging:rehearsal
EOF

cat > docs/P1_CLOSURE.md <<'EOF'
# Wapp P1 closure

P1 is considered technically closed after all of the following are green:

- P1.25 isolated integration tests;
- P1.26 administrative audit migration + integration test;
- P1.27 maintenance migration + integration test;
- P1.28 metrics/alerts tests;
- P1.29 isolated staging rehearsal.

Final local closure command:

```bash
pnpm staging:rehearsal
```

The rehearsal uses production Dockerfiles but does NOT use the production
Compose environment, domain, TLS certificate, database, Redis, Evolution
credentials or S3 bucket.

It creates disposable:

- MySQL 8.4;
- Redis 7;
- MinIO S3-compatible storage;
- migration container;
- Fastify API;
- dedicated BullMQ worker;
- Next.js standalone server;
- local Caddy reverse proxy.

Validation includes:

- the complete `pnpm verify` quality gate;
- production Docker image builds;
- Prisma `migrate deploy`;
- MySQL/Redis readiness;
- private shared S3 bucket initialization;
- dedicated worker startup;
- compiled maintenance run;
- API live/ready/health smoke;
- Web `/login` smoke;
- authenticated Prometheus scrape.

Default local URL:

`http://127.0.0.1:18080`

The stack is automatically removed at the end. It uses no named data volumes
and never runs `docker compose down -v`.

For investigation, keep the stack after a run:

```bash
WAPP_STAGING_KEEP=1 pnpm staging:rehearsal
```

This is staging/rehearsal only. P1.24 production deployment remains prepared
but intentionally untested until a real deployment window is approved.
EOF

echo "[P1.29] Shell syntax..."
bash -n scripts/staging-rehearsal.sh

if command -v docker >/dev/null 2>&1 &&
   docker compose version >/dev/null 2>&1
then
  echo "[P1.29] Compose structure..."
  WAPP_STAGING_PORT=18080 \
    docker compose \
    -f infra/staging/docker-compose.yml \
    config \
    >/dev/null
else
  echo "[P1.29] Docker unavailable; compose config validation skipped."
fi

echo "[P1.29] Typechecking..."
pnpm typecheck

echo
echo "[P1.29] Staging rehearsal installed."
echo
echo "To perform the final P1 closure rehearsal later:"
echo "  pnpm staging:rehearsal"
echo
echo "This does NOT contact production."
