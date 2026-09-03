#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command_name in docker pnpm node; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: $command_name is required for RH5 drill."
    exit 1
  fi
done

RUN_ID="$(
  node -e 'process.stdout.write(`${Date.now()}-${process.pid}`)'
)"

MYSQL_NAME="wapp-rh5-mysql-$RUN_ID"
ROOT_PASSWORD="Rh5RootPassword123456"
APP_PASSWORD="Rh5AppPassword123456"
OWNER_EMAIL="owner-rh5@example.test"
OWNER_NAME="RH5 Owner"
COMPANY_NAME="RH5 Company"
FINAL_PASSWORD="A-Strong#Owner-Passphrase-9482"
MYSQL_PORT=""

cleanup() {
  set +e
  docker rm \
    -f \
    "$MYSQL_NAME" \
    >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

echo "[RH5 drill] Starting disposable MySQL 8.4 without named volumes..."

docker run \
  -d \
  --name "$MYSQL_NAME" \
  -e "MYSQL_ROOT_PASSWORD=$ROOT_PASSWORD" \
  -e "MYSQL_DATABASE=wapp" \
  -e "MYSQL_USER=wapp" \
  -e "MYSQL_PASSWORD=$APP_PASSWORD" \
  -p "127.0.0.1::3306" \
  mysql:8.4 \
  >/dev/null

ready=0

for _ in $(seq 1 90); do
  if docker exec \
    -e "MYSQL_PWD=$ROOT_PASSWORD" \
    "$MYSQL_NAME" \
    mysqladmin \
      --host=127.0.0.1 \
      --user=root \
      --silent \
      ping \
      >/dev/null 2>&1
  then
    ready=1
    break
  fi

  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  echo "ERROR: disposable RH5 MySQL did not become ready."
  docker logs --tail=100 "$MYSQL_NAME" || true
  exit 1
fi

MYSQL_PORT="$(
  docker port \
    "$MYSQL_NAME" \
    3306/tcp \
    | head -n 1 \
    | sed -E 's/.*:([0-9]+)$/\1/'
)"

if [[ ! "$MYSQL_PORT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: could not resolve disposable RH5 MySQL host port."
  exit 1
fi

DATABASE_URL="mysql://wapp:${APP_PASSWORD}@127.0.0.1:${MYSQL_PORT}/wapp"
SHADOW_DATABASE_URL="mysql://wapp:${APP_PASSWORD}@127.0.0.1:${MYSQL_PORT}/wapp_shadow"

runtime_env=(
  "NODE_ENV=test"
  "RH5_ALLOW_NON_PRODUCTION=true"
  "HOST=127.0.0.1"
  "PORT=4000"
  "WEB_URL=http://127.0.0.1:3000"
  "TRUST_PROXY=false"
  "DATABASE_URL=$DATABASE_URL"
  "SHADOW_DATABASE_URL=$SHADOW_DATABASE_URL"
  "JOBS_EMBEDDED_WORKER=false"
  "JWT_SECRET=Rh5SyntheticJwtSecret_123456789012345678901234567890"
  "METRICS_TOKEN=Rh5SyntheticMetricsToken_123456789012345678901234567"
  "COOKIE_SECURE=false"
  "EVOLUTION_BASE_URL=http://127.0.0.1:18080"
  "EVOLUTION_API_KEY=Rh5SyntheticEvolutionKey_12345678901234567890123456"
  "EVOLUTION_WEBHOOK_BASE_URL=http://127.0.0.1:4000"
  "EVOLUTION_WEBHOOK_SECRET=Rh5SyntheticWebhookSecret_12345678901234567890123456"
  "MEDIA_STORAGE_DRIVER=local"
)

echo "[RH5 drill] Preparing distinct Prisma shadow database..."

docker exec \
  -e "MYSQL_PWD=$ROOT_PASSWORD" \
  "$MYSQL_NAME" \
  mysql \
    --host=127.0.0.1 \
    --user=root \
    -e "CREATE DATABASE wapp_shadow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL PRIVILEGES ON wapp_shadow.* TO 'wapp'@'%'; FLUSH PRIVILEGES;"

echo "[RH5 drill] Applying complete Prisma migration history..."

env \
  "${runtime_env[@]}" \
  pnpm \
    --filter @wapp/api \
    db:deploy

echo "[RH5 drill] Confirming empty first-OWNER state..."

empty_status="$(
  env \
    "${runtime_env[@]}" \
    pnpm \
      --filter @wapp/api \
      exec \
      tsx \
      src/scripts/prod-first-owner-status.ts \
      | tail -n 1
)"

if ! grep -Fq '"state":"EMPTY"' <<<"$empty_status"; then
  echo "ERROR: expected EMPTY first-owner state."
  printf '%s\n' "$empty_status"
  exit 1
fi

echo "[RH5 drill] Creating sealed OWNER..."

bootstrap_output="$(
  env \
    "${runtime_env[@]}" \
    "BOOTSTRAP_OWNER_EMAIL=$OWNER_EMAIL" \
    "BOOTSTRAP_OWNER_NAME=$OWNER_NAME" \
    "BOOTSTRAP_COMPANY_NAME=$COMPANY_NAME" \
    pnpm \
      --filter @wapp/api \
      exec \
      tsx \
      src/scripts/prod-first-owner-bootstrap.ts
)"

