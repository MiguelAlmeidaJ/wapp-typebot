#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.28] Installing metrics and operational alerts..."

for required in \
  "apps/api/package.json" \
  "apps/api/src/app.ts" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/security/permissions.ts" \
  "apps/api/src/security/permissions.test.ts" \
  "apps/api/src/jobs/media-capture.queue.ts" \
  "apps/api/src/jobs/maintenance.queue.ts" \
  "apps/api/src/jobs/maintenance.service.ts"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -q "model MaintenanceRun" apps/api/prisma/schema.prisma; then
  echo "ERROR: P1.27 must be installed before P1.28."
  exit 1
fi

mkdir -p \
  apps/api/src/modules/observability \
  docs

if ! node -e "const p=require('./apps/api/package.json'); process.exit(p.dependencies?.['prom-client'] ? 0 : 1)" >/dev/null 2>&1
then
  echo "[P1.28] Adding prom-client..."
  pnpm --filter @wapp/api add prom-client@^15.1.3
fi

cat > apps/api/src/modules/observability/metrics-token.ts <<'EOF'
import {
  timingSafeEqual
} from "node:crypto";

export function validMetricsAuthorization(
  expectedToken: string,
  authorization:
    | string
    | undefined
) {
  if (
    !expectedToken ||
    !authorization
      ?.startsWith(
        "Bearer "
      )
  ) {
    return false;
  }

  const candidate =
    authorization
      .slice(
        "Bearer ".length
      )
      .trim();

  const expected =
    Buffer.from(
      expectedToken
    );

  const received =
    Buffer.from(
      candidate
    );

  if (
    expected.length !==
    received.length
  ) {
    return false;
  }

  return timingSafeEqual(
    expected,
    received
  );
}
EOF

cat > apps/api/src/modules/observability/metrics-token.test.ts <<'EOF'
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  validMetricsAuthorization
} from "./metrics-token.js";

test(
  "metrics bearer token validation is strict",
  () => {
    const token =
      "metrics_token_abcdefghijklmnopqrstuvwxyz_123456";

    assert.equal(
      validMetricsAuthorization(
        token,
        `Bearer ${token}`
      ),
      true
    );

    assert.equal(
      validMetricsAuthorization(
        token,
        "Bearer wrong"
      ),
      false
    );

    assert.equal(
      validMetricsAuthorization(
        "",
        "Bearer anything"
      ),
      false
    );

    assert.equal(
      validMetricsAuthorization(
        token,
        undefined
      ),
      false
    );
  }
);
EOF

cat > apps/api/src/modules/observability/metrics.service.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";
import {
  Counter,
  Gauge,
  Histogram,
  Registry,
  collectDefaultMetrics
} from "prom-client";

import { prisma } from "../../lib/database.js";
import {
  getMediaCaptureJobCounts
} from "../../jobs/media-capture.queue.js";
import {
  getMaintenanceJobCounts
} from "../../jobs/maintenance.queue.js";

const registry =
  new Registry();

collectDefaultMetrics({
  register:
    registry,
  prefix:
    "wapp_process_"
});

const httpRequests =
  new Counter({
    name:
      "wapp_http_requests_total",
    help:
      "HTTP requests handled by Wapp API.",
    labelNames: [
      "method",
      "route",
      "status"
    ] as const,
    registers: [
      registry
    ]
  });

const httpDuration =
  new Histogram({
    name:
      "wapp_http_request_duration_seconds",
    help:
      "Wapp API request duration.",
    labelNames: [
      "method",
      "route",
      "status"
    ] as const,
    buckets: [
      0.01,
      0.025,
      0.05,
      0.1,
      0.25,
      0.5,
      1,
      2.5,
      5
    ],
    registers: [
      registry
    ]
  });

const tickets =
  new Gauge({
    name:
      "wapp_tickets",
    help:
      "Tickets by status.",
    labelNames: [
      "status"
    ] as const,
    registers: [
      registry
    ]
  });

const whatsappHealth =
  new Gauge({
    name:
      "wapp_whatsapp_connections",
    help:
      "WhatsApp connections by health state.",
    labelNames: [
      "health"
    ] as const,
    registers: [
      registry
    ]
  });

