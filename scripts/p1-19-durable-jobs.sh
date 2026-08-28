#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.19] Building durable Redis job queue..."

for required in \
  "apps/api/package.json" \
  "apps/api/.env.example" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/media/media-capture.service.ts"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/jobs \
  docs

# ---------------------------------------------------------------------------
# BullMQ
# ---------------------------------------------------------------------------

if ! node -e '
const pkg = require("./apps/api/package.json");
process.exit(pkg.dependencies?.bullmq ? 0 : 1);
'; then
  echo "[P1.19] Installing BullMQ..."
  pnpm --filter @wapp/api add bullmq@^5.0.0
else
  echo "[P1.19] BullMQ already installed."
fi

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/config/env.ts";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "const booleanTrueFromEnv"
  )
) {
  const anchor =
    `const booleanFromEnv = z
  .enum(["true", "false"])
  .default("false")
  .transform(value => value === "true");`;

  if (!content.includes(anchor)) {
    throw new Error(
      "booleanFromEnv anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

const booleanTrueFromEnv = z
  .enum(["true", "false"])
  .default("true")
  .transform(value => value === "true");`
    );
}

if (
  !content.includes(
    "JOBS_EMBEDDED_WORKER:"
  )
) {
  const anchor =
    '  REDIS_URL: z.string().min(1).optional(),';

  if (!content.includes(anchor)) {
    throw new Error(
      "REDIS_URL env anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  JOBS_EMBEDDED_WORKER: booleanTrueFromEnv,
  JOBS_MEDIA_CAPTURE_CONCURRENCY: z.coerce
    .number()
    .int()
    .positive()
    .max(32)
    .default(4),
  JOBS_MEDIA_CAPTURE_ATTEMPTS: z.coerce
    .number()
    .int()
    .min(1)
    .max(20)
    .default(5),`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Job queue environment installed."
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/.env.example";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "JOBS_EMBEDDED_WORKER="
  )
) {
  const anchor =
    "REDIS_URL=redis://127.0.0.1:6379";

  if (!content.includes(anchor)) {
    throw new Error(
      "REDIS_URL .env.example anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

# Durable background jobs
# true keeps local development zero-config.
# In production you may set false and run a dedicated worker process.
JOBS_EMBEDDED_WORKER=true
JOBS_MEDIA_CAPTURE_CONCURRENCY=4
JOBS_MEDIA_CAPTURE_ATTEMPTS=5`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Redis options for BullMQ
# ---------------------------------------------------------------------------

cat > apps/api/src/jobs/job-redis.ts <<'EOF'
import type { RedisOptions } from "ioredis";

import { env } from "../config/env.js";

function redisUrl() {
  if (!env.REDIS_URL) {
    throw new Error(
      "REDIS_URL is required for durable jobs."
    );
  }

  return new URL(
    env.REDIS_URL
  );
}

function baseOptions():
  RedisOptions {
  const url =
    redisUrl();

  const pathname =
    url.pathname
      .replace(
        /^\/+/,
        ""
      );

  const db =
    pathname
      ? Number(
          pathname
        )
      : 0;

  if (
    !Number.isInteger(
      db
    ) ||
    db < 0
  ) {
    throw new Error(
      "Invalid Redis database in REDIS_URL."
    );
  }

  return {
    host:
      url.hostname,
    port:
      Number(
        url.port ||
        "6379"
      ),
    username:
      url.username
        ? decodeURIComponent(
            url.username
          )
        : undefined,
    password:
      url.password
        ? decodeURIComponent(
            url.password
          )
        : undefined,
    db,
    ...(url.protocol ===
      "rediss:"
      ? {
          tls: {}
        }
      : {})
  };
}

export function jobProducerRedisOptions():
  RedisOptions {
  return {
    ...baseOptions(),
    maxRetriesPerRequest:
      1,
    enableReadyCheck:
      true
  };
}

export function jobWorkerRedisOptions():
  RedisOptions {
  return {
    ...baseOptions(),
    /*
     * BullMQ workers require null so blocking commands can survive normal
     * Redis reconnects without ioredis aborting the request.
     */
    maxRetriesPerRequest:
      null,
    enableReadyCheck:
      true
  };
}
EOF

# ---------------------------------------------------------------------------
# Queue
# ---------------------------------------------------------------------------

cat > apps/api/src/jobs/media-capture.queue.ts <<'EOF'
import {
  Queue,
  type JobsOptions
} from "bullmq";

import { env } from "../config/env.js";
import {
  jobProducerRedisOptions
} from "./job-redis.js";

export const MEDIA_CAPTURE_QUEUE =
  "wapp-media-capture";

export const MEDIA_CAPTURE_JOB =
  "capture-message-media";

export interface MediaCaptureJobData {
  messageId: string;
}

let queue:
  | Queue<
      MediaCaptureJobData
    >
  | null =
  null;

function getQueue() {
  if (!env.REDIS_URL) {
    throw new Error(
      "Redis is not configured for durable media jobs."
    );
  }

  if (queue) {
    return queue;
  }

  queue =
    new Queue<
      MediaCaptureJobData
    >(
      MEDIA_CAPTURE_QUEUE,
      {
        connection:
          jobProducerRedisOptions(),
        defaultJobOptions: {
          attempts:
            env
              .JOBS_MEDIA_CAPTURE_ATTEMPTS,
          backoff: {
            type:
              "exponential",
            delay:
              2_000
          },
          removeOnComplete: {
            age:
              60 * 60,
            count:
              2_000
          },
          removeOnFail: {
            age:
              7 * 24 * 60 * 60,
            count:
              5_000
          }
        }
      }
    );

  return queue;
}

function jobOptions(
  messageId: string
): JobsOptions {
  return {
    /*
     * BullMQ custom ids make webhook duplication / repeated scheduling
     * idempotent while the job is still retained by the queue.
     */
    jobId:
      `media-${messageId}`
  };
}

export async function enqueueMediaCaptureJob(
  messageId: string
) {
  const target =
    getQueue();

  const jobId =
    `media-${messageId}`;

  const existing =
    await target.getJob(
      jobId
    );

  if (existing) {
    const state =
      await existing
        .getState();

    /*
     * A failed job already exhausted its automatic retries. Keep it for
     * diagnostics; the existing manual retry endpoint remains available.
     */
    return {
      queued: false,
      jobId:
        existing.id ??
        jobId,
      state
    };
  }

  const job =
    await target.add(
      MEDIA_CAPTURE_JOB,
      {
        messageId
      },
      jobOptions(
        messageId
      )
    );

  return {
    queued: true,
    jobId:
      job.id ??
      jobId,
    state:
      "waiting"
  };
}

export async function getMediaCaptureJobCounts() {
  if (!env.REDIS_URL) {
    return {
      configured:
        false,
      waiting: 0,
      active: 0,
      delayed: 0,
      failed: 0
    };
  }

  const counts =
    await getQueue()
      .getJobCounts(
        "waiting",
        "active",
        "delayed",
        "failed"
      );

  return {
    configured:
      true,
    waiting:
      counts.waiting ??
      0,
    active:
      counts.active ??
      0,
    delayed:
      counts.delayed ??
      0,
    failed:
      counts.failed ??
      0
  };
}

export async function closeMediaCaptureQueue() {
  const current =
    queue;

  queue =
    null;

  if (current) {
    await current.close();
  }
}
EOF

# ---------------------------------------------------------------------------
# Worker
# ---------------------------------------------------------------------------

cat > apps/api/src/jobs/media-capture.worker.ts <<'EOF'
import {
  Worker,
  type Job
} from "bullmq";

import { env } from "../config/env.js";
import {
  captureMessageMedia
} from "../modules/media/media-capture.service.js";
import {
  MEDIA_CAPTURE_JOB,
  MEDIA_CAPTURE_QUEUE,
  type MediaCaptureJobData
} from "./media-capture.queue.js";
import {
  jobWorkerRedisOptions
} from "./job-redis.js";

export function createMediaCaptureWorker() {
  if (!env.REDIS_URL) {
    throw new Error(
      "REDIS_URL is required to start the media worker."
    );
  }

  const worker =
    new Worker<
      MediaCaptureJobData
    >(
      MEDIA_CAPTURE_QUEUE,
      async (
        job:
          Job<
            MediaCaptureJobData
          >
      ) => {
        if (
          job.name !==
          MEDIA_CAPTURE_JOB
        ) {
          throw new Error(
            `Unsupported media job: ${job.name}`
          );
        }

        await captureMessageMedia(
          job.data.messageId,
          {
            throwOnFailure:
              true
          }
        );
      },
      {
        connection:
          jobWorkerRedisOptions(),
        concurrency:
          env
            .JOBS_MEDIA_CAPTURE_CONCURRENCY
      }
    );

  worker.on(
    "error",
    error => {
      console.error(
        "[jobs:media] worker error",
        error
      );
    }
  );

  worker.on(
    "failed",
    (
      job,
      error
    ) => {
      console.warn(
        "[jobs:media] job attempt failed",
        {
          jobId:
            job?.id,
          messageId:
            job?.data
              ?.messageId,
          attemptsMade:
            job?.attemptsMade,
          error:
            error.message
        }
      );
    }
  );

  return worker;
}
EOF

# ---------------------------------------------------------------------------
# Runtime: embedded worker for zero-config dev + standalone support
# ---------------------------------------------------------------------------

cat > apps/api/src/jobs/job-runtime.ts <<'EOF'
import type {
  Worker
} from "bullmq";

import { env } from "../config/env.js";
import {
  closeMediaCaptureQueue
} from "./media-capture.queue.js";
import {
  createMediaCaptureWorker
} from "./media-capture.worker.js";

let embeddedWorker:
  | Worker
  | null =
  null;

export function startEmbeddedJobWorker() {
  if (
    !env.REDIS_URL ||
    !env.JOBS_EMBEDDED_WORKER ||
    embeddedWorker
  ) {
    return;
  }

  embeddedWorker =
    createMediaCaptureWorker();

  console.info(
    "[jobs] embedded media worker started",
    {
      concurrency:
        env
          .JOBS_MEDIA_CAPTURE_CONCURRENCY
    }
  );
}

export function getJobRuntimeStatus() {
  return {
    redisConfigured:
      Boolean(
        env.REDIS_URL
      ),
    embeddedWorkerEnabled:
      env
        .JOBS_EMBEDDED_WORKER,
    embeddedWorkerRunning:
      Boolean(
        embeddedWorker
      ),
    mediaConcurrency:
      env
        .JOBS_MEDIA_CAPTURE_CONCURRENCY,
    mediaAttempts:
      env
        .JOBS_MEDIA_CAPTURE_ATTEMPTS
  };
}

export async function closeJobRuntime() {
  const worker =
    embeddedWorker;

  embeddedWorker =
    null;

  if (worker) {
    await worker.close();
  }

  await closeMediaCaptureQueue();
}
EOF

# ---------------------------------------------------------------------------
# Standalone worker entrypoint
# ---------------------------------------------------------------------------

cat > apps/api/src/worker.ts <<'EOF'
import { prisma } from "./lib/database.js";
import {
  closeMediaCaptureQueue
} from "./jobs/media-capture.queue.js";
import {
  createMediaCaptureWorker
} from "./jobs/media-capture.worker.js";
import {
  closeRealtimeTransport
} from "./modules/realtime/realtime.bus.js";

const worker =
  createMediaCaptureWorker();

console.info(
  "[jobs] Wapp media worker started"
);

let shuttingDown =
  false;

async function shutdown(
  signal: string
) {
  if (shuttingDown) {
    return;
  }

  shuttingDown =
    true;

  console.info(
    `[jobs] shutting down (${signal})`
  );

  await worker.close();
  await closeMediaCaptureQueue();
  await closeRealtimeTransport();
  await prisma.$disconnect();

  process.exit(0);
}

process.on(
  "SIGINT",
  () => {
    void shutdown(
      "SIGINT"
    );
  }
);

process.on(
  "SIGTERM",
  () => {
    void shutdown(
      "SIGTERM"
    );
  }
);

worker.on(
  "error",
  error => {
    console.error(
      "[jobs] worker error",
      error
    );
  }
);
EOF

# ---------------------------------------------------------------------------
# Capture service: queue scheduling + retry-aware errors
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/media/media-capture.service.ts";

let content =
  fs.readFileSync(path, "utf8");

content =
  content.replace(
    'import { setImmediate } from "node:timers";\n\n',
    ""
  );

const queueImport =
  'import { enqueueMediaCaptureJob } from "../../jobs/media-capture.queue.js";';

if (
  !content.includes(
    queueImport
  )
) {
  const anchor =
    'import { AppError } from "../../errors/app-error.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "media capture import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${queueImport}`
    );
}

const signatureOld =
  `export async function captureMessageMedia(
  messageId: string
) {`;

const signatureNew =
  `export async function captureMessageMedia(
  messageId: string,
  options: {
    throwOnFailure?: boolean;
  } = {}
) {`;

if (
  content.includes(
    signatureOld
  )
) {
  content =
    content.replace(
      signatureOld,
      signatureNew
    );
} else if (
  !content.includes(
    "throwOnFailure?: boolean"
  )
) {
  throw new Error(
    "captureMessageMedia signature anchor not found."
  );
}

const catchReturn =
  `    return failed;
  }
}

export function scheduleMessageMediaCapture(
  messageId: string
) {
  setImmediate(() => {
    void captureMessageMedia(
      messageId
    ).catch(() => {
      // The capture service persists its own failure state.
    });
  });
}`;

const catchReturnReplacement =
  `    if (
      options.throwOnFailure
    ) {
      throw (
        error instanceof Error
          ? error
          : new Error(
              messageText
            )
      );
    }

    return failed;
  }
}

export function scheduleMessageMediaCapture(
  messageId: string
) {
  void enqueueMediaCaptureJob(
    messageId
  ).catch(error => {
    /*
     * Redis queue failures must not lose the media workflow. P1.15 readiness
     * will expose Redis degradation in production; locally/transiently we
     * preserve the previous direct capture behavior.
     */
    console.warn(
      "[jobs:media] enqueue failed; using direct fallback",
      error instanceof Error
        ? error.message
        : error
    );

    void captureMessageMedia(
      messageId
    ).catch(() => {
      // The capture service persists its own failure state.
    });
  });
}`;

if (
  content.includes(
    catchReturn
  )
) {
  content =
    content.replace(
      catchReturn,
      catchReturnReplacement
    );
} else if (
  !content.includes(
    "enqueue failed; using direct fallback"
  )
) {
  throw new Error(
    "scheduleMessageMediaCapture block not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Media capture now schedules durable jobs with direct fallback."
);
NODE

# ---------------------------------------------------------------------------
# App lifecycle
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/app.ts";

let content =
  fs.readFileSync(path, "utf8");

const runtimeImport =
  `import {
  closeJobRuntime,
  startEmbeddedJobWorker
} from "./jobs/job-runtime.js";`;

if (
  !content.includes(
    "startEmbeddedJobWorker"
  )
) {
  const anchor =
    'import { env } from "./config/env.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "app env import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${runtimeImport}`
    );
}

if (
  !content.includes(
    "await closeJobRuntime();"
  )
) {
  const marker =
    `  app.addHook("onClose", async () => {`;

  if (!content.includes(marker)) {
    throw new Error(
      "app onClose anchor not found."
    );
  }

  content =
    content.replace(
      marker,
      `${marker}
    await closeJobRuntime();`
    );
}

if (
  !content.includes(
    "startEmbeddedJobWorker();"
  )
) {
  const anchor =
    `  return app;`;

  const index =
    content.lastIndexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "app return anchor not found."
    );
  }

  content =
    content.slice(
      0,
      index
    ) +
    `  startEmbeddedJobWorker();

` +
    content.slice(
      index
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Job worker lifecycle integrated with Fastify."
);
NODE

# ---------------------------------------------------------------------------
# Package scripts
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

pkg.scripts ??= {};

pkg.scripts["worker:dev"] =
  "tsx watch src/worker.ts";

pkg.scripts["worker:start"] =
  "node dist/worker.js";

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);

