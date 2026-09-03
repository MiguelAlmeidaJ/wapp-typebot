#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=/dev/null
source scripts/prod-backup-common.sh

require_backup_config

BACKUP_FILE="${1:-}"

if [[ -z "$BACKUP_FILE" ]]; then
  echo "Usage: pnpm prod:backup:verify -- /absolute/path/to/backup.wappbak"
  exit 2
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "ERROR: backup file does not exist: $BACKUP_FILE"
  exit 1
fi

MANIFEST_FILE="$(manifest_for_backup "$BACKUP_FILE")"

if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo "ERROR: backup manifest does not exist: $MANIFEST_FILE"
  exit 1
fi

node scripts/prod-backup-manifest.mjs \
  verify \
  "$BACKUP_FILE" \
  "$MANIFEST_FILE" \
  "$MYSQL_DATABASE" \
  >/dev/null

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wapp-prod-backup-verify.XXXXXX")"
PLAIN_FILE="$TMP_DIR/backup.sql"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

node scripts/prod-backup-crypto.mjs \
  decrypt \
  "$BACKUP_FILE" \
  "$PLAIN_FILE" \
  "$BACKUP_PASSPHRASE_FILE"

if [[ ! -s "$PLAIN_FILE" ]]; then
  echo "ERROR: decrypted backup is empty."
  exit 1
fi

if ! grep -a -Fq -- "-- MySQL dump" "$PLAIN_FILE" && \
   ! grep -a -Fq -- "SET " "$PLAIN_FILE"; then
  echo "ERROR: decrypted payload does not look like a MySQL logical dump."
  exit 1
fi

echo "[prod:backup:verify] PASS — encrypted backup integrity and SQL payload verified."