const media =
  new Gauge({
    name:
      "wapp_message_media",
    help:
      "Messages by media processing state.",
    labelNames: [
      "status"
    ] as const,
    registers: [
      registry
    ]
  });

const deliveryFailed =
  new Gauge({
    name:
      "wapp_outbound_delivery_failed_24h",
    help:
      "Outbound messages with failed delivery in the last 24 hours.",
    registers: [
      registry
    ]
  });

const jobs =
  new Gauge({
    name:
      "wapp_jobs",
    help:
      "BullMQ jobs by queue and state.",
    labelNames: [
      "queue",
      "state"
    ] as const,
    registers: [
      registry
    ]
  });

const maintenanceLastSuccess =
  new Gauge({
    name:
      "wapp_maintenance_last_success_timestamp_seconds",
    help:
      "Unix timestamp of the most recent successful maintenance run.",
    registers: [
      registry
    ]
  });

const requestStarted =
  new WeakMap<
    object,
    number
  >();

export function installHttpMetricsHooks(
  app: FastifyInstance
) {
  app.addHook(
    "onRequest",
    async request => {
      requestStarted.set(
        request,
        performance.now()
      );
    }
  );

  app.addHook(
    "onResponse",
    async (
      request,
      reply
    ) => {
      const start =
        requestStarted.get(
          request
        );

      requestStarted.delete(
        request
      );

      const labels = {
        method:
          request.method,
        route:
          request
            .routeOptions
            .url ??
          "unknown",
        status:
          String(
            reply.statusCode
          )
      };

      httpRequests.inc(
        labels
      );

      if (
        start !==
        undefined
      ) {
        httpDuration.observe(
          labels,
          Math.max(
            0,
            performance.now() -
              start
          ) /
            1_000
        );
      }
    }
  );
}

async function refreshOperationalMetrics() {
  tickets.reset();
  whatsappHealth.reset();
  media.reset();
  jobs.reset();

  const [
    ticketGroups,
    healthGroups,
    mediaGroups,
    failed24h,
    mediaJobs,
    maintenanceJobs,
    lastMaintenance
  ] =
    await Promise.all([
      prisma.ticket.groupBy({
        by: [
          "status"
        ],
        _count: {
          _all: true
        }
      }),
      prisma.whatsAppConnection.groupBy({
        by: [
          "healthStatus"
        ],
        _count: {
          _all: true
        }
      }),
      prisma.message.groupBy({
        by: [
          "mediaStatus"
        ],
        _count: {
          _all: true
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
              new Date(
                Date.now() -
                  24 *
                    60 *
                    60 *
                    1_000
              )
          }
        }
      }),
      getMediaCaptureJobCounts(),
      getMaintenanceJobCounts(),
      prisma.maintenanceRun.findFirst({
        where: {
          status:
            "SUCCESS"
        },
        orderBy: {
          finishedAt:
            "desc"
        },
        select: {
          finishedAt:
            true
        }
      })
    ]);

  for (
    const item
    of ticketGroups
  ) {
    tickets.set(
      {
        status:
          item.status
      },
      item._count._all
    );
  }

  for (
    const item
    of healthGroups
  ) {
    whatsappHealth.set(
      {
        health:
          item.healthStatus
      },
      item._count._all
    );
  }

  for (
    const item
    of mediaGroups
  ) {
    media.set(
      {
        status:
          item.mediaStatus
      },
      item._count._all
    );
  }

  deliveryFailed.set(
    failed24h
  );

  for (
    const [
      state,
      value
    ]
    of Object.entries(
      mediaJobs
    )
  ) {
    if (
      state ===
      "configured" ||
      typeof value !==
        "number"
    ) {
      continue;
    }

    jobs.set(
      {
        queue:
          "media",
        state
      },
      value
    );
  }

  for (
    const [
      state,
      value
    ]
    of Object.entries(
      maintenanceJobs
    )
  ) {
    if (
      state ===
      "configured" ||
      typeof value !==
        "number"
    ) {
      continue;
    }

    jobs.set(
      {
        queue:
          "maintenance",
        state
      },
      value
    );
  }

  maintenanceLastSuccess.set(
    lastMaintenance
      ?.finishedAt
      ?.getTime()
      ? lastMaintenance
          .finishedAt
          .getTime() /
        1_000
      : 0
  );
}

