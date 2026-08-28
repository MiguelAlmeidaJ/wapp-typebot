# P2.7 Notifications

P2.7 adds persistent, recipient-scoped notifications.

## Persistent model

Each notification belongs to:

- one company;
- one company membership;
- optionally one ticket/message.

Fields include:

- type;
- title/body;
- unread/read state;
- occurrence count;
- updated timestamp;
- dedupe key.

Unread state survives refresh, logout and server restart.

## Notification sources

### New inbound ticket

If a ticket is unassigned:

1. notify active members configured in the ticket queue;
2. if the queue has no explicit members, notify all active company members.

### Inbound message on an existing ticket

If assigned, only the active assignee is notified.

If unassigned, the same queue/fallback recipient policy is used.

Repeated inbound messages for the same ticket are coalesced into one
notification per recipient. The notification becomes unread again, updates its
preview and increments `occurrenceCount`.

### Assignment / transfer

When a ticket is transferred to another membership, that membership receives a
targeted notification.

Self-assignment does not notify the actor.

P2.4 `ASSIGN_MEMBERSHIP` automation also creates the targeted assignment
notification when it changes the assignee.

## Realtime privacy

The Redis realtime bus remains company-scoped internally, but
`notification.created` is filtered by the authenticated membership inside the
SSE route.

A browser never receives another membership's notification event.

The event carries ids only; notification content is fetched through the
recipient-scoped API.

## Browser alerts

The Dashboard layout mounts one global Notification Center.

Browser notifications are opt-in and require an explicit user click.

Desktop alerts are only shown when:

- browser permission is granted;
- the Wapp document is not visible.

This is realtime browser notification, not Web Push. The browser/app must still
have an active authenticated Wapp tab. Offline push infrastructure is outside
P2.7.

## Deep links

Clicking a notification navigates to:

`/dashboard/conversations?ticket=<ticket id>`

The conversation page consumes the target once and immediately removes the
query parameter while keeping the selected conversation open.

## API

- `GET /api/v1/notifications`
- `POST /api/v1/notifications/:id/read`
- `POST /api/v1/notifications/read-all`

All endpoints are authenticated and automatically scoped to the current
membership. There is no API to read another member's notification list.

## Migration

P2.7 introduces the `Notification` table.
