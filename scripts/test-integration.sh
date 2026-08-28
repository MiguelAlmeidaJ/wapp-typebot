#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE="infra/test/docker-compose.integration.yml"
PROJECT="wapp-it-${RANDOM}-$$"

if ! docker version >/dev/null 2>&1; then
  echo "ERROR: Docker is required for P1.25 integration tests."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose is required for P1.25 integration tests."
  exit 1
fi

cleanup() {
  docker compose \
    -p "$PROJECT" \
    -f "$COMPOSE_FILE" \
    down \
    --remove-orphans \
    >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

echo "[integration] Starting disposable MySQL + Redis..."
docker compose \
  -p "$PROJECT" \
  -f "$COMPOSE_FILE" \
  up \
  -d \
  --wait

MYSQL_PORT="$(
  docker compose \
    -p "$PROJECT" \
    -f "$COMPOSE_FILE" \
    port mysql 3306 |
    tail -n 1 |
    awk -F: '{print $NF}' |
    tr -d '\r'
)"

REDIS_PORT="$(
  docker compose \
    -p "$PROJECT" \
    -f "$COMPOSE_FILE" \
    port redis 6379 |
    tail -n 1 |
    awk -F: '{print $NF}' |
    tr -d '\r'
)"

if [[ -z "$MYSQL_PORT" || -z "$REDIS_PORT" ]]; then
  echo "ERROR: could not resolve disposable service ports."
  exit 1
fi

export NODE_ENV=test
export DATABASE_URL="mysql://wapp_test:wapp_test_password@127.0.0.1:${MYSQL_PORT}/wapp_test"
export REDIS_URL="redis://127.0.0.1:${REDIS_PORT}/0"
export WEB_URL="http://localhost:3000"
export TRUST_PROXY=false
export JWT_SECRET="integration_jwt_secret_abcdefghijklmnopqrstuvwxyz_123456"
export COOKIE_SECURE=false
export EVOLUTION_BASE_URL="http://127.0.0.1:9"
export EVOLUTION_API_KEY="integration_evolution_api_key_abcdefghijklmnopqrstuvwxyz"
export EVOLUTION_WEBHOOK_BASE_URL="http://localhost:4000"
export EVOLUTION_WEBHOOK_SECRET="integration_webhook_secret_abcdefghijklmnopqrstuvwxyz"
export EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS=3600
export MEDIA_STORAGE_DRIVER=local
export MEDIA_STORAGE_PATH=".runtime/integration-media"
export JOBS_EMBEDDED_WORKER=false

echo "[integration] Applying real Prisma migrations..."
pnpm --filter @wapp/api db:deploy

echo "[integration] Running API integration suite..."
pnpm --filter @wapp/api exec \
  tsx --test \
  src/integration/critical.integration.test.ts

echo "[integration] PASS"
