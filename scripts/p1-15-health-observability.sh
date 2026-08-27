#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.15] Building health, readiness and request observability..."

for required in \
  "apps/api/src/app.ts" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/lib/database.ts" \
  "apps/api/src/modules/realtime/realtime.bus.ts"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/health \
  docs

# ---------------------------------------------------------------------------
# Health service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/health/health.service.ts <<'EOF'
import { env } from "../../config/env.js";
import { prisma } from "../../lib/database.js";
import { getRealtimeTransportStatus } from "../realtime/realtime.bus.js";

interface ProbeResult {
  ok: boolean;
  latencyMs: number;
  error?: string;
}

async function timedProbe(
  probe: () => Promise<void>
): Promise<ProbeResult> {
  const startedAt =
    performance.now();

  try {
    await probe();

    return {
      ok: true,
      latencyMs:
        Math.max(
          0,
          Math.round(
            performance.now() -
            startedAt
          )
        )
    };
  } catch (error) {
    return {
      ok: false,
      latencyMs:
        Math.max(
          0,
          Math.round(
            performance.now() -
            startedAt
          )
        ),
      error:
        error instanceof Error
          ? error.message
          : "unknown_error"
    };
  }
}

export function getLiveness() {
  return {
    status: "ok" as const,
    service: "wapp-api",
    uptimeSeconds:
      Math.floor(
        process.uptime()
      ),
    timestamp:
      new Date()
        .toISOString()
  };
}

export async function getReadiness() {
  const database =
    await timedProbe(
      async () => {
        await prisma.$queryRaw`SELECT 1`;
      }
    );

  const realtime =
    getRealtimeTransportStatus();

  /*
   * If Redis is configured, readiness requires it.
   *
   * The EventEmitter fallback remains useful for local development and
   * transient runtime behavior, but an instance advertising itself as
   * "ready" should not silently join a multi-replica production pool while
   * disconnected from the distributed bus.
   */
  const redisRequired =
    Boolean(
      env.REDIS_URL
    );

  const redisOk =
    !redisRequired ||
    realtime.redisReady;

  const ready =
    database.ok &&
    redisOk;

  return {
    ready,
    status:
      ready
        ? "ready"
        : "not_ready",
    checks: {
      database: {
        status:
          database.ok
            ? "ok"
            : "error",
        latencyMs:
          database.latencyMs,
        ...(database.error
          ? {
              error:
                database.error
            }
          : {})
      },
      redis: {
        required:
          redisRequired,
        configured:
          realtime.redisConfigured,
        ready:
          realtime.redisReady,
        mode:
          realtime.mode,
        status:
          redisOk
            ? "ok"
            : "error"
      }
    },
    timestamp:
      new Date()
        .toISOString()
  };
}

export async function getHealthDetails() {
  const readiness =
    await getReadiness();

  const memory =
    process.memoryUsage();

  return {
    status:
      readiness.ready
        ? "ok"
        : "degraded",
    service:
      "wapp-api",
    environment:
      env.NODE_ENV,
    pid:
      process.pid,
    node:
      process.version,
    uptimeSeconds:
      Math.floor(
        process.uptime()
      ),
    memory: {
      rssMb:
        Math.round(
          memory.rss /
          1024 /
          1024
        ),
      heapUsedMb:
        Math.round(
          memory.heapUsed /
          1024 /
          1024
        ),
      heapTotalMb:
        Math.round(
          memory.heapTotal /
          1024 /
          1024
        )
    },
    readiness: {
      ready:
        readiness.ready,
      checks:
        readiness.checks
    },
    timestamp:
      new Date()
        .toISOString()
  };
}
EOF

# ---------------------------------------------------------------------------
# Health routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/health/health.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";

import {
  getHealthDetails,
  getLiveness,
  getReadiness
} from "./health.service.js";

export async function healthRoutes(
  app: FastifyInstance
) {
  app.get(
    "/health/live",
    async () =>
      getLiveness()
  );

  app.get(
    "/health/ready",
    async (
      _request,
      reply
    ) => {
      const readiness =
        await getReadiness();

      return reply
        .status(
          readiness.ready
            ? 200
            : 503
        )
        .send(
          readiness
        );
    }
  );

  /*
   * Backward-compatible detailed endpoint.
   *
   * /health intentionally remains diagnostic and returns 200 while the
   * process itself can answer HTTP. Load balancers/orchestrators should use
   * /health/ready for admission decisions.
   */
  app.get(
    "/health",
    async () =>
      getHealthDetails()
  );
}
EOF

