# P3.4 Saved contact segments

P3.4 adds dynamic saved audiences. A segment stores a filter definition, not a
frozen list of contact IDs. Every preview or future use resolves the definition
against current database state.

## Safety boundary

P3.4 does not send WhatsApp messages and has no campaign/bulk-send endpoint.
Only direct contacts are eligible (`Contact.isGroup = false`). An empty
"all contacts" segment is rejected; at least one narrowing criterion must be
explicit.

## Criteria

Standard contact data:
- text search across name, WhatsApp name, phone and email;
- has / does not have phone;
- has / does not have email;
- last activity within 7, 30 or 90 days;
- never seen.

P3.1 custom fields:
- equals;
- not equal;
- contains for TEXT fields;
- empty;
- not empty.

P3.2 pipeline:
- one pipeline criterion;
- one or more current stages;
- optionally contacts with no stage in that pipeline.

P3.3 follow-up:
- any;
- has open task;
- has overdue task;
- has no open task.

All configured criteria are combined with AND.

## RBAC

All roles can read active saved segments and run previews. OWNER, ADMIN and
SUPERVISOR can create, edit, archive and reactivate shared segments. AGENT
cannot mutate shared segment definitions.

## API

- GET `/api/v1/segments`
- GET `/api/v1/segments/manage`
- GET `/api/v1/segments/context`
- POST `/api/v1/segments/preview`
- POST `/api/v1/segments`
- PATCH `/api/v1/segments/:id`
- GET `/api/v1/segments/:id/contacts`

Preview responses return a maximum of 100 contact records plus the full dynamic
count and a `truncated` flag.

## UI

`/dashboard/segments` contains the saved list, builder, P3.1/P3.2/P3.3 filters,
dynamic preview and deep links back to Contacts / Conversations.

## Migration

P3.4 introduces `ContactSegment`.
