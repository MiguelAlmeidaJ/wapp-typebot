import {
  Worker
} from "bullmq";

import {
  evaluateAutomationEvent
} from "../modules/automations/automation.service.js";
import {
  AUTOMATION_JOB_NAME,
  AUTOMATION_QUEUE_NAME,
  type AutomationJobData
} from "./automation.queue.js";
import {
  jobWorkerRedisOptions
} from "./job-redis.js";

export function createAutomationWorker() {
  const worker =
    new Worker<
      AutomationJobData
    >(
      AUTOMATION_QUEUE_NAME,
      async job => {
        if (
          job.name !==
          AUTOMATION_JOB_NAME
        ) {
          throw new Error(
            `Unknown automation job: ${job.name}`
          );
        }

        return evaluateAutomationEvent(
          job.data
        );
      },
      {
        connection:
          jobWorkerRedisOptions(),
        concurrency: 3
      }
    );

  worker.on(
    "failed",
    (
      job,
      error
    ) => {
      console.error(
        "[automations] job failed",
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