export async function renderMetrics() {
  await refreshOperationalMetrics();

  return registry.metrics();
}

export function metricsContentType() {
  return registry.contentType;
}
EOF

cat > apps/api/src/modules/observability/alerts.service.ts <<'EOF'
import { env } from "../../config/env.js";
import { prisma } from "../../lib/database.js";

export interface OperationalAlert {
  code: string;
  severity:
    | "INFO"
    | "WARNING"
    | "CRITICAL";
  count: number;
  message: string;
}

export async function getOperationalAlerts(
  companyId: string
) {
  const staleCutoff =
    new Date(
      Date.now() -
        env
          .MAINTENANCE_STALE_MEDIA_MINUTES *
          60 *
          1_000
    );

  const last24h =
    new Date(
      Date.now() -
        24 *
          60 *
          60 *
          1_000
    );

  const [
    down,
    degraded,
    staleMedia,
    failedMedia,
    failedDelivery,
    maintenanceFailure
  ] =
    await Promise.all([
      prisma.whatsAppConnection.count({
        where: {
          companyId,
          healthStatus:
            "DOWN"
        }
      }),
      prisma.whatsAppConnection.count({
        where: {
          companyId,
          healthStatus:
            "DEGRADED"
        }
      }),
      prisma.message.count({
        where: {
          companyId,
          mediaStatus:
            "PENDING",
          createdAt: {
            lt:
              staleCutoff
          }
        }
      }),
      prisma.message.count({
        where: {
          companyId,
          mediaStatus:
            "FAILED"
        }
      }),
      prisma.message.count({
        where: {
          companyId,
          direction:
            "OUTBOUND",
          deliveryStatus:
            "FAILED",
          timestamp: {
            gte:
              last24h
          }
        }
      }),
      prisma.maintenanceRun.findFirst({
        where: {
          status:
            "FAILED",
          createdAt: {
            gte:
              last24h
          }
        },
        select: {
          id: true
        }
      })
    ]);

  const alerts:
    OperationalAlert[] =
    [];

  if (down > 0) {
    alerts.push({
      code:
        "EVOLUTION_DOWN",
      severity:
        "CRITICAL",
      count:
        down,
      message:
        `${down} conexão(ões) sem resposta da Evolution.`
    });
  }

  if (degraded > 0) {
    alerts.push({
      code:
        "WHATSAPP_DEGRADED",
      severity:
        "WARNING",
      count:
        degraded,
      message:
        `${degraded} conexão(ões) acessíveis, mas não conectadas.`
    });
  }

  if (
    staleMedia >
    0
  ) {
    alerts.push({
      code:
        "MEDIA_STALE_PENDING",
      severity:
        "WARNING",
      count:
        staleMedia,
      message:
        `${staleMedia} mídia(s) permanecem pendentes além da janela operacional.`
    });
  }

  if (
    failedMedia >
    0
  ) {
    alerts.push({
      code:
        "MEDIA_FAILED",
      severity:
        "WARNING",
      count:
        failedMedia,
      message:
        `${failedMedia} mídia(s) falharam no processamento.`
    });
  }

  if (
    failedDelivery >
    0
  ) {
    alerts.push({
      code:
        "DELIVERY_FAILED",
      severity:
        "WARNING",
      count:
        failedDelivery,
      message:
        `${failedDelivery} mensagem(ns) de saída falharam nas últimas 24h.`
    });
  }

  if (
    maintenanceFailure
  ) {
    alerts.push({
      code:
        "MAINTENANCE_FAILED",
      severity:
        "CRITICAL",
      count: 1,
      message:
        "O housekeeping automático registrou falha nas últimas 24h."
    });
  }

  return {
    status:
      alerts.some(
        alert =>
          alert.severity ===
          "CRITICAL"
      )
        ? "CRITICAL"
        : alerts.length >
            0
          ? "ATTENTION"
          : "OK",
    alerts,
    checkedAt:
      new Date()
        .toISOString()
  };
}
EOF

cat > apps/api/src/modules/observability/observability.routes.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";

