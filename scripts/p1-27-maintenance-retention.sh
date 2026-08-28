#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.27] Installing automatic maintenance and retention..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/jobs/job-runtime.ts" \
  "apps/api/src/jobs/job-redis.ts" \
  "apps/api/src/worker.ts" \
  "apps/api/package.json" \
  "package.json"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -q "model AuditLog" apps/api/prisma/schema.prisma; then
  echo "ERROR: P1.26 must be installed before P1.27."
  exit 1
fi

mkdir -p \
  apps/api/src/jobs \
  apps/api/src/scripts \
  apps/api/prisma/migrations/20260828163000_maintenance_runs \
  docs

node <<'NODE'
const fs=require("node:fs");
const path="apps/api/prisma/schema.prisma";
let content=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");

if(!content.includes("model MaintenanceRun {")){
  content += `

model MaintenanceRun {
  id         String   @id @default(uuid()) @db.Char(36)
  source     String   @db.VarChar(20)
  status     String   @db.VarChar(20)
  result     Json?
  error      String?  @db.Text
  startedAt  DateTime
  finishedAt DateTime?
  createdAt  DateTime @default(now())

  @@index([status, createdAt])
  @@index([createdAt])
}
`;
}

fs.writeFileSync(path,content);
NODE

cat > apps/api/prisma/migrations/20260828163000_maintenance_runs/migration.sql <<'EOF'
CREATE TABLE `MaintenanceRun` (
  `id` CHAR(36) NOT NULL,
  `source` VARCHAR(20) NOT NULL,
  `status` VARCHAR(20) NOT NULL,
  `result` JSON NULL,
  `error` TEXT NULL,
  `startedAt` DATETIME(3) NOT NULL,
  `finishedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  INDEX `MaintenanceRun_status_createdAt_idx` (`status`, `createdAt`),
  INDEX `MaintenanceRun_createdAt_idx` (`createdAt`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

cat > apps/api/src/jobs/maintenance.policy.ts <<'EOF'
export function retentionCutoff(
  now: Date,
  retentionDays: number
) {
  return new Date(
    now.getTime() -
      retentionDays *
        24 *
        60 *
        60 *
        1_000
  );
}

export function staleMediaCutoff(
  now: Date,
  staleMinutes: number
) {
  return new Date(
    now.getTime() -
      staleMinutes *
        60 *
        1_000
  );
}
EOF

cat > apps/api/src/jobs/maintenance.policy.test.ts <<'EOF'
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  retentionCutoff,
  staleMediaCutoff
} from "./maintenance.policy.js";

test(
  "maintenance retention cutoffs are deterministic",
  () => {
    const now =
      new Date(
        "2026-08-28T12:00:00.000Z"
      );

    assert.equal(
      retentionCutoff(
        now,
        30
      ).toISOString(),
      "2026-07-29T12:00:00.000Z"
    );

    assert.equal(
      staleMediaCutoff(
        now,
        30
      ).toISOString(),
      "2026-08-28T11:30:00.000Z"
    );
  }
);
EOF

cat > apps/api/src/jobs/maintenance.service.ts <<'EOF'
import type {
  Prisma
} from "../generated/prisma/client.js";

import { env } from "../config/env.js";
import { prisma } from "../lib/database.js";
import { toPrismaJson } from "../lib/prisma-json.js";
import {
  retentionCutoff,
  staleMediaCutoff
} from "./maintenance.policy.js";

export type MaintenanceSource =
  | "SCHEDULED"
  | "CLI";

export async function runMaintenance(
  source: MaintenanceSource
) {
  const startedAt =
    new Date();

  const run =
    await prisma.maintenanceRun.create({
      data: {
        source,
        status:
          "RUNNING",
        startedAt
      }
    });

  try {
    const sessionCutoff =
      retentionCutoff(
        startedAt,
        env
          .SESSION_RETENTION_DAYS
      );

    const mediaCutoff =
      staleMediaCutoff(
        startedAt,
        env
          .MAINTENANCE_STALE_MEDIA_MINUTES
      );

    const [
      deletedSessions,
      stalePendingMedia,
      failedMedia,
      failedDelivery,
      evolutionDown
    ] =
      await prisma.$transaction([
        prisma.session.deleteMany({
          where: {
            OR: [
              {
                expiresAt: {
                  lt:
                    sessionCutoff
                }
              },
              {
                revokedAt: {
                  not: null,
                  lt:
                    sessionCutoff
                }
              }
            ]
          }
        }),
        prisma.message.count({
          where: {
            mediaStatus:
              "PENDING",
            createdAt: {
              lt:
                mediaCutoff
            }
          }
        }),
        prisma.message.count({
          where: {
            mediaStatus:
              "FAILED"
          }
        }),
        prisma.message.count({
          where: {
            direction:
              "OUTBOUND",
            deliveryStatus:
              "FAILED",
            timestamp: {
              gte:
                retentionCutoff(
                  startedAt,
                  1
                )
            }
          }
        }),
        prisma.whatsAppConnection.count({
          where: {
            healthStatus:
              "DOWN"
          }
        })
      ]);

    const result = {
      deletedSessions:
        deletedSessions.count,
      diagnostics: {
        stalePendingMedia,
        failedMedia,
        failedDeliveryLast24h:
          failedDelivery,
        evolutionDown
      },
      policy: {
        sessionRetentionDays:
          env
            .SESSION_RETENTION_DAYS,
        staleMediaMinutes:
          env
            .MAINTENANCE_STALE_MEDIA_MINUTES
      }
    };

    const finishedAt =
      new Date();

    await prisma.maintenanceRun.update({
      where: {
        id:
          run.id
      },
      data: {
        status:
          "SUCCESS",
        result:
          toPrismaJson(
            result
          ) as Prisma.InputJsonValue,
        finishedAt
      }
    });

    console.info(
      "[maintenance] completed",
      result
    );

    return result;
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : "Unknown maintenance error.";

    await prisma.maintenanceRun.update({
      where: {
        id:
          run.id
      },
      data: {
        status:
          "FAILED",
        error:
          message.slice(
            0,
            4_000
          ),
        finishedAt:
          new Date()
      }
    });

    throw error;
  }
}

export async function getMaintenanceStatus() {
  return prisma.maintenanceRun.findMany({
    orderBy: [
      {
        createdAt:
          "desc"
      },
      {
        id:
          "desc"
      }
    ],
    take: 20
  });
}
EOF

cat > apps/api/src/jobs/maintenance.queue.ts <<'EOF'
import {
  Queue
} from "bullmq";

import { env } from "../config/env.js";
import {
  jobProducerRedisOptions
} from "./job-redis.js";

export const MAINTENANCE_QUEUE_NAME =
  "wapp-maintenance";

export const MAINTENANCE_JOB_NAME =
  "housekeeping";

let queue:
  | Queue
  | null =
  null;

export function getMaintenanceQueue() {
  if (!queue) {
    queue =
      new Queue(
        MAINTENANCE_QUEUE_NAME,
        {
          connection:
            jobProducerRedisOptions()
        }
      );
  }

  return queue;
}

export async function ensureMaintenanceSchedule() {
  if (
    !env.REDIS_URL ||
    !env.MAINTENANCE_ENABLED
  ) {
    return;
  }

  const every =
    env
      .MAINTENANCE_INTERVAL_HOURS *
    60 *
    60 *
    1_000;

  await getMaintenanceQueue()
    .upsertJobScheduler(
      "wapp-housekeeping",
      {
        every
      },
      {
        name:
          MAINTENANCE_JOB_NAME,
        data: {}
      }
    );
}

export async function closeMaintenanceQueue() {
  const current =
    queue;

  queue =
    null;

  if (current) {
    await current.close();
  }
}
EOF

cat > apps/api/src/jobs/maintenance.worker.ts <<'EOF'
import {
  Worker
} from "bullmq";

import {
  jobWorkerRedisOptions
} from "./job-redis.js";
import {
  MAINTENANCE_JOB_NAME,
  MAINTENANCE_QUEUE_NAME
} from "./maintenance.queue.js";
import {
  runMaintenance
} from "./maintenance.service.js";

export function createMaintenanceWorker() {
  const worker =
    new Worker(
      MAINTENANCE_QUEUE_NAME,
      async job => {
        if (
          job.name !==
          MAINTENANCE_JOB_NAME
        ) {
          throw new Error(
            `Unknown maintenance job: ${job.name}`
          );
        }

        return runMaintenance(
          "SCHEDULED"
        );
      },
      {
        connection:
          jobWorkerRedisOptions(),
        concurrency: 1
      }
    );

  worker.on(
    "failed",
    (
      job,
      error
    ) => {
      console.error(
        "[maintenance] job failed",
        {
          jobId:
            job?.id,
          error:
            error.message
        }
      );
    }
  );

  return worker;
}
EOF

cat > apps/api/src/scripts/maintenance-run.ts <<'EOF'
import { prisma } from "../lib/database.js";
import { runMaintenance } from "../jobs/maintenance.service.js";

try {
  const result =
    await runMaintenance(
      "CLI"
    );

  console.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );
} catch (error) {
  console.error(
    "[maintenance] CLI run failed:",
    error instanceof Error
      ? error.message
      : error
  );

  process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
EOF

node <<'NODE'
const fs=require("node:fs");
const path="apps/api/src/config/env.ts";
let content=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");

if(!content.includes("MAINTENANCE_ENABLED:")){
  const anchor=`  JOBS_MEDIA_CAPTURE_ATTEMPTS: z.coerce
    .number()
    .int()
    .min(1)
    .max(20)
    .default(5),`;

  if(!content.includes(anchor)){
    throw new Error("jobs env anchor not found.");
  }

  content=content.replace(anchor,`${anchor}
  MAINTENANCE_ENABLED: booleanTrueFromEnv,
  MAINTENANCE_INTERVAL_HOURS: z.coerce
    .number()
    .int()
    .min(1)
    .max(168)
    .default(6),
  SESSION_RETENTION_DAYS: z.coerce
    .number()
    .int()
    .min(7)
    .max(365)
    .default(30),
  MAINTENANCE_STALE_MEDIA_MINUTES: z.coerce
    .number()
    .int()
    .min(5)
    .max(1_440)
    .default(30),`);
}

fs.writeFileSync(path,content);
NODE

if [[ -f "apps/api/.env.example" ]] &&
   ! grep -q '^MAINTENANCE_ENABLED=' apps/api/.env.example
then
  cat >> apps/api/.env.example <<'EOF'

MAINTENANCE_ENABLED=true
MAINTENANCE_INTERVAL_HOURS=6
SESSION_RETENTION_DAYS=30
MAINTENANCE_STALE_MEDIA_MINUTES=30
EOF
fi

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
import {
  closeMaintenanceQueue,
  ensureMaintenanceSchedule
} from "./maintenance.queue.js";
import {
  createMaintenanceWorker
} from "./maintenance.worker.js";

let embeddedWorkers:
  Worker[] = [];

export function startEmbeddedJobWorker() {
  if (
    !env.REDIS_URL ||
    !env.JOBS_EMBEDDED_WORKER ||
    embeddedWorkers.length >
      0
  ) {
    return;
  }

  embeddedWorkers = [
    createMediaCaptureWorker(),
    createMaintenanceWorker()
  ];

  void ensureMaintenanceSchedule()
    .catch(error => {
      console.error(
        "[maintenance] scheduler setup failed",
        error
      );
    });

  console.info(
    "[jobs] embedded workers started",
    {
      mediaConcurrency:
        env
          .JOBS_MEDIA_CAPTURE_CONCURRENCY,
      maintenance:
        env
          .MAINTENANCE_ENABLED
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
      embeddedWorkers.length >
      0,
    mediaConcurrency:
      env
        .JOBS_MEDIA_CAPTURE_CONCURRENCY,
    mediaAttempts:
      env
        .JOBS_MEDIA_CAPTURE_ATTEMPTS,
    maintenanceEnabled:
      env
        .MAINTENANCE_ENABLED,
    maintenanceIntervalHours:
      env
        .MAINTENANCE_INTERVAL_HOURS
  };
}

export async function closeJobRuntime() {
  const workers =
    embeddedWorkers;

  embeddedWorkers = [];

  await Promise.all(
    workers.map(
      worker =>
        worker.close()
    )
  );

  await Promise.all([
    closeMediaCaptureQueue(),
    closeMaintenanceQueue()
  ]);
}
EOF

cat > apps/api/src/worker.ts <<'EOF'
import { prisma } from "./lib/database.js";
import {
  closeMediaCaptureQueue
} from "./jobs/media-capture.queue.js";
import {
  createMediaCaptureWorker
} from "./jobs/media-capture.worker.js";
import {
  closeMaintenanceQueue,
  ensureMaintenanceSchedule
} from "./jobs/maintenance.queue.js";
import {
  createMaintenanceWorker
} from "./jobs/maintenance.worker.js";
import {
  closeRealtimeTransport
} from "./modules/realtime/realtime.bus.js";

const workers = [
  createMediaCaptureWorker(),
  createMaintenanceWorker()
];

await ensureMaintenanceSchedule();

console.info(
  "[jobs] Wapp workers started",
  {
    workers:
      workers.length
  }
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

  await Promise.all(
    workers.map(
      worker =>
        worker.close()
    )
  );

  await Promise.all([
    closeMediaCaptureQueue(),
    closeMaintenanceQueue()
  ]);

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

for (
  const worker
  of workers
) {
  worker.on(
    "error",
    error => {
      console.error(
        "[jobs] worker error",
        error
      );
    }
  );
}
EOF

node <<'NODE'
const fs=require("node:fs");

const apiPath="apps/api/package.json";
const api=JSON.parse(fs.readFileSync(apiPath,"utf8"));
api.scripts ??= {};
api.scripts["maintenance:run"]="tsx src/scripts/maintenance-run.ts";

const currentTest=api.scripts.test;
if(typeof currentTest==="string" && !currentTest.includes("maintenance.policy.test.ts")){
  api.scripts.test=`${currentTest} src/jobs/maintenance.policy.test.ts`;
}
fs.writeFileSync(apiPath,`${JSON.stringify(api,null,2)}\n`);

const rootPath="package.json";
const root=JSON.parse(fs.readFileSync(rootPath,"utf8"));
root.scripts ??= {};
root.scripts["maintenance:run"]="pnpm --filter @wapp/api maintenance:run";
fs.writeFileSync(rootPath,`${JSON.stringify(root,null,2)}\n`);
NODE

if [[ -f "infra/production/docker-compose.yml" ]] &&
   ! grep -q 'MAINTENANCE_ENABLED:' infra/production/docker-compose.yml
then
  node <<'NODE'
const fs=require("node:fs");
const path="infra/production/docker-compose.yml";
let c=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");
const anchor='  JOBS_MEDIA_CAPTURE_ATTEMPTS: ${JOBS_MEDIA_CAPTURE_ATTEMPTS:-5}';
if(!c.includes(anchor)) throw new Error("production jobs env anchor not found.");
c=c.replace(anchor,`${anchor}
  MAINTENANCE_ENABLED: \${MAINTENANCE_ENABLED:-true}
  MAINTENANCE_INTERVAL_HOURS: \${MAINTENANCE_INTERVAL_HOURS:-6}
  SESSION_RETENTION_DAYS: \${SESSION_RETENTION_DAYS:-30}
  MAINTENANCE_STALE_MEDIA_MINUTES: \${MAINTENANCE_STALE_MEDIA_MINUTES:-30}`);
fs.writeFileSync(path,c);
NODE
fi

if [[ -f "infra/production/.env.production.example" ]] &&
   ! grep -q '^MAINTENANCE_ENABLED=' infra/production/.env.production.example
then
  cat >> infra/production/.env.production.example <<'EOF'

MAINTENANCE_ENABLED=true
MAINTENANCE_INTERVAL_HOURS=6
SESSION_RETENTION_DAYS=30
MAINTENANCE_STALE_MEDIA_MINUTES=30
EOF
fi

cat > docs/MAINTENANCE_RETENTION.md <<'EOF'
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
EOF

echo "[P1.27] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.27] Unit tests..."
pnpm test

echo "[P1.27] Typechecking..."
pnpm typecheck

echo
echo "[P1.27] Maintenance installed."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
