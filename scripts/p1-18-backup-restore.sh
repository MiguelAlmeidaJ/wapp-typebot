#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.18] Installing backup, verification, retention and safe restore..."

for required in package.json .gitignore infra/docker-compose.yml; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p scripts docs

cat > scripts/backup-create.sh <<'EOF'
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
EOF

cat > scripts/backup-verify.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: pnpm backup:verify -- <backup-directory>"
  exit 2
fi

BACKUP_DIR="$(node -e 'const p=require("node:path"); console.log(p.resolve(process.argv[1]));' "$1")"

for file in manifest.json database.sql.gz SHA256SUMS; do
  if [[ ! -f "$BACKUP_DIR/$file" ]]; then
    echo "[backup:verify] ERROR: missing $file"
    exit 1
  fi
done

(
  cd "$BACKUP_DIR"
  sha256sum -c SHA256SUMS
  gzip -t database.sql.gz
)

echo "[backup:verify] OK: $BACKUP_DIR"
EOF

cat > scripts/backup-restore.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE="$ROOT_DIR/infra/docker-compose.yml"
API_ENV="$ROOT_DIR/apps/api/.env"

if [[ $# -lt 1 ]]; then
  echo "Usage: pnpm backup:restore -- <backup-directory> --confirm RESTORE [--db-only]"
  exit 2
fi

BACKUP_DIR="$(node -e 'const p=require("node:path"); console.log(p.resolve(process.argv[1]));' "$1")"
shift

CONFIRM=""
DB_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRM="${2:-}"
      shift 2
      ;;
    --db-only)
      DB_ONLY=true
      shift
      ;;
    *)
      echo "[restore] ERROR: unknown argument: $1"
      exit 2
      ;;
  esac
done

if [[ "$CONFIRM" != "RESTORE" ]]; then
  echo "[restore] Refused. Use --confirm RESTORE explicitly."
  exit 2
fi

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

MEDIA_DRIVER="$(env_value MEDIA_STORAGE_DRIVER)"
MEDIA_DRIVER="${MEDIA_DRIVER:-local}"
MEDIA_PATH="$(env_value MEDIA_STORAGE_PATH)"
MEDIA_PATH="${MEDIA_PATH:-.runtime/media}"
MEDIA_DIR="$(node -e 'const p=require("node:path"); console.log(p.resolve(process.argv[1], process.argv[2]));' "$ROOT_DIR/apps/api" "$MEDIA_PATH")"

bash "$ROOT_DIR/scripts/backup-verify.sh" "$BACKUP_DIR"

if [[ -d "$BACKUP_DIR/media" && "$MEDIA_DRIVER" != "local" && "$DB_ONLY" != "true" ]]; then
  echo "[restore] ERROR: snapshot contains local media but current driver is $MEDIA_DRIVER."
  echo "[restore] Use --db-only or restore/migrate media separately."
  exit 1
fi

MYSQL_CONTAINER="$(docker compose -f "$COMPOSE" ps -q mysql)"
if [[ -z "$MYSQL_CONTAINER" ]]; then
  echo "[restore] ERROR: local mysql service is not running."
  exit 1
fi

echo "[restore] Creating mandatory pre-restore safety backup..."
bash "$ROOT_DIR/scripts/backup-create.sh" pre-restore

echo "[restore] Restoring database..."
gzip -dc "$BACKUP_DIR/database.sql.gz" \
  | docker compose -f "$COMPOSE" exec -T mysql sh -lc \
      'exec mysql --default-character-set=utf8mb4 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"'

if [[ -d "$BACKUP_DIR/media" && "$DB_ONLY" != "true" ]]; then
  echo "[restore] Merging local media..."
  mkdir -p "$MEDIA_DIR"
  cp -a "$BACKUP_DIR/media/." "$MEDIA_DIR/"
fi

echo "[restore] OK."
echo "[restore] Restart the API and validate /health/ready before releasing traffic."
EOF

cat > scripts/backup-prune.mjs <<'EOF'
import fs from "node:fs/promises";
import path from "node:path";

const args = process.argv.slice(2);
const apply = args.includes("--apply");

function value(name, fallback) {
  const index = args.indexOf(`--${name}`);
  if (index < 0) return fallback;
  const parsed = Number(args[index + 1]);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`--${name} must be an integer >= 0`);
  }
  return parsed;
}

const daily = value("daily", 7);
const weekly = value("weekly", 4);
const monthly = value("monthly", 6);
const root = path.resolve(process.env.WAPP_BACKUP_DIR ?? ".backups");

