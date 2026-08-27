# Operational analytics

P1.13 replaces the Dashboard placeholder metrics with real operational data.

## Periods

The operator can view:

- 7 days
- 30 days
- 90 days

## Current-state metrics

The dashboard shows:

- active OPEN/PENDING tickets;
- customers currently waiting;
- current tickets at SLA risk;
- current SLA breaches.

These use the P1.11 ticket clocks and company SLA settings.

## Period metrics

The selected period shows:

- tickets created;
- tickets closed;
- average first-response time;
- first-response SLA compliance.

First-response compliance only uses tickets that have a persisted first inbound
and first response.

Wapp does not invent historical reply cycles that were not persisted before
P1.11.

## Trend

The daily trend compares:

- ticket creation date;
- ticket close date.

## Backlog distribution

Current active backlog is grouped by:

- queue;
- assigned membership.

Each group includes:

- active count;
- waiting count;
- current SLA breach count.

## API

`GET /api/v1/analytics/operational?days=7`

Allowed periods:

- 7
- 30
- 90

The endpoint requires `sla.read`, which is available to every operational role.

## Migration

P1.13 adds no database schema. No Prisma migration is required.
