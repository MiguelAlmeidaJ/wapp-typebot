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
