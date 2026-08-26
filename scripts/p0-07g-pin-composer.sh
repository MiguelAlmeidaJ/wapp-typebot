#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CSS="apps/web/app/globals.css"
LAYOUT="apps/web/app/layout.tsx"

for required in "$CSS" "$LAYOUT"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

echo "[P0.7g] Pinning composer to the conversation footer..."

cat >> "$CSS" <<'EOF'

/* --- WAPP P0.7g / Pinned composer -------------------------------------- */

/*
 * The operational chat has dynamic rows (header + assignment + messages).
 * Pinning the composer removes it from that sizing equation and guarantees
 * that the reply control remains visible at the bottom of the chat panel.
 */
.chat-panel.chat-panel--operations {
  position: relative !important;
  display: flex !important;
  flex-direction: column !important;
  min-height: 0 !important;
  height: 100% !important;
  overflow: hidden !important;
  padding-bottom: 73px !important;
}

.chat-panel--operations .chat-header {
  flex: 0 0 66px !important;
}

.chat-panel--operations .assignment-bar {
  flex: 0 0 auto !important;
}

.chat-panel--operations .message-list {
  flex: 1 1 0 !important;
  min-height: 0 !important;
  overflow-y: auto !important;
  padding-bottom: 28px !important;
}

.chat-panel--operations .composer {
  position: absolute !important;
  z-index: 20 !important;
  right: 0 !important;
  bottom: 0 !important;
  left: 0 !important;

  display: grid !important;
  grid-template-columns: minmax(0, 1fr) 46px !important;
  gap: 10px !important;

  width: 100% !important;
  height: 73px !important;
  min-height: 73px !important;

  border-top: 1px solid var(--line) !important;
  background: #ffffff !important;
  padding: 13px 16px !important;
  box-shadow: 0 -8px 24px rgba(24, 33, 27, 0.035);
}

.chat-panel--operations .composer textarea {
  display: block !important;
  width: 100% !important;
  min-width: 0 !important;
  height: 46px !important;
  min-height: 46px !important;
  max-height: 46px !important;
  opacity: 1 !important;
  visibility: visible !important;
}

.chat-panel--operations .composer__send {
  display: grid !important;
  width: 46px !important;
  height: 46px !important;
  place-items: center !important;
  opacity: 1;
  visibility: visible !important;
}
EOF

echo "[P0.7g] Silencing browser-extension-only body hydration mismatch..."

node <<'NODE'
const fs = require("node:fs");

const path = "apps/web/app/layout.tsx";
let content = fs.readFileSync(path, "utf8");

const plain = "<body>";
const suppressed = "<body suppressHydrationWarning>";

if (content.includes(suppressed)) {
  console.log("Body hydration warning suppression already configured.");
} else if (content.includes(plain)) {
  content = content.replace(plain, suppressed);
  fs.writeFileSync(path, content);
  console.log("Added suppressHydrationWarning to body.");
} else {
  throw new Error("Could not find <body> in app/layout.tsx.");
}
NODE

echo "[P0.7g] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7g] Fix complete."
echo
echo "Restart Next to guarantee fresh CSS:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then hard refresh the browser:"
echo "  Ctrl+Shift+R"
