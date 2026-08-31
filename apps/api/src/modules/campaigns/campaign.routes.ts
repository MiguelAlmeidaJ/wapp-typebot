import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../errors/app-error.js";
import { enqueueCampaignRecipient } from "../../jobs/campaign.queue.js";
import { requirePermission } from "../auth/auth.guard.js";
import {
  getCampaignConsent,
  setCampaignConsent
} from "./campaign-consent.service.js";
import {
  cancelCampaign,
  createCampaign,
  getCampaignContext,
  launchCampaign,
  listCampaignRecipients,
  listCampaigns,
  previewCampaignAudience,
  updateCampaign
} from "./campaign.service.js";
import { canSendCampaign } from "./campaign.policy.js";

const idSchema = z.object({ id: z.string().uuid() });

const campaignInput = z.object({
  segmentId: z.string().uuid(),
  whatsappConnectionId: z.string().uuid(),
  name: z.string().trim().min(2).max(160),
  body: z.string().trim().min(1).max(3800),
  ratePerMinute: z.number().int().min(1).max(10).default(6),
  windowStartAt: z.string().datetime({ offset: true }),
  windowEndAt: z.string().datetime({ offset: true })
});

const campaignUpdate = campaignInput.partial().refine(
  value => Object.keys(value).length > 0,
  { message: "Informe ao menos uma alteração." }
);

const launchSchema = z.object({
  confirmation: z.literal("INICIAR CAMPANHA"),
  confirmedAudienceCount: z.number().int().min(1).max(500)
});

const consentSchema = z.object({
  status: z.enum(["OPTED_IN", "OPTED_OUT"]),
  note: z.string().trim().max(500).nullable().optional()
});

export async function campaignRoutes(app: FastifyInstance) {
  app.get("/api/v1/campaigns", async request => {
    const auth = await requirePermission(request, "campaigns.read");
    return { campaigns: await listCampaigns(auth.companyId) };
  });

  app.get("/api/v1/campaigns/context", async request => {
    const auth = await requirePermission(request, "campaigns.read");
    return getCampaignContext(auth.companyId);
  });

  app.post("/api/v1/campaigns", async (request, reply) => {
    const auth = await requirePermission(request, "campaigns.manage");
    const input = campaignInput.parse(request.body);
    return reply.status(201).send({
      campaign: await createCampaign({
        companyId: auth.companyId,
        actorMembershipId: auth.membershipId,
        ...input,
        windowStartAt: new Date(input.windowStartAt),
        windowEndAt: new Date(input.windowEndAt)
      })
    });
  });

  app.patch("/api/v1/campaigns/:id", async request => {
    const auth = await requirePermission(request, "campaigns.manage");
    const params = idSchema.parse(request.params);
    const input = campaignUpdate.parse(request.body);
    const { windowStartAt, windowEndAt, ...changes } = input;

    return {
      campaign: await updateCampaign({
        companyId: auth.companyId,
        actorMembershipId: auth.membershipId,
        campaignId: params.id,
        ...changes,
        ...(windowStartAt
          ? { windowStartAt: new Date(windowStartAt) }
          : {}),
        ...(windowEndAt
          ? { windowEndAt: new Date(windowEndAt) }
          : {})
      })
    };
  });

  app.post("/api/v1/campaigns/:id/preview", async request => {
    const auth = await requirePermission(request, "campaigns.read");
    const params = idSchema.parse(request.params);
    return previewCampaignAudience({
      companyId: auth.companyId,
      campaignId: params.id
    });
  });

  app.post("/api/v1/campaigns/:id/start", async request => {
    const auth = await requirePermission(request, "campaigns.send");
    if (!canSendCampaign(auth.role)) {
      throw new AppError(
        "Somente OWNER ou ADMIN podem iniciar campanhas.",
        403,
        "CAMPAIGN_SEND_FORBIDDEN"
      );
    }

    const params = idSchema.parse(request.params);
    const input = launchSchema.parse(request.body);
    const launched = await launchCampaign({
      companyId: auth.companyId,
      campaignId: params.id,
      actorMembershipId: auth.membershipId,
      ...input
    });

    let queued = 0;
    for (const recipient of launched.recipients) {
      try {
        if (await enqueueCampaignRecipient({
          recipientId:
            recipient.id,
          plannedFor:
            recipient.plannedFor
        })) queued += 1;
      } catch (error) {
        request.log.error(
          { error, recipientId: recipient.id },
          "campaign enqueue failed; sweep will reconcile"
        );
      }
    }

    return {
      campaignId: launched.campaignId,
      queued,
      durableRecipients: launched.recipients.length
    };
  });

  app.post("/api/v1/campaigns/:id/cancel", async request => {
    const auth = await requirePermission(request, "campaigns.manage");
    const params = idSchema.parse(request.params);
    await cancelCampaign({
      companyId: auth.companyId,
      campaignId: params.id,
      actorMembershipId: auth.membershipId
    });
    return { ok: true };
  });

  app.get("/api/v1/campaigns/:id/recipients", async request => {
    const auth = await requirePermission(request, "campaigns.read");
    const params = idSchema.parse(request.params);
    const query = z.object({
      limit: z.coerce.number().int().min(1).max(500).default(200)
    }).parse(request.query);

    return {
      recipients: await listCampaignRecipients({
        companyId: auth.companyId,
        campaignId: params.id,
        limit: query.limit
      })
    };
  });

  app.get("/api/v1/contacts/:id/campaign-consent", async request => {
    const auth = await requirePermission(request, "contacts.read");
    const params = idSchema.parse(request.params);
    return getCampaignConsent(auth.companyId, params.id);
  });

  app.put("/api/v1/contacts/:id/campaign-consent", async request => {
    const auth = await requirePermission(request, "contacts.manage");
    const params = idSchema.parse(request.params);
    const input = consentSchema.parse(request.body);
    return {
      consent: await setCampaignConsent({
        companyId: auth.companyId,
        contactId: params.id,
        actorMembershipId: auth.membershipId,
        ...input
      })
    };
  });
}
