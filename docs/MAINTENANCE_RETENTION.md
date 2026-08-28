# P1.27 Maintenance and retention

Wapp now has a durable scheduled housekeeping job on the existing BullMQ/Redis
infrastructure.

Default cadence: every 6 hours.

Automatic destructive retention is deliberately narrow:

- only Session rows that have been expired or revoked beyond the configured
  retention window are deleted.

The job does NOT automatically delete:

- contacts;
- tickets;
- messages;
- ticket events;
- audit records;
- media objects;
- failed deliveries.

Instead it records diagnostics for stale PENDING media, FAILED media, FAILED
outbound delivery in the last 24 hours and Evolution connections marked DOWN.

Each execution is stored in `MaintenanceRun` with SUCCESS/FAILED status and
result metadata.

Operator manual run:

`pnpm maintenance:run`

The normal API/worker startup registers the recurring schedule. In production,
the dedicated P1.24 worker consumes both media-capture and maintenance jobs.
