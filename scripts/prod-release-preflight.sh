#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${WAPP_PROD_ENV:-infra/production/.env.production}"
COMPOSE_FILE="infra/production/docker-compose.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing production environment: $ENV_FILE"
  echo "Create it from infra/production/.env.production.example and supply real secrets."
  exit 1
fi

echo "[prod:release:preflight] Git state..."
node scripts/rh6-git-clean.mjs

echo "[prod:release:preflight] Production environment..."
WAPP_PROD_ENV="$ENV_FILE" node scripts/prod-preflight.mjs

echo "[prod:release:preflight] MySQL TLS material..."
bash scripts/prod-mysql-tls-check.sh

echo "[prod:release:preflight] Backup configuration..."
# shellcheck source=/dev/null
source scripts/prod-backup-common.sh
require_backup_config

echo "[prod:release:preflight] Production Compose..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  config \
  --quiet

echo
echo "[prod:release:preflight] PASS."
echo "This is a pre-deployment configuration gate only."
echo "It does not start or modify production containers."
