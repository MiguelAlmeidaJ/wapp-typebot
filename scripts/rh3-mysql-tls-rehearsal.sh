#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command_name in openssl docker pnpm node; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: $command_name is required for RH3 rehearsal."
    exit 1
  fi
done

RUN_ID="$(
  node -e 'process.stdout.write(`${Date.now()}-${process.pid}`)'
)"

MYSQL_NAME="wapp-rh3-mysql-${RUN_ID}"
TLS_DIR_POSIX="$ROOT_DIR/.runtime/rh3-mysql-tls-${RUN_ID}"
ROOT_PASSWORD="Rh3RootPassword123456"
APP_PASSWORD="Rh3AppPassword123456"
MYSQL_PORT=""

mkdir -p "$TLS_DIR_POSIX"

cleanup() {
  set +e
  docker rm \
    -f \
    "$MYSQL_NAME" \
    >/dev/null 2>&1 || true

  rm -rf \
    "$TLS_DIR_POSIX"
}

trap cleanup EXIT INT TERM

echo "[RH3 rehearsal] Generating disposable CA/server certificate..."

openssl genrsa \
  -out "$TLS_DIR_POSIX/ca-key.pem" \
  2048 \
  >/dev/null 2>&1

MSYS2_ARG_CONV_EXCL='/CN=' openssl req \
  -x509 \
  -new \
  -nodes \
  -key "$TLS_DIR_POSIX/ca-key.pem" \
  -sha256 \
  -days 1 \
  -subj "/CN=Wapp RH3 Disposable CA" \
  -out "$TLS_DIR_POSIX/ca.pem" \
  >/dev/null 2>&1

openssl genrsa \
  -out "$TLS_DIR_POSIX/server-key.pem" \
  2048 \
  >/dev/null 2>&1

MSYS2_ARG_CONV_EXCL='/CN=' openssl req \
  -new \
  -key "$TLS_DIR_POSIX/server-key.pem" \
  -subj "/CN=rh3-mysql" \
  -out "$TLS_DIR_POSIX/server.csr" \
  >/dev/null 2>&1

cat > "$TLS_DIR_POSIX/server-ext.cnf" <<'CERT'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:rh3-mysql,DNS:localhost,IP:127.0.0.1
CERT

openssl x509 \
  -req \
  -in "$TLS_DIR_POSIX/server.csr" \
  -CA "$TLS_DIR_POSIX/ca.pem" \
  -CAkey "$TLS_DIR_POSIX/ca-key.pem" \
  -CAcreateserial \
  -out "$TLS_DIR_POSIX/server-cert.pem" \
  -days 1 \
  -sha256 \
  -extfile "$TLS_DIR_POSIX/server-ext.cnf" \
  >/dev/null 2>&1

chmod 644 \
  "$TLS_DIR_POSIX/ca.pem" \
  "$TLS_DIR_POSIX/server-cert.pem" \
  "$TLS_DIR_POSIX/server-key.pem"

HOST_TLS_DIR="$TLS_DIR_POSIX"
NODE_CA_PATH="$TLS_DIR_POSIX/ca.pem"

if command -v cygpath >/dev/null 2>&1; then
  HOST_TLS_DIR="$(
    cygpath \
      -w \
      "$TLS_DIR_POSIX"
  )"

  NODE_CA_PATH="$(
    cygpath \
      -w \
      "$TLS_DIR_POSIX/ca.pem"
  )"
fi

echo "[RH3 rehearsal] Starting disposable MySQL 8.4 with mandatory TLS..."

MSYS_NO_PATHCONV=1 docker run \
  -d \
  --name "$MYSQL_NAME" \
  -e "MYSQL_ROOT_PASSWORD=$ROOT_PASSWORD" \
  -e "MYSQL_DATABASE=wapp" \
  -e "MYSQL_USER=wapp" \
  -e "MYSQL_PASSWORD=$APP_PASSWORD" \
  -p "127.0.0.1::3306" \
  --mount "type=bind,source=$HOST_TLS_DIR,target=/etc/mysql/tls,readonly" \
  mysql:8.4 \
  --require-secure-transport=ON \
  --tls-version=TLSv1.2,TLSv1.3 \
  --ssl-ca=/etc/mysql/tls/ca.pem \
  --ssl-cert=/etc/mysql/tls/server-cert.pem \
  --ssl-key=/etc/mysql/tls/server-key.pem \
  >/dev/null