printf '%s\n' "$bootstrap_output"

if grep -Fq "$FINAL_PASSWORD" <<<"$bootstrap_output"; then
  echo "ERROR: bootstrap output leaked the final password."
  exit 1
fi

pending_status="$(
  env \
    "${runtime_env[@]}" \
    pnpm \
      --filter @wapp/api \
      exec \
      tsx \
      src/scripts/prod-first-owner-status.ts \
      | tail -n 1
)"

if ! grep -Fq '"state":"PENDING_PASSWORD_FINALIZATION"' <<<"$pending_status"; then
  echo "ERROR: expected pending password finalization state."
  printf '%s\n' "$pending_status"
  exit 1
fi

echo "[RH5 drill] Proving bootstrap cannot run twice..."

set +e
env \
  "${runtime_env[@]}" \
  "BOOTSTRAP_OWNER_EMAIL=$OWNER_EMAIL" \
  "BOOTSTRAP_OWNER_NAME=$OWNER_NAME" \
  "BOOTSTRAP_COMPANY_NAME=$COMPANY_NAME" \
  pnpm \
    --filter @wapp/api \
    exec \
    tsx \
    src/scripts/prod-first-owner-bootstrap.ts \
    >/dev/null 2>&1
second_bootstrap_status=$?
set -e

if [[ "$second_bootstrap_status" -eq 0 ]]; then
  echo "ERROR: second first-OWNER bootstrap unexpectedly succeeded."
  exit 1
fi

echo "[RH5 drill] Finalizing real OWNER password through STDIN..."

printf '%s' "$FINAL_PASSWORD" \
  | env \
      "${runtime_env[@]}" \
      "BOOTSTRAP_OWNER_EMAIL=$OWNER_EMAIL" \
      pnpm \
        --filter @wapp/api \
        exec \
        tsx \
        src/scripts/prod-first-owner-finalize.ts

ready_status="$(
  env \
    "${runtime_env[@]}" \
    pnpm \
      --filter @wapp/api \
      exec \
      tsx \
      src/scripts/prod-first-owner-status.ts \
      | tail -n 1
)"

if ! grep -Fq '"state":"READY"' <<<"$ready_status"; then
  echo "ERROR: expected READY first-owner state after finalization."
  printf '%s\n' "$ready_status"
  exit 1
fi

echo "[RH5 drill] Proving final password command is one-time..."

set +e
printf '%s' "$FINAL_PASSWORD" \
  | env \
      "${runtime_env[@]}" \
      "BOOTSTRAP_OWNER_EMAIL=$OWNER_EMAIL" \
      pnpm \
        --filter @wapp/api \
        exec \
        tsx \
        src/scripts/prod-first-owner-finalize.ts \
        >/dev/null 2>&1
second_finalize_status=$?
set -e

if [[ "$second_finalize_status" -eq 0 ]]; then
  echo "ERROR: second OWNER password finalization unexpectedly succeeded."
  exit 1
fi

echo
echo "[RH5 drill] PASS — empty-state guard, sealed OWNER creation, mandatory password finalization and one-shot behavior verified."
