# P3.3 Tasks and follow-ups

P3.3 adds an operational follow-up layer over Contacts.

A task has one contact, one responsible membership, one creator and may
optionally link to a ticket.

Statuses:

- OPEN
- DONE
- CANCELLED

Priorities:

- LOW
- NORMAL
- HIGH
- URGENT

Every task has a due date. A reminder is optional, must be future and cannot be
after the due date.

## Durable reminders

MySQL is the source of truth.

BullMQ queue:

`wapp-task-reminders`

A delayed job is created per reminder and a one-minute sweep reconciles due
tasks if Redis or a worker was unavailable at the original enqueue time.

Delivery uses an atomic reminder claim and deterministic notification dedupe.
Worker retry therefore does not intentionally produce duplicate reminders.

If the responsible membership becomes inactive before delivery, the reminder
is marked failed and remains visible on the task.

## Notifications

P3.3 extends P2.7 with:

- TASK_ASSIGNED
- TASK_REMINDER

Notification gets an optional `contactId`.

Deep-link priority:

1. linked ticket -> Conversations
2. otherwise linked contact -> Contacts

P3.3 also makes `/dashboard/contacts?contact=<id>` reliable, which closes the
same deep-link path used by P3.2 pipeline cards.

## RBAC

All roles can read and operate their own work.

AGENT can create tasks only for themselves and cannot reassign tasks or open
the team-wide agenda.

OWNER / ADMIN / SUPERVISOR can delegate, reassign and view team tasks.

## Immutable history

`CrmTaskEvent` records:

- CREATED
- UPDATED
- REASSIGNED
- COMPLETED
- CANCELLED
- REMINDER_SENT
- REMINDER_FAILED

## UI

Contact profile gets quick task creation and task history.

Global agenda:

`/dashboard/tasks`

It includes open/completed/cancelled views, overdue filtering, My Tasks, a
managerial Team view, and deep links to contact/ticket.

## Migration

P3.3 introduces:

- CrmTask
- CrmTaskEvent
- task enums
- Notification.contactId
