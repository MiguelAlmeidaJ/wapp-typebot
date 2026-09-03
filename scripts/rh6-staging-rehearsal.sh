#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command_name in docker pnpm node; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: $command_name is required for RH6 staging rehearsal."
    exit 1
  fi
done

echo "[RH6 staging] Docker availability..."
docker info >/dev/null

echo "[RH6 staging] Production Compose structural configuration..."
docker compose \
  --env-file infra/production/.env.production.example \
  -f infra/production/docker-compose.yml \
  config \
  --quiet

echo "[RH6 staging] Integration suite..."
pnpm test:integration

echo "[RH6 staging] MySQL 8.4 production TLS rehearsal..."
pnpm rh3:mysql:rehearsal

echo "[RH6 staging] Encrypted backup / destructive restore drill..."
pnpm rh4:backup:drill

echo "[RH6 staging] First OWNER full lifecycle drill..."
pnpm rh5:first-owner:drill

echo
echo "[RH6 staging] PASS — isolated production-path rehearsal completed."
echo "No production Compose project, production database or named production volume was touched."
