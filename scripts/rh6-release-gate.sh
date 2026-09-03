#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:---final}"

case "$MODE" in
  --ci|--final)
    ;;
  *)
    echo "Usage: bash scripts/rh6-release-gate.sh [--ci|--final]"
    exit 2
    ;;
esac

echo "[RH6] Static release topology..."
node scripts/rh6-release-static.mjs

if [[ "$MODE" == "--final" && "${RH6_ALLOW_DIRTY:-false}" != "true" ]]; then
  echo "[RH6] Clean Git gate..."
  node scripts/rh6-git-clean.mjs
fi

echo "[RH6] Production environment template..."
pnpm prod:template

echo "[RH6] Production Compose syntax..."
docker compose \
  --env-file infra/production/.env.production.example \
  -f infra/production/docker-compose.yml \
  config \
  --quiet

echo "[RH6] Prisma schema..."
pnpm --filter @wapp/api exec prisma validate

echo "[RH6] Prisma client generation..."
pnpm db:generate

echo "[RH6] Dependency security..."
node scripts/rh2-dependency-security-gate.mjs
pnpm audit --audit-level moderate
pnpm audit --prod --audit-level moderate

echo "[RH6] Repository security scan..."
pnpm security:scan

echo "[RH6] Unit tests..."
pnpm test

echo "[RH6] Typecheck..."
pnpm typecheck

echo "[RH6] Production build..."
pnpm build

if [[ "$MODE" == "--final" ]]; then
  echo "[RH6] Isolated staging rehearsal..."
  bash scripts/rh6-staging-rehearsal.sh
else
  echo "[RH6] CI mode: Docker staging drills skipped."
fi

echo "[RH6] Final static hardening smokes..."
node scripts/rh3-production-security-smoke.mjs
node scripts/rh4-production-backup-smoke.mjs
node scripts/rh5-first-owner-smoke.mjs

echo "[RH6] Diff whitespace..."
git diff --check

echo
if [[ "$MODE" == "--final" ]]; then
  echo "[RH6] FULL RELEASE GATE PASS."
  echo "Release candidate is approved for an explicit production deployment workflow."
else
  echo "[RH6] CI RELEASE GATE PASS."
fi
