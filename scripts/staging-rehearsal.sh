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
