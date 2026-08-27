# Ticket tags

P1.8 adds reusable company tags to operational tickets.

## Catalog

A tag contains:

- name
- colorKey
- active/inactive state

Colors are semantic UI keys, not arbitrary CSS supplied by users:

- GREEN
- BLUE
- ORANGE
- RED
- PURPLE
- GRAY

## Permissions

OWNER, ADMIN and SUPERVISOR can manage the catalog.

AGENT can read active tags.

Applying/removing tags from a ticket is a ticket operation and follows the
existing assignment rule. An AGENT cannot change tags on a ticket assigned to
another agent.

## Ticket relation

Tags are attached through `TicketTag`.

A ticket can have at most 20 tags.

Replacing ticket tags:

`PUT /api/v1/tickets/:id/tags`

```json
{
  "tagIds": ["uuid-1", "uuid-2"]
}
```

Only active tags from the same company are accepted.

## UI

The Conversations screen provides:

- tag chips on tickets;
- tag chips on the selected ticket;
- a tag picker;
- catalog management for privileged roles;
- a ticket-list filter by tag.

## Realtime

Catalog changes emit:

`tag.updated`

Ticket assignment changes continue using:

`ticket.updated`

This keeps other operator sessions synchronized without turning tags into
messages or WhatsApp content.
