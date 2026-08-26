#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CSS="apps/web/app/globals.css"

if [[ ! -f "$CSS" ]]; then
  echo "ERROR: missing $CSS"
  exit 1
fi

echo "[P0.7f] Switching conversation operations layout to flex..."

cat >> "$CSS" <<'EOF'

/* --- WAPP P0.7f / Robust conversation layout --------------------------- */

.chat-panel.chat-panel--operations {
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
  height: 100%;
  overflow: hidden;
}

.chat-panel--operations .chat-header {
  flex: 0 0 66px;
}

.chat-panel--operations .assignment-bar {
  flex: 0 0 auto;
}

.chat-panel--operations .message-list {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
}

.chat-panel--operations .composer {
  display: grid;
  flex: 0 0 auto;
  grid-template-columns: minmax(0, 1fr) 46px;
  min-height: 72px;
  width: 100%;
  border-top: 1px solid var(--line);
  background: #ffffff;
  padding: 13px 16px;
}

.chat-panel--operations .composer textarea {
  width: 100%;
  min-width: 0;
}

.chat-panel--operations .composer__send {
  flex: 0 0 46px;
}
EOF

echo "[P0.7f] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7f] Composer layout repaired with flex."
echo
echo "Next:"
echo "  refresh http://localhost:3000/dashboard/conversations"
