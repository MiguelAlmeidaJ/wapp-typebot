import { Queue } from "bullmq";
import { env } from "../config/env.js";
import { jobProducerRedisOptions } from "./job-redis.js";

export const CAMPAIGN_QUEUE_NAME = "wapp-campaigns";
export const CAMPAIGN_SEND_JOB = "send-recipient";
export const CAMPAIGN_SWEEP_JOB = "sweep";
let queue: Queue | null = null;

export function getCampaignQueue() {
  queue ??= new Queue(CAMPAIGN_QUEUE_NAME, {
    connection: jobProducerRedisOptions()
  });
  return queue;
}

export async function enqueueCampaignRecipient(input: {
  recipientId: string;
  plannedFor: Date;
}) {
  if (!env.REDIS_URL) return false;
  await getCampaignQueue().add(
    CAMPAIGN_SEND_JOB,
    { recipientId: input.recipientId },
    {
      jobId: `campaign-recipient-${input.recipientId}`,
      delay: Math.max(0, input.plannedFor.getTime() - Date.now()),
      attempts: 1,
      removeOnComplete: { count: 5000 },
      removeOnFail: { count: 5000 }
    }
  );
  return true;
}

export async function ensureCampaignSweep() {
  if (!env.REDIS_URL) return;
  await getCampaignQueue().upsertJobScheduler(
    "wapp-campaign-sweep",
    { every: 60_000 },
    { name: CAMPAIGN_SWEEP_JOB, data: {} }
  );
}

export async function closeCampaignQueue() {
  const current = queue;
  queue = null;
  if (current) await current.close();
}
