import {
  Worker
} from "bullmq";

import {
  jobWorkerRedisOptions
} from "./job-redis.js";
import {
  MAINTENANCE_JOB_NAME,
  MAINTENANCE_QUEUE_NAME
} from "./maintenance.queue.js";
import {
  runMaintenance
} from "./maintenance.service.js";

export function createMaintenanceWorker() {
  const worker =
    new Worker(
      MAINTENANCE_QUEUE_NAME,
      async job => {
        if (
          job.name !==
          MAINTENANCE_JOB_NAME
        ) {
          throw new Error(
            `Unknown maintenance job: ${job.name}`
          );
        }

        return runMaintenance(
          "SCHEDULED"
        );
      },
      {
        connection:
          jobWorkerRedisOptions(),
        concurrency: 1
      }
    );

  worker.on(
    "failed",
    (
      job,
      error
    ) => {
      console.error(
        "[maintenance] job failed",
        {
          jobId:
            job?.id,
          error:
            error.message
        }
      );
    }
  );

  return worker;
}
