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
