# Redis distributed realtime

P1.14 moves Wapp's realtime transport from a process-local EventEmitter to
Redis Pub/Sub while keeping the existing authenticated SSE browser contract.

## Browser contract

The web application continues to connect to:

`GET /api/v1/realtime/events`

No frontend event API changes are required.

## Transport

When `REDIS_URL` is configured and Redis is healthy:

```text
API replica A ── publish ──┐
                           │
                      Redis Pub/Sub
                           │
API replica B ── subscribe ┤
API replica C ── subscribe ┘
          │
          └── local EventEmitter -> SSE clients on that replica
```

Every API replica subscribes to `wapp:realtime:*`.

A published company event therefore reaches SSE clients connected to any API
replica.

## Local fallback

If Redis is missing or temporarily unavailable, Wapp falls back to the local
EventEmitter.

This keeps a single API process usable during local development or a transient
Redis outage.

The fallback cannot distribute events between multiple replicas. Production
multi-replica deployments must treat Redis availability as required
infrastructure.

## Presence

Presence is also distributed.

Each SSE connection receives a unique connection ID and stores a Redis sorted
set member with a 75-second expiry timestamp.

The SSE heartbeat refreshes the entry every 25 seconds.

This preserves multiple-tabs semantics:

- opening a second tab does not emit a second logical online transition;
- closing one of multiple tabs does not mark the membership offline;
- the final connection closing marks the membership offline.

A distributed sweep removes expired connection entries left by crashed API
processes or abruptly disconnected clients.

The sweep uses a Redis lock so only one API replica performs expiry cleanup at
a time.

## Health

`GET /health` now includes:

```json
{
  "realtime": {
    "mode": "redis",
    "redisConfigured": true,
    "redisReady": true
  }
}
```

`mode=local` means the process is currently using the fallback.

## Shutdown

Fastify's `onClose` hook closes Redis subscriber/publisher clients before
disconnecting Prisma.

## Migration

P1.14 requires no Prisma migration.
