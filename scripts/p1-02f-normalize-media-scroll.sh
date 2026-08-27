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

echo "[P1.2f] Normalizing conversation layout and pending-media refresh..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

/* -----------------------------------------------------------------------
 * 1. Normalize outer classes. These replacements are deliberately tolerant
 *    of previous P0.7/P1.2 intermediate states.
 * --------------------------------------------------------------------- */

content = content.replace(
  /<main className="inbox-screen(?: inbox-screen--contained)?">/,
  '<main className="inbox-screen inbox-screen--contained">'
);

content = content.replace(
  /<section className="(?:chat-panel chat-panel--operations|conversation-panel)">/,
  '<section className="conversation-panel">'
);

/*
 * Normalize the body wrapper. At different points this project used:
 * - message-list message-list--assignment
 * - conversation-main
 * - conversation-body
 */
content = content.replace(
  /<div className="(?:message-list message-list--assignment|conversation-main|conversation-body)">/,
  '<div className="conversation-body">'
);

/*
 * Normalize the scroll wrapper:
 * - message-scroll
 * - conversation-messages
 * - conversation-scroll
 */
content = content.replace(
  /<div className="(?:message-scroll|conversation-messages|conversation-scroll)">/,
  '<div className="conversation-scroll">'
);

/*
 * Normalize composer:
 * - composer
 * - composer composer--sticky
 * - conversation-composer
 */
content = content.replace(
  /<form className="(?:composer(?: composer--sticky)?|conversation-composer)" onSubmit=\{handleSend\}>/,
  '<form className="conversation-composer" onSubmit={handleSend}>'
);

/* Validate the final structural tokens exist. */
for (const token of [
  'className="inbox-screen inbox-screen--contained"',
  'className="conversation-panel"',
  'className="conversation-body"',
  'className="conversation-scroll"',
  'className="conversation-composer"'
]) {
  if (!content.includes(token)) {
    throw new Error(
      `Could not normalize required token: ${token}`
    );
  }
}

/* -----------------------------------------------------------------------
 * 2. Pending-media fallback.
 * --------------------------------------------------------------------- */