# ---------------------------------------------------------------------------
# app.ts
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/app.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { healthRoutes } from "./modules/health/health.routes.js";';

if (!content.includes(importLine)) {
  const candidates = [
    'import { realtimeRoutes } from "./modules/realtime/realtime.routes.js";',
    'import { authRoutes } from "./modules/auth/auth.routes.js";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find app.ts health import anchor."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

/*
 * Remove the previous inline /health route. It may be P0's simple database
 * probe or P1.14's extended realtime version, so match the whole route by its
 * stable boundaries instead of exact body text.
 */
const healthStart =
  content.indexOf(
    '  app.get("/health", async () => {'
  );

if (healthStart >= 0) {
  const nextApiRoute =
    content.indexOf(
      '  app.get("/api/v1"',
      healthStart
    );

  if (nextApiRoute < 0) {
    throw new Error(
      "Could not locate /api/v1 after legacy /health route."
    );
  }

  content =
    content.slice(
      0,
      healthStart
    ) +
    content.slice(
      nextApiRoute
    );
}

if (
  !content.includes(
    "await app.register(healthRoutes);"
  )
) {
  const candidates = [
    "  await app.register(authRoutes);",
    "  await app.register(realtimeRoutes);"
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find route registration anchor."
    );
  }

  content =
    content.replace(
      anchor,
      `  await app.register(healthRoutes);
${anchor}`
    );
}

/*
 * Every error response gets Fastify's request id. This is safe to expose and
 * allows support/debugging to correlate UI errors with structured API logs.
 */
if (
  !content.includes(
    "requestId: request.id"
  )
) {
  content =
    content.replace(
      `          details: error.details`,
      `          details: error.details,
          requestId: request.id`
    );

  content =
    content.replace(
      `          details: error.flatten().fieldErrors`,
      `          details: error.flatten().fieldErrors,
          requestId: request.id`
    );

  content =
    content.replace(
      `        message: "Erro interno do servidor."`,
      `        message: "Erro interno do servidor.",
        requestId: request.id`
    );
}

/*
 * Include request id in response headers. Fastify already generates request.id;
 * this makes it visible to browsers, reverse proxies and support tools.
 */
if (
  !content.includes(
    '"X-Request-Id"'
  )
) {
  const marker =
    `  app.setErrorHandler((error, request, reply) => {`;

  if (!content.includes(marker)) {
    throw new Error(
      "Fastify error handler anchor not found."
    );
  }

  const hook = `  app.addHook(
    "onSend",
    async (
      request,
      reply,
      payload
    ) => {
      reply.header(
        "X-Request-Id",
        request.id
      );

      return payload;
    }
  );

`;

  content =
    content.replace(
      marker,
      `${hook}${marker}`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Health routes and request observability registered."
);
NODE

# ---------------------------------------------------------------------------
# CORS: allow browser/support tooling to read X-Request-Id
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/app.ts";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    'exposedHeaders: ["X-Request-Id"]'
  )
) {
  const marker =
    `    allowedHeaders: [
      "Content-Type",
      "Authorization",
      "Accept"
    ]`;

  if (content.includes(marker)) {
    content =
      content.replace(
        marker,
        `${marker},
    exposedHeaders: ["X-Request-Id"]`
      );
  } else {
    /*
     * Local app.ts may have been reformatted/extended. We don't fail the whole
     * milestone just because the browser cannot read the header; server-side
     * correlation still works. Typecheck remains the final guard.
     */
    console.warn(
      "[P1.15] CORS allowedHeaders marker not found; skipped exposedHeaders."
    );
  }
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/HEALTH_OBSERVABILITY.md <<'EOF'
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
EOF

echo "[P1.15] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.15] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.15] Health and observability installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Verify:"
echo "  http://localhost:4000/health/live"
echo "  http://localhost:4000/health/ready"
echo "  http://localhost:4000/health"
echo
echo "Expected with local MySQL + Redis healthy:"
echo "  /health/live  -> HTTP 200"
echo "  /health/ready -> HTTP 200, ready=true"
echo "  /health       -> status=ok"
