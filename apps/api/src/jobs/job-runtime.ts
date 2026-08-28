import type {
  Worker
} from "bullmq";

import { env } from "../config/env.js";
import {
  createTaskReminderWorker
} from "./task-reminder.worker.js";
import {
  closeTaskReminderQueue,
  ensureTaskReminderSweep
} from "./task-reminder.queue.js";
import {
  createScheduledMessageWorker
} from "./scheduled-message.worker.js";
import {
  closeScheduledMessageQueue,
  ensureScheduledMessageSweep
} from "./scheduled-message.queue.js";
import {
  createAutomationWorker
} from "./automation.worker.js";
import {
  closeAutomationQueue
} from "./automation.queue.js";
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
    createMaintenanceWorker(),
    createAutomationWorker(),
    createScheduledMessageWorker(),
    createTaskReminderWorker()
  ];

  void ensureMaintenanceSchedule()
    .catch(error => {
      console.error(
        "[maintenance] scheduler setup failed",
        error
      );
    });

  void ensureScheduledMessageSweep()
    .catch(error => {
      console.error(
        "[scheduled-messages] scheduler setup failed",
        error
      );
    });

  void ensureTaskReminderSweep()
    .catch(error => {
      console.error(
        "[task-reminders] scheduler setup failed",
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
    closeMaintenanceQueue(),
    closeAutomationQueue(),
    closeScheduledMessageQueue(),
    closeTaskReminderQueue()
  ]);
}
