# P1.28 Metrics and operational alerts

## Prometheus metrics

`GET /metrics`

The endpoint is disabled when `METRICS_TOKEN` is empty.

When configured, clients must send:

`Authorization: Bearer <METRICS_TOKEN>`

Metrics include:

- process/runtime defaults;
- HTTP request count and duration by normalized route/method/status;
- ticket counts by status;
- WhatsApp connection health totals;
- message media processing totals;
- failed outbound delivery in the last 24h;
- BullMQ media/maintenance queue state;
- last successful maintenance timestamp.

Company ids, contact ids, phone numbers and message bodies are never metric
labels.

## Operational alerts

`GET /api/v1/observability/alerts`

Permission: `observability.read`.

OWNER, ADMIN and SUPERVISOR can read it. AGENT cannot.

Alerts are company-scoped for Evolution/media/delivery data and expose no
message/contact payload.

Possible codes:

- `EVOLUTION_DOWN`;
- `WHATSAPP_DEGRADED`;
- `MEDIA_STALE_PENDING`;
- `MEDIA_FAILED`;
- `DELIVERY_FAILED`;
- `MAINTENANCE_FAILED`.

The endpoint is diagnostic. It does not auto-delete or auto-retry business
records.
