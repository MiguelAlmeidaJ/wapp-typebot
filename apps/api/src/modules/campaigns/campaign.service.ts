import type { Prisma } from "../../generated/prisma/client.js";
import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import { segmentDefinitionSchema } from "../segments/segment.definition.js";
import {
  buildSegmentWhere,
  resolveSavedSegment
} from "../segments/segment.service.js";
import { recordTicketEvent } from "../tickets/ticket-event.service.js";
import {
  campaignWindowError,
  composeCampaignBody,
  MAX_CAMPAIGN_AUDIENCE,
  nextCampaignDispatchAt,
  plannedCampaignSendAt
} from "./campaign.policy.js";

function requiredJson(value: unknown): Prisma.InputJsonValue {
  const json = toPrismaJson(value);
  if (json === undefined) {
    throw new AppError(
      "Não foi possível serializar a definição do segmento.",
      500,
      "CAMPAIGN_SEGMENT_SERIALIZATION_FAILED"
    );
  }
  return json;
}

function getObject(value: unknown) {
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : undefined;
}

function sentExternalId(result: unknown) {
  const body = getObject(result);
  const key = getObject(body?.key);
  const id = typeof key?.id === "string" ? key.id : undefined;
  if (!id) throw new Error("WhatsApp provider did not return a message id.");
  return id;
}

function sentTimestamp(result: unknown) {
  const body = getObject(result);
  const raw = body?.messageTimestamp;
  const seconds =
    typeof raw === "number" ? raw :
    typeof raw === "string" ? Number(raw) :
    NaN;
  return Number.isFinite(seconds) ? new Date(seconds * 1000) : new Date();
}

function windowMessage(code: string) {
  const map: Record<string, string> = {
    INVALID_WINDOW: "A janela de envio é inválida.",
    START_TOO_SOON: "A janela deve começar com pelo menos 30 segundos de antecedência.",
    END_BEFORE_START: "O fim da janela deve ser posterior ao início.",
    WINDOW_TOO_LONG: "A janela de envio não pode ultrapassar 24 horas.",
    INVALID_RATE: "A taxa deve ficar entre 1 e 10 mensagens por minuto.",
    NO_ELIGIBLE_RECIPIENTS: "O segmento não possui contatos com consentimento explícito.",
    WINDOW_CAPACITY_EXCEEDED: "A audiência não cabe na janela com a taxa escolhida."
  };
  return map[code] ?? "Configuração de envio inválida.";
}

async function requireCampaign(companyId: string, campaignId: string) {
  const campaign = await prisma.campaign.findFirst({
    where: { id: campaignId, companyId },
    include: {
      segment: true,
      whatsappConnection: true,
      createdByMembership: { include: { user: true } }
    }
  });
  if (!campaign) {
    throw new AppError("Campanha não encontrada.", 404, "CAMPAIGN_NOT_FOUND");
  }
  return campaign;
}

async function addEvent(input: {
  companyId: string;
  campaignId: string;
  actorMembershipId: string | null;
  type: "CREATED" | "UPDATED" | "STARTED" | "CANCELLED" | "COMPLETED" | "FAILED";
  metadata?: Record<string, unknown>;
}) {
  return prisma.campaignEvent.create({
    data: {
      companyId: input.companyId,
      campaignId: input.campaignId,
      actorMembershipId: input.actorMembershipId,
      type: input.type,
      ...(input.metadata ? { metadata: toPrismaJson(input.metadata) } : {})
    }
  });
}

export async function listCampaigns(companyId: string) {
  const campaigns = await prisma.campaign.findMany({
    where: { companyId },
    include: {
      segment: { select: { id: true, name: true, isActive: true } },
      whatsappConnection: {
        select: { id: true, name: true, status: true, phoneNumber: true }
      },
      createdByMembership: {
        select: { id: true, user: { select: { id: true, name: true } } }
      }
    },
    orderBy: { updatedAt: "desc" },
    take: 100
  });

  const ids = campaigns.map(item => item.id);
  const grouped = ids.length
    ? await prisma.campaignRecipient.groupBy({
        by: ["campaignId", "status"],
        where: { campaignId: { in: ids } },
        _count: { _all: true }
      })
    : [];

  const map = new Map<string, Record<string, number>>();
  for (const row of grouped) {
    const current = map.get(row.campaignId) ?? {};
    current[row.status] = row._count._all;
    map.set(row.campaignId, current);
  }

  return campaigns.map(item => ({
    ...item,
    recipientStatus: map.get(item.id) ?? {}
  }));
}

