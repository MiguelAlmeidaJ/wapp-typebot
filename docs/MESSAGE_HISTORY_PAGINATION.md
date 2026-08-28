# P1.21 Message history cursor pagination

The ticket message endpoint now opens the newest page and supports cursor
pagination with `before`, `after` and `around`.

Active conversations load the newest 80 messages first. Older pages are
prepended without replacing history already loaded.

Search results deep-link to the exact message using `around=<messageId>`.

Closed tickets can also load older history incrementally.

The canonical layout is preserved:

- `.conversation-panel`
- `.conversation-body`
- `.conversation-scroll` as the only message scroll
- `.conversation-composer` outside the scroll

No Prisma migration is required because the existing
`Message(ticketId, timestamp)` index is reused.
