#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.20] Building Evolution operational health monitoring..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/whatsapp/whatsapp.service.ts" \
  "apps/api/src/modules/whatsapp/whatsapp.routes.ts" \
  "apps/api/src/modules/webhooks/evolution-webhook.routes.ts" \
  "apps/web/app/dashboard/connections/page.tsx"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/whatsapp \
  apps/api/prisma/migrations/20260828123000_evolution_health_monitor \
  docs

# ---------------------------------------------------------------------------
# Prisma schema + migration
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/prisma/schema.prisma";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "enum WhatsAppHealthStatus"
  )
) {
  const anchor = `enum WhatsAppConnectionStatus {
  CREATED
  CONNECTING
  CONNECTED
  DISCONNECTED
  ERROR
}`;

  if (!content.includes(anchor)) {
    throw new Error(
      "WhatsAppConnectionStatus enum anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

enum WhatsAppHealthStatus {
  UNKNOWN
  HEALTHY
  DEGRADED
  DOWN
}`
    );
}

if (
  !content.includes(
    "healthStatus"
  )
) {
  const anchor =
    `  lastError      String?                  @db.Text
  lastEventAt    DateTime?`;

  if (!content.includes(anchor)) {
    throw new Error(
      "WhatsAppConnection health field anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  healthStatus   WhatsAppHealthStatus      @default(UNKNOWN)
  lastHealthCheckAt DateTime?
  lastHealthOkAt DateTime?
  healthError    String?                   @db.Text
  consecutiveHealthFailures Int            @default(0)`
    );

  const indexAnchor =
    `  @@index([companyId, status])`;

  if (!content.includes(indexAnchor)) {
    throw new Error(
      "WhatsAppConnection index anchor not found."
    );
  }

  content =
    content.replace(
      indexAnchor,
      `${indexAnchor}
  @@index([companyId, healthStatus])`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "WhatsApp health schema installed."
);
NODE

cat > apps/api/prisma/migrations/20260828123000_evolution_health_monitor/migration.sql <<'EOF'
ALTER TABLE `WhatsAppConnection`
  ADD COLUMN `healthStatus` ENUM('UNKNOWN', 'HEALTHY', 'DEGRADED', 'DOWN') NOT NULL DEFAULT 'UNKNOWN',
  ADD COLUMN `lastHealthCheckAt` DATETIME(3) NULL,
  ADD COLUMN `lastHealthOkAt` DATETIME(3) NULL,
  ADD COLUMN `healthError` TEXT NULL,
  ADD COLUMN `consecutiveHealthFailures` INTEGER NOT NULL DEFAULT 0;

CREATE INDEX `WhatsAppConnection_companyId_healthStatus_idx`
  ON `WhatsAppConnection`(`companyId`, `healthStatus`);
EOF

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
    "EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS:"
  )
) {
  const anchor =
    '  EVOLUTION_WEBHOOK_SECRET: z.string().min(32),';

  if (!content.includes(anchor)) {
    throw new Error(
      "Evolution env anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS: z.coerce
    .number()
    .int()
    .min(15)
    .max(3_600)
    .default(60),`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

if [[ -f "apps/api/.env.example" ]] &&
   ! grep -q "^EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS=" apps/api/.env.example
then
  printf '\nEVOLUTION_HEALTHCHECK_INTERVAL_SECONDS=60\n' >> apps/api/.env.example
fi

# ---------------------------------------------------------------------------
# Distributed Evolution monitor
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/whatsapp/evolution-health-monitor.service.ts <<'EOF'
import {
  randomUUID
} from "node:crypto";

import { Redis } from "ioredis";

import { env } from "../../config/env.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

const LOCK_KEY =
  "wapp:monitor:evolution-health";

let timer:
  | NodeJS.Timeout
  | null =
  null;

let initialTimer:
  | NodeJS.Timeout
  | null =
  null;

let redis:
  | Redis
  | null =
  null;

let cycleRunning =
  false;

let lastCycleAt:
  | Date
  | null =
  null;

let lastCycleError:
  | string
  | null =
  null;

function monitorIntervalMs() {
  return (
    env
      .EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS *
    1_000
  );
}

function monitorLockMs() {
  return Math.max(
    10_000,
    Math.floor(
      monitorIntervalMs() *
        0.85
    )
  );
}

function getRedis() {
  if (
    !env.REDIS_URL
  ) {
    return null;
  }

  if (redis) {
    return redis;
  }

  redis =
    new Redis(
      env.REDIS_URL,
      {
        enableReadyCheck:
          true,
        maxRetriesPerRequest:
          1,
        retryStrategy(
          attempt
        ) {
          return Math.min(
            attempt *
              250,
            5_000
          );
        }
      }
    );

  redis.on(
    "error",
    error => {
      console.warn(
        "[evolution-health] Redis lock error",
        error.message
      );
    }
  );

  return redis;
}

async function acquireLock() {
  const client =
    getRedis();

  if (!client) {
    /*
     * Without Redis, local development still gets monitoring. Production
     * multi-replica deployments already require Redis for readiness.
     */
    return {
      acquired: true,
      token: null as
        | string
        | null
    };
  }

  const token =
    randomUUID();

  try {
    const result =
      await client.call(
        "SET",
        LOCK_KEY,
        token,
        "PX",
        String(
          monitorLockMs()
        ),
        "NX"
      );

    return {
      acquired:
        String(
          result ?? ""
        ) === "OK",
      token
    };
  } catch (error) {
    console.warn(
      "[evolution-health] Could not acquire distributed lock",
      error instanceof Error
        ? error.message
        : error
    );

    return {
      acquired: false,
      token
    };
  }
}

async function releaseLock(
  token:
    | string
    | null
) {
  if (!token) {
    return;
  }

  const client =
    redis;

  if (!client) {
    return;
  }

  try {
    await client.eval(
      `
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      end
      return 0
      `,
      1,
      LOCK_KEY,
      token
    );
  } catch {
    // Lock expires automatically.
  }
}

function normalizeState(
  state: string
) {
  return state
    .trim()
    .toLowerCase();
}

function connectionStatus(
  state: string
):
  | "CONNECTED"
  | "CONNECTING"
  | "DISCONNECTED"
  | null {
  switch (
    normalizeState(
      state
    )
  ) {
    case "open":
    case "connected":
      return "CONNECTED";
    case "connecting":
      return "CONNECTING";
    case "close":
    case "closed":
    case "disconnected":
      return "DISCONNECTED";
    default:
      return null;
  }
}

function healthStatus(
  state: string
):
  | "HEALTHY"
  | "DEGRADED" {
  return connectionStatus(
    state
  ) === "CONNECTED"
    ? "HEALTHY"
    : "DEGRADED";
}

async function checkConnection(
  connection: {
    id: string;
    companyId: string;
    instanceName: string;
    status:
      | "CREATED"
      | "CONNECTING"
      | "CONNECTED"
      | "DISCONNECTED"
      | "ERROR";
    healthStatus:
      | "UNKNOWN"
      | "HEALTHY"
      | "DEGRADED"
      | "DOWN";
    healthError:
      | string
      | null;
  }
) {
  const checkedAt =
    new Date();

  try {
    const provider =
      await evolutionWhatsAppClient
        .connectionState(
          connection
            .instanceName
        );

    const mappedStatus =
      connectionStatus(
        provider.state
      );

    const nextHealth =
      healthStatus(
        provider.state
      );

    const unknownState =
      mappedStatus
        ? null
        : `Estado Evolution não reconhecido: ${provider.state}`;

    const stateChanged =
      Boolean(
        mappedStatus &&
        mappedStatus !==
          connection.status
      );

    const healthChanged =
      nextHealth !==
        connection.healthStatus ||
      unknownState !==
        connection.healthError;

    await prisma
      .whatsAppConnection
      .update({
        where: {
          id:
            connection.id
        },
        data: {
          ...(mappedStatus
            ? {
                status:
                  mappedStatus
              }
            : {}),
          healthStatus:
            nextHealth,
          lastHealthCheckAt:
            checkedAt,
          ...(nextHealth ===
          "HEALTHY"
            ? {
                lastHealthOkAt:
                  checkedAt
              }
            : {}),
          healthError:
            unknownState,
          consecutiveHealthFailures:
            0
        }
      });

    if (
      stateChanged ||
      healthChanged
    ) {
      publishRealtime(
        connection
          .companyId,
        {
          type:
            "connection.updated",
          connectionId:
            connection.id
        }
      );
    }

    return {
      ok: true,
      healthStatus:
        nextHealth
    } as const;
  } catch (error) {
    const message =
      (
        error instanceof Error
          ? error.message
          : "Evolution API indisponível."
      ).slice(
        0,
        2_000
      );

    const healthChanged =
      connection
        .healthStatus !==
        "DOWN" ||
      connection
        .healthError !==
        message;

    await prisma
      .whatsAppConnection
      .update({
        where: {
          id:
            connection.id
        },
        data: {
          healthStatus:
            "DOWN",
          lastHealthCheckAt:
            checkedAt,
          healthError:
            message,
          consecutiveHealthFailures: {
            increment: 1
          }
        }
      });

    if (healthChanged) {
      publishRealtime(
        connection
          .companyId,
        {
          type:
            "connection.updated",
          connectionId:
            connection.id
        }
      );
    }

    return {
      ok: false,
      healthStatus:
        "DOWN" as const,
      error:
        message
    };
  }
}

export async function runEvolutionHealthCycle() {
  if (cycleRunning) {
    return {
      skipped: true,
      reason:
        "cycle_already_running"
    } as const;
  }

  const lock =
    await acquireLock();

  if (!lock.acquired) {
    return {
      skipped: true,
      reason:
        "distributed_lock_not_acquired"
    } as const;
  }

  cycleRunning =
    true;

  try {
    const connections =
      await prisma
        .whatsAppConnection
        .findMany({
          where: {
            provider:
              "EVOLUTION_BAILEYS"
          },
          select: {
            id: true,
            companyId: true,
            instanceName:
              true,
            status: true,
            healthStatus:
              true,
            healthError:
              true
          },
          orderBy: {
            createdAt:
              "asc"
          }
        });

    let healthy = 0;
    let degraded = 0;
    let down = 0;

    /*
     * Sequential checks avoid creating a burst against Evolution when many
     * numbers are connected. The default 60-second cycle is intentionally
     * conservative.
     */
    for (
      const connection
      of connections
    ) {
      const result =
        await checkConnection(
          connection
        );

      if (
        result.healthStatus ===
        "HEALTHY"
      ) {
        healthy += 1;
      } else if (
        result.healthStatus ===
        "DEGRADED"
      ) {
        degraded += 1;
      } else {
        down += 1;
      }
    }

    lastCycleAt =
      new Date();

    lastCycleError =
      null;

    return {
      skipped: false,
      checked:
        connections.length,
      healthy,
      degraded,
      down
    } as const;
  } catch (error) {
    lastCycleError =
      error instanceof Error
        ? error.message
        : "Evolution health cycle failed.";

    throw error;
  } finally {
    cycleRunning =
      false;

    await releaseLock(
      lock.token
    );
  }
}

export async function getEvolutionHealthSummary(
  companyId: string
) {
  const grouped =
    await prisma
      .whatsAppConnection
      .groupBy({
        by: [
          "healthStatus"
        ],
        where: {
          companyId,
          provider:
            "EVOLUTION_BAILEYS"
        },
        _count: {
          _all: true
        }
      });

  const summary = {
    UNKNOWN: 0,
    HEALTHY: 0,
    DEGRADED: 0,
    DOWN: 0
  };

  for (
    const item
    of grouped
  ) {
    summary[
      item.healthStatus
    ] =
      item._count._all;
  }

  return {
    total:
      Object.values(
        summary
      ).reduce(
        (
          total,
          value
        ) =>
          total +
          value,
        0
      ),
    statuses:
      summary,
    monitor:
      getEvolutionHealthMonitorStatus()
  };
}

export function getEvolutionHealthMonitorStatus() {
  return {
    running:
      Boolean(
        timer
      ),
    cycleRunning,
    intervalSeconds:
      env
        .EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS,
    lastCycleAt:
      lastCycleAt
        ?.toISOString() ??
      null,
    lastCycleError
  };
}

export function startEvolutionHealthMonitor() {
  if (timer) {
    return;
  }

  const run = () => {
    void runEvolutionHealthCycle()
      .catch(error => {
        console.error(
          "[evolution-health] cycle failed",
          error
        );
      });
  };

  initialTimer =
    setTimeout(
      run,
      3_000
    );

  initialTimer.unref();

  timer =
    setInterval(
      run,
      monitorIntervalMs()
    );

  timer.unref();

  console.info(
    "[evolution-health] monitor started",
    {
      intervalSeconds:
        env
          .EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS
    }
  );
}

export async function stopEvolutionHealthMonitor() {
  if (initialTimer) {
    clearTimeout(
      initialTimer
    );
    initialTimer =
      null;
  }

  if (timer) {
    clearInterval(
      timer
    );
    timer =
      null;
  }

  const client =
    redis;

  redis =
    null;

  if (!client) {
    return;
  }

  try {
    await client.quit();
  } catch {
    client.disconnect();
  }
}
EOF

# ---------------------------------------------------------------------------
# WhatsApp health endpoint
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/whatsapp/whatsapp.routes.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { getEvolutionHealthSummary } from "./evolution-health-monitor.service.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { requirePermission } from "../auth/auth.guard.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "whatsapp.routes auth import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    '"/api/v1/whatsapp/health"'
  )
) {
  const anchor =
    `  app.get(
    "/api/v1/whatsapp/connections",`;

  if (!content.includes(anchor)) {
    throw new Error(
      "WhatsApp connections route anchor not found."
    );
  }

  const route = `  app.get(
    "/api/v1/whatsapp/health",
    async request => {
      const auth =
        await requirePermission(
          request,
          "whatsapp.read"
        );

      return getEvolutionHealthSummary(
        auth.companyId
      );
    }
  );

`;

  content =
    content.replace(
      anchor,
      `${route}${anchor}`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "WhatsApp health summary endpoint installed."
);
NODE

# ---------------------------------------------------------------------------
# Manual sync also refreshes health state
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/whatsapp/whatsapp.service.ts";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "function mapEvolutionHealth"
  )
) {
  const anchor =
    `function mapEvolutionState(
  state: string
): "CREATED" | "CONNECTING" | "CONNECTED" | "DISCONNECTED" | "ERROR" {`;

  const start =
    content.indexOf(
      anchor
    );

  if (start < 0) {
    throw new Error(
      "mapEvolutionState anchor not found."
    );
  }

  const end =
    content.indexOf(
      "\n}\n\nexport async function listConnections",
      start
    );

  if (end < 0) {
    throw new Error(
      "mapEvolutionState end anchor not found."
    );
  }

  const insertAt =
    end + 3;

  const helper = `
function mapEvolutionHealth(
  state: string
): "HEALTHY" | "DEGRADED" {
  const mapped =
    mapEvolutionState(
      state
    );

  return mapped ===
    "CONNECTED"
    ? "HEALTHY"
    : "DEGRADED";
}
`;

  content =
    content.slice(
      0,
      insertAt
    ) +
    helper +
    content.slice(
      insertAt
    );
}

const syncOld = `      data: {
        status: mapEvolutionState(state.state),
        lastError: null,
        lastEventAt: new Date()
      }`;

const syncNew = `      data: {
        status:
          mapEvolutionState(
            state.state
          ),
        lastError: null,
        healthStatus:
          mapEvolutionHealth(
            state.state
          ),
        lastHealthCheckAt:
          new Date(),
        ...(mapEvolutionHealth(
          state.state
        ) === "HEALTHY"
          ? {
              lastHealthOkAt:
                new Date()
            }
          : {}),
        healthError: null,
        consecutiveHealthFailures:
          0,
        lastEventAt: new Date()
      }`;

if (
  content.includes(
    syncOld
  )
) {
  content =
    content.replace(
      syncOld,
      syncNew
    );
}

const catchOld = `      data: {
        lastError: message,
        lastEventAt: new Date()
      }`;

const catchNew = `      data: {
        lastError: message,
        healthStatus:
          "DOWN",
        lastHealthCheckAt:
          new Date(),
        healthError:
          message,
        consecutiveHealthFailures: {
          increment: 1
        },
        lastEventAt: new Date()
      }`;

if (
  content.includes(
    catchOld
  )
) {
  content =
    content.replace(
      catchOld,
      catchNew
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Manual sync now updates Evolution health fields."
);
NODE

# ---------------------------------------------------------------------------
# Webhook connection events prove provider liveness without touching lastEvent semantics
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/webhooks/evolution-webhook.routes.ts";

let content =
  fs.readFileSync(path, "utf8");

const oldBlock = `            data: {
              status: mappedState,
              phoneNumber: owner?.replace(/\\D/g, "") || undefined,
              lastError: null,
              lastEventAt: new Date()
            }`;

const newBlock = `            data: {
              status:
                mappedState,
              phoneNumber:
                owner?.replace(
                  /\\D/g,
                  ""
                ) ||
                undefined,
              lastError:
                null,
              healthStatus:
                mappedState ===
                "CONNECTED"
                  ? "HEALTHY"
                  : "DEGRADED",
              lastHealthCheckAt:
                new Date(),
              ...(mappedState ===
              "CONNECTED"
                ? {
                    lastHealthOkAt:
                      new Date()
                  }
                : {}),
              healthError:
                null,
              consecutiveHealthFailures:
                0,
              lastEventAt:
                new Date()
            }`;

if (
  content.includes(
    oldBlock
  )
) {
  content =
    content.replace(
      oldBlock,
      newBlock
    );
} else if (
  !content.includes(
    "consecutiveHealthFailures"
  )
) {
  throw new Error(
    "Webhook connection update block not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Connection webhooks now refresh health immediately."
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

const importBlock = `import {
  startEvolutionHealthMonitor,
  stopEvolutionHealthMonitor
} from "./modules/whatsapp/evolution-health-monitor.service.js";`;

if (
  !content.includes(
    "startEvolutionHealthMonitor"
  )
) {
  const anchor =
    'import { whatsappRoutes } from "./modules/whatsapp/whatsapp.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "app WhatsApp route import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importBlock}`
    );
}

if (
  !content.includes(
    "await stopEvolutionHealthMonitor();"
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
    await stopEvolutionHealthMonitor();`
    );
}

if (
  !content.includes(
    "startEvolutionHealthMonitor();"
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
    `  startEvolutionHealthMonitor();

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
  "Evolution monitor lifecycle integrated."
);
NODE

# ---------------------------------------------------------------------------
# Frontend: health fields + remove stable connection polling
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/connections/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "type HealthStatus"
  )
) {
  const anchor = `type ConnectionStatus =
  | "CREATED"
  | "CONNECTING"
  | "CONNECTED"
  | "DISCONNECTED"
  | "ERROR";`;

  if (!content.includes(anchor)) {
    throw new Error(
      "ConnectionStatus type anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

type HealthStatus =
  | "UNKNOWN"
  | "HEALTHY"
  | "DEGRADED"
  | "DOWN";`
    );
}

if (
  !content.includes(
    "healthStatus: HealthStatus;"
  )
) {
  const anchor =
    `  lastError: string | null;
  lastEventAt: string | null;`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Connection interface health anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  healthStatus: HealthStatus;
  lastHealthCheckAt: string | null;
  lastHealthOkAt: string | null;
  healthError: string | null;
  consecutiveHealthFailures: number;`
    );
}

if (
  !content.includes(
    "const healthLabels"
  )
) {
  const anchor = `const statusLabels: Record<ConnectionStatus, string> = {
  CREATED: "Criada",
  CONNECTING: "Aguardando QR",
  CONNECTED: "Conectada",
  DISCONNECTED: "Desconectada",
  ERROR: "Erro"
};`;

  if (!content.includes(anchor)) {
    throw new Error(
      "statusLabels anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

const healthLabels: Record<HealthStatus, string> = {
  UNKNOWN: "Aguardando checagem",
  HEALTHY: "Saudável",
  DEGRADED: "Degradada",
  DOWN: "Evolution indisponível"
};

function healthCheckLabel(
  value: string | null
) {
  if (!value) {
    return "ainda não verificada";
  }

  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      dateStyle:
        "short",
      timeStyle:
        "short"
    }
  ).format(
    new Date(
      value
    )
  );
}`
    );
}

const pollingOld = `        connections
          .filter(connection =>
            ["CONNECTING", "CONNECTED", "DISCONNECTED"].includes(
              connection.status
            )
          )`;

const pollingNew = `        connections
          .filter(
            connection =>
              connection.status ===
              "CONNECTING"
          )`;

if (
  content.includes(
    pollingOld
  )
) {
  content =
    content.replace(
      pollingOld,
      pollingNew
    );
} else if (
  content.includes(
    '["CONNECTING", "CONNECTED", "DISCONNECTED"]'
  )
) {
  throw new Error(
    "Connection polling block format diverged."
  );
}

if (
  !content.includes(
    "Saúde <strong>"
  )
) {
  const anchor = `                    {connection.phoneNumber && (
                      <span>
                        Número <strong>{connection.phoneNumber}</strong>
                      </span>
                    )}`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Connection meta render anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
                    <span>
                      Saúde{" "}
                      <strong>
                        {healthLabels[connection.healthStatus]}
                      </strong>
                    </span>
                    <span>
                      Checagem{" "}
                      <strong>
                        {healthCheckLabel(connection.lastHealthCheckAt)}
                      </strong>
                    </span>`
    );
}

if (
  !content.includes(
    "connection.healthError"
  )
) {
  const anchor = `                  {connection.lastError && (
                    <div className="connection-error">
                      {connection.lastError}
                    </div>
                  )}`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Connection error render anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

                  {connection.healthError &&
                    connection.healthError !== connection.lastError && (
                      <div className="connection-error">
                        Evolution: {connection.healthError}
                      </div>
                    )}`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Connections UI now shows backend health and only polls while connecting."
);
NODE

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/EVOLUTION_HEALTH_MONITORING.md <<'EOF'
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
EOF

echo "[P1.20] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.20] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.20] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.20] Evolution health monitoring installed."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Validation:"
echo "  1. open /dashboard/connections"
echo "  2. wait up to ~60 seconds"
echo "  3. confirm health becomes HEALTHY for a connected instance"
echo "  4. confirm lastEventAt is not artificially refreshed every minute"
echo "  5. GET /api/v1/whatsapp/health while authenticated"
