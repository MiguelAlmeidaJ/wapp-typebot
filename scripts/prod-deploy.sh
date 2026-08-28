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
