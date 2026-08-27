# Internal ticket notes

P1.6 adds an internal collaboration timeline to each ticket.

Internal notes are not WhatsApp messages.

They:

- are never sent to the customer;
- do not modify `Ticket.lastMessage`;
- are stored separately from `Message`;
- record the author's company membership;
- are visible to the company team;
- update other open Wapp sessions through realtime.

## Model

```text
Ticket
  |
  +-- TicketNote
        |
        +-- authorMembership
        +-- body
        +-- createdAt
```

Notes are append-only in P1.6. There is intentionally no edit/delete endpoint
yet, preserving a simple operational audit trail.

## Authorization

Reading notes requires access to the company ticket.

Creating a note uses the same assignment protection as ticket operations:
an AGENT cannot add a note to a ticket assigned to another agent, while
OWNER/ADMIN/SUPERVISOR retain override capability.

Creating a note does not automatically claim an unassigned ticket.

## Realtime

Creation publishes:

`note.created`

with `ticketId` and `noteId`.

The drawer refreshes when another operator adds a note to the selected ticket.
