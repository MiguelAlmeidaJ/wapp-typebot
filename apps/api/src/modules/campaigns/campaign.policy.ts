import type { WappRole } from "../../lib/tokens.js";

export const MAX_CAMPAIGN_AUDIENCE = 500;
export const CAMPAIGN_OPT_OUT_FOOTER =
  "Para não receber mais mensagens, responda SAIR.";

const OPT_OUT = new Set([
  "sair",
  "parar",
  "cancelar",
  "remover",
  "nao quero receber",
  "não quero receber"
]);

export function isCampaignOptOutKeyword(value: string | null | undefined) {
  const normalized = (value ?? "")
    .trim()
    .toLocaleLowerCase("pt-BR")
    .replace(/[.!?,;:]+$/g, "")
    .replace(/\s+/g, " ");
  return OPT_OUT.has(normalized);
}

export function canSendCampaign(role: WappRole) {
  return role === "OWNER" || role === "ADMIN";
}

export function composeCampaignBody(input: {
  template: string;
  contactName: string;
}) {
  const name = input.contactName.trim();
  const firstName = name.split(/\s+/)[0] ?? name;
  const body = input.template
    .replaceAll("{{nome}}", name)
    .replaceAll("{{primeiro_nome}}", firstName)
    .trim();
  return `${body}\n\n${CAMPAIGN_OPT_OUT_FOOTER}`;
}

export function plannedCampaignSendAt(
  startAt: Date,
  index: number,
  ratePerMinute: number
) {
  return new Date(
    startAt.getTime() +
      Math.floor(index * (60_000 / ratePerMinute))
  );
}

export function campaignWindowError(input: {
  now: Date;
  startAt: Date;
  endAt: Date;
  eligibleRecipients: number;
  ratePerMinute: number;
}) {
  if (!Number.isFinite(input.startAt.getTime()) ||
      !Number.isFinite(input.endAt.getTime())) return "INVALID_WINDOW";
  if (input.startAt.getTime() - input.now.getTime() < 30_000) return "START_TOO_SOON";
  if (input.endAt <= input.startAt) return "END_BEFORE_START";
  if (input.endAt.getTime() - input.startAt.getTime() > 86_400_000) return "WINDOW_TOO_LONG";
  if (input.ratePerMinute < 1 || input.ratePerMinute > 10) return "INVALID_RATE";
  if (input.eligibleRecipients <= 0) return "NO_ELIGIBLE_RECIPIENTS";
  const last = plannedCampaignSendAt(
    input.startAt,
    input.eligibleRecipients - 1,
    input.ratePerMinute
  );
  return last > input.endAt ? "WINDOW_CAPACITY_EXCEEDED" : null;
}