export async function getCampaignContext(companyId: string) {
  const [segments, connections] = await Promise.all([
    prisma.contactSegment.findMany({
      where: { companyId, isActive: true },
      select: { id: true, name: true, description: true },
      orderBy: { name: "asc" }
    }),
    prisma.whatsAppConnection.findMany({
      where: { companyId },
      select: { id: true, name: true, status: true, phoneNumber: true },
      orderBy: { name: "asc" }
    })
  ]);
  return { segments, connections };
}

function validateDraftWindow(
  startAt: Date,
  endAt: Date,
  ratePerMinute: number
) {
  const error = campaignWindowError({
    now: new Date(0),
    startAt,
    endAt,
    eligibleRecipients: 1,
    ratePerMinute
  });
  if (error && error !== "START_TOO_SOON") {
    throw new AppError(
      windowMessage(error),
      422,
      "CAMPAIGN_WINDOW_INVALID"
    );
  }
}

export async function createCampaign(input: {
  companyId: string;
  actorMembershipId: string;
  segmentId: string;
  whatsappConnectionId: string;
  name: string;
  body: string;
  ratePerMinute: number;
  windowStartAt: Date;
  windowEndAt: Date;
}) {
  const [segment, connection] = await Promise.all([
    prisma.contactSegment.findFirst({
      where: { id: input.segmentId, companyId: input.companyId, isActive: true }
    }),
    prisma.whatsAppConnection.findFirst({
      where: { id: input.whatsappConnectionId, companyId: input.companyId }
    })
  ]);
  if (!segment) {
    throw new AppError(
      "Segmento não encontrado ou arquivado.",
      422,
      "CAMPAIGN_SEGMENT_INVALID"
    );
  }
  if (!connection) {
    throw new AppError(
      "Conexão WhatsApp não encontrada.",
      422,
      "CAMPAIGN_CONNECTION_INVALID"
    );
  }

  const body = input.body.trim();
  if (!body || body.length > 3800) {
    throw new AppError(
      "A mensagem deve ter entre 1 e 3800 caracteres.",
      422,
      "CAMPAIGN_BODY_INVALID"
    );
  }

  validateDraftWindow(
    input.windowStartAt,
    input.windowEndAt,
    input.ratePerMinute
  );

  const campaign = await prisma.campaign.create({
    data: {
      companyId: input.companyId,
      segmentId: segment.id,
      whatsappConnectionId: connection.id,
      createdByMembershipId: input.actorMembershipId,
      name: input.name.trim(),
      body,
      ratePerMinute: input.ratePerMinute,
      windowStartAt: input.windowStartAt,
      windowEndAt: input.windowEndAt
    }
  });

  await addEvent({
    companyId: input.companyId,
    campaignId: campaign.id,
    actorMembershipId: input.actorMembershipId,
    type: "CREATED"
  });

  publishRealtime(input.companyId, {
    type: "campaign.updated",
    campaignId: campaign.id,
    membershipId: input.actorMembershipId
  });

  return campaign;
}

