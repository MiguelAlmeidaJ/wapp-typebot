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

echo "[backup:drill] Executando CHECK TABLE em todas as tabelas..."

TABLE_LIST="$(
  docker exec \
    --env "MYSQL_PWD=$DRILL_PASSWORD" \
    "$CONTAINER" \
    mysql \
      --protocol=TCP \
      --host=127.0.0.1 \
      --batch \
      --skip-column-names \
      --user=root \
      --execute="SELECT table_name FROM information_schema.tables WHERE table_schema='${DRILL_DB}' AND table_type='BASE TABLE' ORDER BY table_name;"
)"

if [[ -z "$TABLE_LIST" ]]; then
  echo "[backup:drill] Nenhuma tabela encontrada para CHECK TABLE."
  exit 1
fi

CHECK_FAILED=false

while IFS= read -r TABLE_NAME; do
  [[ -z "$TABLE_NAME" ]] && continue

  CHECK_OUTPUT="$(
    docker exec \
      --env "MYSQL_PWD=$DRILL_PASSWORD" \
      "$CONTAINER" \
      mysql \
        --protocol=TCP \
        --host=127.0.0.1 \
        --batch \
        --skip-column-names \
        --user=root \
        "$DRILL_DB" \
        --execute="CHECK TABLE \`${TABLE_NAME}\`;" \
      2>&1
  )"

  printf '%s\n' "$CHECK_OUTPUT"

  if ! printf '%s\n' "$CHECK_OUTPUT" |
    awk -F '\t' '
      $3 == "status" && $4 == "OK" {
        ok = 1
      }
      END {
        exit ok ? 0 : 1
      }
    '
  then
    CHECK_FAILED=true
  fi
done <<< "$TABLE_LIST"

if [[ "$CHECK_FAILED" == "true" ]]; then
  echo
  echo "[backup:drill] CHECK TABLE encontrou uma ou mais tabelas com problema."
  exit 1
fi

echo "[backup:drill] CHECK TABLE: OK"

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
