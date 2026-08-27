# P0.7 Operations

P0.7 adds operational ownership on top of the conversation domain.

## Ticket lifecycle

```text
Inbound message
    |
    v
PENDING + optional default queue
    |
    +-- agent claims ----------> OPEN
    |
    +-- transferred to queue --> PENDING
    |
    +-- transferred to agent --> OPEN
    |
    v
CLOSED
```

Sending a message from an unassigned PENDING ticket automatically claims it for
that Wapp membership before sending.

## Queues

Queues belong to a company. Memberships can be assigned to zero or more queues.

If a queue has configured members, Wapp only allows assignment to a membership
that belongs to that queue. An empty queue membership list is treated as an
unrestricted queue during this milestone.

A WhatsApp connection may define a default queue. New tickets from that
connection enter that queue automatically.

## Groups

`WhatsAppConnection.acceptGroups` is false by default.

Evolution may still deliver group events to the Wapp webhook, but Wapp drops
those events before creating Contact/Ticket/Message when the connection has
groups disabled. This makes the policy independent for each connection.

Existing group tickets created before P0.7 are not deleted automatically.

## Realtime

P0.7 replaces the three-second inbox polling loop with an authenticated
Server-Sent Events stream:

```text
Wapp API EventEmitter -> authenticated SSE -> Next client
```

The same SSE connection also maintains an in-memory online/offline presence count per membership (multiple tabs are counted safely).

This in-memory bus is correct for the current single API process. Before running
multiple API replicas, the bus should be moved to Redis Pub/Sub so every replica
sees the same events.

## P1.14 distributed realtime

The original P0.7 EventEmitter transport was intentionally limited to one API
process.

P1.14 keeps the same SSE contract but distributes company events and operator
presence through Redis Pub/Sub / Redis presence state.

See `docs/REDIS_REALTIME.md`.
