import {
  Queue
} from "bullmq";

import {
  env
} from "../config/env.js";
import {
  scheduledMessageDelay
} from "../modules/scheduled-messages/scheduled-message.policy.js";
import {
  jobProducerRedisOptions
} from "./job-redis.js";

export const SCHEDULED_MESSAGE_QUEUE_NAME =
  "wapp-scheduled-messages";

export const SCHEDULED_MESSAGE_DELIVER_JOB =
  "deliver";

export const SCHEDULED_MESSAGE_SWEEP_JOB =
  "sweep";

interface DeliveryData {
  scheduledMessageId: string;
}

let queue:
  | Queue
  | null =
  null;

export function getScheduledMessageQueue() {
  if (!queue) {
    queue =
      new Queue(
        SCHEDULED_MESSAGE_QUEUE_NAME,
        {
          connection:
            jobProducerRedisOptions()
        }
      );
  }

  return queue;
}

export async function enqueueScheduledMessageDelivery(input: {
  scheduledMessageId: string;
  scheduledFor: Date;
}) {
  if (
    !env.REDIS_URL
  ) {
    return false;
  }

  await getScheduledMessageQueue()
    .add(
      SCHEDULED_MESSAGE_DELIVER_JOB,
      {
        scheduledMessageId:
          input.scheduledMessageId
      } satisfies DeliveryData,
      {
        jobId:
          `scheduled-message-${input.scheduledMessageId}`,
        delay:
          scheduledMessageDelay(
            new Date(),
            input.scheduledFor
          ),
        attempts:
          1,
        removeOnComplete: {
          count:
            2000
        },
        removeOnFail: {
          count:
            2000
        }
      }
    );

  return true;
}

export async function ensureScheduledMessageSweep() {
  if (
    !env.REDIS_URL
  ) {
    return;
  }

  await getScheduledMessageQueue()
    .upsertJobScheduler(
      "wapp-scheduled-message-sweep",
      {
        every:
          60_000
      },
      {
        name:
          SCHEDULED_MESSAGE_SWEEP_JOB,
        data: {}
      }
    );
}

export async function removeScheduledMessageJob(
  scheduledMessageId: string
) {
  if (
    !env.REDIS_URL
  ) {
    return;
  }

  const job =
    await getScheduledMessageQueue()
      .getJob(
        `scheduled-message-${scheduledMessageId}`
      );

  if (
    job &&
    ![
      "active",
      "completed",
      "failed"
    ].includes(
      await job.getState()
    )
  ) {
    await job.remove();
  }
}

export async function closeScheduledMessageQueue() {
  const current =
    queue;

  queue =
    null;

  if (
    current
  ) {
    await current.close();
  }
}
