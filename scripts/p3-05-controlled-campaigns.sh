#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEMA="apps/api/prisma/schema.prisma"
APP="apps/api/src/app.ts"
PERMISSIONS="apps/api/src/security/permissions.ts"
PERMISSIONS_TEST="apps/api/src/security/permissions.test.ts"
INGESTION="apps/api/src/modules/messages/message-ingestion.service.ts"
JOB_RUNTIME="apps/api/src/jobs/job-runtime.ts"
WORKER="apps/api/src/worker.ts"
REALTIME_API="apps/api/src/modules/realtime/realtime.bus.ts"
REALTIME_WEB="apps/web/lib/realtime-types.ts"
UI_PERMISSIONS="apps/web/lib/permissions.ts"
DASHBOARD="apps/web/app/dashboard/page.tsx"
CONTACTS_PAGE="apps/web/app/dashboard/contacts/page.tsx"
CSS="apps/web/app/globals.css"

echo "[P3.5] Installing controlled campaigns..."

for check in \
  "$SCHEMA|model ContactSegment {" \
  "$SCHEMA|model CrmTask {" \
  "apps/api/src/modules/segments/segment.service.ts|buildSegmentWhere" \
  "apps/api/src/modules/segments/segment.service.ts|resolveSavedSegment" \
  "apps/api/src/modules/segments/segment.definition.ts|segmentDefinitionSchema" \
  "$APP|await app.register(segmentRoutes);" \
  "$PERMISSIONS|segments.manage" \
  "$JOB_RUNTIME|createTaskReminderWorker()" \
  "$WORKER|createTaskReminderWorker()" \
  "$INGESTION|notifyInboundTicketActivity" \
  "$REALTIME_API|segment.updated" \
  "$UI_PERMISSIONS|segments.view" \
  "$DASHBOARD|href: \"/dashboard/segments\""
do
  file="${check%%|*}"
  marker="${check#*|}"
  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: P3.5 prerequisite missing: $file -> $marker"
    echo "P3.5 made no changes."
    exit 1
  fi
done

for required in "$PERMISSIONS_TEST" "$REALTIME_WEB" "$CONTACTS_PAGE" "$CSS"; do
  [[ -f "$required" ]] || { echo "ERROR: missing $required"; exit 1; }
done

mkdir -p apps/api/src/modules/campaigns apps/api/src/jobs \
  apps/api/prisma/migrations/20260829004500_controlled_campaigns \
  apps/web/app/dashboard/campaigns apps/web/components/contacts docs

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/prisma/schema.prisma";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("enum CampaignStatus {")) {
  const anchor = "enum MembershipRole {";
  const i = content.indexOf(anchor);
  if (i < 0) throw new Error("MembershipRole enum anchor not found.");
  content = content.slice(0, i) + `enum CampaignStatus {
  DRAFT
  RUNNING
  COMPLETED
  CANCELLED
  FAILED
}

enum CampaignRecipientStatus {
  PENDING
  PROCESSING
  SENT
  FAILED
  SUPPRESSED
  CANCELLED
}

enum CampaignEventType {
  CREATED
  UPDATED
  STARTED
  CANCELLED
  COMPLETED
  FAILED
}

enum CampaignConsentStatus {
  OPTED_IN
  OPTED_OUT
}

enum CampaignConsentSource {
  MANUAL
  INBOUND_KEYWORD
}

` + content.slice(i);
}

function bounds(model) {
  const start = content.indexOf(`model ${model} {`);
  if (start < 0) throw new Error(`${model} model not found.`);
  const end = content.indexOf("\n}", start);
  if (end < 0) throw new Error(`${model} model end not found.`);
  return { start, end };
}
function addRelation(model, field, line) {
  const b = bounds(model);
  const block = content.slice(b.start, b.end);
  if (block.includes(`\n  ${field} `)) return;
  content = content.slice(0, b.end) + `\n${line}` + content.slice(b.end);
}

addRelation("Company", "campaigns", "  campaigns                Campaign[]");
addRelation("Company", "campaignEvents", "  campaignEvents           CampaignEvent[]");
addRelation("Company", "campaignConsents", "  campaignConsents         ContactCampaignConsent[]");
addRelation("CompanyMembership", "createdCampaigns", "  createdCampaigns         Campaign[]");
addRelation("CompanyMembership", "campaignEvents", "  campaignEvents           CampaignEvent[]");
addRelation("CompanyMembership", "campaignConsentUpdates", "  campaignConsentUpdates   ContactCampaignConsent[]");
addRelation("Contact", "campaignConsent", "  campaignConsent          ContactCampaignConsent?");
addRelation("Contact", "campaignRecipients", "  campaignRecipients       CampaignRecipient[]");
addRelation("WhatsAppConnection", "campaigns", "  campaigns                Campaign[]");
addRelation("ContactSegment", "campaigns", "  campaigns                Campaign[]");

if (!content.includes("model ContactCampaignConsent {")) {
  content += `

model ContactCampaignConsent {
  id                    String                @id @default(uuid()) @db.Char(36)
  companyId             String                @db.Char(36)
  contactId             String                @unique @db.Char(36)
  updatedByMembershipId String?               @db.Char(36)
  status                CampaignConsentStatus
  source                CampaignConsentSource @default(MANUAL)
  note                  String?               @db.VarChar(500)
  company               Company               @relation(fields: [companyId], references: [id], onDelete: Cascade)
  contact               Contact               @relation(fields: [contactId], references: [id], onDelete: Cascade)
  updatedByMembership   CompanyMembership?    @relation(fields: [updatedByMembershipId], references: [id], onDelete: SetNull)
  createdAt             DateTime              @default(now())
  updatedAt             DateTime              @updatedAt

  @@index([companyId, status, updatedAt])
  @@index([updatedByMembershipId, updatedAt])
}

model Campaign {
  id                    String             @id @default(uuid()) @db.Char(36)
  companyId             String             @db.Char(36)
  segmentId             String             @db.Char(36)
  whatsappConnectionId  String             @db.Char(36)
  createdByMembershipId String             @db.Char(36)
  name                  String             @db.VarChar(160)
  body                  String             @db.Text
  status                CampaignStatus     @default(DRAFT)
  ratePerMinute         Int                @default(6)
  windowStartAt         DateTime
  windowEndAt           DateTime
  audienceSnapshotAt    DateTime?
  segmentDefinition     Json?
  segmentContacts       Int                @default(0)
  eligibleRecipients    Int                @default(0)
  optedOutRecipients    Int                @default(0)
  unknownConsent        Int                @default(0)
  startedAt             DateTime?
  completedAt           DateTime?
  cancelledAt           DateTime?
  error                 String?            @db.VarChar(1000)
  company               Company            @relation(fields: [companyId], references: [id], onDelete: Cascade)
  segment               ContactSegment     @relation(fields: [segmentId], references: [id], onDelete: Restrict)
  whatsappConnection    WhatsAppConnection @relation(fields: [whatsappConnectionId], references: [id], onDelete: Restrict)
  createdByMembership   CompanyMembership  @relation(fields: [createdByMembershipId], references: [id], onDelete: Restrict)
  recipients            CampaignRecipient[]
  events                CampaignEvent[]
  createdAt             DateTime           @default(now())
  updatedAt             DateTime           @updatedAt

  @@index([companyId, status, updatedAt])
  @@index([segmentId, createdAt])
  @@index([whatsappConnectionId, status])
  @@index([createdByMembershipId, createdAt])
}

model CampaignRecipient {
  id                String                  @id @default(uuid()) @db.Char(36)
  campaignId        String                  @db.Char(36)
  contactId         String                  @db.Char(36)
  status            CampaignRecipientStatus @default(PENDING)
  snapshotName      String                  @db.VarChar(190)
  snapshotRemoteJid String                  @db.VarChar(190)
  exclusionReason   String?                 @db.VarChar(80)
  plannedFor        DateTime?
  claimedAt         DateTime?
  sentAt            DateTime?
  externalId        String?                 @db.VarChar(190)
  ticketId          String?                 @db.Char(36)
  messageId         String?                 @db.Char(36)
  error             String?                 @db.VarChar(1000)
  campaign          Campaign                @relation(fields: [campaignId], references: [id], onDelete: Cascade)
  contact           Contact                 @relation(fields: [contactId], references: [id], onDelete: Cascade)
  createdAt         DateTime                @default(now())
  updatedAt         DateTime                @updatedAt

  @@unique([campaignId, contactId])
  @@index([campaignId, status, plannedFor])
  @@index([contactId, createdAt])
  @@index([status, plannedFor])
}

model CampaignEvent {
  id                String             @id @default(uuid()) @db.Char(36)
  companyId         String             @db.Char(36)
  campaignId        String             @db.Char(36)
  actorMembershipId String?            @db.Char(36)
  type              CampaignEventType
  metadata          Json?
  company           Company            @relation(fields: [companyId], references: [id], onDelete: Cascade)
  campaign          Campaign           @relation(fields: [campaignId], references: [id], onDelete: Cascade)
  actorMembership   CompanyMembership? @relation(fields: [actorMembershipId], references: [id], onDelete: SetNull)
  createdAt         DateTime           @default(now())

  @@index([companyId, createdAt])
  @@index([campaignId, createdAt])
}
`;
}

