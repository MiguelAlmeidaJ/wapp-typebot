import { Worker } from "bullmq";
import {
  deliverTaskReminder,
  reconcileTaskReminders
} from "../modules/tasks/task.service.js";
import { jobWorkerRedisOptions } from "./job-redis.js";
import {
  enqueueTaskReminder,
  TASK_REMINDER_DELIVER_JOB,
  TASK_REMINDER_QUEUE_NAME,
  TASK_REMINDER_SWEEP_JOB
} from "./task-reminder.queue.js";

export function createTaskReminderWorker() {
  const worker = new Worker(
    TASK_REMINDER_QUEUE_NAME,
    async job => {
      if (job.name === TASK_REMINDER_DELIVER_JOB) {
        const taskId =
          typeof job.data?.taskId === "string" ? job.data.taskId : null;
        const expectedRemindAt =
          typeof job.data?.expectedRemindAt === "string"
            ? job.data.expectedRemindAt
            : null;

        if (!taskId || !expectedRemindAt) {
          throw new Error("taskId and expectedRemindAt are required.");
        }

        return deliverTaskReminder(taskId, expectedRemindAt);
      }

      if (job.name === TASK_REMINDER_SWEEP_JOB) {
        const due = await reconcileTaskReminders();

        for (const task of due) {
          if (task.reminderAt) {
            await enqueueTaskReminder({
              taskId: task.id,
              reminderAt: task.reminderAt
            });
          }
        }

        return {
          queued: due.length
        };
      }

      throw new Error(`Unknown task reminder job: ${job.name}`);
    },
    {
      connection: jobWorkerRedisOptions(),
      concurrency: 3
    }
  );

  worker.on("failed", (job, error) => {
    console.error("[task-reminders] job failed", {
      jobId: job?.id,
      error: error.message
    });
  });

  return worker;
}
