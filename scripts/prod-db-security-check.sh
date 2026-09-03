#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${WAPP_PROD_ENV:-infra/production/.env.production}"
COMPOSE_FILE="infra/production/docker-compose.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing $ENV_FILE"
  exit 1
fi

echo "[prod:mysql:verify] TLS assets..."
bash scripts/prod-mysql-tls-check.sh

echo "[prod:mysql:verify] Server secure-transport state..."
server_state="$(
  docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    exec \
    -T \
    mysql \
    sh \
    -lc '
      MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
      mysql \
        --ssl-mode=REQUIRED \
        --host=127.0.0.1 \
        --user=root \
        --batch \
        --skip-column-names \
        -e "SELECT @@require_secure_transport, @@tls_version;"
    '
)"

printf '%s\n' "$server_state"

if ! grep -Eq '^(1|ON)[[:space:]]' <<<"$server_state"; then
  echo "ERROR: MySQL require_secure_transport is not ON."
  exit 1
fi

echo "[prod:mysql:verify] Application account authentication plugin..."
auth_state="$(
  docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    exec \
    -T \
    mysql \
    sh \
    -lc '
      MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
      mysql \
        --ssl-mode=REQUIRED \
        --host=127.0.0.1 \
        --user=root \
        --batch \
        --skip-column-names \
        -e "SELECT user, host, plugin FROM mysql.user WHERE user = '\''$MYSQL_USER'\'';"
    '
)"

printf '%s\n' "$auth_state"

if ! grep -Fq "caching_sha2_password" <<<"$auth_state"; then
  echo "ERROR: application MySQL account is not using caching_sha2_password."
  exit 1
fi

echo "[prod:mysql:verify] Plain TCP connection must be rejected..."
set +e
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  exec \
  -T \
  mysql \
  sh \
  -lc '
    MYSQL_PWD="$MYSQL_PASSWORD" \
    mysql \
      --ssl-mode=DISABLED \
      --host=mysql \
      --user="$MYSQL_USER" \
      "$MYSQL_DATABASE" \
      -e "SELECT 1;" \
      >/dev/null 2>&1
  '
plaintext_status=$?
set -e

if [[ "$plaintext_status" -eq 0 ]]; then
  echo "ERROR: MySQL accepted an unencrypted TCP connection."
  exit 1
fi

echo "[prod:mysql:verify] Runtime API Prisma TLS session..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  exec \
  -T \
  api \
  node \
  dist/scripts/db-transport-check.js

echo
echo "[prod:mysql:verify] PASS — server requires TLS, app user uses caching_sha2_password, plaintext TCP denied, Prisma session encrypted."