export async function updateCampaign(input: {
  companyId: string;
  actorMembershipId: string;
  campaignId: string;
  segmentId?: string;
  whatsappConnectionId?: string;
  name?: string;
  body?: string;
  ratePerMinute?: number;
  windowStartAt?: Date;
  windowEndAt?: Date;
}) {
  const campaign = await requireCampaign(input.companyId, input.campaignId);
  if (campaign.status !== "DRAFT") {
    throw new AppError(
      "Somente rascunhos podem ser editados.",
      409,
      "CAMPAIGN_NOT_DRAFT"
    );
  }

  if (input.segmentId) {
    const segment = await prisma.contactSegment.findFirst({
      where: { id: input.segmentId, companyId: input.companyId, isActive: true }
    });
    if (!segment) throw new AppError(
      "Segmento não encontrado ou arquivado.",
      422,
      "CAMPAIGN_SEGMENT_INVALID"
    );
  }

  if (input.whatsappConnectionId) {
    const connection = await prisma.whatsAppConnection.findFirst({
      where: {
        id: input.whatsappConnectionId,
        companyId: input.companyId
      }
    });
    if (!connection) throw new AppError(
      "Conexão WhatsApp não encontrada.",
      422,
      "CAMPAIGN_CONNECTION_INVALID"
    );
  }

  const nextBody = input.body !== undefined ? input.body.trim() : campaign.body;
  if (!nextBody || nextBody.length > 3800) {
    throw new AppError(
      "A mensagem deve ter entre 1 e 3800 caracteres.",
      422,
      "CAMPAIGN_BODY_INVALID"
    );
  }

  const nextStart = input.windowStartAt ?? campaign.windowStartAt;
  const nextEnd = input.windowEndAt ?? campaign.windowEndAt;
  const nextRate = input.ratePerMinute ?? campaign.ratePerMinute;
  validateDraftWindow(nextStart, nextEnd, nextRate);

  const updated = await prisma.campaign.update({
    where: { id: campaign.id },
    data: {
      ...(input.segmentId ? { segmentId: input.segmentId } : {}),
      ...(input.whatsappConnectionId
        ? { whatsappConnectionId: input.whatsappConnectionId }
        : {}),
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(input.body !== undefined ? { body: nextBody } : {}),
      ...(input.ratePerMinute !== undefined ? { ratePerMinute: nextRate } : {}),
      ...(input.windowStartAt ? { windowStartAt: nextStart } : {}),
      ...(input.windowEndAt ? { windowEndAt: nextEnd } : {})
    }
  });

  await addEvent({
    companyId: input.companyId,
    campaignId: campaign.id,
    actorMembershipId: input.actorMembershipId,
    type: "UPDATED"
  });

  publishRealtime(input.companyId, {
    type: "campaign.updated",
    campaignId: campaign.id,
    membershipId: input.actorMembershipId
  });

  return updated;
}

export async function previewCampaignAudience(input: {
  companyId: string;
  campaignId: string;
}) {
  const campaign = await requireCampaign(input.companyId, input.campaignId);

  await resolveSavedSegment({
    companyId: input.companyId,
    segmentId: campaign.segmentId,
    limit: 1
  });

  const definition = segmentDefinitionSchema.parse(campaign.segment.definition);
  const where = buildSegmentWhere({
    companyId: input.companyId,
    definition,
    now: new Date()
  });

  const segmentContacts = await prisma.contact.count({ where });

  if (segmentContacts > MAX_CAMPAIGN_AUDIENCE) {
    return {
      segmentContacts,
      eligibleRecipients: 0,
      optedOutRecipients: 0,
      unknownConsent: 0,
      blocked: true,
      blockReason:
        `A audiência excede o limite inicial de ${MAX_CAMPAIGN_AUDIENCE} contatos. Refine o segmento.`,
      estimatedLastSendAt: null
    };
  }

  const contacts = await prisma.contact.findMany({
    where,
    select: {
      id: true,
      campaignConsent: { select: { status: true } }
    }
  });

  let eligibleRecipients = 0;
  let optedOutRecipients = 0;
  let unknownConsent = 0;

  for (const contact of contacts) {
    const status = contact.campaignConsent?.status;
    if (status === "OPTED_IN") eligibleRecipients += 1;
    else if (status === "OPTED_OUT") optedOutRecipients += 1;
    else unknownConsent += 1;
  }

  const error = campaignWindowError({
    now: new Date(),
    startAt: campaign.windowStartAt,
    endAt: campaign.windowEndAt,
    eligibleRecipients,
    ratePerMinute: campaign.ratePerMinute
  });

  return {
    segmentContacts,
    eligibleRecipients,
    optedOutRecipients,
    unknownConsent,
    blocked: Boolean(error),
    blockReason: error ? windowMessage(error) : null,
    estimatedLastSendAt: eligibleRecipients
      ? plannedCampaignSendAt(
          campaign.windowStartAt,
          eligibleRecipients - 1,
          campaign.ratePerMinute
        )
      : null
  };
}

