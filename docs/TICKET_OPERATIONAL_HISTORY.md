# Ticket operational history

P1.12 adds an immutable operational audit log to each ticket.

## Events

The first event set is:

- `CREATED`
- `CLAIMED`
- `TRANSFERRED`
- `CLOSED`
- `REOPENED`
- `TAGS_UPDATED`

Messages and internal notes are intentionally not duplicated into this log.

## Actor

User actions store `actorMembershipId`.

System-generated actions, such as creation from an inbound WhatsApp message,
have no actor membership and are displayed as `Sistema`.

## Metadata

Events can preserve operational snapshots such as:

- previous/new queue;
- previous/new assignee;
- tag names;
- initial message direction.

Metadata is descriptive history. Current ticket state continues to come from
the normal Ticket/Tag/Queue models.

## API

`GET /api/v1/tickets/:id/events`

The endpoint is company-scoped and returns at most the latest 300 events,
ordered newest first.

## Realtime

New audit entries publish:

`ticket.event.created`

An open history drawer refreshes automatically.

## Historical limitation

P1.12 does not invent past transfer/claim/tag events that were never recorded.

Existing tickets therefore start accumulating reliable audit history from the
moment P1.12 is deployed. This is preferable to creating inaccurate historical
records.

## Migration

P1.12 requires a Prisma migration for the `TicketEvent` model and relations.
