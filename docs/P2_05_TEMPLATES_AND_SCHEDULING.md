# P2.5 Templates and scheduled messages

P2.5 deliberately reuses Wapp Quick Replies as the reusable template catalog.
Creating a second template table would duplicate ownership, variables,
activation and permissions that already exist in Quick Replies.

Operational flow:

1. type a message or insert a Quick Reply in the composer;
2. open the clock control;
3. choose the final text and local date/time;
4. Wapp persists the schedule in MySQL before queueing delivery.

## Database source of truth

`ScheduledMessage` statuses:

- `PENDING`
- `PROCESSING`
- `SENT`
- `CANCELLED`
- `FAILED`

The database is authoritative. Redis/BullMQ is the execution transport.

## Delivery durability

At creation Wapp adds a delayed BullMQ job.

A `wapp-scheduled-message-sweep` scheduler also runs every minute. It finds
database records that are already due but still `PENDING` and re-enqueues them.
This recovers schedules when Redis or a worker was unavailable at creation or
at the original delivery time.

## Duplicate-send safety

Delivery claims a schedule atomically:

`PENDING -> PROCESSING`

Only one worker can claim it.

Automatic BullMQ retries are disabled because retrying an outbound WhatsApp
side effect after an uncertain failure can duplicate a message.

A schedule stuck in `PROCESSING` for more than 15 minutes becomes `FAILED`
with an explicit "delivery may be uncertain" warning. It is never resent
automatically.

## Authorization

An AGENT can schedule messages only for a ticket they are allowed to operate.

If a ticket is assigned to another agent, only OWNER / ADMIN / SUPERVISOR can
create the schedule.

An AGENT can cancel only their own pending schedule. OWNER / ADMIN /
SUPERVISOR can cancel any pending schedule in their company.

If the author membership or user becomes inactive before delivery, the
scheduled message fails instead of sending under a disabled identity.

## Ticket lifecycle

A message is not sent if its ticket was closed before the scheduled time.

A disconnected WhatsApp connection produces `FAILED` instead of an automatic
retry.

Successful scheduled sends are normal outbound `Message` records and update
ticket last-message / outbound SLA fields.

## History

Operational ticket history records:

- `MESSAGE_SCHEDULED`
- `SCHEDULED_MESSAGE_CANCELLED`
- `SCHEDULED_MESSAGE_SENT`
- `SCHEDULED_MESSAGE_FAILED`

## Scope

P2.5 schedules text only.

Quoted replies, media, voice notes and reactions remain immediate-only.
