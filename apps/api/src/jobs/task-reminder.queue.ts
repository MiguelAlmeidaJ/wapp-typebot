import { Queue } from "bullmq";
import { env } from "../config/env.js";
import { jobProducerRedisOptions } from "./job-redis.js";

export const TASK_REMINDER_QUEUE_NAME = "wapp-task-reminders";
export const TASK_REMINDER_DELIVER_JOB = "deliver";
export const TASK_REMINDER_SWEEP_JOB = "sweep";

let queue: Queue | null = null;

export function getTaskReminderQueue() {
  if (!queue) {
    queue = new Queue(TASK_REMINDER_QUEUE_NAME, {
      connection: jobProducerRedisOptions()
    });
  }
  return queue;
}

export async function enqueueTaskReminder(input: {
  taskId: string;
  reminderAt: Date;
}) {
  if (!env.REDIS_URL) return false;

  await getTaskReminderQueue().add(
    TASK_REMINDER_DELIVER_JOB,
    {
      taskId: input.taskId,
      expectedRemindAt: input.reminderAt.toISOString()
    },
    {
      jobId: `task-reminder-${input.taskId}-${input.reminderAt.getTime()}`,
      delay: Math.max(0, input.reminderAt.getTime() - Date.now()),
      attempts: 3,
      backoff: {
        type: "exponential",
        delay: 5_000
      },
      removeOnComplete: {
        count: 2_000
      },
      removeOnFail: {
        count: 2_000
      }
    }
  );

  return true;
}

export async function ensureTaskReminderSweep() {
  if (!env.REDIS_URL) return;

  await getTaskReminderQueue().upsertJobScheduler(
    "wapp-task-reminder-sweep",
    {
      every: 60_000
    },
    {
      name: TASK_REMINDER_SWEEP_JOB,
      data: {}
    }
  );
}

export async function closeTaskReminderQueue() {
  const current = queue;
  queue = null;
  if (current) await current.close();
}
