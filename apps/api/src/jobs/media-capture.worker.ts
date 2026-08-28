import {
  Worker,
  type Job
} from "bullmq";

import { env } from "../config/env.js";
import {
  captureMessageMedia
} from "../modules/media/media-capture.service.js";
import {
  MEDIA_CAPTURE_JOB,
  MEDIA_CAPTURE_QUEUE,
  type MediaCaptureJobData
} from "./media-capture.queue.js";
import {
  jobWorkerRedisOptions
} from "./job-redis.js";

export function createMediaCaptureWorker() {
  if (!env.REDIS_URL) {
    throw new Error(
      "REDIS_URL is required to start the media worker."
    );
  }

  const worker =
    new Worker<
      MediaCaptureJobData
    >(
      MEDIA_CAPTURE_QUEUE,
      async (
        job:
          Job<
            MediaCaptureJobData
          >
      ) => {
        if (
          job.name !==
          MEDIA_CAPTURE_JOB
        ) {
          throw new Error(
            `Unsupported media job: ${job.name}`
          );
        }

        await captureMessageMedia(
          job.data.messageId,
          {
            throwOnFailure:
              true
          }
        );
      },
      {
        connection:
          jobWorkerRedisOptions(),
        concurrency:
          env
            .JOBS_MEDIA_CAPTURE_CONCURRENCY
      }
    );

  worker.on(
    "error",
    error => {
      console.error(
        "[jobs:media] worker error",
        error
      );
    }
  );

  worker.on(
    "failed",
    (
      job,
      error
    ) => {
      console.warn(
        "[jobs:media] job attempt failed",
        {
          jobId:
            job?.id,
          messageId:
            job?.data
              ?.messageId,
          attemptsMade:
            job?.attemptsMade,
          error:
            error.message
        }
      );
    }
  );

  return worker;
}
