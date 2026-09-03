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

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "ERROR: OWNER password finalization must run from an interactive terminal."
  exit 1
fi

read -r -p "OWNER email: " OWNER_EMAIL

if [[ -z "$OWNER_EMAIL" ]]; then
  echo "ERROR: OWNER email is required."
  exit 1
fi

printf 'New OWNER password: '
IFS= read -r -s OWNER_PASSWORD
printf '\n'

printf 'Repeat OWNER password: '
IFS= read -r -s OWNER_PASSWORD_CONFIRM
printf '\n'

if [[ "$OWNER_PASSWORD" != "$OWNER_PASSWORD_CONFIRM" ]]; then
  unset OWNER_PASSWORD OWNER_PASSWORD_CONFIRM
  echo "ERROR: passwords do not match."
  exit 1
fi

if [[ -z "$OWNER_PASSWORD" ]]; then
  unset OWNER_PASSWORD OWNER_PASSWORD_CONFIRM
  echo "ERROR: password cannot be empty."
  exit 1
fi

echo "[prod:first-owner:finalize] Production preflight..."
WAPP_PROD_ENV="$ENV_FILE" node scripts/prod-preflight.mjs

echo "[prod:first-owner:finalize] Finalizing password through STDIN..."

printf '%s' "$OWNER_PASSWORD" \
  | docker compose \
      --env-file "$ENV_FILE" \
      -f "$COMPOSE_FILE" \
      run \
      --rm \
      -T \
      -e "BOOTSTRAP_OWNER_EMAIL=$OWNER_EMAIL" \
      api \
      node \
      dist/scripts/prod-first-owner-finalize.js

unset OWNER_PASSWORD OWNER_PASSWORD_CONFIRM

echo
echo "[prod:first-owner:finalize] First OWNER is ready for login."
