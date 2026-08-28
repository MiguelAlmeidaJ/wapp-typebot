#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PAGE="apps/web/app/dashboard/conversations/page.tsx"
CSS="apps/web/app/globals.css"

echo "[P2.8] Installing mobile/responsive refinement..."

for required in \
  "$PAGE" \
  "$CSS" \
  "apps/web/app/dashboard/page.tsx"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p docs scripts

# ---------------------------------------------------------------------------
# Conversations: expose explicit responsive state without changing behavior.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldMain =
  `<main className="inbox-screen inbox-screen--contained">`;

const newMain =
  `<main
      className={
        selectedTicket
          ? "inbox-screen inbox-screen--contained inbox-screen--conversation-open"
          : "inbox-screen inbox-screen--contained"
      }
    >`;

if (
  content.includes(
    oldMain
  )
) {
  content =
    content.replace(
      oldMain,
      newMain
    );
} else if (
  !content.includes(
    "inbox-screen--conversation-open"
  )
) {
  throw new Error(
    "Conversation main responsive-state anchor not found."
  );
}

const oldInbox =
  `<section className="inbox">`;

const newInbox =
  `<section
        className={
          selectedTicket
            ? "inbox inbox--conversation-open"
            : "inbox"
        }
      >`;

if (
  content.includes(
    oldInbox
  )
) {
  content =
    content.replace(
      oldInbox,
      newInbox
    );
} else if (
  !content.includes(
    "inbox--conversation-open"
  )
) {
  throw new Error(
    "Conversation inbox responsive-state anchor not found."
  );
}

/*
 * Preserve the canonical P1.2f scroll ownership. P2.8 may only add layout
 * state around it; it must never turn the composer into part of the scroll.
 */
for (
  const marker
  of [
    'className="conversation-body"',
    'className="conversation-scroll"',
    'className="conversation-composer'
  ]
) {
  if (
    !content.includes(
      marker
    )
  ) {
    throw new Error(
      `Canonical conversation marker missing: ${marker}`
    );
  }
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.8] Responsive conversation state installed."
);
NODE

# ---------------------------------------------------------------------------
# Responsive CSS.
# This is deliberately appended so it wins over legacy desktop rules without
# reopening old style blocks or changing desktop composition.
# ---------------------------------------------------------------------------

if ! grep -Fq -- "WAPP P2.8 / RESPONSIVE PRODUCT PASS" "$CSS"; then
cat >> "$CSS" <<'EOF'

/* --- WAPP P2.8 / RESPONSIVE PRODUCT PASS ----------------------------- */

/*
 * Tablet: keep the two-pane inbox, but reduce the fixed list width and let
 * operational controls scroll instead of crushing the conversation.
 */
@media (max-width: 1080px) {
  .inbox-screen--contained {
    padding-inline: 14px;
  }

  .inbox {
    grid-template-columns: minmax(270px, 32vw) minmax(0, 1fr);
  }

  .inbox-topbar {
    align-items: flex-start;
    gap: 14px;
  }

  .inbox-topbar__right {
    display: flex;
    max-width: 58vw;
    overflow-x: auto;
    align-items: center;
    gap: 6px;
    padding-bottom: 3px;
    scrollbar-width: thin;
  }

  .inbox-topbar__right > * {
    flex: 0 0 auto;
  }

  .conversation-home-grid {
    grid-template-columns: minmax(0, 1fr);
  }

  .conversation-home-side {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
  }

  .conversation-overview-note {
    grid-column: 1 / -1;
  }

  .assignment-bar {
    flex-wrap: nowrap;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scrollbar-width: thin;
  }

  .assignment-bar > * {
    flex: 0 0 auto;
  }
}

/*
 * Phone: the inbox becomes a true one-screen flow.
 *
 * No selected ticket:
 *   ticket-list = visible
 *   conversation-panel = hidden
 *
 * Selected ticket:
 *   ticket-list = hidden
 *   conversation-panel = full viewport
 */
