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
REASON_RAW="${WAPP_BACKUP_REASON:-scheduled}"

REASON="$(
  printf '%s' "$REASON_RAW" \
    | tr '[:space:]' '-' \
    | tr -cd 'A-Za-z0-9._-' \
    | cut -c1-40
)"

if [[ -z "$REASON" ]]; then
  REASON="scheduled"
fi

echo "[prod:backup:create] Production preflight..."
WAPP_PROD_ENV="$ENV_FILE" node scripts/prod-preflight.mjs

echo "[prod:backup:create] MySQL TLS assets..."
bash scripts/prod-mysql-tls-check.sh

echo "[prod:backup:create] Confirming MySQL is running..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  exec \
  -T \
  mysql \
  true \
  >/dev/null

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE="wapp-db-${STAMP}-${REASON}"
FINAL_BACKUP="$BACKUP_DIR/$BASE.wappbak"
FINAL_MANIFEST="$BACKUP_DIR/$BASE.manifest.json"

if [[ -e "$FINAL_BACKUP" || -e "$FINAL_MANIFEST" ]]; then
  echo "ERROR: backup target already exists for this timestamp."
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wapp-prod-backup-create.XXXXXX")"
PLAIN_FILE="$TMP_DIR/database.sql"
ENCRYPTED_PARTIAL="$BACKUP_DIR/.$BASE.wappbak.partial"
MANIFEST_PARTIAL="$BACKUP_DIR/.$BASE.manifest.json.partial"

cleanup() {
  rm -rf "$TMP_DIR"
  rm -f "$ENCRYPTED_PARTIAL" "$MANIFEST_PARTIAL"
}

trap cleanup EXIT INT TERM

echo "[prod:backup:create] Creating transaction-consistent MySQL dump..."

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  exec \
  -T \
  mysql \
  sh \
  -lc '
    exec env MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
      mysqldump \
        --ssl-mode=VERIFY_IDENTITY \
        --ssl-ca=/etc/mysql/tls/ca.pem \
        --host=127.0.0.1 \
        --user=root \
        --single-transaction \
        --quick \
        --routines \
        --events \
        --triggers \
        --hex-blob \
        --set-gtid-purged=OFF \
        --no-tablespaces \
        "$MYSQL_DATABASE"
  ' \
  > "$PLAIN_FILE"

if [[ ! -s "$PLAIN_FILE" ]]; then
  echo "ERROR: mysqldump produced an empty file."
  exit 1
fi

echo "[prod:backup:create] Encrypting before external persistence..."

node scripts/prod-backup-crypto.mjs \
  encrypt \
  "$PLAIN_FILE" \
  "$ENCRYPTED_PARTIAL" \
  "$BACKUP_PASSPHRASE_FILE"

node scripts/prod-backup-manifest.mjs \
  create \
  "$ENCRYPTED_PARTIAL" \
  "$MANIFEST_PARTIAL" \
  "$MYSQL_DATABASE" \
  "$REASON"

mv \
  "$ENCRYPTED_PARTIAL" \
  "$FINAL_BACKUP"

mv \
  "$MANIFEST_PARTIAL" \
  "$FINAL_MANIFEST"

chmod 600 \
  "$FINAL_BACKUP" \
  "$FINAL_MANIFEST" \
  2>/dev/null || true

echo "[prod:backup:create] Verifying encrypted artifact..."
bash scripts/prod-backup-verify.sh \
  "$FINAL_BACKUP"

if [[ "$BACKUP_AUTO_PRUNE" == "true" ]]; then
  echo "[prod:backup:create] Applying retention policy..."
  bash scripts/prod-backup-prune.sh \
    --apply
fi

echo
echo "[prod:backup:create] PASS."
echo "Backup: $FINAL_BACKUP"
echo "Manifest: $FINAL_MANIFEST"
echo "BACKUP_FILE=$FINAL_BACKUP"