import { env } from "../../config/env.js";
import { requirePermission } from "../auth/auth.guard.js";
import { getOperationalAlerts } from "./alerts.service.js";
import {
  metricsContentType,
  renderMetrics
} from "./metrics.service.js";
import {
  validMetricsAuthorization
} from "./metrics-token.js";

export async function observabilityRoutes(
  app: FastifyInstance
) {
  app.get(
    "/metrics",
    async (
      request,
      reply
    ) => {
      if (
        !env.METRICS_TOKEN
      ) {
        return reply
          .status(404)
          .send({
            error: {
              code:
                "NOT_FOUND",
              message:
                "Not found."
            }
          });
      }

      if (
        !validMetricsAuthorization(
          env.METRICS_TOKEN,
          request.headers
            .authorization
        )
      ) {
        return reply
          .status(401)
          .send({
            error: {
              code:
                "UNAUTHORIZED",
              message:
                "Unauthorized."
            }
          });
      }

      reply.header(
        "Content-Type",
        metricsContentType()
      );

      return reply.send(
        await renderMetrics()
      );
    }
  );

  app.get(
    "/api/v1/observability/alerts",
    async request => {
      const auth =
        await requirePermission(
          request,
          "observability.read"
        );

      return getOperationalAlerts(
        auth.companyId
      );
    }
  );
}
EOF

node <<'NODE'
const fs=require("node:fs");
const path="apps/api/src/jobs/maintenance.queue.ts";
let content=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");

if(!content.includes("getMaintenanceJobCounts")){
  const anchor=`export async function closeMaintenanceQueue() {`;
  if(!content.includes(anchor)) throw new Error("maintenance close anchor not found.");
  const helper=`export async function getMaintenanceJobCounts() {
  if (!env.REDIS_URL) {
    return {
      configured: false,
      waiting: 0,
      active: 0,
      delayed: 0,
      failed: 0
    };
  }

  const counts =
    await getMaintenanceQueue()
      .getJobCounts(
        "waiting",
        "active",
        "delayed",
        "failed"
      );

  return {
    configured: true,
    waiting:
      counts.waiting ?? 0,
    active:
      counts.active ?? 0,
    delayed:
      counts.delayed ?? 0,
    failed:
      counts.failed ?? 0
  };
}

`;
  content=content.replace(anchor,`${helper}${anchor}`);
}

fs.writeFileSync(path,content);
NODE

node <<'NODE'
const fs=require("node:fs");
const path="apps/api/src/config/env.ts";
let c=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");

if(!c.includes("METRICS_TOKEN:")){
  const anchor=`  JWT_SECRET: z.string().min(32),`;
  if(!c.includes(anchor)) throw new Error("JWT env anchor not found.");
  c=c.replace(anchor,`${anchor}
  METRICS_TOKEN: z
    .string()
    .min(32)
    .optional()
    .or(z.literal("")),`);
}

fs.writeFileSync(path,c);
NODE

if [[ -f "apps/api/.env.example" ]] &&
   ! grep -q '^METRICS_TOKEN=' apps/api/.env.example
then
  printf '\nMETRICS_TOKEN=\n' >> apps/api/.env.example
fi

node <<'NODE'
const fs=require("node:fs");
const path="apps/api/src/security/permissions.ts";
let c=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");

if(!c.includes('| "observability.read"')){
  c=c.replace('  | "audit.read"',`  | "audit.read"
  | "observability.read"`);

  c=c.replace('    "audit.read",',`    "audit.read",
    "observability.read",`);

  const adminIndex=c.indexOf('  ADMIN: [');
  const supervisorIndex=c.indexOf('  SUPERVISOR: [');
  if(adminIndex>=0 && supervisorIndex>adminIndex){
    const part=c.slice(adminIndex,supervisorIndex);
    if(!part.includes('"observability.read"')){
      c=c.slice(0,adminIndex)+part.replace('    "audit.read",',`    "audit.read",
    "observability.read",`)+c.slice(supervisorIndex);
    }
  }

  const supStart=c.indexOf('  SUPERVISOR: [');
  const agentStart=c.indexOf('  AGENT: [');
  if(supStart>=0 && agentStart>supStart){
    const part=c.slice(supStart,agentStart);
    if(!part.includes('"observability.read"')){
      c=c.slice(0,supStart)+part.replace('    "contacts.read",',`    "observability.read",
    "contacts.read",`)+c.slice(agentStart);
    }
  }
}

