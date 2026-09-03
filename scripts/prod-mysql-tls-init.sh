#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TLS_DIR="${WAPP_MYSQL_TLS_DIR:-infra/production/mysql-tls}"

for command_name in openssl docker; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: $command_name is required."
    exit 1
  fi
done

mkdir -p "$TLS_DIR"

for file in \
  ca-key.pem \
  ca.pem \
  server-key.pem \
  server-cert.pem \
  server.csr \
  server-ext.cnf
do
  if [[ -e "$TLS_DIR/$file" ]]; then
    echo "ERROR: refusing to overwrite existing MySQL TLS material: $TLS_DIR/$file"
    echo "Certificate rotation must be performed as an explicit operation."
    exit 1
  fi
done

echo "[prod:mysql:tls:init] Generating private production CA..."
openssl genrsa \
  -out "$TLS_DIR/ca-key.pem" \
  4096

MSYS2_ARG_CONV_EXCL='/CN=' openssl req \
  -x509 \
  -new \
  -nodes \
  -key "$TLS_DIR/ca-key.pem" \
  -sha256 \
  -days 3650 \
  -subj "/CN=Wapp Production MySQL CA" \
  -out "$TLS_DIR/ca.pem"

echo "[prod:mysql:tls:init] Generating MySQL server key and CSR..."
openssl genrsa \
  -out "$TLS_DIR/server-key.pem" \
  3072

MSYS2_ARG_CONV_EXCL='/CN=' openssl req \
  -new \
  -key "$TLS_DIR/server-key.pem" \
  -subj "/CN=mysql" \
  -out "$TLS_DIR/server.csr"

cat > "$TLS_DIR/server-ext.cnf" <<'CERT'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:mysql,DNS:localhost,IP:127.0.0.1
CERT

openssl x509 \
  -req \
  -in "$TLS_DIR/server.csr" \
  -CA "$TLS_DIR/ca.pem" \
  -CAkey "$TLS_DIR/ca-key.pem" \
  -CAcreateserial \
  -out "$TLS_DIR/server-cert.pem" \
  -days 825 \
  -sha256 \
  -extfile "$TLS_DIR/server-ext.cnf"

rm -f \
  "$TLS_DIR/server.csr" \
  "$TLS_DIR/server-ext.cnf" \
  "$TLS_DIR/ca.srl"

chmod 600 \
  "$TLS_DIR/ca-key.pem" \
  "$TLS_DIR/server-key.pem"

chmod 644 \
  "$TLS_DIR/ca.pem" \
  "$TLS_DIR/server-cert.pem"

echo "[prod:mysql:tls:init] Verifying certificate chain..."
openssl verify \
  -CAfile "$TLS_DIR/ca.pem" \
  "$TLS_DIR/server-cert.pem"

openssl x509 \
  -in "$TLS_DIR/server-cert.pem" \
  -noout \
  -checkend 2592000

if [[ "$(uname -s)" == "Linux" ]]; then
  HOST_TLS_DIR="$TLS_DIR"

  if command -v realpath >/dev/null 2>&1; then
    HOST_TLS_DIR="$(realpath "$TLS_DIR")"
  fi

  echo "[prod:mysql:tls:init] Setting MySQL-container ownership on server TLS files..."

  docker run \
    --rm \
    --entrypoint sh \
    --user 0 \
    --mount "type=bind,source=$HOST_TLS_DIR,target=/tls" \
    mysql:8.4 \
    -c 'chown 999:999 /tls/ca.pem /tls/server-cert.pem /tls/server-key.pem && chmod 644 /tls/ca.pem /tls/server-cert.pem && chmod 600 /tls/server-key.pem'
else
  echo "[prod:mysql:tls:init] WARN: non-Linux host detected."
  echo "Before real Linux production deployment, run this initializer on the deployment host so the MySQL process owns its private key."
fi

echo
echo "[prod:mysql:tls:init] PASS."
echo "CA private key remains host-only: $TLS_DIR/ca-key.pem"
echo "Never mount ca-key.pem into MySQL or application containers."
