import fs from "node:fs";

const schema = fs.readFileSync("apps/api/prisma/schema.prisma", "utf8");
const service = fs.readFileSync(
  "apps/api/src/modules/campaigns/campaign.service.ts",
  "utf8"
);
const consent = fs.readFileSync(
  "apps/api/src/modules/campaigns/campaign-consent.service.ts",
  "utf8"
);
const ingestion = fs.readFileSync(
  "apps/api/src/modules/messages/message-ingestion.service.ts",
  "utf8"
);
const worker = fs.readFileSync(
  "apps/api/src/jobs/campaign.worker.ts",
  "utf8"
);

for (const marker of [
  "model Campaign {",
  "model CampaignRecipient {",
  "model ContactCampaignConsent {"
]) {
  if (!schema.includes(marker)) throw new Error(`P3.5 schema marker missing: ${marker}`);
}

for (const marker of [
  "eligibleRecipients",
  "NO_EXPLICIT_CONSENT",
  "composeCampaignBody",
  "confirmedAudienceCount",
  "INICIAR CAMPANHA"
]) {
  if (!service.includes(marker)) throw new Error(`P3.5 service marker missing: ${marker}`);
}

if (!consent.includes("campaign.consent.updated")) {
  throw new Error("P3.5 consent realtime marker missing.");
}
if (!ingestion.includes("applyInboundCampaignOptOut")) {
  throw new Error("P3.5 inbound opt-out integration missing.");
}
if (!worker.includes("limiter:")) {
  throw new Error("P3.5 campaign worker limiter missing.");
}

console.log("[P3.5] campaign smoke PASS");
