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
