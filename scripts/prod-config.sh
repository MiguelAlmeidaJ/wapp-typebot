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
