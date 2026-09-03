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

if [[ ! -t 0 ]]; then
  echo "ERROR: first OWNER bootstrap must be launched from an interactive terminal."
  exit 1
fi

read -r -p "OWNER email: " OWNER_EMAIL
read -r -p "OWNER name: " OWNER_NAME
read -r -p "Company name: " COMPANY_NAME

if [[ -z "$OWNER_EMAIL" || -z "$OWNER_NAME" || -z "$COMPANY_NAME" ]]; then
  echo "ERROR: email, OWNER name and company name are required."
  exit 1
fi

echo
echo "This command is one-shot and only works on an empty identity database."
read -r -p "Type CREATE FIRST OWNER to continue: " CONFIRMATION

if [[ "$CONFIRMATION" != "CREATE FIRST OWNER" ]]; then
  echo "Bootstrap cancelled."
  exit 1
fi

echo "[prod:first-owner:bootstrap] Production preflight..."
WAPP_PROD_ENV="$ENV_FILE" node scripts/prod-preflight.mjs

echo "[prod:first-owner:bootstrap] MySQL TLS assets..."
bash scripts/prod-mysql-tls-check.sh

echo "[prod:first-owner:bootstrap] Creating sealed first OWNER..."

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  run \
  --rm \
  -T \
  -e "BOOTSTRAP_OWNER_EMAIL=$OWNER_EMAIL" \
  -e "BOOTSTRAP_OWNER_NAME=$OWNER_NAME" \
  -e "BOOTSTRAP_COMPANY_NAME=$COMPANY_NAME" \
  api \
  node \
  dist/scripts/prod-first-owner-bootstrap.js

echo
echo "Next mandatory step:"
echo "  pnpm prod:first-owner:finalize"
