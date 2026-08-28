# P2.4 Operational automations

P2.4 adds deterministic company-scoped automation rules.

## Triggers

- `TICKET_CREATED`
- `INBOUND_MESSAGE`

Only inbound WhatsApp events schedule rules. Automated outbound messages do not
schedule another automation, preventing message loops.

## Conditions

A rule can restrict execution by:

- keyword contained in the inbound message, case-insensitive;
- only when the ticket is still unassigned;
- direct contact / group / all conversations.

Rules run by ascending priority.

## Actions

Actions execute in order:

- `SET_QUEUE`
- `ASSIGN_MEMBERSHIP`
- `ADD_TAG`
- `SEND_TEXT`

An automated text is stored with no `sentByUserId`. It is intentionally not
attributed to an operator and does not claim the ticket.

Supported variables:

- `{nome}`
- `{primeiro_nome}`
- `{empresa}`

## Durability

When Redis is configured, evaluation is queued in BullMQ `wapp-automations`.

Jobs use one attempt because a rule can contain side effects such as sending a
WhatsApp message. Automatic retries could duplicate an already-delivered side
effect.

Without Redis, development mode uses an explicitly non-durable inline fallback.

## Idempotency

Each rule/source-message/trigger combination has a unique `AutomationRun`
dedupe key. Duplicate webhook processing does not execute the same rule twice.

## Observability

Each matched rule gets an `AutomationRun`:

- RUNNING
- SUCCESS
- FAILED

Successful execution also appends the ticket-history event
`AUTOMATION_APPLIED`.

Rule create/update operations are written to the P1.26 administrative audit.

## RBAC

- OWNER: read/manage
- ADMIN: read/manage
- SUPERVISOR: read/manage
- AGENT: read only

## UI

`/dashboard/automations`

The first P2.4 UI supports:

- create a rule;
- choose trigger and conditions;
- compose queue/assignee/tag/text actions;
- activate/pause a rule;
- inspect its latest execution state.

The API already supports PATCH updates for later richer rule editing.

## Migration

P2.4 introduces:

- `AutomationRule`
- `AutomationAction`
- `AutomationRun`
