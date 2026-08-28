# P2.3 Advanced inbox filters

P2.3 moves inbox filtering to the API instead of filtering only the ticket
array already loaded in the browser.

`GET /api/v1/tickets` accepts:

- `status=ACTIVE|OPEN|PENDING|CLOSED`;
- `q=<name, WhatsApp name, phone, JID or last message>`;
- `queueId=<uuid>|NONE`;
- `assigneeId=<membership uuid>|ME|NONE`;
- `unreadOnly=true|false`;
- `tagId=<uuid>`;
- `conversationType=ALL|DIRECT|GROUP`.

`ME` is resolved from the authenticated membership, never from a user id
provided by the browser.

The inbox orders unread conversations first, then newest activity.

The left column gets a debounced search, compact status chips, unread toggle,
queue/assignee/tag/type filters, active-filter count and one-click reset.

No message-scroll, composer, quoted-reply or reaction layout is changed.
