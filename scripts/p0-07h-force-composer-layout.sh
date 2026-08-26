#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CSS="apps/web/app/globals.css"

if [[ ! -f "$CSS" ]]; then
  echo "ERROR: missing $CSS"
  exit 1
fi

echo "[P0.7h] Forcing bounded conversation layout..."

cat >> "$CSS" <<'EOF'

/* --- WAPP P0.7h / Bound the actual P0.7 DOM ---------------------------- */

/*
 * This deliberately targets the DOM that exists in Conversations rather than
 * relying on an auxiliary operations class.
 *
 * Without explicit rows, .message-list--assignment can become an implicit grid
 * row as tall as its content/container and place .composer below the visible
 * inbox. The composer itself is healthy; the message list is consuming its
 * space.
 */
.inbox > .chat-panel {
  position: relative !important;
  display: grid !important;
  grid-template-rows: 66px auto minmax(0, 1fr) !important;
  grid-template-columns: minmax(0, 1fr) !important;

  width: 100% !important;
  height: 100% !important;
  min-width: 0 !important;
  min-height: 0 !important;

  overflow: hidden !important;
  padding-bottom: 73px !important;
}

.inbox > .chat-panel > .chat-header {
  grid-row: 1 !important;
  min-height: 0 !important;
}

.inbox > .chat-panel > .assignment-bar {
  grid-row: 2 !important;
  min-height: 0 !important;
}

.inbox > .chat-panel > .message-list,
.inbox > .chat-panel > .message-list--assignment {
  grid-row: 3 !important;

  width: 100% !important;
  height: auto !important;
  min-height: 0 !important;
  max-height: 100% !important;

  overflow-x: hidden !important;
  overflow-y: auto !important;

  align-self: stretch !important;
  justify-self: stretch !important;
}

.inbox > .chat-panel > .composer {
  position: absolute !important;
  z-index: 100 !important;

  right: 0 !important;
  bottom: 0 !important;
  left: 0 !important;

  display: grid !important;
  grid-template-columns: minmax(0, 1fr) 46px !important;
  gap: 10px !important;

  width: 100% !important;
  height: 73px !important;
  min-height: 73px !important;

  margin: 0 !important;
  border-top: 1px solid var(--line) !important;
  background: #ffffff !important;
  padding: 13px 16px !important;

  opacity: 1 !important;
  visibility: visible !important;
  transform: none !important;
}

.inbox > .chat-panel > .composer textarea {
  display: block !important;
  width: 100% !important;
  height: 46px !important;
  min-width: 0 !important;
  min-height: 46px !important;
  max-height: 46px !important;

  opacity: 1 !important;
  visibility: visible !important;
}

.inbox > .chat-panel > .composer .composer__send {
  display: grid !important;
  width: 46px !important;
  height: 46px !important;
  place-items: center !important;

  visibility: visible !important;
}

/*
 * Desktop inbox must itself be height-constrained so the right-hand grid has a
 * real amount of free space to distribute.
 */
@media (min-width: 821px) {
  .inbox {
    height: calc(100dvh - 160px) !important;
    min-height: 520px !important;
    max-height: calc(100dvh - 110px) !important;
  }
}
EOF

echo "[P0.7h] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7h] Layout constraints installed."
echo
echo "Restart Next:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then hard refresh:"
echo "  Ctrl+Shift+R"