fs.writeFileSync(path, content);
console.log("[P3.5] Prisma campaign models prepared.");
NODE

cat > apps/api/prisma/migrations/20260829004500_controlled_campaigns/migration.sql <<'EOF'
CREATE TABLE `ContactCampaignConsent` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `updatedByMembershipId` CHAR(36) NULL,
  `status` ENUM('OPTED_IN', 'OPTED_OUT') NOT NULL,
  `source` ENUM('MANUAL', 'INBOUND_KEYWORD') NOT NULL DEFAULT 'MANUAL',
  `note` VARCHAR(500) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `ContactCampaignConsent_contactId_key` (`contactId`),
  INDEX `ContactCampaignConsent_companyId_status_updatedAt_idx` (`companyId`, `status`, `updatedAt`),
  INDEX `ContactCampaignConsent_updatedByMembershipId_updatedAt_idx` (`updatedByMembershipId`, `updatedAt`),
  CONSTRAINT `ContactCampaignConsent_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ContactCampaignConsent_contactId_fkey` FOREIGN KEY (`contactId`) REFERENCES `Contact`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ContactCampaignConsent_updatedByMembershipId_fkey` FOREIGN KEY (`updatedByMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `Campaign` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `segmentId` CHAR(36) NOT NULL,
  `whatsappConnectionId` CHAR(36) NOT NULL,
  `createdByMembershipId` CHAR(36) NOT NULL,
  `name` VARCHAR(160) NOT NULL,
  `body` TEXT NOT NULL,
  `status` ENUM('DRAFT','RUNNING','COMPLETED','CANCELLED','FAILED') NOT NULL DEFAULT 'DRAFT',
  `ratePerMinute` INTEGER NOT NULL DEFAULT 6,
  `windowStartAt` DATETIME(3) NOT NULL,
  `windowEndAt` DATETIME(3) NOT NULL,
  `audienceSnapshotAt` DATETIME(3) NULL,
  `segmentDefinition` JSON NULL,
  `segmentContacts` INTEGER NOT NULL DEFAULT 0,
  `eligibleRecipients` INTEGER NOT NULL DEFAULT 0,
  `optedOutRecipients` INTEGER NOT NULL DEFAULT 0,
  `unknownConsent` INTEGER NOT NULL DEFAULT 0,
  `startedAt` DATETIME(3) NULL,
  `completedAt` DATETIME(3) NULL,
  `cancelledAt` DATETIME(3) NULL,
  `error` VARCHAR(1000) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `Campaign_companyId_status_updatedAt_idx` (`companyId`, `status`, `updatedAt`),
  INDEX `Campaign_segmentId_createdAt_idx` (`segmentId`, `createdAt`),
  INDEX `Campaign_whatsappConnectionId_status_idx` (`whatsappConnectionId`, `status`),
  INDEX `Campaign_createdByMembershipId_createdAt_idx` (`createdByMembershipId`, `createdAt`),
  CONSTRAINT `Campaign_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `Campaign_segmentId_fkey` FOREIGN KEY (`segmentId`) REFERENCES `ContactSegment`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `Campaign_whatsappConnectionId_fkey` FOREIGN KEY (`whatsappConnectionId`) REFERENCES `WhatsAppConnection`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `Campaign_createdByMembershipId_fkey` FOREIGN KEY (`createdByMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `CampaignRecipient` (
  `id` CHAR(36) NOT NULL,
  `campaignId` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `status` ENUM('PENDING','PROCESSING','SENT','FAILED','SUPPRESSED','CANCELLED') NOT NULL DEFAULT 'PENDING',
  `snapshotName` VARCHAR(190) NOT NULL,
  `snapshotRemoteJid` VARCHAR(190) NOT NULL,
  `exclusionReason` VARCHAR(80) NULL,
  `plannedFor` DATETIME(3) NULL,
  `claimedAt` DATETIME(3) NULL,
  `sentAt` DATETIME(3) NULL,
  `externalId` VARCHAR(190) NULL,
  `ticketId` CHAR(36) NULL,
  `messageId` CHAR(36) NULL,
  `error` VARCHAR(1000) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `CampaignRecipient_campaignId_contactId_key` (`campaignId`, `contactId`),
  INDEX `CampaignRecipient_campaignId_status_plannedFor_idx` (`campaignId`, `status`, `plannedFor`),
  INDEX `CampaignRecipient_contactId_createdAt_idx` (`contactId`, `createdAt`),
  INDEX `CampaignRecipient_status_plannedFor_idx` (`status`, `plannedFor`),
  CONSTRAINT `CampaignRecipient_campaignId_fkey` FOREIGN KEY (`campaignId`) REFERENCES `Campaign`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CampaignRecipient_contactId_fkey` FOREIGN KEY (`contactId`) REFERENCES `Contact`(`id`) ON DELETE CASCADE ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `CampaignEvent` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `campaignId` CHAR(36) NOT NULL,
  `actorMembershipId` CHAR(36) NULL,
  `type` ENUM('CREATED','UPDATED','STARTED','CANCELLED','COMPLETED','FAILED') NOT NULL,
  `metadata` JSON NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  INDEX `CampaignEvent_companyId_createdAt_idx` (`companyId`, `createdAt`),
  INDEX `CampaignEvent_campaignId_createdAt_idx` (`campaignId`, `createdAt`),
  CONSTRAINT `CampaignEvent_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CampaignEvent_campaignId_fkey` FOREIGN KEY (`campaignId`) REFERENCES `Campaign`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CampaignEvent_actorMembershipId_fkey` FOREIGN KEY (`actorMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

cat > apps/api/src/modules/campaigns/campaign.policy.ts <<'EOF'
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
EOF

cat > apps/api/src/modules/campaigns/campaign.policy.test.ts <<'EOF'
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  campaignWindowError,
  canSendCampaign,
  composeCampaignBody,
  isCampaignOptOutKeyword,
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
EOF

cat > apps/api/src/modules/campaigns/campaign-consent.service.ts <<'EOF'
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import { isCampaignOptOutKeyword } from "./campaign.policy.js";

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
    await prisma.campaignRecipient.updateMany({
      where: {
        contactId: contact.id,
        status: "PENDING",
        campaign: { companyId: input.companyId, status: "RUNNING" }
      },
      data: {
        status: "SUPPRESSED",
        exclusionReason: "OPTED_OUT_AFTER_START"
      }
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

  await prisma.campaignRecipient.updateMany({
    where: {
      contactId: contact.id,
      status: "PENDING",
      campaign: { companyId: input.companyId, status: "RUNNING" }
    },
    data: { status: "SUPPRESSED", exclusionReason: "INBOUND_OPT_OUT" }
  });

  publishRealtime(input.companyId, {
    type: "campaign.consent.updated",
    contactId: contact.id
  });

  return { changed: true };
}
EOF

cat > apps/api/src/modules/campaigns/campaign.service.ts <<'EOF'
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

async function refreshCampaignCompletion(campaignId: string) {
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
EOF

cat > apps/api/src/jobs/campaign.queue.ts <<'EOF'
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
EOF

cat > apps/api/src/jobs/campaign.worker.ts <<'EOF'
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
EOF

cat > apps/api/src/modules/campaigns/campaign.routes.ts <<'EOF'
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
        if (await enqueueCampaignRecipient(recipient)) queued += 1;
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
EOF

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const importLine =
  'import { campaignRoutes } from "./modules/campaigns/campaign.routes.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { segmentRoutes } from "./modules/segments/segment.routes.js";';
  if (!content.includes(anchor)) {
    throw new Error("segmentRoutes import anchor not found.");
  }
  content = content.replace(anchor, `${anchor}\n${importLine}`);
}

if (!content.includes("await app.register(campaignRoutes);")) {
  const anchor = "  await app.register(segmentRoutes);";
  if (!content.includes(anchor)) {
    throw new Error("segmentRoutes registration anchor not found.");
  }
  content = content.replace(
    anchor,
    `${anchor}\n  await app.register(campaignRoutes);`
  );
}

fs.writeFileSync(path, content);
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/modules/messages/message-ingestion.service.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const importLine =
  'import { applyInboundCampaignOptOut } from "../campaigns/campaign-consent.service.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { publishRealtime } from "../realtime/realtime.bus.js";';
  if (!content.includes(anchor)) {
    throw new Error("message ingestion realtime import anchor not found.");
  }
  content = content.replace(anchor, `${anchor}\n${importLine}`);
}

if (!content.includes("applyInboundCampaignOptOut({")) {
  const pattern =
    /if\s*\(\s*!parsed\.fromMe\s*\)\s*\{\s*await\s+notifyInboundTicketActivity\s*\(/m;
  if (!pattern.test(content)) {
    throw new Error("Inbound notification branch not found structurally.");
  }
  content = content.replace(
    pattern,
    `if (!parsed.fromMe) {
    await applyInboundCampaignOptOut({
      companyId: connection.companyId,
      contactId: contact.id,
      body: parsed.body
    });

    await notifyInboundTicketActivity(`
  );
}

fs.writeFileSync(path, content);
console.log("[P3.5] Inbound opt-out integration installed.");
NODE

node <<'NODE'
const fs = require("node:fs");

function patch(path, standalone) {
  let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

  const importAnchor = standalone
    ? 'import { prisma } from "./lib/database.js";'
    : 'import { env } from "../config/env.js";';

  if (!content.includes('campaign.worker.js"')) {
    if (!content.includes(importAnchor)) {
      throw new Error(`import anchor missing in ${path}`);
    }
    const prefix = standalone ? "./jobs/" : "./";
    content = content.replace(
      importAnchor,
      `${importAnchor}
import { createCampaignWorker } from "${prefix}campaign.worker.js";
import {
  closeCampaignQueue,
  ensureCampaignSweep
} from "${prefix}campaign.queue.js";`
    );
  }

  if (!content.includes("createCampaignWorker()")) {
    const anchor = standalone
      ? "  createTaskReminderWorker()"
      : "    createTaskReminderWorker()";
    if (!content.includes(anchor)) {
      throw new Error(`task reminder worker anchor missing in ${path}`);
    }
    content = content.replace(anchor, `${anchor},\n${standalone ? "  " : "    "}createCampaignWorker()`);
  }

  if (!content.includes("ensureCampaignSweep()")) {
    const anchor = standalone
      ? "await ensureTaskReminderSweep();"
      : `  void ensureTaskReminderSweep()
    .catch(error => {
      console.error(
        "[task-reminders] scheduler setup failed",
        error
      );
    });`;

    if (!content.includes(anchor)) {
      throw new Error(`task reminder sweep anchor missing in ${path}`);
    }

    const addition = standalone
      ? `${anchor}\nawait ensureCampaignSweep();`
      : `${anchor}

  void ensureCampaignSweep()
    .catch(error => {
      console.error(
        "[campaigns] scheduler setup failed",
        error
      );
    });`;

    content = content.replace(anchor, addition);
  }

  if (!content.includes("closeCampaignQueue()")) {
    const anchor = "    closeTaskReminderQueue()";
    if (!content.includes(anchor)) {
      throw new Error(`task reminder close anchor missing in ${path}`);
    }
    content = content.replace(anchor, `${anchor},\n    closeCampaignQueue()`);
  }

  fs.writeFileSync(path, content);
}

patch("apps/api/src/jobs/job-runtime.ts", false);
patch("apps/api/src/worker.ts", true);
console.log("[P3.5] Campaign worker runtime installed.");
NODE

node <<'NODE'
const fs = require("node:fs");

function arrayBounds(source, role) {
  const start = source.indexOf(`  ${role}: [`);
  if (start < 0) throw new Error(`${role} permission block not found.`);
  const open = source.indexOf("[", start);
  let depth = 0, inString = false, quote = "", escape = false;

  for (let i = open; i < source.length; i += 1) {
    const ch = source[i];

    if (inString) {
      if (escape) escape = false;
      else if (ch === "\\") escape = true;
      else if (ch === quote) inString = false;
      continue;
    }

    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      continue;
    }

    if (ch === "[") depth += 1;
    else if (ch === "]") {
      depth -= 1;
      if (depth === 0) return { start: open, end: i };
    }
  }

  throw new Error(`${role} permission array end not found.`);
}

function patchPermissionFile(
  path,
  typeName,
  wanted
) {
  let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
  const typeStart = content.indexOf(`export type ${typeName} =`);
  const typeEnd = content.indexOf(";", typeStart);

  if (typeStart < 0 || typeEnd < 0) {
    throw new Error(`${typeName} union not found.`);
  }

  let union = content.slice(typeStart, typeEnd);

  for (const permission of new Set(Object.values(wanted).flat())) {
    if (!union.includes(`"${permission}"`)) {
      union += `\n  | "${permission}"`;
    }
  }

  content =
    content.slice(0, typeStart) +
    union +
    content.slice(typeEnd);

  for (const role of ["AGENT", "SUPERVISOR", "ADMIN", "OWNER"]) {
    const b = arrayBounds(content, role);
    const block = content.slice(b.start, b.end + 1);
    const missing = wanted[role].filter(
      permission => !block.includes(`"${permission}"`)
    );

    if (!missing.length) continue;

    const before = content.slice(0, b.end).replace(/\s+$/, "");
    const after = content.slice(b.end);
    const separator =
      before.endsWith("[") ? "\n" :
      before.endsWith(",") ? "\n" :
      ",\n";

    content =
      before +
      separator +
      missing.map(permission => `    "${permission}"`).join(",\n") +
      "\n  " +
      after;
  }

  fs.writeFileSync(path, content);
}

patchPermissionFile(
  "apps/api/src/security/permissions.ts",
  "WappPermission",
  {
    OWNER: ["campaigns.read", "campaigns.manage", "campaigns.send"],
    ADMIN: ["campaigns.read", "campaigns.manage", "campaigns.send"],
    SUPERVISOR: ["campaigns.read", "campaigns.manage"],
    AGENT: ["campaigns.read"]
  }
);

patchPermissionFile(
  "apps/web/lib/permissions.ts",
  "UiPermission",
  {
    OWNER: ["campaigns.view", "campaigns.manage", "campaigns.send"],
    ADMIN: ["campaigns.view", "campaigns.manage", "campaigns.send"],
    SUPERVISOR: ["campaigns.view", "campaigns.manage"],
    AGENT: ["campaigns.view"]
  }
);

console.log("[P3.5] Campaign RBAC installed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const permissionPath = "apps/api/src/security/permissions.ts";
const testPath = "apps/api/src/security/permissions.test.ts";
const source = fs.readFileSync(permissionPath, "utf8").replace(/\r\n/g, "\n");
let test = fs.readFileSync(testPath, "utf8").replace(/\r\n/g, "\n");

const start = source.indexOf("export type WappPermission =");
const end = source.indexOf(";", start);
const permissions = Array.from(
  source.slice(start, end).matchAll(/"([^"]+)"/g),
  match => match[1]
);

const declarationStart = test.indexOf("const allPermissions:");
const describeStart = test.indexOf("describe(", declarationStart);
if (declarationStart < 0 || describeStart < 0) {
  throw new Error("permissions.test allPermissions boundary not found.");
}

const declaration = `const allPermissions:
  WappPermission[] = [
${permissions.map(permission => `    "${permission}"`).join(",\n")}
  ];

`;

test =
  test.slice(0, declarationStart) +
  declaration +
  test.slice(describeStart);

if (!test.includes('"campaign launch is owner/admin only"')) {
  test += `

describe(
  "controlled campaign permissions",
  () => {
    it(
      "campaign launch is owner/admin only",
      () => {
        for (
          const role
          of ["OWNER", "ADMIN"] as const
        ) {
          assert.equal(roleHasPermission(role, "campaigns.read"), true);
          assert.equal(roleHasPermission(role, "campaigns.manage"), true);
          assert.equal(roleHasPermission(role, "campaigns.send"), true);
        }

        assert.equal(roleHasPermission("SUPERVISOR", "campaigns.read"), true);
        assert.equal(roleHasPermission("SUPERVISOR", "campaigns.manage"), true);
        assert.equal(roleHasPermission("SUPERVISOR", "campaigns.send"), false);
        assert.equal(roleHasPermission("AGENT", "campaigns.read"), true);
        assert.equal(roleHasPermission("AGENT", "campaigns.manage"), false);
        assert.equal(roleHasPermission("AGENT", "campaigns.send"), false);
      }
    );
  }
);
`;
}

fs.writeFileSync(testPath, test);
console.log(`[P3.5] permissions.test rebuilt with ${permissions.length} permissions.`);
NODE

node <<'NODE'
const fs = require("node:fs");

function patch(path) {
  let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
  const typeStart = content.indexOf("export type RealtimeEventType =");
  const typeEnd = content.indexOf(";", typeStart);
  if (typeStart < 0 || typeEnd < 0) {
    throw new Error(`RealtimeEventType missing in ${path}`);
  }

  let union = content.slice(typeStart, typeEnd);
  for (const type of ["campaign.updated", "campaign.consent.updated"]) {
    if (!union.includes(`"${type}"`)) union += `\n  | "${type}"`;
  }

  content =
    content.slice(0, typeStart) +
    union +
    content.slice(typeEnd);

  const interfaceStart = content.indexOf("export interface RealtimeEvent {");
  const interfaceEnd = content.indexOf("\n}", interfaceStart);
  if (interfaceStart < 0 || interfaceEnd < 0) {
    throw new Error(`RealtimeEvent interface missing in ${path}`);
  }

  let block = content.slice(interfaceStart, interfaceEnd);
  if (!block.includes("campaignId?: string;")) {
    block += "\n  campaignId?: string;";
  }

  content =
    content.slice(0, interfaceStart) +
    block +
    content.slice(interfaceEnd);

  fs.writeFileSync(path, content);
}

patch("apps/api/src/modules/realtime/realtime.bus.ts");
patch("apps/web/lib/realtime-types.ts");
console.log("[P3.5] Campaign realtime installed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/app/dashboard/page.tsx";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes('href: "/dashboard/campaigns"')) {
  const anchor = `  {
    label: "Segmentos",
    href: "/dashboard/segments",
    permission: "segments.view"
  },`;
  if (!content.includes(anchor)) {
    throw new Error("Segments navigation anchor not found.");
  }

  content = content.replace(
    anchor,
    `${anchor}
  {
    label: "Campanhas",
    href: "/dashboard/campaigns",
    permission: "campaigns.view"
  },`
  );
}

fs.writeFileSync(path, content);
NODE

cat > apps/web/components/contacts/contact-campaign-consent.tsx <<'EOF'
"use client";

import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

interface Payload {
  status: "UNKNOWN" | "OPTED_IN" | "OPTED_OUT";
  consent: {
    status: "OPTED_IN" | "OPTED_OUT";
    source: "MANUAL" | "INBOUND_KEYWORD";
    note: string | null;
  } | null;
}

export function ContactCampaignConsent({ contactId }: { contactId: string }) {
  const { request, subscribe } = useAuth();
  const [payload, setPayload] = useState<Payload | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    setPayload(
      await request<Payload>(
        `/api/v1/contacts/${contactId}/campaign-consent`
      )
    );
  }, [contactId, request]);

  useEffect(() => {
    void load().catch(() => {
      setError("Não foi possível carregar o consentimento.");
    });
  }, [load]);

  useEffect(
    () =>
      subscribe("/api/v1/realtime/events", event => {
        if (
          event.type === "campaign.consent.updated" &&
          event.contactId === contactId
        ) {
          void load();
        }
      }),
    [contactId, load, subscribe]
  );

  async function setStatus(status: "OPTED_IN" | "OPTED_OUT") {
    setBusy(true);
    setError("");
    try {
      await request(
        `/api/v1/contacts/${contactId}/campaign-consent`,
        {
          method: "PUT",
          body: JSON.stringify({
            status,
            note:
              status === "OPTED_IN"
                ? "Consentimento registrado manualmente no Wapp."
                : "Contato marcado para não receber campanhas."
          })
        }
      );
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar o consentimento."
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="contact-campaign-consent">
      <div>
        <span className="eyebrow">Campanhas</span>
        <strong>Consentimento</strong>
        <small>
          Sem autorização explícita, o contato fica fora de campanhas.
        </small>
      </div>

      <span className={`contact-consent-badge contact-consent-badge--${payload?.status ?? "UNKNOWN"}`}>
        {payload?.status === "OPTED_IN"
          ? "Autorizado"
          : payload?.status === "OPTED_OUT"
            ? "Opt-out"
            : "Não informado"}
      </span>

      <div className="contact-campaign-consent__actions">
        <button
          disabled={busy}
          onClick={() => void setStatus("OPTED_IN")}
          type="button"
        >
          Registrar autorização
        </button>
        <button
          disabled={busy}
          onClick={() => void setStatus("OPTED_OUT")}
          type="button"
        >
          Não receber
        </button>
      </div>

      {error && <small className="contact-consent-error">{error}</small>}
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/app/dashboard/contacts/page.tsx";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
const importLine =
  'import { ContactCampaignConsent } from "@/components/contacts/contact-campaign-consent";';

if (!content.includes(importLine)) {
  const anchor =
    'import { ContactTasksPanel } from "@/components/contacts/contact-tasks-panel";';
  if (!content.includes(anchor)) {
    throw new Error("ContactTasksPanel import not found.");
  }
  content = content.replace(anchor, `${anchor}\n${importLine}`);
}

if (!content.includes("<ContactCampaignConsent")) {
  const anchor = "              <ContactTasksPanel";
  if (!content.includes(anchor)) {
    throw new Error("ContactTasksPanel mount not found.");
  }

  content = content.replace(
    anchor,
    `              <ContactCampaignConsent
                contactId={
                  detail.id
                }
              />

${anchor}`
  );
}

fs.writeFileSync(path, content);
NODE

cat > apps/web/app/dashboard/campaigns/page.tsx <<'EOF'
"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";
import { roleCan } from "@/lib/permissions";

interface Segment {
  id: string;
  name: string;
}
interface Connection {
  id: string;
  name: string;
  status: string;
}
interface Campaign {
  id: string;
  name: string;
  body: string;
  status: "DRAFT" | "RUNNING" | "COMPLETED" | "CANCELLED" | "FAILED";
  segmentId: string;
  whatsappConnectionId: string;
  ratePerMinute: number;
  windowStartAt: string;
  windowEndAt: string;
  segment: { id: string; name: string };
  whatsappConnection: { id: string; name: string; status: string };
  recipientStatus: Record<string, number>;
}
interface Preview {
  segmentContacts: number;
  eligibleRecipients: number;
  optedOutRecipients: number;
  unknownConsent: number;
  blocked: boolean;
  blockReason: string | null;
  estimatedLastSendAt: string | null;
}
interface Recipient {
  id: string;
  status: string;
  snapshotName: string;
  plannedFor: string | null;
  sentAt: string | null;
  exclusionReason: string | null;
  error: string | null;
  contact: {
    id: string;
    name: string;
    phoneNumber: string | null;
    email: string | null;
  };
}

function localValue(date: Date) {
  return new Date(
    date.getTime() - date.getTimezoneOffset() * 60_000
  ).toISOString().slice(0, 16);
}

function initialWindow() {
  const start = new Date(Date.now() + 5 * 60_000);
  const end = new Date(start.getTime() + 4 * 60 * 60_000);
  return { start: localValue(start), end: localValue(end) };
}

function dt(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short"
  }).format(new Date(value));
}

export default function CampaignsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();
  const defaults = useMemo(() => initialWindow(), []);

  const [campaigns, setCampaigns] = useState<Campaign[]>([]);
  const [segments, setSegments] = useState<Segment[]>([]);
  const [connections, setConnections] = useState<Connection[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [recipients, setRecipients] = useState<Recipient[]>([]);
  const [preview, setPreview] = useState<Preview | null>(null);

  const [name, setName] = useState("");
  const [segmentId, setSegmentId] = useState("");
  const [connectionId, setConnectionId] = useState("");
  const [body, setBody] = useState("");
  const [rate, setRate] = useState(6);
  const [windowStart, setWindowStart] = useState(defaults.start);
  const [windowEnd, setWindowEnd] = useState(defaults.end);
  const [confirmation, setConfirmation] = useState("");

  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const canManage = session
    ? roleCan(session.role, "campaigns.manage")
    : false;
  const canSend = session
    ? roleCan(session.role, "campaigns.send")
    : false;

  const selected = useMemo(
    () => campaigns.find(item => item.id === selectedId) ?? null,
    [campaigns, selectedId]
  );

  const load = useCallback(async () => {
    const [campaignPayload, context] = await Promise.all([
      request<{ campaigns: Campaign[] }>("/api/v1/campaigns"),
      request<{ segments: Segment[]; connections: Connection[] }>(
        "/api/v1/campaigns/context"
      )
    ]);
    setCampaigns(campaignPayload.campaigns);
    setSegments(context.segments);
    setConnections(context.connections);
    setSegmentId(current => current || context.segments[0]?.id || "");
    setConnectionId(
      current =>
        current ||
        context.connections.find(item => item.status === "CONNECTED")?.id ||
        context.connections[0]?.id ||
        ""
    );
  }, [request]);

  const loadRecipients = useCallback(async (campaignId: string) => {
    const payload = await request<{ recipients: Recipient[] }>(
      `/api/v1/campaigns/${campaignId}/recipients?limit=200`
    );
    setRecipients(payload.recipients);
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }
    if (session && !roleCan(session.role, "campaigns.view")) {
      router.replace("/dashboard");
      return;
    }
    if (session) {
      setBusy(true);
      void load()
        .catch(() => setError("Não foi possível carregar campanhas."))
        .finally(() => setBusy(false));
    }
  }, [load, loading, router, session]);

  useEffect(() => {
    if (!session) return;
    return subscribe("/api/v1/realtime/events", event => {
      if (event.type === "campaign.updated") {
        void load();
        if (
          selectedId &&
          (!event.campaignId || event.campaignId === selectedId)
        ) {
          void loadRecipients(selectedId);
        }
      }
    });
  }, [load, loadRecipients, selectedId, session, subscribe]);

  function resetDraft() {
    const next = initialWindow();
    setSelectedId(null);
    setRecipients([]);
    setPreview(null);
    setName("");
    setBody("");
    setRate(6);
    setWindowStart(next.start);
    setWindowEnd(next.end);
    setConfirmation("");
    setError("");
    setNotice("");
  }

  function choose(campaign: Campaign) {
    setSelectedId(campaign.id);
    setName(campaign.name);
    setSegmentId(campaign.segmentId);
    setConnectionId(campaign.whatsappConnectionId);
    setBody(campaign.body);
    setRate(campaign.ratePerMinute);
    setWindowStart(localValue(new Date(campaign.windowStartAt)));
    setWindowEnd(localValue(new Date(campaign.windowEndAt)));
    setPreview(null);
    setConfirmation("");
    setError("");
    setNotice("");
    void loadRecipients(campaign.id);
  }

  async function save() {
    if (!canManage) return;
    setSaving(true);
    setError("");
    setNotice("");

    try {
      const payload = await request<{ campaign: Campaign }>(
        selectedId
          ? `/api/v1/campaigns/${selectedId}`
          : "/api/v1/campaigns",
        {
          method: selectedId ? "PATCH" : "POST",
          body: JSON.stringify({
            segmentId,
            whatsappConnectionId: connectionId,
            name: name.trim(),
            body: body.trim(),
            ratePerMinute: rate,
            windowStartAt: new Date(windowStart).toISOString(),
            windowEndAt: new Date(windowEnd).toISOString()
          })
        }
      );

      setSelectedId(payload.campaign.id);
      setPreview(null);
      setNotice(selectedId ? "Rascunho atualizado." : "Rascunho criado.");
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar a campanha."
      );
    } finally {
      setSaving(false);
    }
  }

  async function previewAudience() {
    if (!selectedId) {
      setError("Salve o rascunho antes da prévia.");
      return;
    }
    setSaving(true);
    setError("");
    try {
      setPreview(
        await request<Preview>(
          `/api/v1/campaigns/${selectedId}/preview`,
          { method: "POST" }
        )
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível calcular a audiência."
      );
    } finally {
      setSaving(false);
    }
  }

  async function start() {
    if (!selectedId || !preview || preview.blocked) return;
    setSaving(true);
    setError("");
    try {
      const result = await request<{
        queued: number;
        durableRecipients: number;
      }>(
        `/api/v1/campaigns/${selectedId}/start`,
        {
          method: "POST",
          body: JSON.stringify({
            confirmation,
            confirmedAudienceCount: preview.eligibleRecipients
          })
        }
      );
      setNotice(
        `Campanha iniciada: ${result.durableRecipients} destinatários persistidos, ${result.queued} jobs enfileirados agora.`
      );
      setConfirmation("");
      await Promise.all([load(), loadRecipients(selectedId)]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível iniciar a campanha."
      );
    } finally {
      setSaving(false);
    }
  }

  async function cancel() {
    if (!selectedId) return;
    setSaving(true);
    setError("");
    try {
      await request(`/api/v1/campaigns/${selectedId}/cancel`, {
        method: "POST"
      });
      setNotice("Campanha cancelada. Envios já realizados não são revertidos.");
      await Promise.all([load(), loadRecipients(selectedId)]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível cancelar."
      );
    } finally {
      setSaving(false);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando campanhas…</main>;
  }

  const editable = !selected || selected.status === "DRAFT";

  return (
    <main className="campaign-screen">
      <header className="campaign-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">CRM</span>
          <h1>Campanhas</h1>
          <p>
            Envios controlados com segmento, consentimento explícito,
            janela e limite de velocidade.
          </p>
        </div>
        {canManage && (
          <button className="ghost-button" onClick={resetDraft} type="button">
            Nova campanha
          </button>
        )}
      </header>

      {error && (
        <div className="campaign-feedback campaign-feedback--error">
          {error}
        </div>
      )}
      {notice && <div className="campaign-feedback">{notice}</div>}

      <section className="campaign-layout">
        <aside className="campaign-list">
          <header>
            <strong>Campanhas</strong>
            <span>{campaigns.length}</span>
          </header>
          <div>
            {campaigns.map(campaign => (
              <button
                className={
                  selectedId === campaign.id
                    ? "campaign-list-item campaign-list-item--active"
                    : "campaign-list-item"
                }
                key={campaign.id}
                onClick={() => choose(campaign)}
                type="button"
              >
                <div>
                  <strong>{campaign.name}</strong>
                  <small>{campaign.segment.name}</small>
                </div>
                <span>{campaign.status}</span>
              </button>
            ))}
            {!busy && campaigns.length === 0 && (
              <div className="campaign-empty">Nenhuma campanha criada.</div>
            )}
          </div>
        </aside>

        <section className="campaign-builder">
          <header>
            <div>
              <strong>{selected?.name ?? "Novo rascunho"}</strong>
              <span>
                A audiência é recalculada novamente na confirmação final.
              </span>
            </div>
            {selected &&
              ["DRAFT", "RUNNING"].includes(selected.status) &&
              canManage && (
                <button
                  className="ghost-button"
                  disabled={saving}
                  onClick={() => void cancel()}
                  type="button"
                >
                  Cancelar
                </button>
              )}
          </header>

          <div className="campaign-consent-rule">
            <strong>Consentimento obrigatório</strong>
            <p>
              Somente contatos marcados como “Autorizado” na ficha podem
              receber. Opt-out e consentimento desconhecido são suprimidos.
            </p>
          </div>

          <div className="campaign-form-grid">
            <label>
              <span>Nome</span>
              <input
                disabled={!editable}
                maxLength={160}
                onChange={event => setName(event.target.value)}
                value={name}
              />
            </label>
            <label>
              <span>Segmento</span>
              <select
                disabled={!editable}
                onChange={event => setSegmentId(event.target.value)}
                value={segmentId}
              >
                <option value="">Selecionar…</option>
                {segments.map(item => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Conexão</span>
              <select
                disabled={!editable}
                onChange={event => setConnectionId(event.target.value)}
                value={connectionId}
              >
                <option value="">Selecionar…</option>
                {connections.map(item => (
                  <option key={item.id} value={item.id}>
                    {item.name} · {item.status}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Velocidade</span>
              <select
                disabled={!editable}
                onChange={event => setRate(Number(event.target.value))}
                value={rate}
              >
                {[1, 2, 3, 4, 5, 6, 8, 10].map(value => (
                  <option key={value} value={value}>
                    {value}/min
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Início</span>
              <input
                disabled={!editable}
                onChange={event => setWindowStart(event.target.value)}
                type="datetime-local"
                value={windowStart}
              />
            </label>
            <label>
              <span>Fim</span>
              <input
                disabled={!editable}
                onChange={event => setWindowEnd(event.target.value)}
                type="datetime-local"
                value={windowEnd}
              />
            </label>
          </div>

          <label className="campaign-message-field">
            <span>Mensagem</span>
            <textarea
              disabled={!editable}
              maxLength={3800}
              onChange={event => setBody(event.target.value)}
              placeholder="Olá, {{primeiro_nome}}! ..."
              rows={7}
              value={body}
            />
            <small>
              Variáveis: {"{{nome}}"} e {"{{primeiro_nome}}"}. O aviso
              “responda SAIR” é anexado automaticamente.
            </small>
          </label>

          {canManage && editable && (
            <div className="campaign-builder__actions">
              <button
                className="primary-button"
                disabled={
                  saving ||
                  !name.trim() ||
                  !segmentId ||
                  !connectionId ||
                  !body.trim()
                }
                onClick={() => void save()}
                type="button"
              >
                <span>
                  {selectedId ? "Atualizar rascunho" : "Salvar rascunho"}
                </span>
              </button>
              {selectedId && (
                <button
                  className="ghost-button"
                  disabled={saving}
                  onClick={() => void previewAudience()}
                  type="button"
                >
                  Calcular audiência
                </button>
              )}
            </div>
          )}

          {preview && (
            <section className="campaign-preview">
              <div className="campaign-preview__numbers">
                <article><span>Segmento</span><strong>{preview.segmentContacts}</strong></article>
                <article><span>Autorizados</span><strong>{preview.eligibleRecipients}</strong></article>
                <article><span>Opt-out</span><strong>{preview.optedOutRecipients}</strong></article>
                <article><span>Sem consentimento</span><strong>{preview.unknownConsent}</strong></article>
              </div>

              {preview.blocked ? (
                <p className="campaign-preview__blocked">
                  {preview.blockReason}
                </p>
              ) : (
                <>
                  <p>
                    Último envio estimado:{" "}
                    <strong>{dt(preview.estimatedLastSendAt)}</strong>
                  </p>
                  {canSend && (
                    <div className="campaign-launch">
                      <label>
                        <span>Confirmação final</span>
                        <input
                          onChange={event => setConfirmation(event.target.value)}
                          placeholder="INICIAR CAMPANHA"
                          value={confirmation}
                        />
                      </label>
                      <button
                        className="primary-button"
                        disabled={
                          saving || confirmation !== "INICIAR CAMPANHA"
                        }
                        onClick={() => void start()}
                        type="button"
                      >
                        <span>
                          Iniciar para {preview.eligibleRecipients} contatos
                        </span>
                      </button>
                    </div>
                  )}
                </>
              )}
            </section>
          )}
        </section>

        <section className="campaign-recipients">
          <header>
            <div>
              <strong>Destinatários</strong>
              <span>{selected?.status ?? "Selecione uma campanha"}</span>
            </div>
            {selected && (
              <small>
                Enviados {selected.recipientStatus.SENT ?? 0} · Falhas{" "}
                {selected.recipientStatus.FAILED ?? 0} · Suprimidos{" "}
                {selected.recipientStatus.SUPPRESSED ?? 0}
              </small>
            )}
          </header>
          <div>
            {recipients.map(item => (
              <article className="campaign-recipient" key={item.id}>
                <button
                  onClick={() =>
                    router.push(
                      `/dashboard/contacts?contact=${item.contact.id}`
                    )
                  }
                  type="button"
                >
                  <strong>{item.snapshotName}</strong>
                  <small>
                    {item.contact.phoneNumber ??
                      item.contact.email ??
                      "Contato"}
                  </small>
                </button>
                <div>
                  <span>{item.status}</span>
                  <small>
                    {item.sentAt
                      ? dt(item.sentAt)
                      : item.plannedFor
                        ? dt(item.plannedFor)
                        : item.exclusionReason ?? "—"}
                  </small>
                </div>
                {item.error && <p>{item.error}</p>}
              </article>
            ))}
            {selected && recipients.length === 0 && (
              <div className="campaign-empty">
                O snapshot aparece quando a campanha for iniciada.
              </div>
            )}
            {!selected && (
              <div className="campaign-empty">
                Selecione uma campanha para acompanhar.
              </div>
            )}
          </div>
        </section>
      </section>
    </main>
  );
}
EOF

if ! grep -Fq -- "WAPP P3.5 / CONTROLLED CAMPAIGNS" "$CSS"; then
cat >> "$CSS" <<'EOF'

/* --- WAPP P3.5 / CONTROLLED CAMPAIGNS ------------------------------- */
.contact-campaign-consent {
  display: grid;
  grid-template-columns: minmax(190px, 1fr) auto auto;
  align-items: center;
  gap: 12px;
  margin-top: 12px;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
  padding: 11px 13px;
}
.contact-campaign-consent > div:first-child { display: grid; gap: 2px; }
.contact-campaign-consent strong { font-size: 10px; }
.contact-campaign-consent small { color: var(--muted); font-size: 7px; }
.contact-consent-badge {
  border-radius: 999px;
  background: #eef1ef;
  color: #68716c;
  padding: 4px 7px;
  font-size: 7px;
  font-weight: 800;
}
.contact-consent-badge--OPTED_IN {
  background: var(--accent-soft);
  color: var(--accent-dark);
}
.contact-consent-badge--OPTED_OUT {
  background: rgba(168, 78, 73, 0.09);
  color: #973a32;
}
.contact-campaign-consent__actions { display: flex; gap: 6px; }
.contact-campaign-consent__actions button {
  min-height: 32px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: white;
  padding: 0 8px;
  font-size: 7px;
  cursor: pointer;
}
.contact-consent-error { grid-column: 1 / -1; color: #973a32 !important; }

.campaign-screen {
  min-height: 100vh;
  overflow-x: hidden;
  background: var(--surface-subtle);
  padding: 32px clamp(18px, 4vw, 56px) 56px;
}
.campaign-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 20px;
}
.campaign-header h1 {
  margin: 6px 0 5px;
  font-size: clamp(32px, 4vw, 48px);
  letter-spacing: -0.05em;
}
.campaign-header p {
  max-width: 700px;
  margin: 0;
  color: var(--muted);
  font-size: 10px;
  line-height: 1.5;
}
.campaign-feedback {
  margin-top: 12px;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 9px 10px;
  font-size: 8px;
}
.campaign-feedback--error {
  background: rgba(163, 59, 50, 0.07);
  color: #973a32;
}
.campaign-layout {
  display: grid;
  grid-template-columns: 220px minmax(470px, 1fr) minmax(290px, .75fr);
  gap: 10px;
  align-items: start;
  margin-top: 14px;
}
.campaign-list,
.campaign-builder,
.campaign-recipients {
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
}
.campaign-list,
.campaign-recipients {
  position: sticky;
  top: 14px;
  max-height: calc(100dvh - 165px);
}
.campaign-list > header,
.campaign-recipients > header,
.campaign-builder > header {
  display: flex;
  min-height: 45px;
  align-items: center;
  justify-content: space-between;
  gap: 9px;
  border-bottom: 1px solid var(--line);
  padding: 9px 11px;
}
.campaign-list > header strong,
.campaign-recipients > header strong,
.campaign-builder > header strong { font-size: 10px; }
.campaign-list > header span,
.campaign-recipients > header span,
.campaign-recipients > header small,
.campaign-builder > header span {
  color: var(--muted);
  font-size: 7px;
}
.campaign-list > div,
.campaign-recipients > div {
  max-height: calc(100dvh - 212px);
  overflow-y: auto;
  padding: 6px;
}
.campaign-list-item {
  display: flex;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  border: 1px solid transparent;
  border-radius: 9px;
  background: transparent;
  padding: 9px 8px;
  text-align: left;
  cursor: pointer;
}
.campaign-list-item:hover,
.campaign-list-item--active {
  border-color: var(--line);
  background: #f7f9f7;
}
.campaign-list-item--active {
  border-color: rgba(31, 122, 80, .25);
  background: var(--accent-soft);
}
.campaign-list-item > div { display: grid; min-width: 0; gap: 2px; }
.campaign-list-item strong {
  overflow: hidden;
  font-size: 8px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.campaign-list-item small,
.campaign-list-item > span { color: var(--muted); font-size: 6px; }

.campaign-consent-rule {
  border-bottom: 1px solid var(--line);
  background: #f7faf8;
  padding: 10px 12px;
}
.campaign-consent-rule strong { font-size: 8px; }
.campaign-consent-rule p {
  margin: 3px 0 0;
  color: #59635d;
  font-size: 7px;
  line-height: 1.45;
}
.campaign-form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
  padding: 11px 12px;
}
.campaign-form-grid label,
.campaign-message-field,
.campaign-launch label { display: grid; gap: 4px; }
.campaign-form-grid label > span,
.campaign-message-field > span,
.campaign-launch label > span {
  color: var(--muted);
  font-size: 7px;
  font-weight: 750;
}
.campaign-form-grid input,
.campaign-form-grid select,
.campaign-message-field textarea,
.campaign-launch input {
  width: 100%;
  min-height: 36px;
  border: 1px solid var(--line);
  border-radius: 8px;
  outline: 0;
  background: white;
  padding: 7px 8px;
  color: var(--ink);
  font: inherit;
  font-size: 8px;
}
.campaign-message-field {
  border-top: 1px solid #edf0ed;
  border-bottom: 1px solid #edf0ed;
  padding: 11px 12px;
}
.campaign-message-field textarea {
  min-height: 150px;
  resize: vertical;
  line-height: 1.45;
}
.campaign-message-field small { color: var(--muted); font-size: 7px; }
.campaign-builder__actions { display: flex; gap: 7px; padding: 11px 12px; }

.campaign-preview {
  border-top: 1px solid var(--line);
  background: #fafbfa;
  padding: 11px 12px;
}
.campaign-preview__numbers {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 9px;
  background: white;
}
.campaign-preview__numbers article {
  display: grid;
  gap: 2px;
  border-right: 1px solid var(--line);
  padding: 9px;
}
.campaign-preview__numbers article:last-child { border-right: 0; }
.campaign-preview__numbers span { color: var(--muted); font-size: 6px; }
.campaign-preview__numbers strong { font-size: 15px; }
.campaign-preview > p { margin: 9px 0 0; color: var(--muted); font-size: 7px; }
.campaign-preview__blocked { color: #973a32 !important; }
.campaign-launch {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 8px;
  align-items: end;
  margin-top: 10px;
  border-top: 1px solid var(--line);
  padding-top: 10px;
}

.campaign-recipient {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 6px 8px;
  border-bottom: 1px solid #edf0ed;
  padding: 9px 7px;
}
.campaign-recipient > button {
  display: grid;
  min-width: 0;
  gap: 2px;
  border: 0;
  background: transparent;
  padding: 0;
  text-align: left;
  cursor: pointer;
}
.campaign-recipient > button strong {
  overflow: hidden;
  font-size: 8px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.campaign-recipient > button small,
.campaign-recipient > div small { color: var(--muted); font-size: 6px; }
.campaign-recipient > div { display: grid; gap: 2px; justify-items: end; }
.campaign-recipient > div span { font-size: 6px; font-weight: 800; }
.campaign-recipient > p {
  grid-column: 1 / -1;
  margin: 0;
  color: #973a32;
  font-size: 6px;
}
.campaign-empty {
  padding: 24px 10px;
  color: var(--muted);
  font-size: 8px;
  text-align: center;
}

@media (max-width: 1180px) {
  .campaign-layout { grid-template-columns: 210px minmax(0, 1fr); }
  .campaign-recipients {
    position: static;
    grid-column: 2;
    max-height: none;
  }
}
@media (max-width: 760px) {
  .contact-campaign-consent { grid-template-columns: 1fr; }
  .contact-campaign-consent__actions { flex-direction: column; }
  .contact-campaign-consent__actions button { min-height: 40px; }
  .campaign-screen {
    min-height: 100dvh;
    padding: 20px 12px calc(82px + env(safe-area-inset-bottom, 0px));
  }
  .campaign-header { align-items: flex-start; flex-direction: column; }
  .campaign-layout { grid-template-columns: 1fr; }
  .campaign-list,
  .campaign-recipients { position: static; max-height: none; }
  .campaign-recipients { grid-column: auto; }
  .campaign-form-grid,
  .campaign-launch { grid-template-columns: 1fr; }
  .campaign-form-grid input,
  .campaign-form-grid select,
  .campaign-message-field textarea,
  .campaign-launch input {
    min-height: 42px;
    font-size: 16px;
  }
  .campaign-preview__numbers { grid-template-columns: repeat(2, 1fr); }
  .campaign-builder__actions { flex-direction: column; }
}
/* --- /WAPP P3.5 ----------------------------------------------------- */
EOF
fi

cat > scripts/p3-05-campaign-smoke.mjs <<'EOF'
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
EOF

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
const current = pkg.scripts?.test;
if (typeof current !== "string") throw new Error("API test script missing.");
const file = "src/modules/campaigns/campaign.policy.test.ts";
if (!current.includes(file)) pkg.scripts.test = `${current} ${file}`;
fs.writeFileSync(path, `${JSON.stringify(pkg, null, 2)}\n`);
NODE

cat > docs/P3_05_CONTROLLED_CAMPAIGNS.md <<'EOF'
# P3.5 Controlled campaigns

P3.5 adds governed outbound campaigns over P3.4 saved segments.

## Eligibility

A contact is eligible only with explicit `OPTED_IN` campaign consent.

No consent row means UNKNOWN and is not eligible.

`OPTED_OUT` is never eligible.

Direct inbound commands `SAIR`, `PARAR`, `CANCELAR`, `REMOVER`,
`NAO QUERO RECEBER` and `NÃO QUERO RECEBER` automatically record opt-out.
The match is exact after normalization, avoiding accidental suppression from a
normal sentence that merely contains one of those words.

Every campaign message automatically appends:

`Para não receber mais mensagens, responda SAIR.`

The footer cannot be disabled.

## Dynamic segment and launch snapshot

Preview resolves the current P3.4 segment.

Start resolves it again and requires:

- exact current eligible count;
- literal confirmation `INICIAR CAMPANHA`.

Only after that is `CampaignRecipient` snapshot created.

Consent is checked again immediately before every provider send, so a contact
that opts out after campaign start is still suppressed.

## Initial safety limits

- direct contacts only;
- maximum segment audience: 500;
- explicit opt-in required;
- 1–10 messages/minute per campaign;
- global BullMQ limiter: 10 jobs/minute;
- explicit one-time window;
- maximum window: 24h.

The 500-contact limit is intentionally conservative for the first live rollout.

## Durable execution

Queue: `wapp-campaigns`.

Database recipient rows are the source of truth.

A one-minute sweep recovers pending recipients whose original enqueue did not
happen while Redis was unavailable.

Provider-send jobs use `attempts = 1`. Automatic provider retry is intentionally
disabled because a provider may accept a message even when local persistence
fails afterwards; retrying could duplicate the outbound message.

PROCESSING recipients older than 15 minutes become FAILED with an uncertain
state instead of being resent.

## Conversation integration

A successful campaign send uses the existing Evolution text path,
`Contact.remoteJid`, normal Ticket/Message persistence and
`deliveryStatus = PENDING`, so ordinary delivery/read webhooks continue the
message lifecycle.

Campaign messages appear in the same conversation history as manual and
scheduled outbound messages.

## RBAC

OWNER / ADMIN: read, prepare, start and cancel.

SUPERVISOR: read, prepare and cancel, but cannot start.

AGENT: read only.

Contact consent itself is an operational Contacts action.

## Personalization

Supported variables:

- `{{nome}}`
- `{{primeiro_nome}}`

No expression evaluation or arbitrary template code exists.

## Migration

P3.5 introduces:

- `ContactCampaignConsent`
- `Campaign`
- `CampaignRecipient`
- `CampaignEvent`
- related enums
EOF

echo "[P3.5] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P3.5] Campaign smoke..."
node scripts/p3-05-campaign-smoke.mjs

echo "[P3.5] Unit tests..."
pnpm test

echo "[P3.5] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.5] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.5] CODE VALIDATION PASS."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
echo
echo "First live test:"
echo "  - segment with at most 2 test contacts"
echo "  - mark only 1 as OPTED_IN"
echo "  - preview must show 1 eligible"
echo "  - run at 1 message/minute"
echo "  - reply SAIR and verify the next preview shows opt-out"
