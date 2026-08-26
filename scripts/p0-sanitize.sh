#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.1] Removing legacy secrets/configuration from Git tracking..."

git rm --cached --ignore-unmatch \
  backend/.env \
  frontend/.env \
  backend/config/config.json

backup_and_replace() {
  local current="$1"
  local example="$2"
  local backup="$3"

  if [[ -f "$current" ]]; then
    if [[ ! -f "$backup" ]]; then
      mv "$current" "$backup"
      echo "Backup created: $backup"
    else
      rm -f "$current"
      echo "Backup already exists: $backup"
    fi
  fi

  cp "$example" "$current"
  echo "Local safe config created: $current"
}

backup_and_replace \
  "backend/.env" \
  "backend/.env.example" \
  "backend/.env.legacy.local"

backup_and_replace \
  "frontend/.env" \
  "frontend/.env.example" \
  "frontend/.env.legacy.local"

backup_and_replace \
  "backend/config/config.json" \
  "backend/config/config.example.json" \
  "backend/config/config.legacy.local.json"

echo
echo "[P0.1] Done."
echo "Legacy files remain only as ignored local backups."
echo
echo "Next:"
echo "  1. Review backend/.env and set a local MySQL password."
echo "  2. Generate new JWT_SECRET and JWT_REFRESH_SECRET."
echo "  3. Run: git status"
echo "  4. Commit only the sanitized files."
echo
echo "IMPORTANT: this removes secrets from the current branch going forward,"
