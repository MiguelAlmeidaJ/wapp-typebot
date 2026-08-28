#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.18c] Installing isolated restore drill..."

for required in \
  "package.json" \
  "scripts/backup-verify.sh"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

cat > scripts/backup-restore-drill.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# pnpm can forward an explicit separator to shell scripts.
if [[ "${1:-}" == "--" ]]; then
  shift
fi

BACKUP_DIR="${1:-}"

if [[ -z "$BACKUP_DIR" ]]; then
  echo "Uso:"
  echo "  pnpm backup:drill -- .backups/wapp-YYYYMMDDTHHMMSSZ"
  exit 2
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "[backup:drill] Snapshot não encontrado: $BACKUP_DIR"
  exit 1
fi

DUMP="$BACKUP_DIR/database.sql.gz"

if [[ ! -f "$DUMP" ]]; then
  echo "[backup:drill] Dump não encontrado: $DUMP"
  exit 1
fi

for command in docker gzip node; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "[backup:drill] Comando obrigatório não encontrado: $command"
    exit 1
  fi
done

echo "[backup:drill] Verificando snapshot antes do restore..."
bash scripts/backup-verify.sh "$BACKUP_DIR"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
CONTAINER="wapp-restore-drill-${STAMP,,}-$$"
DRILL_DB="wapp_restore_drill"
DRILL_PASSWORD="$(
  node -e 'process.stdout.write(require("node:crypto").randomBytes(24).toString("hex"))'
)"

cleanup() {
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "[backup:drill] Removendo MySQL temporário..."
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

echo "[backup:drill] Subindo MySQL 8.4 isolado..."
docker run \
  --detach \
  --rm \
  --name "$CONTAINER" \
  --env "MYSQL_ROOT_PASSWORD=$DRILL_PASSWORD" \
  --env "MYSQL_DATABASE=$DRILL_DB" \
  mysql:8.4 \
  >/dev/null

echo "[backup:drill] Aguardando MySQL ficar pronto..."

READY=false

for _ in $(seq 1 60); do
  if docker exec \
    --env "MYSQL_PWD=$DRILL_PASSWORD" \
    "$CONTAINER" \
    mysqladmin \
      ping \
      --host=127.0.0.1 \
      --user=root \
      --silent \
      >/dev/null 2>&1
  then
    READY=true
    break
  fi

  sleep 2
done

if [[ "$READY" != "true" ]]; then
  echo "[backup:drill] MySQL temporário não ficou pronto a tempo."
  docker logs "$CONTAINER" 2>&1 | tail -n 80 || true
  exit 1
fi

echo "[backup:drill] Restaurando database.sql.gz no banco isolado..."

gzip -dc "$DUMP" |
  docker exec \
    --interactive \
    --env "MYSQL_PWD=$DRILL_PASSWORD" \
    "$CONTAINER" \
    mysql \
      --user=root \
      --default-character-set=utf8mb4 \
      "$DRILL_DB"

echo "[backup:drill] Restore SQL concluído."

TABLE_COUNT="$(
  docker exec \
    --env "MYSQL_PWD=$DRILL_PASSWORD" \
    "$CONTAINER" \
    mysql \
      --batch \
      --skip-column-names \
      --user=root \
      --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DRILL_DB}';"
)"

if ! [[ "$TABLE_COUNT" =~ ^[0-9]+$ ]]; then
  echo "[backup:drill] Não foi possível validar quantidade de tabelas: $TABLE_COUNT"
  exit 1
fi

if (( TABLE_COUNT == 0 )); then
  echo "[backup:drill] Restore terminou sem tabelas. Snapshot inválido."
  exit 1
fi

echo "[backup:drill] Tabelas restauradas: $TABLE_COUNT"

PRISMA_MIGRATIONS="$(
  docker exec \
    --env "MYSQL_PWD=$DRILL_PASSWORD" \
    "$CONTAINER" \
    mysql \
      --batch \
      --skip-column-names \
      --user=root \
      --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DRILL_DB}' AND table_name='_prisma_migrations';"
)"

