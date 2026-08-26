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

echo "[P0.7j] Separating message scroll from reply composer..."

node <<'NODE'
const fs = require("node:fs");

const path = "apps/web/app/dashboard/conversations/page.tsx";
let content = fs.readFileSync(path, "utf8");

if (content.includes('className="message-scroll"')) {
  console.log("message-scroll wrapper already exists.");
  process.exit(0);
}

const opening = '<div className="message-list message-list--assignment">';
if (!content.includes(opening)) {
  throw new Error(
    "Could not find message-list--assignment opening element."
  );
}

content = content.replace(
  opening,
  `${opening}
                <div className="message-scroll">`
);

const boundaryRegex =
  /(\s*<div ref=\{bottomRef\} \/>\s*)(<form className="composer composer--sticky")/m;

const match = content.match(boundaryRegex);

if (!match) {
  throw new Error(
    "Could not find the boundary between messages and composer."
  );
}

content = content.replace(
  boundaryRegex,
  `${match[1]}                </div>

                ${match[2]}`
);

fs.writeFileSync(path, content);
console.log("Wrapped messages in message-scroll.");
NODE

cat >> "$CSS" <<'EOF'

/* --- WAPP P0.7j / Messages scroll + fixed composer --------------------- */

.inbox > .chat-panel > .message-list--assignment {
  display: grid !important;
  grid-template-rows: minmax(0, 1fr) auto !important;
  grid-template-columns: minmax(0, 1fr) !important;
  min-height: 0 !important;
  height: 100% !important;
  overflow: hidden !important;
  padding: 0 !important;
}

.inbox
  > .chat-panel
  > .message-list--assignment
  > .message-scroll {
  min-width: 0 !important;
  min-height: 0 !important;
  overflow-x: hidden !important;
  overflow-y: auto !important;
  padding: 26px clamp(20px, 5vw, 70px) 22px !important;
}

.inbox
  > .chat-panel
  > .message-list--assignment
  > .composer.composer--sticky {
  position: static !important;
  display: grid !important;
  grid-template-columns: minmax(0, 1fr) 46px !important;
  gap: 10px !important;
  width: 100% !important;
  height: auto !important;
  min-height: 72px !important;
  margin: 0 !important;
  border: 0 !important;
  border-top: 1px solid var(--line) !important;
  border-radius: 0 !important;
  background: #ffffff !important;
  padding: 12px 16px !important;
  opacity: 1 !important;
  visibility: visible !important;
  transform: none !important;
  box-shadow: none !important;
}

.inbox
  > .chat-panel
  > .message-list--assignment
  > .composer.composer--sticky
  textarea {
  width: 100% !important;
  height: 46px !important;
  min-height: 46px !important;
  max-height: 120px !important;
}

@media (max-width: 820px) {
  .inbox
    > .chat-panel
    > .message-list--assignment
    > .message-scroll {
    padding: 18px 12px !important;
  }

  .inbox
    > .chat-panel
    > .message-list--assignment
    > .composer.composer--sticky {
    padding: 10px 12px !important;
  }
}
EOF

echo "[P0.7j] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7j] Conversation layout corrected."
echo
echo "Restart Next:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then hard refresh:"
echo "  Ctrl+Shift+R"
