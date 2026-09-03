#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command_name in docker node; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: $command_name is required for RH4 drill."
    exit 1
  fi
done

RUN_ID="$(
  node -e 'process.stdout.write(`${Date.now()}-${process.pid}`)'
)"

MYSQL_NAME="wapp-rh4-mysql-$RUN_ID"
TMP_DIR="$ROOT_DIR/.runtime/rh4-backup-drill-$RUN_ID"
ROOT_PASSWORD="Rh4RootPassword123456"
PASSPHRASE_FILE="$TMP_DIR/passphrase"
PLAIN="$TMP_DIR/source.sql"
ENCRYPTED="$TMP_DIR/wapp-db-20990101T000000Z-drill.wappbak"
MANIFEST="$TMP_DIR/wapp-db-20990101T000000Z-drill.manifest.json"
RESTORED="$TMP_DIR/restored.sql"
TAMPERED="$TMP_DIR/tampered.wappbak"
TAMPER_OUT="$TMP_DIR/tampered.sql"

cleanup() {
  set +e

  docker rm \
    -f \
    "$MYSQL_NAME" \
    >/dev/null 2>&1 || true

  rm -rf \
    "$TMP_DIR"
}

trap cleanup EXIT INT TERM

mkdir -p "$TMP_DIR"

printf '%s\n' \
  "Rh4DisposableBackupPassphrase_12345678901234567890" \
  > "$PASSPHRASE_FILE"

chmod 600 "$PASSPHRASE_FILE" 2>/dev/null || true

echo "[RH4 drill] Starting disposable MySQL 8.4 without named volumes..."

docker run \
  -d \
  --name "$MYSQL_NAME" \
  -e "MYSQL_ROOT_PASSWORD=$ROOT_PASSWORD" \
  mysql:8.4 \
  >/dev/null

ready=0

for _ in $(seq 1 90); do
  if docker exec \
    -e "MYSQL_PWD=$ROOT_PASSWORD" \
    "$MYSQL_NAME" \
    mysqladmin \
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
  echo "ERROR: disposable RH4 MySQL did not become ready."
  docker logs --tail=100 "$MYSQL_NAME" || true
  exit 1
fi

echo "[RH4 drill] Seeding authoritative source data..."

docker exec \
  -i \
  -e "MYSQL_PWD=$ROOT_PASSWORD" \
  "$MYSQL_NAME" \
  mysql \
    --host=127.0.0.1 \
    --user=root \
  <<'SQL'
CREATE DATABASE wapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE wapp;
CREATE TABLE rh4_restore_probe (
  id INT PRIMARY KEY,
  label VARCHAR(100) NOT NULL,
  amount INT NOT NULL
);
INSERT INTO rh4_restore_probe (id, label, amount) VALUES
  (1, 'first', 10),
  (2, 'second', 20),
  (3, 'third', 30);
SQL

echo "[RH4 drill] Creating logical dump..."

docker exec \
  -e "MYSQL_PWD=$ROOT_PASSWORD" \
  "$MYSQL_NAME" \
  mysqldump \
    --host=127.0.0.1 \
    --user=root \
    --single-transaction \
    --quick \
    --hex-blob \
    --set-gtid-purged=OFF \
    --no-tablespaces \
    wapp \
  > "$PLAIN"

if [[ ! -s "$PLAIN" ]]; then
  echo "ERROR: RH4 drill dump is empty."
  exit 1
fi

echo "[RH4 drill] Encrypting + manifesting backup..."

node scripts/prod-backup-crypto.mjs \
  encrypt \
  "$PLAIN" \
  "$ENCRYPTED" \
  "$PASSPHRASE_FILE"

node scripts/prod-backup-manifest.mjs \
  create \
  "$ENCRYPTED" \
  "$MANIFEST" \
  wapp \
  drill

node scripts/prod-backup-manifest.mjs \
  verify \
  "$ENCRYPTED" \
  "$MANIFEST" \
  wapp \
  >/dev/null

echo "[RH4 drill] Proving encrypted payload authentication detects tampering..."

cp \
  "$ENCRYPTED" \
  "$TAMPERED"

node - "$TAMPERED" <<'NODE'
const fs = require("node:fs");

const path =
  process.argv[
    2
  ];

const file =
  fs.openSync(
    path,
    "r+"
  );

try {
  const info =
    fs.fstatSync(
      file
    );

  const position =
    Math.floor(
      info.size /
      2
    );

  const byte =
    Buffer.alloc(
      1
    );

  fs.readSync(
    file,
    byte,
    0,
    1,
    position
  );

  byte[
    0
  ] ^=
    0x01;

  fs.writeSync(
    file,
    byte,
    0,
    1,
    position
  );
} finally {
  fs.closeSync(
    file
  );
}
NODE

set +e
node scripts/prod-backup-crypto.mjs \
  decrypt \
  "$TAMPERED" \
  "$TAMPER_OUT" \
  "$PASSPHRASE_FILE" \
  >/dev/null 2>&1
tamper_status=$?
set -e

if [[ "$tamper_status" -eq 0 ]]; then
  echo "ERROR: tampered encrypted backup was accepted."
  exit 1
fi

echo "[RH4 drill] Destroying source database to make the restore meaningful..."

docker exec \
  -e "MYSQL_PWD=$ROOT_PASSWORD" \
  "$MYSQL_NAME" \
  mysql \
    --host=127.0.0.1 \
    --user=root \
    -e "DROP DATABASE wapp; CREATE DATABASE wapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

echo "[RH4 drill] Decrypting + restoring..."

node scripts/prod-backup-crypto.mjs \
  decrypt \
  "$ENCRYPTED" \
  "$RESTORED" \
  "$PASSPHRASE_FILE"

docker exec \
  -i \
  -e "MYSQL_PWD=$ROOT_PASSWORD" \
  "$MYSQL_NAME" \
  mysql \
    --host=127.0.0.1 \
    --user=root \
    wapp \
  < "$RESTORED"

probe="$(
  docker exec \
    -e "MYSQL_PWD=$ROOT_PASSWORD" \
    "$MYSQL_NAME" \
    mysql \
      --host=127.0.0.1 \
      --user=root \
      --batch \
      --skip-column-names \
      wapp \
      -e "SELECT CONCAT(COUNT(*), ':', SUM(amount)) FROM rh4_restore_probe;" \
    | tr -d '\r'
)"

if [[ "$probe" != "3:60" ]]; then
  echo "ERROR: restore verification mismatch; expected 3:60, got $probe"
  exit 1
fi

echo
echo "[RH4 drill] PASS — encrypted backup, tamper detection, destructive loss and restore all verified."
