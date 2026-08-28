#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERIFY="scripts/backup-verify.sh"

if [[ ! -f "$VERIFY" ]]; then
  echo "ERROR: missing $VERIFY"
  exit 1
fi

echo "[P1.18b] Fixing backup verification argument handling..."

cat > "$VERIFY" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# pnpm may forward an explicit `--` to shell scripts.
if [[ "${1:-}" == "--" ]]; then
  shift
fi

BACKUP_DIR="${1:-}"

if [[ -z "$BACKUP_DIR" ]]; then
  echo "Uso:"
  echo "  pnpm backup:verify .backups/wapp-YYYYMMDDTHHMMSSZ"
  echo "ou:"
  echo "  pnpm backup:verify -- .backups/wapp-YYYYMMDDTHHMMSSZ"
  exit 2
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "[backup:verify] Snapshot não encontrado: $BACKUP_DIR"
  exit 1
fi

MANIFEST="$BACKUP_DIR/manifest.json"
CHECKSUMS="$BACKUP_DIR/SHA256SUMS"
DUMP="$BACKUP_DIR/database.sql.gz"

for required in "$MANIFEST" "$CHECKSUMS" "$DUMP"; do
  if [[ ! -f "$required" ]]; then
    echo "[backup:verify] Arquivo obrigatório ausente: $required"
    exit 1
  fi
done

echo "[backup:verify] Checking SHA-256..."

(
  cd "$BACKUP_DIR"
  sha256sum -c SHA256SUMS
)

echo "[backup:verify] Checking gzip integrity..."
gzip -t "$DUMP"

echo "[backup:verify] Checking manifest JSON..."
node -e '
const fs = require("node:fs");
const path = process.argv[1];

const manifest = JSON.parse(
  fs.readFileSync(path, "utf8")
);

if (
  !manifest ||
  typeof manifest !== "object"
) {
  throw new Error("Manifest inválido.");
}

if (
  !manifest.createdAt
) {
  throw new Error("Manifest sem createdAt.");
}

console.log(
  `[backup:verify] Manifest OK — ${manifest.createdAt}`
);
' "$MANIFEST"

echo "[backup:verify] OK: $BACKUP_DIR"
EOF

chmod +x "$VERIFY"

echo "[P1.18b] Shell syntax..."
bash -n "$VERIFY"

echo
echo "[P1.18b] Backup verifier fixed."
echo
echo "Verify the snapshot already created with:"
echo "  pnpm backup:verify -- .backups/wapp-20260828T111956Z"