fs.writeFileSync(path,c);
NODE

node <<'NODE'
const fs=require("node:fs");
const path="apps/api/src/security/permissions.test.ts";
let c=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");

if(!c.includes('"observability.read",')){
  c=c.replace('    "audit.read",',`    "audit.read",
    "observability.read",`);

  const supAllowed=`          const permission
          of [
            "contacts.manage",`;
  if(c.includes(supAllowed)){
    c=c.replace(supAllowed,`          const permission
          of [
            "observability.read",
            "contacts.manage",`);
  }

  const agentDenied=`          const permission
          of [
            "admin.test",`;
  if(c.includes(agentDenied)){
    c=c.replace(agentDenied,`          const permission
          of [
            "admin.test",
            "observability.read",`);
  }
}

fs.writeFileSync(path,c);
NODE

node <<'NODE'
const fs=require("node:fs");
const path="apps/api/src/app.ts";
let c=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");

const routeImport='import { observabilityRoutes } from "./modules/observability/observability.routes.js";';
const metricsImport='import { installHttpMetricsHooks } from "./modules/observability/metrics.service.js";';

if(!c.includes(routeImport)){
  const anchor='import { healthRoutes } from "./modules/health/health.routes.js";';
  if(!c.includes(anchor)) throw new Error("health import anchor not found.");
  c=c.replace(anchor,`${anchor}
${routeImport}
${metricsImport}`);
}

if(!c.includes("installHttpMetricsHooks(app);")){
  const anchor='  installAdminAuditHooks(app);';
  if(!c.includes(anchor)) throw new Error("P1.26 audit hook anchor not found.");
  c=c.replace(anchor,`${anchor}
  installHttpMetricsHooks(app);`);
}

if(!c.includes("await app.register(observabilityRoutes);")){
  const anchor='  await app.register(healthRoutes);';
  if(!c.includes(anchor)) throw new Error("health route registration anchor not found.");
  c=c.replace(anchor,`${anchor}
  await app.register(observabilityRoutes);`);
}

fs.writeFileSync(path,c);
NODE

node <<'NODE'
const fs=require("node:fs");
const path="apps/api/package.json";
const p=JSON.parse(fs.readFileSync(path,"utf8"));
const test=p.scripts?.test;
if(typeof test==="string" && !test.includes("metrics-token.test.ts")){
  p.scripts.test=`${test} src/modules/observability/metrics-token.test.ts`;
}
fs.writeFileSync(path,`${JSON.stringify(p,null,2)}\n`);
NODE

if [[ -f "infra/production/docker-compose.yml" ]] &&
   ! grep -q 'METRICS_TOKEN:' infra/production/docker-compose.yml
then
  node <<'NODE'
const fs=require("node:fs");
const path="infra/production/docker-compose.yml";
let c=fs.readFileSync(path,"utf8").replace(/\r\n/g,"\n");
const anchor='  JWT_SECRET: ${JWT_SECRET}';
if(!c.includes(anchor)) throw new Error("production JWT env anchor not found.");
c=c.replace(anchor,`${anchor}
  METRICS_TOKEN: \${METRICS_TOKEN:-}`);
fs.writeFileSync(path,c);
NODE
fi

if [[ -f "infra/production/.env.production.example" ]] &&
   ! grep -q '^METRICS_TOKEN=' infra/production/.env.production.example
then
  cat >> infra/production/.env.production.example <<'EOF'

# Prometheus scrape bearer token. Use 32+ random characters.
METRICS_TOKEN=CHANGE_ME_RANDOM_METRICS_TOKEN_32_PLUS
EOF
fi

cat > docs/OBSERVABILITY.md <<'EOF'
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
EOF

echo "[P1.28] Unit tests..."
pnpm test

echo "[P1.28] Typechecking..."
pnpm typecheck

echo "[P1.28] Integration tests..."
pnpm test:integration

echo
echo "[P1.28] Observability installed."
echo "No Prisma migration is introduced by P1.28."