@media (max-width: 760px) {
  html,
  body {
    min-width: 0;
    overflow-x: hidden;
  }

  body {
    padding-bottom: env(safe-area-inset-bottom, 0px);
  }

  button,
  [role="button"],
  .primary-button,
  .secondary-button,
  .ghost-button,
  .connections-back {
    touch-action: manipulation;
  }

  input,
  select,
  textarea {
    font-size: 16px;
  }

  .inbox-screen--contained {
    display: flex;
    width: 100%;
    height: 100dvh;
    min-height: 100dvh;
    flex-direction: column;
    overflow: hidden;
    padding: 0;
    background: var(--surface-subtle);
  }

  .inbox-topbar {
    display: flex;
    min-height: 62px;
    flex: 0 0 auto;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    overflow: hidden;
    border-bottom: 1px solid var(--line);
    background: rgba(255, 255, 255, 0.96);
    padding: calc(8px + env(safe-area-inset-top, 0px)) 10px 8px;
    backdrop-filter: blur(14px);
  }

  .inbox-topbar > div:first-child {
    min-width: 0;
  }

  .inbox-topbar .connections-back {
    min-height: 34px;
    padding-inline: 8px;
  }

  .inbox-topbar .eyebrow {
    display: none;
  }

  .inbox-topbar h1 {
    margin: 2px 0 0;
    font-size: 21px;
    letter-spacing: -0.04em;
  }

  .inbox-topbar__right {
    display: flex;
    max-width: 58vw;
    overflow-x: auto;
    align-items: center;
    gap: 5px;
    padding-bottom: 2px;
    scrollbar-width: none;
  }

  .inbox-topbar__right::-webkit-scrollbar {
    display: none;
  }

  .inbox-topbar__right > span {
    display: none;
  }

  .inbox-topbar__right .ghost-button {
    min-height: 34px;
    flex: 0 0 auto;
    padding-inline: 9px;
    font-size: 8px;
  }

  .inbox-screen--conversation-open .inbox-topbar {
    display: none;
  }

  .inbox-error,
  .inbox-notice {
    flex: 0 0 auto;
    margin: 7px 8px 0;
  }

  .inbox {
    display: grid;
    min-width: 0;
    min-height: 0;
    flex: 1 1 auto;
    grid-template-columns: minmax(0, 1fr);
    overflow: hidden;
    border: 0;
    border-radius: 0;
  }

  .ticket-list {
    display: flex;
    width: 100%;
    min-width: 0;
    min-height: 0;
    height: 100%;
    flex-direction: column;
    overflow: hidden;
    border-right: 0;
    background: white;
  }

  .ticket-list__heading {
    flex: 0 0 auto;
    padding: 12px 10px 9px;
  }

  .ticket-list__items {
    min-height: 0;
    flex: 1 1 auto;
    overflow-y: auto;
    overscroll-behavior: contain;
    -webkit-overflow-scrolling: touch;
  }

  .ticket-item {
    min-height: 76px;
    padding: 11px 10px;
  }

  .ticket-item .ticket-avatar {
    width: 42px;
    height: 42px;
    flex-basis: 42px;
  }

  .inbox-status-filters {
    display: flex;
    overflow-x: auto;
    gap: 5px;
    padding-bottom: 2px;
    scrollbar-width: none;
  }

  .inbox-status-filters::-webkit-scrollbar {
    display: none;
  }

  .inbox-status-chip {
    min-height: 34px;
    flex: 0 0 auto;
    padding-inline: 10px;
  }

  .inbox-ticket-search input,
  .inbox-advanced-filters select {
    min-height: 42px;
  }

  .inbox-advanced-filters__body {
    grid-template-columns: 1fr;
  }

  .conversation-panel {
    display: none;
    width: 100%;
    min-width: 0;
    min-height: 0;
    height: 100%;
    overflow: hidden;
    background: white;
  }

  .inbox--conversation-open .ticket-list {
    display: none;
  }

  .inbox--conversation-open .conversation-panel {
    display: flex;
    min-height: 0;
    flex-direction: column;
  }

  /*
   * Mobile intentionally does not render the duplicate desktop overview.
   * The ticket list itself is the mobile home.
   */
  .inbox:not(.inbox--conversation-open) .conversation-panel {
    display: none;
  }

  .chat-header {
    min-width: 0;
    min-height: 58px;
    flex: 0 0 auto;
    gap: 8px;
    border-bottom: 1px solid var(--line);
    padding: calc(7px + env(safe-area-inset-top, 0px)) 9px 7px;
    background: rgba(255, 255, 255, 0.98);
    z-index: 16;
  }

  .chat-header__contact {
    min-width: 0;
    flex: 1 1 auto;
    gap: 7px;
  }

  .chat-header__contact > div:last-child {
    min-width: 0;
  }

  .chat-header__contact strong,
  .chat-header__contact span {
    display: block;
    overflow: hidden;
    max-width: 100%;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .chat-header__contact strong {
    font-size: 11px;
  }

  .chat-header__contact span {
    font-size: 8px;
  }

  .chat-header .ticket-avatar {
    width: 34px;
    height: 34px;
    flex: 0 0 34px;
  }

  .conversation-home-back {
    display: grid;
    width: 40px;
    height: 40px;
    flex: 0 0 40px;
    place-items: center;
    border-radius: 10px;
    font-size: 16px;
  }

  .chat-header__actions {
    display: flex;
    flex: 0 0 auto;
    gap: 5px;
  }

  .chat-header__actions .primary-button,
  .chat-header__actions .ghost-button {
    min-height: 38px;
    padding-inline: 9px;
    font-size: 8px;
  }

  .assignment-bar {
    display: flex;
    min-width: 0;
    min-height: 52px;
    flex: 0 0 auto;
    flex-wrap: nowrap;
    align-items: flex-end;
    gap: 6px;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    border-bottom: 1px solid var(--line);
    padding: 6px 9px;
    scrollbar-width: none;
  }

  .assignment-bar::-webkit-scrollbar {
    display: none;
  }

  .assignment-bar > div:not(.selected-ticket-tags) {
    width: 150px;
    flex: 0 0 150px;
  }

  .assignment-bar select {
    width: 100%;
    min-height: 38px;
  }

  .assignment-bar > button {
    min-height: 38px;
    flex: 0 0 auto;
    padding-inline: 10px;
  }

  .assignment-bar > small {
    display: none;
  }

  .selected-ticket-tags {
    display: flex;
    max-width: 220px;
    overflow-x: auto;
    flex: 0 0 auto;
    gap: 4px;
    scrollbar-width: none;
  }

  .conversation-body {
    position: relative;
    display: flex;
    min-width: 0;
    min-height: 0;
    flex: 1 1 auto;
    flex-direction: column;
    overflow: hidden;
  }

  .conversation-scroll {
    min-width: 0;
    min-height: 0;
    flex: 1 1 auto;
    overflow-y: auto;
    overscroll-behavior-y: contain;
    padding: 12px 9px 16px;
    -webkit-overflow-scrolling: touch;
  }

  .message-row {
    width: 100%;
    padding-inline: 0;
  }

  .message-bubble {
    max-width: min(88vw, 560px);
  }

  .message-bubble--media {
    max-width: min(90vw, 560px);
  }

  .message-quoted-preview {
    max-width: 100%;
  }

  .message-meta {
    gap: 5px;
  }

  .message-reaction-trigger,
  .message-reply-action,
  .message-reaction-option {
    min-width: 32px;
    min-height: 32px;
  }

  .message-reaction-picker {
    max-width: calc(100vw - 28px);
  }

  /*
   * Composer remains outside .conversation-scroll. This is the important
   * P1.2f invariant and gives the phone a stable messaging surface.
   */
  .conversation-composer {
    position: relative;
    inset: auto;
    min-width: 0;
    flex: 0 0 auto;
    gap: 6px;
    border-top: 1px solid var(--line);
    background: rgba(255, 255, 255, 0.99);
    padding: 8px 9px
      calc(8px + env(safe-area-inset-bottom, 0px));
    box-shadow: 0 -8px 24px rgba(28, 43, 34, 0.045);
    z-index: 14;
  }

  .conversation-composer textarea {
    min-width: 0;
    min-height: 42px;
    max-height: 112px;
    font-size: 16px;
    line-height: 1.35;
  }

  .conversation-composer button,
  .conversation-composer .composer__schedule {
    min-width: 40px;
    min-height: 40px;
  }

  .composer-replying,
  .attachment-preview,
  .voice-note-preview {
    max-width: 100%;
  }

  /*
   * Conversation tools become viewport sheets. They remain children of
   * .conversation-body, so no second page-level scroll is introduced.
   */
  .ticket-history-drawer,
  .sla-monitor-drawer,
  .closed-tickets-drawer,
  .conversation-search,
  .tag-manager,
  .quick-reply-manager,
  .ticket-notes-drawer {
    position: absolute;
    inset: 0;
    width: 100%;
    max-width: none;
    height: 100%;
    max-height: none;
    overflow-y: auto;
    border: 0;
    border-radius: 0;
    background: white;
    z-index: 36;
    -webkit-overflow-scrolling: touch;
  }

  .ticket-tag-picker {
    position: absolute;
    right: 8px;
    bottom: 8px;
    left: 8px;
    top: auto;
    width: auto;
    max-width: none;
    max-height: min(66dvh, 520px);
    overflow-y: auto;
    border-radius: 16px;
    box-shadow: 0 18px 50px rgba(22, 37, 28, 0.18);
    z-index: 38;
  }

  .scheduled-message-drawer {
    max-height: min(58dvh, 520px);
    flex: 0 0 auto;
    padding: 11px 10px;
  }

  .scheduled-message-form {
    grid-template-columns: 1fr;
  }

  .scheduled-message-form__footer {
    grid-column: auto;
  }

  /*
   * Global dashboard becomes a bottom-navigation workspace on phones.
   * Existing role filtering still controls which nav items exist.
   */
  .workspace {
    display: block;
    min-height: 100dvh;
    padding-bottom: calc(70px + env(safe-area-inset-bottom, 0px));
  }

  .workspace__content {
    min-width: 0;
  }

  .sidebar {
    position: fixed;
    top: auto;
    right: 8px;
    bottom: calc(8px + env(safe-area-inset-bottom, 0px));
    left: 8px;
    width: auto;
    height: 56px;
    min-height: 0;
    z-index: 220;
    flex-direction: row;
    border: 1px solid var(--line);
    border-radius: 16px;
    background: rgba(255, 255, 255, 0.96);
    box-shadow: 0 14px 42px rgba(22, 37, 28, 0.14);
    padding: 4px;
    backdrop-filter: blur(16px);
  }

  .sidebar__top {
    width: 100%;
    min-width: 0;
  }

  .sidebar__top > :not(.sidebar__nav) {
    display: none;
  }

  .sidebar__nav {
    display: flex;
    width: 100%;
    height: 100%;
    overflow-x: auto;
    align-items: stretch;
    gap: 2px;
    scrollbar-width: none;
  }

  .sidebar__nav::-webkit-scrollbar {
    display: none;
  }

  .nav-item {
    min-width: 86px;
    min-height: 46px;
    flex: 1 0 86px;
    justify-content: center;
    border-radius: 12px;
    padding: 0 9px;
    font-size: 8px;
    text-align: center;
  }

  .nav-item__dot,
  .sidebar__user {
    display: none;
  }

  .topbar {
    min-height: 52px;
    padding: calc(8px + env(safe-area-inset-top, 0px)) 12px 8px;
  }

  .dashboard {
    padding: 16px 12px 28px;
  }

  .dashboard__intro {
    align-items: flex-start;
    gap: 10px;
  }

  .dashboard__intro h1 {
    font-size: 28px;
  }

  .dashboard-grid,
  .dashboard-grid--single {
    grid-template-columns: 1fr;
  }

  .panel {
    min-width: 0;
  }

  /*
   * P2.6 reports already had a responsive pass; this closes touch/safe-area
   * details and prevents tables from widening the document.
   */
  .management-reports {
    max-width: 100vw;
    overflow-x: hidden;
    padding-bottom:
      calc(82px + env(safe-area-inset-bottom, 0px));
  }

  .management-report-panel,
  .management-report-table {
    min-width: 0;
    max-width: 100%;
  }

  .management-report-table {
    overflow-x: auto;
    overscroll-behavior-x: contain;
    -webkit-overflow-scrolling: touch;
  }

  .management-trend-chart {
    min-width: 560px;
  }

  .management-report-panel--trend {
    overflow-x: auto;
  }

  /*
   * P2.7 notification center stays above bottom navigation and opens within
   * the physical phone width.
   */
  .notification-center {
    top: calc(10px + env(safe-area-inset-top, 0px));
    right: 10px;
  }

  .notification-center__trigger {
    min-height: 38px;
  }

  .notification-center__panel {
    position: fixed;
    top: calc(54px + env(safe-area-inset-top, 0px));
    right: 10px;
    left: 10px;
    width: auto;
    max-height:
      calc(
        100dvh -
        72px -
        env(safe-area-inset-top, 0px) -
        env(safe-area-inset-bottom, 0px)
      );
  }

  .notification-center__list {
    max-height:
      calc(
        100dvh -
        205px -
        env(safe-area-inset-top, 0px) -
        env(safe-area-inset-bottom, 0px)
      );
  }

  .notification-item {
    min-height: 66px;
    padding: 11px 12px;
  }

  /*
   * Shared administration forms: no horizontal document overflow and touch
   * controls large enough to operate without precision tapping.
   */
  .connections-back,
  .primary-button,
  .secondary-button,
  .ghost-button {
    min-height: 40px;
  }

  main {
    max-width: 100vw;
  }
}

@media (max-width: 430px) {
  .chat-header__actions .ghost-button {
    max-width: 74px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .assignment-bar > div:not(.selected-ticket-tags) {
    width: 136px;
    flex-basis: 136px;
  }

  .message-bubble,
  .message-bubble--media {
    max-width: 92vw;
  }

  .management-state-strip,
  .management-summary-grid {
    grid-template-columns: 1fr 1fr;
  }

  .management-agent-row {
    grid-template-columns: 1fr;
  }

  .management-agent-row__identity {
    grid-column: auto;
  }
}

@media (
  max-width: 900px
) and (
  max-height: 600px
) and (
  orientation: landscape
) {
  .inbox-screen--conversation-open .chat-header {
    min-height: 50px;
    padding-top: 5px;
    padding-bottom: 5px;
  }

  .assignment-bar {
    min-height: 46px;
    padding-top: 4px;
    padding-bottom: 4px;
  }

  .conversation-composer {
    padding-top: 5px;
    padding-bottom:
      calc(5px + env(safe-area-inset-bottom, 0px));
  }

  .ticket-history-drawer,
  .sla-monitor-drawer,
  .closed-tickets-drawer,
  .conversation-search,
  .tag-manager,
  .quick-reply-manager,
  .ticket-notes-drawer {
    overscroll-behavior: contain;
  }
}

/* --- /WAPP P2.8 ------------------------------------------------------ */
EOF
fi

# ---------------------------------------------------------------------------
# Static responsive smoke check
# ---------------------------------------------------------------------------

cat > scripts/p2-08-responsive-smoke.mjs <<'EOF'
import fs from "node:fs";

const page =
  fs.readFileSync(
    "apps/web/app/dashboard/conversations/page.tsx",
    "utf8"
  );

const css =
  fs.readFileSync(
    "apps/web/app/globals.css",
    "utf8"
  );

const requiredPageMarkers = [
  "inbox-screen--conversation-open",
  "inbox--conversation-open",
  'className="conversation-body"',
  'className="conversation-scroll"',
  'className="conversation-composer'
];

const requiredCssMarkers = [
  "WAPP P2.8 / RESPONSIVE PRODUCT PASS",
  "@media (max-width: 760px)",
  ".inbox--conversation-open .ticket-list",
  ".inbox--conversation-open .conversation-panel",
  ".conversation-composer",
  "100dvh",
  "safe-area-inset-bottom",
  ".sidebar",
  ".notification-center__panel"
];

for (
  const marker
  of requiredPageMarkers
) {
  if (
    !page.includes(
      marker
    )
  ) {
    throw new Error(
      `P2.8 page marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of requiredCssMarkers
) {
  if (
    !css.includes(
      marker
    )
  ) {
    throw new Error(
      `P2.8 CSS marker missing: ${marker}`
    );
  }
}

const scrollIndex =
  page.indexOf(
    'className="conversation-scroll"'
  );

const composerIndex =
  page.indexOf(
    'className="conversation-composer'
  );

if (
  scrollIndex <
    0 ||
  composerIndex <
    0 ||
  composerIndex <
    scrollIndex
) {
  throw new Error(
    "Canonical conversation scroll/composer ordering changed."
  );
}

console.log(
  "[P2.8] responsive smoke PASS"
);
EOF

cat > docs/P2_08_MOBILE_RESPONSIVE.md <<'EOF'
# P2.8 Mobile / responsive refinement

P2.8 is a product-layout pass. It does not change ticket, message or realtime
business logic.

## Conversation flow

Below 760 px the inbox uses one screen at a time.

Without a selected ticket:

- the ticket list occupies the full available viewport;
- the desktop overview panel is not duplicated on mobile.

With a selected ticket:

- the ticket list is hidden;
- `.conversation-panel` occupies the full viewport;
- the existing back arrow clears the selection and returns to the ticket list.

This is controlled by:

- `.inbox-screen--conversation-open`
- `.inbox--conversation-open`

No viewport-width checks are added to React business logic.

## Scroll invariant

P2.8 preserves the canonical P1.2f structure:

- `.conversation-body`
- `.conversation-scroll` is the message scroll owner
- `.conversation-composer` remains outside that scroll

The mobile composer is not implemented with a second sticky scroll container.

## Touch / phone behavior

- important controls receive larger touch targets;
- form controls use a phone-safe font size to avoid iOS focus zoom;
- assignment controls scroll horizontally instead of shrinking into unusable
  widths;
- message bubbles cap against the physical viewport;
- safe-area insets are respected for notched devices;
- `100dvh` is used for the conversation surface.

## Drawers

Conversation tools become full conversation-body sheets on phone widths:

- operational history;
- SLA;
- closed tickets;
- message search;
- tag manager;
- quick reply manager;
- internal notes.

Tag selection remains a compact bottom sheet.

## Dashboard

The desktop sidebar becomes a bottom navigation surface on phone widths.
Existing RBAC still determines which navigation entries exist.

## P2.6 / P2.7

Management reports keep tables horizontally contained inside their own panel.

Notification Center is constrained to the physical phone width and remains
above the mobile navigation.

## Validation

`scripts/p2-08-responsive-smoke.mjs` asserts:

- responsive conversation state exists;
- canonical scroll/composer markers still exist;
- responsive CSS and safe-area rules exist;
- composer still follows the message-scroll block in the source.

No Prisma migration is required.
EOF

echo "[P2.8] Responsive smoke..."
node scripts/p2-08-responsive-smoke.mjs

echo "[P2.8] Unit regression..."
pnpm test

echo "[P2.8] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.8] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.8] CODE VALIDATION PASS."
echo "No Prisma migration is required."
echo
echo "Next:"
echo "  pnpm test:integration"
echo "  pnpm dev"
echo
echo "Manual viewport checks:"
echo "  390x844"
echo "  430x932"
echo "  768x1024"
echo "  desktop >= 1280"
