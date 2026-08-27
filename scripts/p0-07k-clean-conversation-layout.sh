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

echo "[P0.7k] Cleaning conversation layout and removing accumulated hotfixes..."

node <<'NODE'
const fs = require("node:fs");

const pagePath = "apps/web/app/dashboard/conversations/page.tsx";
let page = fs.readFileSync(pagePath, "utf8");

const replacements = [
  [
    'className="message-list message-list--assignment"',
    'className="conversation-main"'
  ],
  [
    'className="message-scroll"',
    'className="conversation-messages"'
  ],
  [
    'className="composer composer--sticky"',
    'className="conversation-composer"'
  ]
];

for (const [from, to] of replacements) {
  if (page.includes(from)) {
    page = page.replace(from, to);
  } else if (!page.includes(to)) {
    throw new Error(`Expected JSX class not found: ${from}`);
  }
}

fs.writeFileSync(pagePath, page);

const cssPath = "apps/web/app/globals.css";
let css = fs.readFileSync(cssPath, "utf8");

/*
 * P0.7f through P0.7j were iterative emergency layout overrides.
 * They all target the same elements with !important and are now the main
 * source of unpredictable sizing. Remove the whole experimental tail and
 * replace it with one canonical layout.
 */
const oldHotfixMarker =
  "/* --- WAPP P0.7f / Robust conversation layout";

const hotfixStart = css.indexOf(oldHotfixMarker);

if (hotfixStart >= 0) {
  css = css.slice(0, hotfixStart).trimEnd() + "\n\n";
  console.log("Removed accumulated P0.7f-P0.7j CSS overrides.");
} else if (!css.includes("WAPP P0.7k / Canonical conversation layout")) {
  console.warn(
    "P0.7f marker not found; keeping existing CSS and appending canonical layout."
  );
}

const canonical = `/* --- WAPP P0.7k / Canonical conversation layout ----------------------- */

/*
 * There are only four vertical regions:
 *   header
 *   assignment
 *   conversation-main
 *
 * conversation-main then owns:
 *   messages (the only scrollable region)
 *   composer (never scrolls away)
 */
.chat-panel.chat-panel--operations {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  padding: 0;
}

.chat-panel--operations > .chat-header {
  flex: 0 0 66px;
  min-height: 66px;
}

.chat-panel--operations > .assignment-bar {
  flex: 0 0 auto;
}

.conversation-main {
  display: flex;
  flex: 1 1 0;
  flex-direction: column;
  width: 100%;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
}

.conversation-messages {
  flex: 1 1 0;
  min-width: 0;
  min-height: 0;
  overflow-x: hidden;
  overflow-y: auto;
  padding: 26px clamp(20px, 5vw, 70px) 22px;
  overscroll-behavior: contain;
}

.conversation-composer {
  display: grid;
  flex: 0 0 auto;
  grid-template-columns: minmax(0, 1fr) 46px;
  gap: 10px;
  width: 100%;
  min-height: 72px;
  margin: 0;
  border: 0;
  border-top: 1px solid var(--line);
  background: #ffffff;
  padding: 12px 16px;
}

.conversation-composer textarea {
  display: block;
  width: 100%;
  min-width: 0;
  height: 46px;
  min-height: 46px;
  max-height: 120px;
  resize: none;
  border: 1px solid var(--line);
  border-radius: 13px;
  outline: none;
  background: var(--surface-subtle);
  padding: 13px 14px;
  font-size: 12px;
  line-height: 1.5;
}

.conversation-composer textarea:focus {
  border-color: var(--accent);
  background: #ffffff;
}

.conversation-composer .composer__send {
  display: grid;
  width: 46px;
  height: 46px;
  align-self: end;
  place-items: center;
  border: 0;
  border-radius: 13px;
  background: var(--sidebar);
  color: #ffffff;
  font-size: 20px;
}

.conversation-composer .composer__send:disabled {
  opacity: 0.35;
}

/*
 * The previous 620px min-height could push the bottom of the inbox below
 * shorter desktop viewports. Keep the entire operator panel inside the
 * viewport and let only the internal lists scroll.
 */
@media (min-width: 821px) {
  .inbox {
    height: calc(100dvh - 150px);
    min-height: 0;
    max-height: none;
  }
}

@media (max-width: 820px) {
  .conversation-messages {
    padding: 18px 12px;
  }

  .conversation-composer {
    padding: 10px 12px;
  }
}
`;

if (!css.includes("WAPP P0.7k / Canonical conversation layout")) {
  css += canonical;
}

fs.writeFileSync(cssPath, css);

console.log("Conversation JSX now uses isolated classes.");
console.log("Canonical conversation CSS installed.");
NODE

echo "[P0.7k] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7k] Clean layout installed."
echo
echo "Restart Next:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then hard refresh:"
echo "  Ctrl+Shift+R"
