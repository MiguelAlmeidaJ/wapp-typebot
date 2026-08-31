import fs from "node:fs";

const ci = fs.readFileSync(
  ".github/workflows/quality-gate.yml",
  "utf8"
);
const policy = fs.readFileSync(
  "apps/api/src/modules/campaigns/campaign.policy.ts",
  "utf8"
);
const queue = fs.readFileSync(
  "apps/api/src/jobs/campaign.queue.ts",
  "utf8"
);
const worker = fs.readFileSync(
  "apps/api/src/jobs/campaign.worker.ts",
  "utf8"
);
const service = fs.readFileSync(
  "apps/api/src/modules/campaigns/campaign.service.ts",
  "utf8"
);
const consent = fs.readFileSync(
  "apps/api/src/modules/campaigns/campaign-consent.service.ts",
  "utf8"
);
const integration = fs.readFileSync(
  "apps/api/src/integration/critical.integration.test.ts",
  "utf8"
);

for (const marker of [
  "DATABASE_URL: mysql://wapp_ci:",
  "SHADOW_DATABASE_URL: mysql://wapp_ci:"
]) {
  if (!ci.includes(marker)) {
    throw new Error(`CI marker missing: ${marker}`);
  }
}

for (const marker of [
  "nextCampaignDispatchAt",
  "rate_limited",
  "export async function refreshCampaignCompletion"
]) {
  if (!(policy + service).includes(marker)) {
    throw new Error(`Campaign pacing marker missing: ${marker}`);
  }
}

if (!queue.includes("input.plannedFor.getTime()")) {
  throw new Error("Reschedulable campaign job id missing.");
}
if (!worker.includes("concurrency: 1")) {
  throw new Error("Campaign worker single concurrency marker missing.");
}
if (!worker.includes('"rescheduleAt" in result')) {
  throw new Error("Campaign worker reschedule marker missing.");
}
if (!consent.includes("suppressPendingCampaignRecipients")) {
  throw new Error("Opt-out completion helper missing.");
}
if (!integration.includes(
  "P3 CRM chain: field, pipeline, task, segment and campaign consent"
)) {
  throw new Error("P3 integration chain missing.");
}

console.log("[P3.5.1] stabilization smoke PASS");
