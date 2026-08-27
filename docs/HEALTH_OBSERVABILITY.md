# Health and request observability

P1.15 separates process liveness from dependency readiness and improves error
correlation.

## Liveness

`GET /health/live`

This endpoint answers whether the API process is alive.

It does not contact MySQL or Redis.

Use it for process/container restart decisions.

Expected status:

`200`

## Readiness

`GET /health/ready`

Readiness checks:

- MySQL with a real `SELECT 1`;
- Redis/realtime when `REDIS_URL` is configured.

A dependency failure returns HTTP `503`.

Use this endpoint for load balancer or orchestrator traffic admission.

Example:

```json
{
  "ready": true,
  "status": "ready",
  "checks": {
    "database": {
      "status": "ok",
      "latencyMs": 2
    },
    "redis": {
      "required": true,
      "configured": true,
      "ready": true,
      "mode": "redis",
      "status": "ok"
    }
  }
}
```

## Detailed health

`GET /health`

This remains backward-compatible as the human/monitoring diagnostic endpoint.

It reports:

- status (`ok` or `degraded`);
- Node version;
- process id;
- uptime;
- RSS/heap memory;
- database readiness and latency;
- Redis/realtime state.

The detailed endpoint returns HTTP 200 while the API process itself can answer.
Use `/health/ready`, not `/health`, for traffic admission.

## Request correlation

Every API response receives:

`X-Request-Id`

Fastify already assigns the underlying request id.

Error payloads now also expose:

```json
{
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "Erro interno do servidor.",
    "requestId": "req-123"
  }
}
```

This identifier can be matched with the API log entry for the same request.

No token, password, cookie or secret is included in the request id.

## Evolution API

Evolution is intentionally not a readiness dependency.

A WhatsApp-provider outage should degrade messaging functionality, but it should
not remove the Wapp API from the load balancer and make contacts, history,
administration or diagnostics unavailable.

Provider-specific monitoring belongs in integration health/alerts.

## Migration

P1.15 requires no Prisma migration.
