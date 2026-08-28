import {
  Worker
} from "bullmq";

import {
  deliverScheduledMessage,
  reconcileScheduledMessages
} from "../modules/scheduled-messages/scheduled-message.service.js";
import {
  jobWorkerRedisOptions
} from "./job-redis.js";
import {
  SCHEDULED_MESSAGE_DELIVER_JOB,
  SCHEDULED_MESSAGE_QUEUE_NAME,
  SCHEDULED_MESSAGE_SWEEP_JOB,
  enqueueScheduledMessageDelivery
} from "./scheduled-message.queue.js";

export function createScheduledMessageWorker() {
  const worker =
    new Worker(
      SCHEDULED_MESSAGE_QUEUE_NAME,
      async job => {
        if (
          job.name ===
          SCHEDULED_MESSAGE_DELIVER_JOB
        ) {
          const scheduledMessageId =
            typeof job.data
                ?.scheduledMessageId ===
              "string"
              ? job.data
                  .scheduledMessageId
              : null;

          if (
            !scheduledMessageId
          ) {
            throw new Error(
              "scheduledMessageId is required."
            );
          }

          return deliverScheduledMessage(
            scheduledMessageId
          );
        }

        if (
          job.name ===
          SCHEDULED_MESSAGE_SWEEP_JOB
        ) {
          const due =
            await reconcileScheduledMessages();

          for (
            const item
            of due
          ) {
            await enqueueScheduledMessageDelivery({
              scheduledMessageId:
                item.id,
              scheduledFor:
                item.scheduledFor
            });
          }

          return {
            queued:
              due.length
          };
        }

        throw new Error(
          `Unknown scheduled-message job: ${job.name}`
        );
      },
      {
        connection:
          jobWorkerRedisOptions(),
        concurrency:
          3
      }
    );

  worker.on(
    "failed",
    (
      job,
      error
    ) => {
      console.error(
        "[scheduled-messages] job failed",
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
