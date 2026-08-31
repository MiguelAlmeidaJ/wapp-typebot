import assert from "node:assert/strict";
import { test } from "node:test";
import {
  campaignWindowError,
  canSendCampaign,
  composeCampaignBody,
  isCampaignOptOutKeyword,
  nextCampaignDispatchAt,
  plannedCampaignSendAt
} from "./campaign.policy.js";

test("campaign sending is owner/admin only", () => {
  assert.equal(canSendCampaign("OWNER"), true);
  assert.equal(canSendCampaign("ADMIN"), true);
  assert.equal(canSendCampaign("SUPERVISOR"), false);
});
test("opt-out is explicit", () => {
  assert.equal(isCampaignOptOutKeyword("SAIR"), true);
  assert.equal(isCampaignOptOutKeyword("Quero saber como sair depois"), false);
});
test("campaign body adds opt-out", () => {
  const body = composeCampaignBody({
    template: "Olá, {{primeiro_nome}}!",
    contactName: "Maria Silva"
  });
  assert.match(body, /Olá, Maria!/);
  assert.match(body, /responda SAIR/);
});
test("planned sends are spaced", () => {
  const start = new Date("2026-08-31T12:00:00.000Z");
  assert.equal(
    plannedCampaignSendAt(start, 5, 6).toISOString(),
    "2026-08-31T12:00:50.000Z"
  );
});
test("window capacity is enforced", () => {
  assert.equal(
    campaignWindowError({
      now: new Date("2026-08-31T11:00:00.000Z"),
      startAt: new Date("2026-08-31T12:00:00.000Z"),
      endAt: new Date("2026-08-31T12:01:00.000Z"),
      eligibleRecipients: 20,
      ratePerMinute: 10
    }),
    "WINDOW_CAPACITY_EXCEEDED"
  );
});


test("recovered campaign backlog keeps its configured cadence", () => {
  const now = new Date("2026-08-31T12:10:00.000Z");
  const lastActivityAt = new Date("2026-08-31T12:09:30.000Z");

  assert.equal(
    nextCampaignDispatchAt({
      now,
      lastActivityAt,
      ratePerMinute: 1
    }).toISOString(),
    "2026-08-31T12:10:30.000Z"
  );

  assert.equal(
    nextCampaignDispatchAt({
      now,
      lastActivityAt: null,
      ratePerMinute: 1
    }).toISOString(),
    now.toISOString()
  );
});
