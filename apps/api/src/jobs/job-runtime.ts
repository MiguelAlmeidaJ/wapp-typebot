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
