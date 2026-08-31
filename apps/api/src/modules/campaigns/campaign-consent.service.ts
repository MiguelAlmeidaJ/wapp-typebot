import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import { isCampaignOptOutKeyword } from "./campaign.policy.js";
import { refreshCampaignCompletion } from "./campaign.service.js";

async function requireDirectContact(companyId: string, contactId: string) {
  const contact = await prisma.contact.findFirst({
    where: { id: contactId, companyId, isGroup: false },
    select: { id: true, name: true }
  });
  if (!contact) {
    throw new AppError(
      "Contato não encontrado ou não elegível para campanhas.",
      404,
      "CAMPAIGN_CONTACT_NOT_FOUND"
    );
  }
  return contact;
}

async function suppressPendingCampaignRecipients(input: {
  companyId: string;
  contactId: string;
  reason: string;
}) {
  const affected =
    await prisma.campaignRecipient.findMany({
      where: {
        contactId: input.contactId,
        status: "PENDING",
        campaign: {
          companyId: input.companyId,
          status: "RUNNING"
        }
      },
      select: {
        campaignId: true
      }
    });

  if (affected.length === 0) return;

  await prisma.campaignRecipient.updateMany({
    where: {
      contactId: input.contactId,
      status: "PENDING",
      campaign: {
        companyId: input.companyId,
        status: "RUNNING"
      }
    },
    data: {
      status: "SUPPRESSED",
      exclusionReason: input.reason
    }
  });

  for (const campaignId of new Set(
    affected.map(item => item.campaignId)
  )) {
    await refreshCampaignCompletion(campaignId);
  }
}

export async function getCampaignConsent(companyId: string, contactId: string) {
  const contact = await requireDirectContact(companyId, contactId);
  const consent = await prisma.contactCampaignConsent.findUnique({
    where: { contactId: contact.id },
    include: {
      updatedByMembership: {
        select: { id: true, user: { select: { id: true, name: true } } }
      }
    }
  });
  return { status: consent?.status ?? "UNKNOWN", consent };
}

export async function setCampaignConsent(input: {
  companyId: string;
  contactId: string;
  actorMembershipId: string;
  status: "OPTED_IN" | "OPTED_OUT";
  note?: string | null;
}) {
  const contact = await requireDirectContact(input.companyId, input.contactId);
  const consent = await prisma.contactCampaignConsent.upsert({
    where: { contactId: contact.id },
    create: {
      companyId: input.companyId,
      contactId: contact.id,
      updatedByMembershipId: input.actorMembershipId,
      status: input.status,
      source: "MANUAL",
      note: input.note?.trim().slice(0, 500) || null
    },
    update: {
      updatedByMembershipId: input.actorMembershipId,
      status: input.status,
      source: "MANUAL",
      note: input.note?.trim().slice(0, 500) || null
    }
  });

  if (input.status === "OPTED_OUT") {
    await suppressPendingCampaignRecipients({
      companyId: input.companyId,
      contactId: contact.id,
      reason: "OPTED_OUT_AFTER_START"
    });
  }

  publishRealtime(input.companyId, {
    type: "campaign.consent.updated",
    contactId: contact.id,
    membershipId: input.actorMembershipId
  });

  return consent;
}

export async function applyInboundCampaignOptOut(input: {
  companyId: string;
  contactId: string;
  body: string | null | undefined;
}) {
  if (!isCampaignOptOutKeyword(input.body)) return { changed: false };

  const contact = await prisma.contact.findFirst({
    where: { id: input.contactId, companyId: input.companyId, isGroup: false },
    select: { id: true }
  });
  if (!contact) return { changed: false };

  await prisma.contactCampaignConsent.upsert({
    where: { contactId: contact.id },
    create: {
      companyId: input.companyId,
      contactId: contact.id,
      status: "OPTED_OUT",
      source: "INBOUND_KEYWORD",
      note: "Opt-out recebido pelo WhatsApp."
    },
    update: {
      status: "OPTED_OUT",
      source: "INBOUND_KEYWORD",
      updatedByMembershipId: null,
      note: "Opt-out recebido pelo WhatsApp."
    }
  });

  await suppressPendingCampaignRecipients({
    companyId: input.companyId,
    contactId: contact.id,
    reason: "INBOUND_OPT_OUT"
  });

  publishRealtime(input.companyId, {
    type: "campaign.consent.updated",
    contactId: contact.id
  });

  return { changed: true };
}
