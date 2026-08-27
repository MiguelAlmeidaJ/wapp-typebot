import { env } from "../../config/env.js";
import { prisma } from "../../lib/database.js";
import { getRealtimeTransportStatus } from "../realtime/realtime.bus.js";
import {
  checkMediaStorageHealth,
  getMediaStorageMode
} from "../media/media-storage.js";

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

  const storage =
    await checkMediaStorageHealth();

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
    mediaStorage: {
      driver:
        getMediaStorageMode(),
      status:
        storage.ok
          ? "ok"
          : "error",
      ...(storage.error
        ? {
            error:
              storage.error
          }
        : {})
    },
    timestamp:
      new Date()
        .toISOString()
  };
}
