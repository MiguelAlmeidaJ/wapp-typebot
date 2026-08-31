import { Worker } from "bullmq";
import {
  deliverCampaignRecipient,
  reconcileCampaignRecipients
} from "../modules/campaigns/campaign.service.js";
import {
  CAMPAIGN_QUEUE_NAME,
  CAMPAIGN_SEND_JOB,
  CAMPAIGN_SWEEP_JOB,
  enqueueCampaignRecipient
} from "./campaign.queue.js";
import { jobWorkerRedisOptions } from "./job-redis.js";

export function createCampaignWorker() {
  const worker = new Worker(
    CAMPAIGN_QUEUE_NAME,
    async job => {
      if (job.name === CAMPAIGN_SEND_JOB) {
        const recipientId =
          typeof job.data?.recipientId === "string"
            ? job.data.recipientId
            : null;
        if (!recipientId) throw new Error("recipientId is required.");
        return deliverCampaignRecipient(recipientId);
      }

      if (job.name === CAMPAIGN_SWEEP_JOB) {
        const pending = await reconcileCampaignRecipients();
        let queued = 0;
        for (const item of pending) {
          if (
            item.plannedFor &&
            await enqueueCampaignRecipient({
              recipientId: item.id,
              plannedFor: item.plannedFor
            })
          ) {
            queued += 1;
          }
        }
        return { queued };
      }

      throw new Error(`Unknown campaign job: ${job.name}`);
    },
    {
      connection: jobWorkerRedisOptions(),
      concurrency: 2,
      limiter: { max: 10, duration: 60_000 }
    }
  );

  worker.on("failed", (job, error) => {
    console.error("[campaigns] job failed", {
      jobId: job?.id,
      error: error.message
    });
  });

  return worker;
}
