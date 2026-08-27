# Closed tickets and safe reopen

P1.10 adds a read-only archive workflow for closed tickets.

## Operator workflow

The Conversations screen exposes an `Encerrados` control.

The archive drawer contains:

- closed ticket list;
- contact/queue/assignee context;
- read-only message history;
- media rendering through the existing protected media endpoint;
- safe reopen.

The normal conversation composer is never shown inside the archive.

## Safe reopen

`POST /api/v1/tickets/:id/reopen`

Reopening follows the existing ticket assignment rule.

When a closed ticket is reopened successfully:

- `activeKey` is restored;
- status becomes `OPEN`;
- it is assigned to the operator who reopened it;
- `closedAt` becomes null;
- unread count resets to zero.

## Duplicate protection

Before reopening, Wapp checks whether the same company + WhatsApp connection +
contact already has an OPEN/PENDING ticket.

If one exists, Wapp returns that existing active ticket instead of reopening
the old one.

The unique `activeKey` remains the final concurrency guard. If an inbound
message races with the reopen operation and creates an active ticket between
the pre-check and update, Wapp resolves the newly active ticket and opens it.

This preserves the invariant of one active ticket per connection/contact.

## Data preservation

Reopening does not erase:

- messages;
- internal notes;
- tags;
- queue history stored on the ticket;
- media;
- message delivery status.

No Prisma migration is required for P1.10.
