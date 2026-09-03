#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TLS_DIR="${WAPP_MYSQL_TLS_DIR:-infra/production/mysql-tls}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required for production MySQL TLS validation."
  exit 1
fi

for file in \
  ca.pem \
  server-cert.pem \
  server-key.pem
do
  if [[ ! -s "$TLS_DIR/$file" ]]; then
    echo "ERROR: missing MySQL TLS file: $TLS_DIR/$file"
    echo "Run pnpm prod:mysql:tls:init on the production deployment host."
    exit 1
  fi
done

openssl verify \
  -CAfile "$TLS_DIR/ca.pem" \
  "$TLS_DIR/server-cert.pem" \
  >/dev/null

if ! openssl x509 \
  -in "$TLS_DIR/server-cert.pem" \
  -noout \
  -checkend 2592000
then
  echo "ERROR: MySQL server certificate expires in less than 30 days."
  exit 1
fi

san="$(
  openssl x509 \
    -in "$TLS_DIR/server-cert.pem" \
    -noout \
    -ext subjectAltName
)"

if ! grep -Fq "DNS:mysql" <<<"$san"; then
  echo "ERROR: MySQL server certificate is missing SAN DNS:mysql."
  exit 1
fi

if [[ -e "$TLS_DIR/ca-key.pem" ]]; then
  if git check-ignore -q "$TLS_DIR/ca-key.pem"; then
    :
  else
    echo "ERROR: CA private key is not ignored by Git."
    exit 1
  fi
fi

echo "[prod:mysql:tls:check] PASS — chain valid, SAN mysql present, certificate valid for >30 days."
