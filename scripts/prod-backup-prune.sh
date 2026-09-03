#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=/dev/null
source scripts/prod-backup-common.sh

require_backup_config
acquire_prod_backup_lock

MODE="${1:-dry-run}"

if [[ "$MODE" == "--apply" ]]; then
  MODE="apply"
elif [[ "$MODE" == "dry-run" || -z "$MODE" ]]; then
  MODE="dry-run"
else
  echo "Usage: pnpm prod:backup:prune [-- --apply]"
  exit 2
fi

node scripts/prod-backup-prune.mjs \
  "$BACKUP_DIR" \
  "$BACKUP_RETENTION_DAYS" \
  "$BACKUP_MIN_KEEP" \
  "$MODE"
