#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

transient=(
  scripts/rh1-production-compose-environment.sh
  scripts/rh2-dependency-security.sh
  scripts/rh2b-pnpm11-overrides-lock-gate.sh
  scripts/rh2c-mariadb-published-patched-line.sh
  scripts/rh2-resume-mariadb-353.sh
  scripts/rh2d-prisma-mysql2-security.sh
  scripts/rh3-mysql-production-security.sh
  scripts/rh3a-git-bash-openssl-subject.sh
  scripts/rh4-production-backup-restore.sh
  scripts/rh5-first-owner-bootstrap.sh
  scripts/rh5a-company-slug-resume.sh
  scripts/rh5b-typescript-localpart-resume.sh
  scripts/rh5c-shadow-db-resume.sh
)

removed=0

for file in "${transient[@]}"; do
  if [[ -f "$file" ]]; then
    rm -f "$file"
    echo "[RH6 cleanup] removed transient installer: $file"
    removed=$((removed + 1))
  fi
done

echo "[RH6 cleanup] PASS — removed $removed transient installer(s)."
