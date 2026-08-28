#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE="$ROOT_DIR/infra/docker-compose.yml"
API_ENV="$ROOT_DIR/apps/api/.env"

if [[ $# -lt 1 ]]; then
  echo "Usage: pnpm backup:restore -- <backup-directory> --confirm RESTORE [--db-only]"
  exit 2
fi

BACKUP_DIR="$(node -e 'const p=require("node:path"); console.log(p.resolve(process.argv[1]));' "$1")"
shift

CONFIRM=""
DB_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRM="${2:-}"
      shift 2
      ;;
    --db-only)
      DB_ONLY=true
      shift
      ;;
    *)
      echo "[restore] ERROR: unknown argument: $1"
      exit 2
      ;;
  esac
done

if [[ "$CONFIRM" != "RESTORE" ]]; then
  echo "[restore] Refused. Use --confirm RESTORE explicitly."
  exit 2
fi

env_value() {
  local key="$1"
  [[ -f "$API_ENV" ]] || return 0
  local line
  line="$(grep -E "^${key}=" "$API_ENV" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 0
  local value="${line#*=}"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

MEDIA_DRIVER="$(env_value MEDIA_STORAGE_DRIVER)"
MEDIA_DRIVER="${MEDIA_DRIVER:-local}"
MEDIA_PATH="$(env_value MEDIA_STORAGE_PATH)"
MEDIA_PATH="${MEDIA_PATH:-.runtime/media}"
MEDIA_DIR="$(node -e 'const p=require("node:path"); console.log(p.resolve(process.argv[1], process.argv[2]));' "$ROOT_DIR/apps/api" "$MEDIA_PATH")"

bash "$ROOT_DIR/scripts/backup-verify.sh" "$BACKUP_DIR"

if [[ -d "$BACKUP_DIR/media" && "$MEDIA_DRIVER" != "local" && "$DB_ONLY" != "true" ]]; then
  echo "[restore] ERROR: snapshot contains local media but current driver is $MEDIA_DRIVER."
  echo "[restore] Use --db-only or restore/migrate media separately."
  exit 1
fi

MYSQL_CONTAINER="$(docker compose -f "$COMPOSE" ps -q mysql)"
if [[ -z "$MYSQL_CONTAINER" ]]; then
  echo "[restore] ERROR: local mysql service is not running."
  exit 1
fi

echo "[restore] Creating mandatory pre-restore safety backup..."
bash "$ROOT_DIR/scripts/backup-create.sh" pre-restore

echo "[restore] Restoring database..."
gzip -dc "$BACKUP_DIR/database.sql.gz" \
  | docker compose -f "$COMPOSE" exec -T mysql sh -lc \
      'exec mysql --default-character-set=utf8mb4 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"'

if [[ -d "$BACKUP_DIR/media" && "$DB_ONLY" != "true" ]]; then
  echo "[restore] Merging local media..."
  mkdir -p "$MEDIA_DIR"
  cp -a "$BACKUP_DIR/media/." "$MEDIA_DIR/"
fi

echo "[restore] OK."
echo "[restore] Restart the API and validate /health/ready before releasing traffic."
