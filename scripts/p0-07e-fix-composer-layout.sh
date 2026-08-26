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

echo "[P0.7e] Fixing conversation composer layout..."

node <<'NODE'
const fs = require("node:fs");

const pagePath =
  "apps/web/app/dashboard/conversations/page.tsx";
let page = fs.readFileSync(pagePath, "utf8");

const plainSection =
  '<section className="chat-panel">';

const fixedSection =
  '<section className="chat-panel chat-panel--operations">';

if (page.includes(plainSection)) {
  page = page.replace(plainSection, fixedSection);
  console.log("Added explicit operations layout class.");
} else if (page.includes(fixedSection)) {
  console.log("Operations layout class already present.");
} else {
  throw new Error(
    "Could not find chat-panel section in conversations page."
  );
}

fs.writeFileSync(pagePath, page);

const cssPath = "apps/web/app/globals.css";
let css = fs.readFileSync(cssPath, "utf8");

const hasRule = `.chat-panel:has(.assignment-bar) {
  grid-template-rows: 66px auto minmax(0, 1fr) auto;
}`;

const explicitRule = `.chat-panel--operations {
  grid-template-rows: 66px auto minmax(0, 1fr) auto;
  min-height: 0;
}

.chat-panel--operations .message-list {
  min-height: 0;
  overflow-y: auto;
}

.chat-panel--operations .composer {
  position: relative;
  z-index: 2;
  min-height: 72px;
}`;

if (css.includes(hasRule)) {
  css = css.replace(hasRule, explicitRule);
  console.log("Replaced :has() grid rule with explicit layout rule.");
} else if (!css.includes(".chat-panel--operations {")) {
  css += `

/* --- WAPP P0.7e / Composer layout -------------------------------------- */

${explicitRule}
`;
  console.log("Added explicit operations grid rule.");
} else {
  console.log("Operations grid rule already present.");
}

fs.writeFileSync(cssPath, css);
NODE

echo "[P0.7e] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7e] Composer layout repaired."
echo
echo "Restart or let Next hot-reload, then reopen:"
echo "  http://localhost:3000/dashboard/conversations"
