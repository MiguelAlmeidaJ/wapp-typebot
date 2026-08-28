# P2.6 Management reports

P2.6 adds a management layer on top of the P1.13 operational analytics.

Endpoint:

`GET /api/v1/reports/management?days=7|30|90&queueId=<optional uuid>`

Permission:

`reports.read`

Allowed roles:

- OWNER
- ADMIN
- SUPERVISOR

AGENT does not receive management-report access.

## Current operational state

The report exposes the current number of:

- active tickets;
- tickets waiting for a reply;
- tickets currently beyond SLA;
- unassigned tickets.

These are snapshots, not period totals.

## Period comparison

The selected period is compared with the immediately preceding period of the
same size.

Metrics:

- created tickets;
- closed tickets;
- reopened tickets;
- outbound messages sent by actual Wapp users;
- average first-response time;
- first-response SLA compliance;
- average resolution time;
- closed/created throughput.

When the previous value is zero, Wapp returns a null percentage change rather
than inventing an infinite percentage.

## Agent attribution

P2.6 deliberately avoids attributing historical production to the ticket's
current assignee.

Closed-ticket production uses the `CLOSED` TicketEvent
`actorMembershipId`.

Outbound-message production uses Message `sentByUserId`.

The current active-ticket count still uses current assignment because that is
a workload snapshot.

This makes transfer-heavy workflows materially more trustworthy.

## Queue metrics

Queue metrics use the queue currently/finally associated with each ticket.
The schema does not yet persist a complete historical queue dimension for every
metric sample. This limitation is explicit and should be considered when a
ticket moves between queues during the reporting period.

## Time metrics

First response:

`firstInboundAt -> firstResponseAt`

Resolution:

`createdAt -> closedAt`

These are elapsed wall-clock durations. Business-hours calendars are not part
of P2.6.

## UI

`/dashboard/reports`

Includes:

- 7 / 30 / 90-day period control;
- queue filter;
- current-state strip;
- comparison KPI cards;
- created-vs-closed daily trend;
- queue performance table;
- attributable agent production table.

No database migration is required for P2.6.
