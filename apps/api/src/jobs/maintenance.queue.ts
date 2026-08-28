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

export async function getMaintenanceJobCounts() {
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

export async function closeMaintenanceQueue() {
  const current =
    queue;

  queue =
    null;

  if (current) {
    await current.close();
  }
}
