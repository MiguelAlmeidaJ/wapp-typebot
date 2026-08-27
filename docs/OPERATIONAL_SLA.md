# Operational SLA

P1.11 adds response-time clocks to Wapp tickets.

## Company settings

Each company defines:

- `firstResponseSlaMinutes`
- `replySlaMinutes`

Defaults:

- first response: 15 minutes
- next response: 30 minutes

OWNER, ADMIN and SUPERVISOR can change these values.

AGENT can read the SLA monitor but cannot change thresholds.

## Ticket clocks

Wapp stores:

- `firstInboundAt`
- `firstResponseAt`
- `lastInboundAt`
- `lastOutboundAt`
- `waitingSince`

These are operational timestamps, not UI-only calculations.

### Inbound

When a customer message arrives:

- first inbound is preserved;
- last inbound is updated;
- `waitingSince` starts/restarts.

### Outbound

When an outbound message is sent either through Wapp or detected through the
WhatsApp webhook:

- last outbound is updated;
- `waitingSince` is cleared;
- first response is recorded if this is the first reply after the first inbound.

## Monitor severity

For a running SLA clock:

- below 70% of limit: waiting
- 70%-99%: risk
- 100%+: breached

The monitor refreshes elapsed labels every 30 seconds.

Realtime ticket/message/SLA events refresh the source data.

## Existing tickets

After the Prisma migration, run the backfill script once:

`pnpm --filter @wapp/api exec tsx src/scripts/backfill-ticket-sla.ts`

It reconstructs the clocks from existing Message history.

The backfill does not change messages, assignment, queue, tags, notes or ticket
status.
