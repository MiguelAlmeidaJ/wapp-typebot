#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=/dev/null
source scripts/prod-backup-common.sh

require_backup_config
acquire_prod_backup_lock

ENV_FILE="${WAPP_PROD_ENV:-infra/production/.env.production}"
COMPOSE_FILE="infra/production/docker-compose.yml"
BACKUP_FILE="${1:-}"
CONFIRMATION="${WAPP_PROD_RESTORE_CONFIRM:-}"
ALLOW_COMMIT_MISMATCH="${WAPP_PROD_RESTORE_ALLOW_COMMIT_MISMATCH:-false}"

if [[ -z "$BACKUP_FILE" ]]; then
  echo "Usage: WAPP_PROD_RESTORE_CONFIRM='RESTORE PRODUCTION DATABASE' pnpm prod:backup:restore -- /absolute/path/to/backup.wappbak"
  exit 2
fi

if [[ "$CONFIRMATION" != "RESTORE PRODUCTION DATABASE" ]]; then
  echo "ERROR: destructive restore refused."
  echo "Set WAPP_PROD_RESTORE_CONFIRM exactly to: RESTORE PRODUCTION DATABASE"
  exit 1
fi

if [[ "$ALLOW_COMMIT_MISMATCH" != "true" && "$ALLOW_COMMIT_MISMATCH" != "false" ]]; then
  echo "ERROR: WAPP_PROD_RESTORE_ALLOW_COMMIT_MISMATCH must be true or false."
  exit 1
fi

MANIFEST_FILE="$(manifest_for_backup "$BACKUP_FILE")"

echo "[prod:backup:restore] Verifying backup before any production change..."
bash scripts/prod-backup-verify.sh \
  "$BACKUP_FILE"

BACKUP_COMMIT="$(
  node scripts/prod-backup-manifest.mjs \
    get \
    _ \
    "$MANIFEST_FILE" \
    gitCommit
)"

CURRENT_COMMIT="$(
  git rev-parse HEAD
)"

if [[ "$BACKUP_COMMIT" != "$CURRENT_COMMIT" && "$ALLOW_COMMIT_MISMATCH" != "true" ]]; then
  echo "ERROR: backup was created from a different application commit."
  echo "Backup commit: $BACKUP_COMMIT"
  echo "Current commit: $CURRENT_COMMIT"
  echo "Checkout the backup commit before restore, or explicitly set WAPP_PROD_RESTORE_ALLOW_COMMIT_MISMATCH=true after compatibility review."
  exit 1
fi

echo "[prod:backup:restore] Production preflight..."
WAPP_PROD_ENV="$ENV_FILE" node scripts/prod-preflight.mjs

echo "[prod:backup:restore] MySQL TLS assets..."
bash scripts/prod-mysql-tls-check.sh

echo "[prod:backup:restore] Creating mandatory pre-restore safety backup..."

safety_output="$(
  WAPP_BACKUP_REASON=pre-restore \
    bash scripts/prod-backup-create.sh
)"

printf '%s\n' "$safety_output"

SAFETY_BACKUP="$(
  printf '%s\n' "$safety_output" \
    | sed -n 's/^BACKUP_FILE=//p' \
    | tail -n 1
)"

if [[ -z "$SAFETY_BACKUP" || ! -f "$SAFETY_BACKUP" ]]; then
  echo "ERROR: mandatory pre-restore safety backup could not be confirmed."
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wapp-prod-restore.XXXXXX")"
PLAIN_FILE="$TMP_DIR/database.sql"
SERVICES_STOPPED=0
RESTORE_SUCCEEDED=0

cleanup() {
  status=$?

  rm -rf "$TMP_DIR"

  if [[ "$SERVICES_STOPPED" -eq 1 && "$RESTORE_SUCCEEDED" -ne 1 ]]; then
    echo
    echo "IMPORTANT: restore did not complete."
    echo "API and worker were intentionally left stopped to avoid serving a partially restored database."
    echo "Safety backup: $SAFETY_BACKUP"
  fi

  exit "$status"
}

trap cleanup EXIT INT TERM

echo "[prod:backup:restore] Decrypting verified backup to ephemeral storage..."

node scripts/prod-backup-crypto.mjs \
  decrypt \
  "$BACKUP_FILE" \
  "$PLAIN_FILE" \
  "$BACKUP_PASSPHRASE_FILE"

echo "[prod:backup:restore] Stopping API and worker..."

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  stop \
  api \
  worker

SERVICES_STOPPED=1

echo "[prod:backup:restore] Recreating application database..."

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  exec \
  -T \
  mysql \
  sh \
  -lc '
    exec env MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
      mysql \
        --ssl-mode=VERIFY_IDENTITY \
        --ssl-ca=/etc/mysql/tls/ca.pem \
        --host=127.0.0.1 \
        --user=root \
        -e "DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`; CREATE DATABASE \`$MYSQL_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  '

echo "[prod:backup:restore] Importing logical backup..."

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  exec \
  -T \
  mysql \
  sh \
  -lc '
    exec env MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
      mysql \
        --ssl-mode=VERIFY_IDENTITY \
        --ssl-ca=/etc/mysql/tls/ca.pem \
        --host=127.0.0.1 \
        --user=root \
        "$MYSQL_DATABASE"
  ' \
  < "$PLAIN_FILE"

echo "[prod:backup:restore] Verifying restored schema is non-empty..."

table_count="$(
  docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    exec \
    -T \
    mysql \
    sh \
    -lc '
      exec env MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
        mysql \
          --ssl-mode=VERIFY_IDENTITY \
          --ssl-ca=/etc/mysql/tls/ca.pem \
          --host=127.0.0.1 \
          --user=root \
          --batch \
          --skip-column-names \
          -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '\''$MYSQL_DATABASE'\'';"
    ' \
    | tr -d '\r'
)"

if [[ ! "$table_count" =~ ^[0-9]+$ ]] || (( table_count < 1 )); then
  echo "ERROR: restored database contains no tables."
  exit 1
fi

echo "[prod:backup:restore] Flushing stale Redis operational state..."

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  exec \
  -T \
  redis \
  sh \
  -lc '
    redis-cli \
      -a "$REDIS_PASSWORD" \
      FLUSHDB \
      >/dev/null
  '

echo "[prod:backup:restore] Starting API and worker..."

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  start \
  api \
  worker

echo "[prod:backup:restore] Verifying production database transport..."
pnpm prod:mysql:verify

RESTORE_SUCCEEDED=1
SERVICES_STOPPED=0

echo
echo "[prod:backup:restore] PASS — production database restored."
echo "Restored backup: $BACKUP_FILE"
echo "Safety backup: $SAFETY_BACKUP"
echo "Restored table count: $table_count"
