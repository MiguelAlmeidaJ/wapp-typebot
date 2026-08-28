#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE="$ROOT_DIR/infra/docker-compose.yml"
BACKUP_ROOT="${WAPP_BACKUP_DIR:-$ROOT_DIR/.backups}"
API_ENV="$ROOT_DIR/apps/api/.env"
REASON="${1:-manual}"

env_value() {
  local key="$1"
  [[ -f "$API_ENV" ]] || return 0
  local line
  line="$(grep -E "^${key}=" "$API_ENV" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 0
  local value="${line#*=}"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

resolve_media_dir() {
  local configured
  configured="$(env_value MEDIA_STORAGE_PATH)"
  configured="${configured:-.runtime/media}"
  node -e 'const p=require("node:path"); console.log(p.resolve(process.argv[1], process.argv[2]));' \
    "$ROOT_DIR/apps/api" "$configured"
}

for command in docker gzip sha256sum node git; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "[backup] ERROR: required command not found: $command"
    exit 1
  }
done

MYSQL_CONTAINER="$(docker compose -f "$COMPOSE" ps -q mysql)"
if [[ -z "$MYSQL_CONTAINER" ]]; then
  echo "[backup] ERROR: local mysql service is not running."
  echo "[backup] Start it with: pnpm infra:up"
  exit 1
fi

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
NAME="wapp-$TIMESTAMP"
FINAL_DIR="$BACKUP_ROOT/$NAME"
TEMP_DIR="$BACKUP_ROOT/.$NAME.tmp-$$"

mkdir -p "$BACKUP_ROOT"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

cleanup() {
  if [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

echo "[backup] Dumping MySQL..."
docker compose -f "$COMPOSE" exec -T mysql sh -lc \
  'exec mysqldump --single-transaction --quick --skip-lock-tables --add-drop-table --hex-blob --set-gtid-purged=OFF --no-tablespaces --default-character-set=utf8mb4 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  | gzip -9 > "$TEMP_DIR/database.sql.gz"

gzip -t "$TEMP_DIR/database.sql.gz"

DB_NAME="$(docker compose -f "$COMPOSE" exec -T mysql sh -lc 'printf "%s" "$MYSQL_DATABASE"')"
MEDIA_DRIVER="$(env_value MEDIA_STORAGE_DRIVER)"
MEDIA_DRIVER="${MEDIA_DRIVER:-local}"
MEDIA_DIR="$(resolve_media_dir)"
MEDIA_INCLUDED=false

if [[ "$MEDIA_DRIVER" == "local" && -d "$MEDIA_DIR" ]]; then
  echo "[backup] Copying local media..."
  mkdir -p "$TEMP_DIR/media"
  cp -a "$MEDIA_DIR/." "$TEMP_DIR/media/"
  MEDIA_INCLUDED=true
fi

COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
DUMP_BYTES="$(node -e 'const fs=require("node:fs"); console.log(fs.statSync(process.argv[1]).size);' "$TEMP_DIR/database.sql.gz")"

read -r MEDIA_FILES MEDIA_BYTES < <(
  node - "$TEMP_DIR/media" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const root = process.argv[2];
let files = 0;
let bytes = 0;
function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const absolute = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(absolute);
    else if (entry.isFile()) {
      files += 1;
      bytes += fs.statSync(absolute).size;
    }
  }
}
walk(root);
process.stdout.write(`${files} ${bytes}\n`);
NODE
)

node - "$TEMP_DIR/manifest.json" "$TIMESTAMP" "$REASON" "$COMMIT" "$DB_NAME" "$DUMP_BYTES" "$MEDIA_DRIVER" "$MEDIA_INCLUDED" "$MEDIA_FILES" "$MEDIA_BYTES" <<'NODE'
const fs = require("node:fs");
const [
  ,
  ,
  output,
  timestamp,
  reason,
  commit,
  database,
  dumpBytes,
  mediaDriver,
  mediaIncluded,
  mediaFiles,
  mediaBytes
] = process.argv;

const manifest = {
  version: 1,
  application: "wapp",
  createdAt: timestamp,
  reason,
  gitCommit: commit || null,
  database: {
    engine: "mysql",
    name: database,
    dump: "database.sql.gz",
    dumpBytes: Number(dumpBytes),
    transport: "docker-compose"
  },
  media: {
    driver: mediaDriver,
    included: mediaIncluded === "true",
    path: mediaIncluded === "true" ? "media" : null,
    files: Number(mediaFiles),
    bytes: Number(mediaBytes)
  }
};

fs.writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
NODE

(
  cd "$TEMP_DIR"
  : > SHA256SUMS
  while IFS= read -r file; do
    sha256sum "$file" >> SHA256SUMS
  done < <(find . -type f ! -name SHA256SUMS | sort)
)

mv "$TEMP_DIR" "$FINAL_DIR"
trap - EXIT

echo "[backup] OK: $FINAL_DIR"
echo "[backup] Verify with:"
echo "pnpm backup:verify -- \"$FINAL_DIR\""