if (!content.includes("const hasPendingMedia = messages.some(")) {
  const candidates = [
    `  const openCount = tickets.filter(ticket => ticket.status === "OPEN").length;`,
    `  const openCount = tickets.filter(
    ticket => ticket.status === "OPEN"
  ).length;`
  ];

  const anchor = candidates.find(candidate =>
    content.includes(candidate)
  );

  if (!anchor) {
    throw new Error(
      "Could not find openCount anchor for pending-media state."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

  const hasPendingMedia = messages.some(
    message => message.mediaStatus === "PENDING"
  );`
  );
}

if (!content.includes("[P1.2f pending media fallback]")) {
  const effectRegex =
    /  useEffect\(\(\) => \{\s*bottomRef\.current\?\.scrollIntoView\(\{\s*behavior: "smooth",\s*block: "end"\s*\}\);\s*\}, \[messages\]\);/;

  const match = content.match(effectRegex);

  if (!match) {
    throw new Error(
      "Could not find message bottom-scroll effect."
    );
  }

  const fallback = `${match[0]}

  // [P1.2f pending media fallback]
  // SSE remains primary. This polls only while media is still processing.
  useEffect(() => {
    if (
      !session ||
      !selectedId ||
      !hasPendingMedia
    ) {
      return;
    }

    let cancelled = false;

    const refreshPendingMedia = async () => {
      try {
        const payload = await request<MessagesResponse>(
          \`/api/v1/tickets/\${selectedId}/messages\`
        );

        if (!cancelled) {
          setMessages(payload.messages);
        }
      } catch {
        // Non-fatal fallback. Realtime or the next tick can recover.
      }
    };

    const interval = window.setInterval(
      () => {
        void refreshPendingMedia();
      },
      1_200
    );

    void refreshPendingMedia();

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [
    hasPendingMedia,
    request,
    selectedId,
    session
  ]);`;

  content = content.replace(
    effectRegex,
    fallback
  );
}

/*
 * If the failed P1.2e already inserted its own pending fallback before dying,
 * avoid duplicate polling.
 */
const markerE = "// [P1.2e media pending fallback]";
const markerF = "// [P1.2f pending media fallback]";

if (
  content.includes(markerE) &&
  content.includes(markerF)
) {
  const start = content.indexOf(markerE);
  const nextMarker = content.indexOf(markerF);

  if (start >= 0 && nextMarker > start) {
    /*
     * Remove the whole P1.2e useEffect immediately surrounding the marker.
     * Find the preceding "  useEffect" and the closing dependency ");"
     * immediately before the P1.2f marker.
     */
    const effectStart = content.lastIndexOf(
      "  useEffect(",
      start
    );

    const effectEnd = content.lastIndexOf(
      "  ]);",
      nextMarker
    );

    if (
      effectStart >= 0 &&
      effectEnd >= effectStart
    ) {
      content =
        content.slice(0, effectStart) +
        content.slice(effectEnd + 5);
    }
  }
}

fs.writeFileSync(path, content);

console.log("Final conversation class structure normalized.");
console.log("Pending-media fallback ensured exactly once.");
NODE

if ! grep -q "WAPP P1.2f / Canonical conversation viewport" "$CSS"; then
  cat >> "$CSS" <<'EOF'

/* --- WAPP P1.2f / Canonical conversation viewport --------------------- */

/*
 * These selectors use only the new canonical classes.
 * They intentionally avoid every old P0.7 composer selector.
 */

.inbox-screen--contained {
  display: flex !important;
  box-sizing: border-box;
  width: 100%;
  height: 100dvh !important;
  min-height: 0 !important;
  flex-direction: column;
  overflow: hidden !important;
}

.inbox-screen--contained > .inbox-topbar,
.inbox-screen--contained > .inbox-error {
  width: 100%;
  flex: 0 0 auto;
}

.inbox-screen--contained > .inbox {
  width: 100%;
  height: auto !important;
  min-height: 0 !important;
  max-height: none !important;
  flex: 1 1 0;
  overflow: hidden !important;
}

.inbox-screen--contained .ticket-list {
  display: grid;
  min-height: 0;
  grid-template-rows: auto minmax(0, 1fr);
  overflow: hidden;
}

.inbox-screen--contained .ticket-list__items {
  height: auto !important;
  min-height: 0;
  overflow-y: auto;
}

.conversation-panel {
  display: grid !important;
  width: 100%;
  min-width: 0;
  min-height: 0;
  grid-template-rows: auto auto minmax(0, 1fr) !important;
  overflow: hidden !important;
  padding: 0 !important;
  background:
    linear-gradient(
      rgba(247, 248, 245, 0.91),
      rgba(247, 248, 245, 0.91)
    ),
    radial-gradient(
      circle at 30% 40%,
      #dce3dd 1px,
      transparent 1px
    );
  background-size: auto, 20px 20px;
}

.conversation-panel > .chat-header {
  min-height: 66px;
}

.conversation-body {
  display: grid !important;
  width: 100%;
  min-width: 0;
  min-height: 0;
  grid-template-rows: minmax(0, 1fr) auto !important;
  overflow: hidden !important;
  padding: 0 !important;
}

.conversation-scroll {
  width: 100%;
  min-width: 0;
  min-height: 0;
  overflow-x: hidden !important;
  overflow-y: auto !important;
  overscroll-behavior: contain;
  scrollbar-gutter: stable;
  padding: 26px clamp(20px, 5vw, 70px) 22px;
}

.conversation-composer {
  position: static !important;
  display: grid !important;
  width: 100% !important;
  min-width: 0;
  min-height: 70px;
  grid-template-columns: minmax(0, 1fr) 46px !important;
  align-items: end;
  gap: 10px;
  margin: 0 !important;
  border: 0 !important;
  border-top: 1px solid var(--line) !important;
  border-radius: 0 !important;
  background: #fff !important;
  padding: 12px 16px !important;
  opacity: 1 !important;
  visibility: visible !important;
  transform: none !important;
}

.conversation-composer textarea {
  display: block;
  box-sizing: border-box;
  width: 100% !important;
  min-width: 0;
  height: 46px !important;
  min-height: 46px !important;
  max-height: 120px;
  resize: none;
  border: 1px solid var(--line);
  border-radius: 13px;
  outline: none;
  background: var(--surface-subtle);
  padding: 13px 14px;
  font: inherit;
  font-size: 12px;
  line-height: 1.5;
}

.conversation-composer textarea:focus {
  border-color: var(--accent);
  background: #fff;
}

.conversation-composer .composer__send {
  display: grid;
  width: 46px;
  height: 46px;
  place-items: center;
  border: 0;
  border-radius: 13px;
  background: var(--sidebar);
  color: #fff;
  font-size: 20px;
}

.conversation-composer .composer__send:disabled {
  opacity: 0.35;
}

@media (max-width: 820px) {
  .inbox-screen--contained {
    height: auto !important;
    min-height: 100dvh !important;
    overflow: visible !important;
  }

  .inbox-screen--contained > .inbox {
    min-height: 680px !important;
  }

  .conversation-scroll {
    padding: 18px 12px;
  }

  .conversation-composer {
    padding: 10px 12px !important;
  }
}
EOF
fi

echo "[P1.2f] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.2f] Complete."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then hard refresh:"
echo "  Ctrl+Shift+R"
