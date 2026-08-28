# P1.20 Evolution operational health monitoring

P1.20 separates three concepts that were previously easy to confuse:

- WhatsApp connection state;
- real webhook activity;
- provider/API health.

## Persisted fields

Each `WhatsAppConnection` now stores:

- `healthStatus`: `UNKNOWN`, `HEALTHY`, `DEGRADED`, `DOWN`;
- `lastHealthCheckAt`;
- `lastHealthOkAt`;
- `healthError`;
- `consecutiveHealthFailures`.

`lastEventAt` is intentionally preserved for actual Evolution activity and
manual lifecycle operations. The periodic health monitor does not overwrite it.

## Classification

`HEALTHY`

Evolution is reachable and reports the instance as open/connected.

`DEGRADED`

Evolution is reachable, but the WhatsApp instance is connecting, disconnected,
closed or reports another non-connected state.

`DOWN`

The monitor cannot successfully query Evolution for the instance.

`UNKNOWN`

No health cycle has evaluated the connection since the migration.

## Distributed monitoring

The API starts a health cycle every:

```env
EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS=60
```

When Redis is configured, a distributed lock ensures that only one Wapp API
process performs a cycle at a time.

This avoids N replicas multiplying health requests against Evolution.

The lock is not a durable business job. Missing one health cycle is harmless;
the next cycle recomputes authoritative state.

## Realtime

When connection state, health state or health error changes, Wapp emits the
existing:

`connection.updated`

event.

The connections screen therefore refreshes through the existing SSE contract.

## Browser polling reduction

Before P1.20 the connections page called `/sync` every 8 seconds for:

- CONNECTING;
- CONNECTED;
- DISCONNECTED.

After P1.20, fast polling remains only while a connection is `CONNECTING`, where
QR onboarding benefits from quick feedback.

Stable connections are monitored centrally by the backend.

## API

Company-scoped summary:

`GET /api/v1/whatsapp/health`

Requires:

`whatsapp.read`

The normal connections list also returns the persisted health fields.

## Readiness

Evolution intentionally remains outside `/health/ready`.

An Evolution outage must not remove the whole Wapp API from service. Contacts,
ticket history, administration, diagnostics and other non-provider operations
remain available.

The connection health view is the operational signal for provider degradation.

## Migration

P1.20 adds a Prisma migration:

`20260828123000_evolution_health_monitor`
