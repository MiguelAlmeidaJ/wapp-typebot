import {
  Queue
} from "bullmq";

import { env } from "../config/env.js";
import type {
  AutomationTriggerValue
} from "../modules/automations/automation.service.js";
import {
  jobProducerRedisOptions
} from "./job-redis.js";

export const AUTOMATION_QUEUE_NAME =
  "wapp-automations";

export const AUTOMATION_JOB_NAME =
  "evaluate";

export interface AutomationJobData {
  companyId: string;
  ticketId: string;
  sourceMessageId: string;
  trigger:
    AutomationTriggerValue;
}

let queue:
  | Queue<
      AutomationJobData
    >
  | null =
  null;

export function getAutomationQueue() {
  if (!queue) {
    queue =
      new Queue<
        AutomationJobData
      >(
        AUTOMATION_QUEUE_NAME,
        {
          connection:
            jobProducerRedisOptions()
        }
      );
  }

  return queue;
}

export async function enqueueAutomationEvaluation(
  data:
    AutomationJobData
) {
  if (!env.REDIS_URL) {
    return false;
  }

  await getAutomationQueue()
    .add(
      AUTOMATION_JOB_NAME,
      data,
      {
        jobId:
          `automation-${data.trigger}-${data.sourceMessageId}`,
        attempts: 1,
        removeOnComplete: {
          count: 1000
        },
        removeOnFail: {
          count: 1000
        }
      }
    );

  return true;
}

export async function closeAutomationQueue() {
  const current =
    queue;

  queue =
    null;

  if (current) {
    await current.close();
  }
}
