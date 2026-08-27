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

echo "[P1.2e] Fixing live media refresh and long conversation layout..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

/* -----------------------------------------------------------------------
 * 1. Isolate the operator layout from all old P0.7 composer overrides.
 * --------------------------------------------------------------------- */

const classReplacements = [
  [
    '<main className="inbox-screen">',
    '<main className="inbox-screen inbox-screen--contained">'
  ],
  [
    '<section className="chat-panel chat-panel--operations">',
    '<section className="conversation-panel">'
  ],
  [
    '<div className="message-list message-list--assignment">',
    '<div className="conversation-body">'
  ],
  [
    '<div className="message-scroll">',
    '<div className="conversation-scroll">'
  ],
  [
    '<form className="composer composer--sticky" onSubmit={handleSend}>',
    '<form className="conversation-composer" onSubmit={handleSend}>'
  ]
];

for (const [from, to] of classReplacements) {
  if (content.includes(from)) {
    content = content.replace(from, to);
  } else if (!content.includes(to)) {
    throw new Error(
      `Expected conversation layout token not found: ${from}`
    );
  }
}

/* -----------------------------------------------------------------------
 * 2. Media fallback refresh.
 *
 * SSE remains the primary path. This interval exists ONLY while at least
 * one visible message is still PENDING, and stops automatically as soon
 * as the API reports READY/FAILED.
 * --------------------------------------------------------------------- */

if (!content.includes("const hasPendingMedia = messages.some(")) {
  const anchor = `  const openCount = tickets.filter(ticket => ticket.status === "OPEN").length;`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticket counters anchor."
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

if (!content.includes("[P1.2e media pending fallback]")) {
  const anchor = `  useEffect(() => {
    bottomRef.current?.scrollIntoView({
      behavior: "smooth",
      block: "end"
    });
  }, [messages]);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find bottom scroll effect."
    );
  }

  const mediaEffect = `${anchor}

  // [P1.2e media pending fallback]
  // SSE is primary. Poll only while a visible media message is still pending.
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
        // Realtime/fallback errors are non-fatal. The next tick can retry.
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
    anchor,
    mediaEffect
  );
}

fs.writeFileSync(path, content);

console.log("Conversation JSX isolated from legacy composer classes.");
console.log("Pending-media fallback refresh installed.");
NODE

if ! grep -q "WAPP P1.2e / Stable conversation viewport" "$CSS"; then
  cat >> "$CSS" <<'EOF'

/* --- WAPP P1.2e / Stable conversation viewport ------------------------ */

/*
 * The operator screen owns the viewport.
 * The browser page itself must never become the chat scroll container.
 */
.inbox-screen--contained {
  display: flex;
  box-sizing: border-box;
  width: 100%;
  height: 100dvh;
  min-height: 0;
  flex-direction: column;
  overflow: hidden;
}

.inbox-screen--contained > .inbox-topbar,
.inbox-screen--contained > .inbox-error {
  width: 100%;
  flex: 0 0 auto;
}

.inbox-screen--contained > .inbox {
  width: 100%;
  height: auto;
  min-height: 0;
  flex: 1 1 0;
  overflow: hidden;
}

/*
 * Keep the ticket list inside the same viewport contract.
 */
.inbox-screen--contained .ticket-list {
  display: grid;
  min-height: 0;
  grid-template-rows: auto minmax(0, 1fr);
  overflow: hidden;
}

.inbox-screen--contained .ticket-list__items {
  height: auto;
  min-height: 0;
  overflow-y: auto;
}

/*
 * Canonical operator panel.
 *
 * header
 * assignment
 * body
 *
 * Only conversation-scroll is scrollable.
 */
.conversation-panel {
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-rows: auto auto minmax(0, 1fr);
  overflow: hidden;
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
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-rows: minmax(0, 1fr) auto;
  overflow: hidden;
}

.conversation-scroll {
  min-width: 0;
  min-height: 0;
  overflow-x: hidden;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 26px clamp(20px, 5vw, 70px) 22px;
  scrollbar-gutter: stable;
}

.conversation-composer {
  display: grid;
  width: 100%;
  min-width: 0;
  min-height: 70px;
  flex: 0 0 auto;
  grid-template-columns: minmax(0, 1fr) 46px;
  align-items: end;
  gap: 10px;
  margin: 0;
  border: 0;
  border-top: 1px solid var(--line);
  border-radius: 0;
  background: #fff;
  padding: 12px 16px;
}

.conversation-composer textarea {
  display: block;
  box-sizing: border-box;
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
    height: auto;
    min-height: 100dvh;
    overflow: visible;
  }

  .inbox-screen--contained > .inbox {
    min-height: 680px;
  }

  .conversation-scroll {
    padding: 18px 12px;
  }

  .conversation-composer {
    padding: 10px 12px;
  }
}
EOF
fi

echo "[P1.2e] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.2e] Done."
echo
echo "Restart Next if it is already running:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then hard refresh the browser:"
echo "  Ctrl+Shift+R"