export async function launchCampaign(input: {
  companyId: string;
  campaignId: string;
  actorMembershipId: string;
  confirmation: string;
  confirmedAudienceCount: number;
}) {
  if (input.confirmation !== "INICIAR CAMPANHA") {
    throw new AppError(
      "Digite INICIAR CAMPANHA para confirmar.",
      422,
      "CAMPAIGN_CONFIRMATION_REQUIRED"
    );
  }

  const campaign = await requireCampaign(input.companyId, input.campaignId);
  if (campaign.status !== "DRAFT") {
    throw new AppError(
      "A campanha não está mais em rascunho.",
      409,
      "CAMPAIGN_NOT_DRAFT"
    );
  }
  if (campaign.whatsappConnection.status !== "CONNECTED") {
    throw new AppError(
      "A conexão WhatsApp precisa estar conectada para iniciar.",
      409,
      "CAMPAIGN_CONNECTION_OFFLINE"
    );
  }

  const preview = await previewCampaignAudience({
    companyId: input.companyId,
    campaignId: campaign.id
  });

  if (preview.blocked) {
    throw new AppError(
      preview.blockReason ?? "A campanha não pode ser iniciada.",
      422,
      "CAMPAIGN_PREVIEW_BLOCKED"
    );
  }
  if (input.confirmedAudienceCount !== preview.eligibleRecipients) {
    throw new AppError(
      "A audiência mudou desde a última prévia. Revise antes de iniciar.",
      409,
      "CAMPAIGN_AUDIENCE_CHANGED"
    );
  }

  const definition = segmentDefinitionSchema.parse(campaign.segment.definition);
  const where = buildSegmentWhere({
    companyId: input.companyId,
    definition,
    now: new Date()
  });

  const contacts = await prisma.contact.findMany({
    where,
    select: {
      id: true,
      name: true,
      remoteJid: true,
      campaignConsent: { select: { status: true } }
    },
    orderBy: { id: "asc" }
  });

  if (contacts.length !== preview.segmentContacts) {
    throw new AppError(
      "A audiência mudou durante a confirmação. Gere uma nova prévia.",
      409,
      "CAMPAIGN_AUDIENCE_CHANGED"
    );
  }

  let sendIndex = 0;
  const recipients = contacts.map(contact => {
    const consent = contact.campaignConsent?.status;
    if (consent === "OPTED_IN") {
      const plannedFor = plannedCampaignSendAt(
        campaign.windowStartAt,
        sendIndex,
        campaign.ratePerMinute
      );
      sendIndex += 1;
      return {
        campaignId: campaign.id,
        contactId: contact.id,
        status: "PENDING" as const,
        snapshotName: contact.name,
        snapshotRemoteJid: contact.remoteJid,
        plannedFor
      };
    }
    return {
      campaignId: campaign.id,
      contactId: contact.id,
      status: "SUPPRESSED" as const,
      snapshotName: contact.name,
      snapshotRemoteJid: contact.remoteJid,
      exclusionReason:
        consent === "OPTED_OUT" ? "OPTED_OUT" : "NO_EXPLICIT_CONSENT",
      plannedFor: null
    };
  });

  const startedAt = new Date();
  await prisma.$transaction(async tx => {
    const changed = await tx.campaign.updateMany({
      where: {
        id: campaign.id,
        companyId: input.companyId,
        status: "DRAFT"
      },
      data: {
        status: "RUNNING",
        audienceSnapshotAt: startedAt,
        segmentDefinition: requiredJson(definition),
        segmentContacts: preview.segmentContacts,
        eligibleRecipients: preview.eligibleRecipients,
        optedOutRecipients: preview.optedOutRecipients,
        unknownConsent: preview.unknownConsent,
        startedAt,
        error: null
      }
    });

    if (changed.count !== 1) {
      throw new AppError(
        "A campanha já foi iniciada ou alterada.",
        409,
        "CAMPAIGN_ALREADY_STARTED"
      );
    }

    await tx.campaignRecipient.createMany({ data: recipients });
    await tx.campaignEvent.create({
      data: {
        companyId: input.companyId,
        campaignId: campaign.id,
        actorMembershipId: input.actorMembershipId,
        type: "STARTED",
        metadata: toPrismaJson({
          segmentContacts: preview.segmentContacts,
          eligibleRecipients: preview.eligibleRecipients,
          optedOutRecipients: preview.optedOutRecipients,
          unknownConsent: preview.unknownConsent
        })
      }
    });
  });

  const pending = await prisma.campaignRecipient.findMany({
    where: { campaignId: campaign.id, status: "PENDING" },
    select: { id: true, plannedFor: true },
    orderBy: { plannedFor: "asc" }
  });

  publishRealtime(input.companyId, {
    type: "campaign.updated",
    campaignId: campaign.id,
    membershipId: input.actorMembershipId
  });

  return {
    campaignId: campaign.id,
    recipients: pending.filter(
      (item): item is { id: string; plannedFor: Date } =>
        Boolean(item.plannedFor)
    )
  };
}

