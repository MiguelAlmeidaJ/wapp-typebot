# P1.19 Durable background jobs

P1.19 replaces process-memory scheduling for inbound media capture with a
Redis-backed BullMQ queue.

## Why

Before P1.19:

```text
webhook -> message persisted -> setImmediate(capture media)
```

If the API process stopped after the message was committed but before the
callback completed, the callback disappeared with that process.

After P1.19:

```text
webhook
  -> message persisted
  -> Redis job
  -> BullMQ worker
  -> Evolution download
  -> media storage
  -> message READY
```

The job survives normal API restarts because queue state is stored in Redis.

## Retry policy

Media capture defaults:

- 5 attempts;
- exponential backoff;
- initial backoff 2 seconds;
- worker concurrency 4.

Environment:

```env
JOBS_MEDIA_CAPTURE_CONCURRENCY=4
JOBS_MEDIA_CAPTURE_ATTEMPTS=5
```

Every worker attempt calls the existing media capture service.

Transient download/storage errors are persisted as `FAILED` for visibility and
then thrown back to BullMQ so another scheduled attempt can occur. A new
attempt sets the message back to `PENDING`.

Permanent errors such as a missing original WhatsApp payload are not retried
indefinitely.

## Idempotency

The queue uses:

```text
media-<messageId>
```

as the BullMQ job id.

Repeated scheduling of the same stored message does not create parallel capture
jobs while the original job is retained.

Message/database idempotency remains the authoritative layer.

## Local development

Default:

```env
JOBS_EMBEDDED_WORKER=true
```

The API starts a BullMQ worker inside the API process. `pnpm dev` therefore
continues to work without opening another terminal.

This is still durable scheduling: jobs live in Redis rather than in an
in-process timer.

## Dedicated production worker

For independent worker scaling:

```env
JOBS_EMBEDDED_WORKER=false
```

Run the API normally, and run one or more worker processes separately:

Development:

```bash
pnpm --filter @wapp/api worker:dev
```

Built production:

```bash
pnpm --filter @wapp/api worker:start
```

Multiple BullMQ workers safely compete for jobs from the same queue.

Do not run a dedicated worker with the embedded worker enabled unless additional
worker concurrency is intentional.

## Redis failure

Redis is required for durable queue semantics.

If enqueue fails, media capture falls back to the pre-P1.19 direct behavior so
message ingestion itself is not lost.

In production, Redis should remain required infrastructure; P1.15 readiness
already reports Redis degradation.

## Shutdown

API shutdown closes:

1. embedded BullMQ worker;
2. producer queue;
3. realtime transport;
4. remaining application resources.

The standalone worker handles SIGINT/SIGTERM and closes BullMQ, realtime and
Prisma cleanly.

## Migration

P1.19 requires no Prisma migration.