console.log(
  "Standalone worker scripts registered."
);
NODE

# ---------------------------------------------------------------------------
# Optional detailed-health status
# ---------------------------------------------------------------------------

if [[ -f "apps/api/src/modules/health/health.service.ts" ]]; then
  node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/health/health.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  );

const importLine =
  'import { getJobRuntimeStatus } from "../../jobs/job-runtime.js";';

if (
  !content.includes(
    importLine
  )
) {
  const firstImport =
    content.indexOf(
      "import "
    );

  if (firstImport < 0) {
    throw new Error(
      "health import anchor not found."
    );
  }

  content =
    content.slice(
      0,
      firstImport
    ) +
    `${importLine}
` +
    content.slice(
      firstImport
    );
}

if (
  !content.includes(
    "jobRuntime:"
  )
) {
  const timestampAnchor =
    `    timestamp:
      new Date()
        .toISOString()`;

  const last =
    content.lastIndexOf(
      timestampAnchor
    );

  if (last >= 0) {
    content =
      content.slice(
        0,
        last
      ) +
      `    jobRuntime:
      getJobRuntimeStatus(),
` +
      content.slice(
        last
      );
  } else {
    console.warn(
      "[P1.19] health details anchor not found; skipped jobRuntime status."
    );
  }
}

fs.writeFileSync(
  path,
  content
);
NODE
fi

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/DURABLE_JOBS.md <<'EOF'
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
EOF

echo "[P1.19] Checking worker source syntax through TypeScript..."
pnpm --filter @wapp/api typecheck

echo "[P1.19] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.19] Durable media jobs installed."
echo "No Prisma migration is required."
echo
echo "Keep locally:"
echo "  JOBS_EMBEDDED_WORKER=true"
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Validation:"
echo "  1. receive an image/audio/document"
echo "  2. confirm PENDING -> READY"
echo "  3. restart API and repeat"
echo "  4. confirm Redis remains healthy in /health/ready"
