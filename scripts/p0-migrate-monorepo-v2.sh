#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.2] Preparing monorepo migration..."

# Never commit patch artifacts.
git rm --cached --ignore-unmatch ./*.patch >/dev/null 2>&1 || true

# Append monorepo ignores without depending on the current .gitignore contents.
MARKER="# --- WAPP MONOREPO ---"
if ! grep -Fq "$MARKER" .gitignore 2>/dev/null; then
  cat >> .gitignore <<'EOF'

# --- WAPP MONOREPO ---
.turbo/
.pnpm-store/
**/.next/
**/dist/
*.patch
.runtime/
**/.runtime/
legacy/**/.env
legacy/**/.env.*
# --- /WAPP MONOREPO ---
EOF
fi

cat > README.md <<'EOF'
# Wapp

Plataforma de atendimento e automação para WhatsApp em reconstrução como
monorepo TypeScript.

## Desenvolvedor

- Miguel Almeida
- miguel@anoar.com.br
- https://github.com/MiguelAlmeidaJ
- https://www.instagram.com/miguelalmeida.j/

## Estrutura

```text
apps/
  api/       Node.js + Fastify + TypeScript
  web/       Next.js + TypeScript

packages/
  contracts/

infra/
docs/
legacy/
```

## Ambiente local

```bash
corepack enable
pnpm install

cp apps/api/.env.example apps/api/.env
cp apps/web/.env.example apps/web/.env.local

pnpm infra:up
pnpm dev
```

- Web: http://localhost:3000
- API: http://localhost:4000
- Health: http://localhost:4000/health

O código herdado fica temporariamente em `legacy/` somente como referência de
comportamento durante a migração.
EOF

mkdir -p legacy/infra

move_dir() {
  local from="$1"
  local to="$2"

  if [[ ! -d "$from" ]]; then
    return
  fi

  if [[ -e "$to" ]]; then
    echo "Skip: destination already exists: $to"
    return
  fi

  git mv "$from" "$to"
  echo "Moved: $from -> $to"
}

move_file() {
  local from="$1"
  local to="$2"

  if [[ ! -f "$from" ]]; then
    return
  fi

  if [[ -e "$to" ]]; then
    echo "Skip: destination already exists: $to"
    return
  fi

  git mv "$from" "$to"
  echo "Moved: $from -> $to"
}

move_dir "backend" "legacy/backend"
move_dir "frontend" "legacy/frontend"

move_file "README" "legacy/infra/README.deploy-original"
move_file "dct-backend" "legacy/infra/dct-backend"
move_file "dct-frontend" "legacy/infra/dct-frontend"
move_file "dct-financeiro" "legacy/infra/dct-financeiro"
move_file "startup.sh" "legacy/infra/startup.sh"
move_file "chmod.sh" "legacy/infra/chmod.sh"

echo
echo "[P0.2] Monorepo layout prepared."
echo
echo "Review with:"
echo "  git status"
echo
echo "Then install:"
echo "  corepack enable"
echo "  pnpm install"
echo
echo "Do not delete legacy/ yet."