export async function cancelCampaign(input: {
  companyId: string;
  campaignId: string;
  actorMembershipId: string;
}) {
  const campaign = await requireCampaign(input.companyId, input.campaignId);
  if (!["DRAFT", "RUNNING"].includes(campaign.status)) {
    throw new AppError(
      "Somente campanhas em rascunho ou execução podem ser canceladas.",
      409,
      "CAMPAIGN_NOT_CANCELLABLE"
    );
  }

  const now = new Date();
  await prisma.$transaction(async tx => {
    const changed = await tx.campaign.updateMany({
      where: {
        id: campaign.id,
        status: { in: ["DRAFT", "RUNNING"] }
      },
      data: { status: "CANCELLED", cancelledAt: now }
    });
    if (changed.count !== 1) {
      throw new AppError(
        "A campanha já mudou de estado.",
        409,
        "CAMPAIGN_STATE_CHANGED"
      );
    }

    await tx.campaignRecipient.updateMany({
      where: { campaignId: campaign.id, status: "PENDING" },
      data: {
        status: "CANCELLED",
        exclusionReason: "CAMPAIGN_CANCELLED"
      }
    });

    await tx.campaignEvent.create({
      data: {
        companyId: input.companyId,
        campaignId: campaign.id,
        actorMembershipId: input.actorMembershipId,
        type: "CANCELLED"
      }
    });
  });

  publishRealtime(input.companyId, {
    type: "campaign.updated",
    campaignId: campaign.id,
    membershipId: input.actorMembershipId
  });
}

export async function listCampaignRecipients(input: {
  companyId: string;
  campaignId: string;
  limit: number;
}) {
  await requireCampaign(input.companyId, input.campaignId);
  return prisma.campaignRecipient.findMany({
    where: { campaignId: input.campaignId },
    include: {
      contact: {
        select: {
          id: true,
          name: true,
          phoneNumber: true,
          email: true
        }
      }
    },
    orderBy: [{ plannedFor: "asc" }, { createdAt: "asc" }],
    take: Math.min(Math.max(input.limit, 1), 500)
  });
}

export async function refreshCampaignCompletion(campaignId: string) {
  const campaign = await prisma.campaign.findUnique({
    where: { id: campaignId },
    select: { id: true, companyId: true, status: true }
  });
  if (!campaign || campaign.status !== "RUNNING") return;

  const active = await prisma.campaignRecipient.count({
    where: {
      campaignId,
      status: { in: ["PENDING", "PROCESSING"] }
    }
  });
  if (active > 0) return;

  const changed = await prisma.campaign.updateMany({
    where: { id: campaignId, status: "RUNNING" },
    data: { status: "COMPLETED", completedAt: new Date() }
  });

  if (changed.count === 1) {
    await addEvent({
      companyId: campaign.companyId,
      campaignId,
      actorMembershipId: null,
      type: "COMPLETED"
    });
    publishRealtime(campaign.companyId, {
      type: "campaign.updated",
      campaignId
    });
  }
}

async function ensureOutboundTicket(input: {
  campaignId: string;
  companyId: string;
  contactId: string;
  connectionId: string;
  defaultQueueId: string | null;
  timestamp: Date;
}) {
  const key = `${input.connectionId}:${input.contactId}`;
  const before = await prisma.ticket.findUnique({
    where: { activeKey: key },
    select: { id: true }
  });

  const ticket = await prisma.ticket.upsert({
    where: { activeKey: key },
    update: {},
    create: {
      companyId: input.companyId,
      whatsappConnectionId: input.connectionId,
      contactId: input.contactId,
      queueId: input.defaultQueueId,
      activeKey: key,
      status: "OPEN",
      lastMessageAt: input.timestamp,
      lastOutboundAt: input.timestamp
    }
  });

  if (!before) {
    await recordTicketEvent({
      companyId: input.companyId,
      ticketId: ticket.id,
      type: "CREATED",
      metadata: {
        source: "CAMPAIGN",
        campaignId: input.campaignId,
        initialDirection: "OUTBOUND"
      }
    });
    publishRealtime(input.companyId, {
      type: "ticket.created",
      ticketId: ticket.id
    });
  }
  return ticket;
}