echo "[RH3 rehearsal] Waiting for MySQL..."

ready=0

for _ in $(seq 1 90); do
  if docker exec \
    -e "MYSQL_PWD=$ROOT_PASSWORD" \
    "$MYSQL_NAME" \
    mysqladmin \
      --ssl-mode=REQUIRED \
      --host=127.0.0.1 \
      --user=root \
      --silent \
      ping \
      >/dev/null 2>&1
  then
    ready=1
    break
  fi

  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  echo "ERROR: disposable MySQL did not become ready."
  docker logs \
    --tail=100 \
    "$MYSQL_NAME" || true
  exit 1
fi

MYSQL_PORT="$(
  docker port \
    "$MYSQL_NAME" \
    3306/tcp \
    | head -n 1 \
    | sed -E 's/.*:([0-9]+)$/\1/'
)"

if [[ ! "$MYSQL_PORT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: could not resolve disposable MySQL host port."
  exit 1
fi

echo "[RH3 rehearsal] Checking caching_sha2_password..."

plugin="$(
  docker exec \
    -e "MYSQL_PWD=$ROOT_PASSWORD" \
    "$MYSQL_NAME" \
    mysql \
      --ssl-mode=REQUIRED \
      --host=127.0.0.1 \
      --user=root \
      --batch \
      --skip-column-names \
      -e "SELECT plugin FROM mysql.user WHERE user='wapp' AND host='%';"
)"

if [[ "$plugin" != "caching_sha2_password" ]]; then
  echo "ERROR: expected caching_sha2_password, got: $plugin"
  exit 1
fi

echo "[RH3 rehearsal] Proving plaintext TCP is rejected..."

set +e
docker exec \
  -e "MYSQL_PWD=$APP_PASSWORD" \
  "$MYSQL_NAME" \
  mysql \
    --ssl-mode=DISABLED \
    --host=127.0.0.1 \
    --user=wapp \
    wapp \
    -e "SELECT 1;" \
    >/dev/null 2>&1
plain_status=$?
set -e

if [[ "$plain_status" -eq 0 ]]; then
  echo "ERROR: disposable MySQL accepted plaintext TCP."
  exit 1
fi

echo "[RH3 rehearsal] Running Wapp Prisma adapter with NODE_ENV=production..."

NODE_ENV=production \
HOST=127.0.0.1 \
PORT=4000 \
WEB_URL=https://wapp.test.invalid \
TRUST_PROXY=true \
DATABASE_URL="mysql://wapp:${APP_PASSWORD}@127.0.0.1:${MYSQL_PORT}/wapp" \
DATABASE_TLS_CA_PATH="$NODE_CA_PATH" \
JOBS_EMBEDDED_WORKER=false \
JWT_SECRET=Rh3SyntheticJwtSecret_123456789012345678901234567890 \
METRICS_TOKEN=Rh3SyntheticMetricsToken_123456789012345678901234567 \
COOKIE_SECURE=true \
EVOLUTION_BASE_URL=https://evolution.test.invalid \
EVOLUTION_API_KEY=Rh3SyntheticEvolutionKey_12345678901234567890123456 \
EVOLUTION_WEBHOOK_BASE_URL=https://wapp.test.invalid \
EVOLUTION_WEBHOOK_SECRET=Rh3SyntheticWebhookSecret_12345678901234567890123456 \
MEDIA_STORAGE_DRIVER=local \
pnpm \
  --filter @wapp/api \
  exec \
  tsx \
  src/scripts/db-transport-check.ts

echo
echo "[RH3 rehearsal] PASS — MySQL 8.4 caching_sha2_password + mandatory TLS works with the Wapp Prisma production adapter."
