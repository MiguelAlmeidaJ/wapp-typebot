#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CSS="apps/web/app/globals.css"

if [[ ! -f "$CSS" ]]; then
  echo "ERROR: missing $CSS"
  exit 1
fi

if ! grep -q "WAPP P1.7 / Quick replies" "$CSS"; then
  echo "ERROR: P1.7 quick reply styles not found."
  exit 1
fi

echo "[P1.7b] Fixing quick reply manager overflow..."

if ! grep -q "WAPP P1.7b / Quick reply drawer overflow" "$CSS"; then
  cat >> "$CSS" <<'EOF'

/* --- WAPP P1.7b / Quick reply drawer overflow ------------------------- */

/*
 * The manager can be taller than the available conversation viewport,
 * especially while creating/editing a reply.
 *
 * Scroll the drawer itself instead of letting the form overflow outside
 * conversation-body.
 */
.quick-reply-manager {
  display: block !important;
  min-height: 0 !important;
  overflow-x: hidden !important;
  overflow-y: auto !important;
  overscroll-behavior: contain;
  scrollbar-gutter: stable;
}

.quick-reply-manager__header {
  position: sticky;
  z-index: 4;
  top: 0;
  background: #fbfcfa;
}

.quick-reply-manager__list {
  min-height: 0;
  overflow: visible !important;
}

.quick-reply-form {
  min-width: 0;
  padding-bottom: 18px;
}

.quick-reply-form textarea {
  min-height: 110px;
  max-height: 240px;
}

.quick-reply-form .primary-button {
  flex: 0 0 auto;
}

@media (max-height: 760px) {
  .quick-reply-manager__header {
    padding: 12px 14px;
  }

  .quick-reply-form {
    gap: 7px;
    padding: 10px 12px 16px;
  }

  .quick-reply-form textarea {
    min-height: 90px;
  }
}
EOF
fi

echo "[P1.7b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.7b] Quick reply drawer overflow fixed."
echo
echo "Restart/hard refresh if needed:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo "  Ctrl+Shift+R"