if [[ "$PRISMA_MIGRATIONS" == "1" ]]; then
  MIGRATION_COUNT="$(
    docker exec \
      --env "MYSQL_PWD=$DRILL_PASSWORD" \
      "$CONTAINER" \
      mysql \
        --batch \
        --skip-column-names \
        --user=root \
        "$DRILL_DB" \
        --execute="SELECT COUNT(*) FROM _prisma_migrations WHERE finished_at IS NOT NULL;"
  )"

  echo "[backup:drill] Migrations Prisma concluídas no snapshot: $MIGRATION_COUNT"
else
  echo "[backup:drill] Aviso: _prisma_migrations não encontrada; seguindo com validação estrutural."
fi

echo "[backup:drill] Executando mysqlcheck..."

docker exec \
  --env "MYSQL_PWD=$DRILL_PASSWORD" \
  "$CONTAINER" \
  mysqlcheck \
    --user=root \
    --check \
    "$DRILL_DB" \
    >/dev/null

echo "[backup:drill] mysqlcheck: OK"

echo "[backup:drill] Amostra de tabelas restauradas:"

docker exec \
  --env "MYSQL_PWD=$DRILL_PASSWORD" \
  "$CONTAINER" \
  mysql \
    --batch \
    --skip-column-names \
    --user=root \
    --execute="SELECT table_name FROM information_schema.tables WHERE table_schema='${DRILL_DB}' ORDER BY table_name LIMIT 15;" \
  | sed 's/^/  - /'

echo
echo "[backup:drill] RESTORE DRILL APROVADO."
echo "[backup:drill] O banco de trabalho não foi alterado."
EOF

chmod +x scripts/backup-restore-drill.sh

node <<'NODE'
const fs = require("node:fs");

const path = "package.json";
const pkg = JSON.parse(
  fs.readFileSync(path, "utf8")
);

pkg.scripts ??= {};

pkg.scripts["backup:drill"] =
  "bash scripts/backup-restore-drill.sh";

fs.writeFileSync(
  path,
  `${JSON.stringify(pkg, null, 2)}\n`
);

console.log("backup:drill script registered.");
NODE

if [[ -f "docs/BACKUP_RESTORE.md" ]] &&
   ! grep -q "## Restore drill isolado" docs/BACKUP_RESTORE.md
then
  cat >> docs/BACKUP_RESTORE.md <<'EOF'

## Restore drill isolado

Depois de criar e verificar um snapshot, valide que o SQL realmente é
restaurável sem tocar no banco de trabalho:

```bash
pnpm backup:drill -- .backups/wapp-YYYYMMDDTHHMMSSZ
```

O drill:

1. executa novamente `backup:verify`;
2. cria um container temporário `mysql:8.4`;
3. cria um banco isolado `wapp_restore_drill`;
4. importa `database.sql.gz`;
5. confirma que há tabelas restauradas;
6. conta migrations Prisma concluídas quando `_prisma_migrations` existe;
7. executa `mysqlcheck`;
8. mostra uma amostra das tabelas;
9. remove o container temporário automaticamente.

O container não publica porta, não usa volume e não se conecta ao banco Wapp
existente.

Nenhum `docker compose down -v` é executado.

O restore drill deve ser executado periodicamente, especialmente antes de
alterações relevantes de infraestrutura ou banco.
EOF
fi

echo "[P1.18c] Shell syntax..."
bash -n scripts/backup-restore-drill.sh

echo "[P1.18c] Package JSON..."
node -e 'JSON.parse(require("node:fs").readFileSync("package.json", "utf8")); console.log("package.json OK")'

echo "[P1.18c] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.18c] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.18c] Isolated restore drill installed."
echo
echo "Run against the snapshot that already passed verification:"
echo "  pnpm backup:drill -- .backups/wapp-20260828T111956Z"
