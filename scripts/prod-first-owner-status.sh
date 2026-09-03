#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${WAPP_PROD_ENV:-infra/production/.env.production}"
COMPOSE_FILE="infra/production/docker-compose.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing production env: $ENV_FILE"
  exit 1
fi

node scripts/prod-preflight.mjs
bash scripts/prod-mysql-tls-check.sh

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  run \
  --rm \
  -T \
  api \
  node \
  dist/scripts/prod-first-owner-status.js