export async function deliverCampaignRecipient(recipientId: string) {
  const recipient = await prisma.campaignRecipient.findUnique({
    where: { id: recipientId },
    include: {
      contact: { include: { campaignConsent: true } },
      campaign: {
        include: {
          whatsappConnection: true,
          createdByMembership: { include: { user: true } }
        }
      }
    }
  });

  if (!recipient || recipient.status !== "PENDING" || !recipient.plannedFor) {
    return { delivered: false, reason: "not_pending" };
  }

  const now = new Date();
  if (recipient.plannedFor.getTime() > now.getTime() + 2000) {
    return { delivered: false, reason: "not_due" };
  }

  if (recipient.campaign.status !== "RUNNING") {
    await prisma.campaignRecipient.update({
      where: { id: recipient.id },
      data: { status: "CANCELLED", exclusionReason: "CAMPAIGN_NOT_RUNNING" }
    });
    return { delivered: false, reason: "campaign_not_running" };
  }

  if (now > recipient.campaign.windowEndAt) {
    await prisma.campaignRecipient.update({
      where: { id: recipient.id },
      data: {
        status: "FAILED",
        error: "A janela de envio encerrou antes do processamento."
      }
    });
    await refreshCampaignCompletion(recipient.campaignId);
    return { delivered: false, reason: "window_expired" };
  }

  if (
    recipient.contact.isGroup ||
    recipient.contact.campaignConsent?.status !== "OPTED_IN"
  ) {
    await prisma.campaignRecipient.update({
      where: { id: recipient.id },
      data: {
        status: "SUPPRESSED",
        exclusionReason: recipient.contact.isGroup
          ? "GROUP_NOT_ELIGIBLE"
          : "CONSENT_NOT_ACTIVE"
      }
    });
    await refreshCampaignCompletion(recipient.campaignId);
    return { delivered: false, reason: "suppressed" };
  }

  if (recipient.campaign.whatsappConnection.status !== "CONNECTED") {
    await prisma.campaignRecipient.update({
      where: { id: recipient.id },
      data: {
        status: "FAILED",
        error: "A conexão WhatsApp estava offline no momento do envio."
      }
    });
    await refreshCampaignCompletion(recipient.campaignId);
    return { delivered: false, reason: "connection_offline" };
  }

  const lastActivity =
    await prisma.campaignRecipient.findFirst({
      where: {
        campaignId: recipient.campaignId,
        id: { not: recipient.id },
        OR: [
          {
            status: "SENT",
            sentAt: { not: null }
          },
          {
            status: "PROCESSING",
            claimedAt: { not: null }
          }
        ]
      },
      orderBy: { updatedAt: "desc" },
      select: {
        sentAt: true,
        claimedAt: true
      }
    });

  const lastActivityAt =
    lastActivity?.sentAt ??
    lastActivity?.claimedAt ??
    null;

  const nextAllowedAt = nextCampaignDispatchAt({
    now,
    lastActivityAt,
    ratePerMinute: recipient.campaign.ratePerMinute
  });

  if (nextAllowedAt.getTime() > now.getTime()) {
    if (
      nextAllowedAt.getTime() >
      recipient.campaign.windowEndAt.getTime()
    ) {
      await prisma.campaignRecipient.updateMany({
        where: {
          id: recipient.id,
          status: "PENDING"
        },
        data: {
          status: "FAILED",
          error:
            "A janela de envio terminou antes do próximo slot seguro da campanha."
        }
      });
      await refreshCampaignCompletion(recipient.campaignId);
      return {
        delivered: false,
        reason: "rate_window_expired" as const,
        rescheduleAt: null
      };
    }

    const rescheduled =
      await prisma.campaignRecipient.updateMany({
        where: {
          id: recipient.id,
          status: "PENDING"
        },
        data: {
          plannedFor: nextAllowedAt
        }
      });

    if (rescheduled.count !== 1) {
      return {
        delivered: false,
        reason: "already_claimed" as const,
        rescheduleAt: null
      };
    }

    return {
      delivered: false,
      reason: "rate_limited" as const,
      rescheduleAt: nextAllowedAt
    };
  }

  const claimed = await prisma.campaignRecipient.updateMany({
    where: { id: recipient.id, status: "PENDING" },
    data: { status: "PROCESSING", claimedAt: now, error: null }
  });
  if (claimed.count !== 1) return { delivered: false, reason: "already_claimed" };

  const body = composeCampaignBody({
    template: recipient.campaign.body,
    contactName: recipient.snapshotName
  });

  try {
    const result = await evolutionWhatsAppClient.sendText({
      instanceName: recipient.campaign.whatsappConnection.instanceName,
      number: recipient.snapshotRemoteJid,
      text: body
    });

    const externalId = sentExternalId(result);
    const timestamp = sentTimestamp(result);

    const ticket = await ensureOutboundTicket({
      campaignId: recipient.campaignId,
      companyId: recipient.campaign.companyId,
      contactId: recipient.contactId,
      connectionId: recipient.campaign.whatsappConnectionId,
      defaultQueueId: recipient.campaign.whatsappConnection.defaultQueueId,
      timestamp
    });

    const message = await prisma.message.create({
      data: {
        companyId: recipient.campaign.companyId,
        ticketId: ticket.id,
        whatsappConnectionId: recipient.campaign.whatsappConnectionId,
        sentByUserId: recipient.campaign.createdByMembership.userId,
        externalId,
        direction: "OUTBOUND",
        type: "TEXT",
        deliveryStatus: "PENDING",
        body,
        timestamp,
        rawPayload: toPrismaJson(result)
      }
    });

    await prisma.ticket.update({
      where: { id: ticket.id },
      data: {
        lastMessage: body,
        lastMessageAt: timestamp,
        lastOutboundAt: timestamp,
        waitingSince: null,
        ...(ticket.firstInboundAt && !ticket.firstResponseAt
          ? { firstResponseAt: timestamp }
          : {})
      }
    });

    await prisma.campaignRecipient.update({
      where: { id: recipient.id },
      data: {
        status: "SENT",
        sentAt: timestamp,
        externalId,
        ticketId: ticket.id,
        messageId: message.id,
        error: null
      }
    });

    publishRealtime(recipient.campaign.companyId, {
      type: "message.created",
      ticketId: ticket.id,
      messageId: message.id
    });
    publishRealtime(recipient.campaign.companyId, {
      type: "campaign.updated",
      campaignId: recipient.campaignId
    });

    await refreshCampaignCompletion(recipient.campaignId);
    return { delivered: true, messageId: message.id };
  } catch (error) {
    const detail = error instanceof Error ? error.message : "Falha desconhecida.";
    await prisma.campaignRecipient.updateMany({
      where: { id: recipient.id, status: "PROCESSING" },
      data: {
        status: "FAILED",
        error:
          `Falha após tentativa de envio; não reenviado para evitar duplicidade. ${detail}`
            .slice(0, 1000)
      }
    });
    await refreshCampaignCompletion(recipient.campaignId);
    return { delivered: false, reason: "send_failed_no_retry" };
  }
}

export async function reconcileCampaignRecipients() {
  const staleBefore = new Date(Date.now() - 15 * 60 * 1000);
  const stale = await prisma.campaignRecipient.findMany({
    where: {
      status: "PROCESSING",
      claimedAt: { lt: staleBefore }
    },
    select: { id: true, campaignId: true },
    take: 100
  });

  for (const item of stale) {
    await prisma.campaignRecipient.updateMany({
      where: {
        id: item.id,
        status: "PROCESSING",
        claimedAt: { lt: staleBefore }
      },
      data: {
        status: "FAILED",
        error:
          "Processamento interrompido em estado incerto; não reenviado para evitar duplicidade."
      }
    });
    await refreshCampaignCompletion(item.campaignId);
  }

  return prisma.campaignRecipient.findMany({
    where: {
      status: "PENDING",
      plannedFor: {
        not: null,
        lte: new Date(Date.now() + 10 * 60 * 1000)
      },
      campaign: { status: "RUNNING" }
    },
    select: { id: true, plannedFor: true },
    orderBy: { plannedFor: "asc" },
    take: 200
  });
}