function parseDate(name) {
  const match = /^wapp-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/.exec(name);
  if (!match) return null;
  const [, y, m, d, hh, mm, ss] = match;
  const date = new Date(`${y}-${m}-${d}T${hh}:${mm}:${ss}Z`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function weekKey(date) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const start = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((d - start) / 86400000) + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

function keepBuckets(backups, keyFn, limit) {
  const keys = new Set();
  const kept = new Set();
  for (const backup of backups) {
    const key = keyFn(backup.date);
    if (keys.has(key)) continue;
    keys.add(key);
    if (kept.size < limit) kept.add(backup.name);
  }
  return kept;
}

let entries;
try {
  entries = await fs.readdir(root, { withFileTypes: true });
} catch (error) {
  if (error?.code === "ENOENT") {
    console.log("[backup:prune] No backup directory.");
    process.exit(0);
  }
  throw error;
}

const backups = entries
  .filter(entry => entry.isDirectory())
  .map(entry => ({ name: entry.name, date: parseDate(entry.name) }))
  .filter(item => item.date)
  .sort((a, b) => b.date - a.date);

if (backups.length === 0) {
  console.log("[backup:prune] No recognized snapshots.");
  process.exit(0);
}

const keep = new Set([backups[0].name]);
for (const name of keepBuckets(backups, d => d.toISOString().slice(0, 10), daily)) keep.add(name);
for (const name of keepBuckets(backups, weekKey, weekly)) keep.add(name);
for (const name of keepBuckets(backups, d => d.toISOString().slice(0, 7), monthly)) keep.add(name);

const remove = backups.filter(item => !keep.has(item.name));

console.log(`[backup:prune] snapshots=${backups.length} keep=${keep.size} remove=${remove.length}`);

for (const backup of remove) {
  console.log(`${apply ? "REMOVING" : "DRY-RUN"} ${backup.name}`);
  if (apply) {
    await fs.rm(path.join(root, backup.name), { recursive: true, force: false });
  }
}

if (!apply && remove.length > 0) {
  console.log("[backup:prune] Nothing removed. Add --apply to execute.");
}
EOF

chmod +x \
  scripts/backup-create.sh \
  scripts/backup-verify.sh \
  scripts/backup-restore.sh

node <<'NODE'
const fs = require("node:fs");
const path = "package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
pkg.scripts ??= {};
Object.assign(pkg.scripts, {
  "backup:create": "bash scripts/backup-create.sh",
  "backup:verify": "bash scripts/backup-verify.sh",
  "backup:prune": "node scripts/backup-prune.mjs",
  "backup:restore": "bash scripts/backup-restore.sh"
});
fs.writeFileSync(path, `${JSON.stringify(pkg, null, 2)}\n`);
NODE

if ! grep -q "^\.backups/$" .gitignore; then
  cat >> .gitignore <<'EOF'

# --- WAPP P1.18 / LOCAL BACKUPS ---
.backups/
# --- /WAPP P1.18 ---
EOF
fi

cat > docs/BACKUP_RESTORE.md <<'EOF'
# P1.18 Backup, restore and retention

Docker volumes provide persistence, not a recovery strategy. P1.18 creates
application-level restore points without deleting Docker volumes.

A snapshot looks like:

```text
.backups/wapp-YYYYMMDDTHHMMSSZ/
├── database.sql.gz
├── media/              # only when local media exists
├── manifest.json
└── SHA256SUMS
```

`.backups/` is ignored by Git. Environment files and application secrets are not
copied into snapshots.

## Create

```bash
pnpm backup:create
```

Optional reason:

```bash
pnpm backup:create -- before-release
```

The local development flow uses the existing MySQL 8.4 Compose service and its
container environment. The dump uses a single transaction and gzip.

If `MEDIA_STORAGE_DRIVER=local`, the local media directory is included. If the
driver is `s3`, media objects are not downloaded into every DB backup; bucket
versioning/provider backup must be configured separately.

## Verify

```bash
pnpm backup:verify -- .backups/wapp-YYYYMMDDTHHMMSSZ
```

Verification checks SHA-256 for every snapshot file and validates the gzip SQL
dump. A backup that has never been verified is not a proven restore point.

## Restore

Stop normal application traffic first.

```bash
pnpm backup:restore -- .backups/wapp-YYYYMMDDTHHMMSSZ --confirm RESTORE
```

Before the destructive database restore, Wapp automatically creates a fresh
`pre-restore` safety backup. The SQL dump contains `DROP TABLE` statements, so
newer database state is intentionally replaced by the selected restore point.

Local media is merged back without deleting extra files.

Emergency database-only restore:

```bash
pnpm backup:restore -- .backups/wapp-YYYYMMDDTHHMMSSZ --confirm RESTORE --db-only
```

After restore: restart API processes, check `/health/ready`, then validate login,
an old conversation/media, and WhatsApp inbound/outbound.

P1.18 never runs `docker compose down -v` and never deletes the MySQL volume.

## Retention

Default retention:

- 7 distinct daily restore points;
- 4 distinct weekly restore points;
- 6 distinct monthly restore points;
- always the newest snapshot.

Preview:

```bash
pnpm backup:prune
```

Apply:

```bash
pnpm backup:prune -- --apply
```

Custom:

```bash
pnpm backup:prune -- --daily 14 --weekly 8 --monthly 12 --apply
```

Only directories matching Wapp's timestamp naming convention are candidates.

## Production baseline

`.backups/` on the DB host is not enough for production. Keep an encrypted
off-host copy and configure S3/provider backup for media.

Initial operational targets, to review against business requirements:

- RPO: at most 24 hours with daily DB backups;
- RTO: 2 hours for documented manual restore.

If the business needs a lower RPO, increase backup frequency before promising
it.

At least monthly, perform a restore drill against an isolated test database.
Successful backup creation alone does not prove recoverability.
EOF

echo "[P1.18] Syntax checking backup scripts..."
bash -n scripts/backup-create.sh
bash -n scripts/backup-verify.sh
bash -n scripts/backup-restore.sh
node --check scripts/backup-prune.mjs

echo "[P1.18] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.18] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.18] Backup/restore foundation installed."
echo "No Prisma migration is required."
echo
echo "Safe validation:"
echo "  pnpm backup:create"
echo "  pnpm backup:verify -- .backups/<snapshot>"
echo
echo "Do NOT test restore against the working database."
echo "Restore should first be exercised against an isolated/test database."
