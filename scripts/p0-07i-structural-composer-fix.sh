#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PAGE="apps/web/app/dashboard/conversations/page.tsx"
CSS="apps/web/app/globals.css"

for required in "$PAGE" "$CSS"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

echo "[P0.7i] Moving reply composer inside the message viewport..."

node <<'NODE'
const fs = require("node:fs");

const path = "apps/web/app/dashboard/conversations/page.tsx";
let content = fs.readFileSync(path, "utf8");

if (content.includes('className="composer composer--sticky"')) {
  console.log("Sticky composer is already installed.");
  process.exit(0);
}

const pattern =
  /(<div ref=\{bottomRef\} \/>\s*)<\/div>\s*(<form className="composer"[\s\S]*?<\/form>)/m;

const match = content.match(pattern);

if (!match) {
  const composerIndex = content.indexOf('className="composer"');
  const messageListIndex = content.indexOf(
    'className="message-list message-list--assignment"'
  );

  console.error("composer index:", composerIndex);
  console.error("message list index:", messageListIndex);

  throw new Error(
    "Could not identify the P0.7 message-list/composer structure. No JSX was changed."
  );
}

const form = match[2].replace(
  'className="composer"',
  'className="composer composer--sticky"'
);

content = content.replace(
  pattern,
  `${match[1]}${form}\n              </div>`
);

fs.writeFileSync(path, content);
console.log(
  "Composer moved inside message-list and marked composer--sticky."
);
NODE

cat >> "$CSS" <<'EOF'

/* --- WAPP P0.7i / Structural reply composer fix ------------------------ */

/*
 * The reply bar now lives inside the scrollable message viewport.
 * This makes it independent from the outer chat grid sizing and prevents
 * assignment controls or implicit rows from pushing it below the viewport.
 */
.inbox > .chat-panel {
  padding-bottom: 0 !important;
}

.inbox > .chat-panel > .message-list--assignment {
  position: relative !important;
  min-height: 0 !important;
  overflow-y: auto !important;
  padding-bottom: 18px !important;
}

.inbox
  > .chat-panel
  > .message-list--assignment
  > .composer.composer--sticky {
  position: sticky !important;
  z-index: 100 !important;

  top: auto !important;
  right: auto !important;
  bottom: 0 !important;
  left: auto !important;

  display: grid !important;
  grid-template-columns: minmax(0, 1fr) 46px !important;
  gap: 10px !important;

  width: 100% !important;
  height: auto !important;
  min-height: 72px !important;

  margin: 22px 0 0 !important;
  border: 1px solid var(--line) !important;
  border-radius: 16px !important;
  background: rgba(255, 255, 255, 0.98) !important;
  padding: 12px !important;

  opacity: 1 !important;
  visibility: visible !important;
  transform: none !important;
  box-shadow: 0 10px 30px rgba(24, 33, 27, 0.08) !important;
  backdrop-filter: blur(12px);
}

.inbox
  > .chat-panel
  > .message-list--assignment
  > .composer.composer--sticky
  textarea {
  display: block !important;
  width: 100% !important;
  min-width: 0 !important;
  height: 46px !important;
  min-height: 46px !important;
  max-height: 120px !important;

  opacity: 1 !important;
  visibility: visible !important;
}

.inbox
  > .chat-panel
  > .message-list--assignment
  > .composer.composer--sticky
  .composer__send {
  display: grid !important;
  width: 46px !important;
  height: 46px !important;
  place-items: center !important;

  opacity: 1;
  visibility: visible !important;
}
EOF

echo "[P0.7i] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7i] Structural composer fix complete."
echo
echo "Restart Next once:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then hard refresh:"
echo "  Ctrl+Shift+R"
