#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required."
  exit 1
fi

RUN_ID="$(
  node -e 'process.stdout.write(`${Date.now()}-${process.pid}`)'
)"

TMP_DIR="$ROOT_DIR/.runtime/rh3-openssl-subject-$RUN_ID"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

mkdir -p "$TMP_DIR"

openssl genrsa \
  -out "$TMP_DIR/key.pem" \
  2048 \
  >/dev/null 2>&1

MSYS2_ARG_CONV_EXCL='/CN=' openssl req \
  -new \
  -key "$TMP_DIR/key.pem" \
  -subj "/CN=rh3-openssl-smoke" \
  -out "$TMP_DIR/request.csr" \
  >/dev/null 2>&1

subject="$(
  openssl req \
    -in "$TMP_DIR/request.csr" \
    -noout \
    -subject
)"

if ! grep -Fq "CN = rh3-openssl-smoke" <<<"$subject" && \
   ! grep -Fq "CN=rh3-openssl-smoke" <<<"$subject"; then
  echo "ERROR: OpenSSL subject smoke produced unexpected subject:"
  printf '%s\n' "$subject"
  exit 1
fi

echo "[RH3a] OpenSSL subject smoke PASS — $subject"
