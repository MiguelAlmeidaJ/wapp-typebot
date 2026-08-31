#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/web/app/dashboard/conversations/page.tsx"

echo "[P3.5.1b] Fixing Next.js Suspense boundary for conversations..."

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

for marker in '"use client";' 'useSearchParams' 'export default function ConversationsPage()'; do
  if ! grep -Fq -- "$marker" "$FILE"; then
    echo "ERROR: expected conversations marker missing: $marker"
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/app/dashboard/conversations/page.tsx";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (
  !content.includes("function ConversationsPageContent()") ||
  !content.includes("<Suspense")
) {
  if (!content.includes('import { Suspense } from "react";')) {
    const anchor = '"use client";\n';
    if (!content.includes(anchor)) {
      throw new Error("Client directive anchor not found.");
    }
    content = content.replace(
      anchor,
      `${anchor}
import { Suspense } from "react";
`
    );
  }

  const declaration =
    /export\s+default\s+function\s+ConversationsPage\s*\(\s*\)\s*\{/g;
  const matches = content.match(declaration) ?? [];

  if (matches.length !== 1) {
    throw new Error(
      `Expected exactly one default ConversationsPage declaration, found ${matches.length}.`
    );
  }

  content = content.replace(
    declaration,
    "function ConversationsPageContent() {"
  );

  content = content.trimEnd() + `

export default function ConversationsPage() {
  return (
    <Suspense
      fallback={
        <main className="dashboard-loading">
          Carregando conversas…
        </main>
      }
    >
      <ConversationsPageContent />
    </Suspense>
  );
}
`;
}

if (!content.includes('import { Suspense } from "react";')) {
  throw new Error("Suspense import verification failed.");
}
if (!content.includes("function ConversationsPageContent()")) {
  throw new Error("Content component verification failed.");
}
if (!content.includes("<ConversationsPageContent />")) {
  throw new Error("Suspense wrapper child verification failed.");
}

const contentIndex = content.indexOf("function ConversationsPageContent()");
const searchIndex = content.indexOf("useSearchParams()");
if (searchIndex < contentIndex) {
  throw new Error("useSearchParams() is not below the content component boundary.");
}

fs.writeFileSync(path, content);
console.log("[P3.5.1b] Suspense boundary installed.");
NODE

echo "[P3.5.1b] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo "[P3.5.1b] Stabilization smoke..."
node scripts/p3-05-01-stabilization-smoke.mjs

echo "[P3.5.1b] Production build..."
pnpm build

echo
echo "[P3.5.1b] PRODUCTION BUILD PASS."
echo
echo "No Prisma migration is required."
echo "Next: commit + push, then verify GitHub Quality Gate."
