#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${WAPP_PROD_ENV:-$ROOT_DIR/infra/production/.env.production}"
COMPOSE_FILE="$ROOT_DIR/infra/production/docker-compose.yml"

prod_env_value() {
  node \
    "$ROOT_DIR/scripts/prod-env-value.mjs" \
    "$ENV_FILE" \
    "$1"
}

require_prod_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: missing production env: $ENV_FILE"
    exit 1
  fi
}

require_backup_config() {
  require_prod_env

  BACKUP_DIR="$(prod_env_value WAPP_BACKUP_DIR)"
  BACKUP_PASSPHRASE_FILE="$(prod_env_value WAPP_BACKUP_PASSPHRASE_FILE)"
  BACKUP_RETENTION_DAYS="$(prod_env_value WAPP_BACKUP_RETENTION_DAYS)"
  BACKUP_MIN_KEEP="$(prod_env_value WAPP_BACKUP_MIN_KEEP)"
  BACKUP_AUTO_PRUNE="$(prod_env_value WAPP_BACKUP_AUTO_PRUNE)"
  MYSQL_DATABASE="$(prod_env_value MYSQL_DATABASE)"

  if [[ -z "$BACKUP_DIR" || -z "$BACKUP_PASSPHRASE_FILE" ]]; then
    echo "ERROR: production backup paths are not configured."
    exit 1
  fi

  case "$BACKUP_DIR" in
    /*) ;;
    *)
      echo "ERROR: WAPP_BACKUP_DIR must be an absolute host path."
      exit 1
      ;;
  esac

  case "$BACKUP_PASSPHRASE_FILE" in
    /*) ;;
    *)
      echo "ERROR: WAPP_BACKUP_PASSPHRASE_FILE must be an absolute host path."
      exit 1
      ;;
  esac

  case "$BACKUP_DIR/" in
    "$ROOT_DIR/"*)
      echo "ERROR: WAPP_BACKUP_DIR must be outside the application repository."
      exit 1
      ;;
  esac

  case "$BACKUP_PASSPHRASE_FILE" in
    "$ROOT_DIR"/*)
      echo "ERROR: backup passphrase file must be outside the application repository."
      exit 1
      ;;
  esac

  if [[ ! "$BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]] || \
     (( BACKUP_RETENTION_DAYS < 7 || BACKUP_RETENTION_DAYS > 3650 )); then
    echo "ERROR: WAPP_BACKUP_RETENTION_DAYS must be between 7 and 3650."
    exit 1
  fi

  if [[ ! "$BACKUP_MIN_KEEP" =~ ^[0-9]+$ ]] || \
     (( BACKUP_MIN_KEEP < 1 || BACKUP_MIN_KEEP > 365 )); then
    echo "ERROR: WAPP_BACKUP_MIN_KEEP must be between 1 and 365."
    exit 1
  fi

  if [[ "$BACKUP_AUTO_PRUNE" != "true" && "$BACKUP_AUTO_PRUNE" != "false" ]]; then
    echo "ERROR: WAPP_BACKUP_AUTO_PRUNE must be true or false."
    exit 1
  fi

  if [[ ! -f "$BACKUP_PASSPHRASE_FILE" ]]; then
    echo "ERROR: backup passphrase file does not exist: $BACKUP_PASSPHRASE_FILE"
    exit 1
  fi

  if [[ "$(uname -s)" == "Linux" ]]; then
    mode="$(stat -c '%a' "$BACKUP_PASSPHRASE_FILE")"

    case "$mode" in
      400|600) ;;
      *)
        echo "ERROR: backup passphrase file permissions must be 400 or 600; found $mode."
        exit 1
        ;;
    esac
  fi

  mkdir -p "$BACKUP_DIR"

  if [[ ! -w "$BACKUP_DIR" ]]; then
    echo "ERROR: backup directory is not writable: $BACKUP_DIR"
    exit 1
  fi

  export \
    BACKUP_DIR \
    BACKUP_PASSPHRASE_FILE \
    BACKUP_RETENTION_DAYS \
    BACKUP_MIN_KEEP \
    BACKUP_AUTO_PRUNE \
    MYSQL_DATABASE
}

acquire_prod_backup_lock() {
  if [[ "${WAPP_BACKUP_LOCK_HELD:-false}" == "true" ]]; then
    return
  fi

  if ! command -v flock >/dev/null 2>&1; then
    echo "ERROR: flock is required on the production backup host."
    exit 1
  fi

  BACKUP_LOCK_FILE="$BACKUP_DIR/.wapp-backup.lock"

  exec 9>"$BACKUP_LOCK_FILE"

  if ! flock -n 9; then
    echo "ERROR: another production backup/restore operation is already running."
    exit 1
  fi

  export WAPP_BACKUP_LOCK_HELD=true
}

manifest_for_backup() {
  local backup="$1"
  printf '%s.manifest.json' "${backup%.wappbak}"
}
