#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEMA="apps/api/prisma/schema.prisma"
APP="apps/api/src/app.ts"
PERMISSIONS="apps/api/src/security/permissions.ts"
PERMISSIONS_TEST="apps/api/src/security/permissions.test.ts"
REALTIME_API="apps/api/src/modules/realtime/realtime.bus.ts"
REALTIME_WEB="apps/web/lib/realtime-types.ts"
UI_PERMISSIONS="apps/web/lib/permissions.ts"
DASHBOARD="apps/web/app/dashboard/page.tsx"
CSS="apps/web/app/globals.css"

echo "[P3.4] Installing saved contact segments..."

for check in \
  "$SCHEMA|model ContactFieldDefinition {" \
  "$SCHEMA|model CrmPipeline {" \
  "$SCHEMA|model CrmTask {" \
  "$APP|await app.register(taskRoutes);" \
  "$PERMISSIONS|tasks.admin" \
  "$REALTIME_API|task.updated" \
  "$UI_PERMISSIONS|tasks.view" \
  "$DASHBOARD|href: \"/dashboard/tasks\""
do
  file="${check%%|*}"
  marker="${check#*|}"
  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: P3.4 prerequisite missing: $file -> $marker"
    echo "P3.4 made no changes."
    exit 1
  fi
done

mkdir -p apps/api/src/modules/segments apps/api/prisma/migrations/20260829003000_contact_segments apps/web/app/dashboard/segments scripts docs

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/prisma/schema.prisma";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

function bounds(modelName) {
  const start = content.indexOf(`model ${modelName} {`);
  if (start < 0) throw new Error(`${modelName} model not found.`);
  const end = content.indexOf("\n}", start);
  if (end < 0) throw new Error(`${modelName} model end not found.`);
  return { start, end };
}

function addRelation(modelName, fieldName, line) {
  const { start, end } = bounds(modelName);
  const block = content.slice(start, end);
  if (block.includes(`\n  ${fieldName} `)) return;
  content = content.slice(0, end) + `\n${line}` + content.slice(end);
}

addRelation("Company", "contactSegments", "  contactSegments          ContactSegment[]");
addRelation("CompanyMembership", "createdContactSegments", "  createdContactSegments   ContactSegment[]");

if (!content.includes("model ContactSegment {")) {
  content += `

model ContactSegment {
  id                    String             @id @default(uuid()) @db.Char(36)
  companyId             String             @db.Char(36)
  createdByMembershipId String?            @db.Char(36)
  name                  String             @db.VarChar(140)
  description           String?            @db.VarChar(500)
  definition            Json
  isActive              Boolean            @default(true)
  company               Company            @relation(fields: [companyId], references: [id], onDelete: Cascade)
  createdByMembership   CompanyMembership? @relation(fields: [createdByMembershipId], references: [id], onDelete: SetNull)
  createdAt             DateTime           @default(now())
  updatedAt             DateTime           @updatedAt

  @@unique([companyId, name])
  @@index([companyId, isActive, updatedAt])
  @@index([createdByMembershipId, updatedAt])
}
`;
}

fs.writeFileSync(path, content);
console.log("[P3.4] ContactSegment Prisma model prepared.");
NODE

cat > apps/api/prisma/migrations/20260829003000_contact_segments/migration.sql <<'SQL'
CREATE TABLE `ContactSegment` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `createdByMembershipId` CHAR(36) NULL,
  `name` VARCHAR(140) NOT NULL,
  `description` VARCHAR(500) NULL,
  `definition` JSON NOT NULL,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `ContactSegment_companyId_name_key` (`companyId`, `name`),
  INDEX `ContactSegment_companyId_isActive_updatedAt_idx` (`companyId`, `isActive`, `updatedAt`),
  INDEX `ContactSegment_createdByMembershipId_updatedAt_idx` (`createdByMembershipId`, `updatedAt`),
  CONSTRAINT `ContactSegment_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ContactSegment_createdByMembershipId_fkey` FOREIGN KEY (`createdByMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SQL

cat > apps/api/src/modules/segments/segment.definition.ts <<'TS'
import { z } from "zod";

export const SEGMENT_CUSTOM_OPERATORS = ["EQ", "NEQ", "CONTAINS", "EMPTY", "NOT_EMPTY"] as const;
export const SEGMENT_LAST_SEEN = ["ANY", "WITHIN_7D", "WITHIN_30D", "WITHIN_90D", "NEVER"] as const;
export const SEGMENT_FOLLOW_UP = ["ANY", "OPEN", "OVERDUE", "NONE"] as const;

const customCriterionSchema = z.object({
  fieldId: z.string().uuid(),
  operator: z.enum(SEGMENT_CUSTOM_OPERATORS),
  value: z.string().trim().max(2_000).nullable().optional()
}).superRefine((criterion, ctx) => {
  if (["EQ", "NEQ", "CONTAINS"].includes(criterion.operator) && !criterion.value?.trim()) {
    ctx.addIssue({ code: "custom", message: "Este operador exige um valor.", path: ["value"] });
  }
});

const pipelineCriterionSchema = z.object({
  pipelineId: z.string().uuid(),
  stageIds: z.array(z.string().uuid()).max(30).default([]),
  includeUnassigned: z.boolean().default(false)
}).refine(value => value.stageIds.length > 0 || value.includeUnassigned, {
  message: "Escolha ao menos uma etapa ou inclua contatos sem etapa."
});

export const segmentDefinitionSchema = z.object({
  search: z.string().trim().max(100).nullable().default(null),
  hasPhone: z.enum(["ANY", "YES", "NO"]).default("ANY"),
  hasEmail: z.enum(["ANY", "YES", "NO"]).default("ANY"),
  lastSeen: z.enum(SEGMENT_LAST_SEEN).default("ANY"),
  customFields: z.array(customCriterionSchema).max(12).default([]),
  pipeline: pipelineCriterionSchema.nullable().default(null),
  followUp: z.enum(SEGMENT_FOLLOW_UP).default("ANY")
}).superRefine((value, ctx) => {
  const ids = value.customFields.map(item => item.fieldId);
  if (new Set(ids).size !== ids.length) {
    ctx.addIssue({ code: "custom", message: "Use cada campo personalizado apenas uma vez.", path: ["customFields"] });
  }
  if (!hasNarrowingCriteria(value)) {
    ctx.addIssue({ code: "custom", message: "Adicione ao menos um critério ao segmento." });
  }
});

export type SegmentDefinition = z.infer<typeof segmentDefinitionSchema>;

export function hasNarrowingCriteria(value: SegmentDefinition) {
  return Boolean(
    value.search?.trim() ||
    value.hasPhone !== "ANY" ||
    value.hasEmail !== "ANY" ||
    value.lastSeen !== "ANY" ||
    value.customFields.length > 0 ||
    value.pipeline ||
    value.followUp !== "ANY"
  );
}

export function lastSeenCutoff(value: SegmentDefinition["lastSeen"], now: Date) {
  const days = value === "WITHIN_7D" ? 7 : value === "WITHIN_30D" ? 30 : value === "WITHIN_90D" ? 90 : null;
  return days ? new Date(now.getTime() - days * 24 * 60 * 60 * 1_000) : null;
}

export function operatorAllowedForField(
  fieldType: "TEXT" | "NUMBER" | "DATE" | "BOOLEAN" | "SELECT",
  operator: SegmentDefinition["customFields"][number]["operator"]
) {
  if (operator === "EMPTY" || operator === "NOT_EMPTY") return true;
  if (operator === "CONTAINS") return fieldType === "TEXT";
  return true;
}
TS

cat > apps/api/src/modules/segments/segment.definition.test.ts <<'TS'
import assert from "node:assert/strict";
import { test } from "node:test";
import { lastSeenCutoff, operatorAllowedForField, segmentDefinitionSchema } from "./segment.definition.js";

test("empty all-contacts definition is rejected", () => {
  assert.equal(segmentDefinitionSchema.safeParse({ search: null }).success, false);
});

test("segment definitions normalize defaults", () => {
  const parsed = segmentDefinitionSchema.parse({ hasPhone: "YES" });
  assert.equal(parsed.hasPhone, "YES");
  assert.equal(parsed.hasEmail, "ANY");
  assert.deepEqual(parsed.customFields, []);
});

test("last seen cutoff is deterministic", () => {
  const now = new Date("2026-08-31T12:00:00.000Z");
  assert.equal(lastSeenCutoff("WITHIN_7D", now)?.toISOString(), "2026-08-24T12:00:00.000Z");
});

test("contains is text-only while empty works for all fields", () => {
  assert.equal(operatorAllowedForField("TEXT", "CONTAINS"), true);
  assert.equal(operatorAllowedForField("NUMBER", "CONTAINS"), false);
  assert.equal(operatorAllowedForField("SELECT", "EMPTY"), true);
});
TS

cat > apps/api/src/modules/segments/segment.service.ts <<'TS'
import type { Prisma } from "../../generated/prisma/client.js";
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import {
  lastSeenCutoff,
  operatorAllowedForField,
  segmentDefinitionSchema,
  type SegmentDefinition
} from "./segment.definition.js";

function jsonOptions(value: unknown) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

async function validateReferences(companyId: string, definition: SegmentDefinition) {
  if (definition.customFields.length > 0) {
    const ids = definition.customFields.map(item => item.fieldId);
    const fields = await prisma.contactFieldDefinition.findMany({
      where: { companyId, id: { in: ids }, isActive: true }
    });
    const byId = new Map(fields.map(field => [field.id, field]));

    for (const criterion of definition.customFields) {
      const field = byId.get(criterion.fieldId);
      if (!field) {
        throw new AppError("Um dos campos personalizados não existe ou está inativo.", 422, "SEGMENT_FIELD_INVALID");
      }
      if (!operatorAllowedForField(field.type, criterion.operator)) {
        throw new AppError(`${field.label}: operador incompatível com o tipo do campo.`, 422, "SEGMENT_FIELD_OPERATOR_INVALID");
      }
      if (
        field.type === "SELECT" &&
        ["EQ", "NEQ"].includes(criterion.operator) &&
        criterion.value &&
        !jsonOptions(field.options).includes(criterion.value)
      ) {
        throw new AppError(`${field.label}: a opção selecionada não existe mais.`, 422, "SEGMENT_FIELD_OPTION_INVALID");
      }
      if (
        field.type === "BOOLEAN" &&
        ["EQ", "NEQ"].includes(criterion.operator) &&
        criterion.value &&
        !["true", "false"].includes(criterion.value)
      ) {
        throw new AppError(`${field.label}: valor booleano inválido.`, 422, "SEGMENT_FIELD_BOOLEAN_INVALID");
      }
    }
  }

  if (definition.pipeline) {
    const pipeline = await prisma.crmPipeline.findFirst({
      where: { id: definition.pipeline.pipelineId, companyId, isActive: true },
      include: {
        stages: {
          where: { id: { in: definition.pipeline.stageIds }, isActive: true },
          select: { id: true }
        }
      }
    });

    if (!pipeline) {
      throw new AppError("O pipeline selecionado não existe ou está inativo.", 422, "SEGMENT_PIPELINE_INVALID");
    }
    if (pipeline.stages.length !== definition.pipeline.stageIds.length) {
      throw new AppError("Uma das etapas selecionadas não pertence ao pipeline ou está inativa.", 422, "SEGMENT_STAGE_INVALID");
    }
  }
}

function customFieldWhere(criterion: SegmentDefinition["customFields"][number]): Prisma.ContactWhereInput {
  if (criterion.operator === "EMPTY") {
    return { customFieldValues: { none: { fieldId: criterion.fieldId } } };
  }
  if (criterion.operator === "NOT_EMPTY") {
    return { customFieldValues: { some: { fieldId: criterion.fieldId } } };
  }
  if (criterion.operator === "NEQ") {
    return { customFieldValues: { none: { fieldId: criterion.fieldId, value: criterion.value ?? "" } } };
  }
  if (criterion.operator === "CONTAINS") {
    return {
      customFieldValues: {
        some: { fieldId: criterion.fieldId, value: { contains: criterion.value ?? "" } }
      }
    };
  }
  return { customFieldValues: { some: { fieldId: criterion.fieldId, value: criterion.value ?? "" } } };
}

export function buildSegmentWhere(input: {
  companyId: string;
  definition: SegmentDefinition;
  now: Date;
}): Prisma.ContactWhereInput {
  const { definition } = input;
  const AND: Prisma.ContactWhereInput[] = [];

  if (definition.search) {
    AND.push({
      OR: [
        { name: { contains: definition.search } },
        { whatsappName: { contains: definition.search } },
        { phoneNumber: { contains: definition.search } },
        { email: { contains: definition.search } }
      ]
    });
  }

  if (definition.hasPhone === "YES") AND.push({ phoneNumber: { not: null } });
  if (definition.hasPhone === "NO") AND.push({ phoneNumber: null });
  if (definition.hasEmail === "YES") AND.push({ email: { not: null } });
  if (definition.hasEmail === "NO") AND.push({ email: null });

  if (definition.lastSeen === "NEVER") {
    AND.push({ lastSeenAt: null });
  } else {
    const cutoff = lastSeenCutoff(definition.lastSeen, input.now);
    if (cutoff) AND.push({ lastSeenAt: { gte: cutoff } });
  }

  for (const criterion of definition.customFields) {
    AND.push(customFieldWhere(criterion));
  }

  if (definition.pipeline) {
    const stageMatch: Prisma.ContactWhereInput = {
      pipelineStates: {
        some: {
          pipelineId: definition.pipeline.pipelineId,
          stageId: { in: definition.pipeline.stageIds }
        }
      }
    };
    const unassigned: Prisma.ContactWhereInput = {
      pipelineStates: { none: { pipelineId: definition.pipeline.pipelineId } }
    };

    if (definition.pipeline.stageIds.length > 0 && definition.pipeline.includeUnassigned) {
      AND.push({ OR: [stageMatch, unassigned] });
    } else if (definition.pipeline.stageIds.length > 0) {
      AND.push(stageMatch);
    } else {
      AND.push(unassigned);
    }
  }

  if (definition.followUp === "OPEN") {
    AND.push({ crmTasks: { some: { status: "OPEN" } } });
  } else if (definition.followUp === "OVERDUE") {
    AND.push({ crmTasks: { some: { status: "OPEN", dueAt: { lt: input.now } } } });
  } else if (definition.followUp === "NONE") {
    AND.push({ crmTasks: { none: { status: "OPEN" } } });
  }

  return {
    companyId: input.companyId,
    isGroup: false,
    ...(AND.length > 0 ? { AND } : {})
  };
}

const previewContactSelect = {
  id: true,
  name: true,
  whatsappName: true,
  phoneNumber: true,
  email: true,
  lastSeenAt: true,
  updatedAt: true,
  pipelineStates: {
    orderBy: { updatedAt: "desc" as const },
    take: 3,
    select: {
      id: true,
      enteredAt: true,
      pipeline: { select: { id: true, name: true } },
      stage: { select: { id: true, name: true, colorKey: true, outcome: true } }
    }
  },
  crmTasks: {
    where: { status: "OPEN" as const },
    orderBy: { dueAt: "asc" as const },
    take: 1,
    select: { id: true, title: true, priority: true, dueAt: true }
  },
  tickets: {
    orderBy: { lastMessageAt: "desc" as const },
    take: 1,
    select: { id: true, status: true, lastMessage: true, lastMessageAt: true }
  }
} satisfies Prisma.ContactSelect;

export async function resolveSegment(input: { companyId: string; definition: unknown; limit: number }) {
  const definition = segmentDefinitionSchema.parse(input.definition);
  await validateReferences(input.companyId, definition);
  const now = new Date();
  const where = buildSegmentWhere({ companyId: input.companyId, definition, now });

  const [count, contacts] = await Promise.all([
    prisma.contact.count({ where }),
    prisma.contact.findMany({
      where,
      select: previewContactSelect,
      orderBy: [{ lastSeenAt: "desc" }, { updatedAt: "desc" }],
      take: Math.min(Math.max(input.limit, 1), 100)
    })
  ]);

  return { definition, count, truncated: count > contacts.length, contacts };
}

export async function listSegments(companyId: string, includeInactive = false) {
  return prisma.contactSegment.findMany({
    where: { companyId, ...(includeInactive ? {} : { isActive: true }) },
    include: {
      createdByMembership: {
        select: { id: true, user: { select: { id: true, name: true } } }
      }
    },
    orderBy: [{ isActive: "desc" }, { updatedAt: "desc" }],
    take: 100
  });
}

async function ensureUniqueName(input: { companyId: string; name: string; excludeId?: string }) {
  const existing = await prisma.contactSegment.findFirst({
    where: {
      companyId: input.companyId,
      name: input.name,
      ...(input.excludeId ? { id: { not: input.excludeId } } : {})
    },
    select: { id: true }
  });
  if (existing) throw new AppError("Já existe um segmento com esse nome.", 409, "SEGMENT_NAME_EXISTS");
}

export async function createSegment(input: {
  companyId: string;
  actorMembershipId: string;
  name: string;
  description?: string | null;
  definition: unknown;
}) {
  const definition = segmentDefinitionSchema.parse(input.definition);
  await Promise.all([
    validateReferences(input.companyId, definition),
    ensureUniqueName({ companyId: input.companyId, name: input.name.trim() })
  ]);

  const segment = await prisma.contactSegment.create({
    data: {
      companyId: input.companyId,
      createdByMembershipId: input.actorMembershipId,
      name: input.name.trim(),
      description: input.description?.trim() || null,
      definition: toPrismaJson(definition)
    },
    include: {
      createdByMembership: {
        select: { id: true, user: { select: { id: true, name: true } } }
      }
    }
  });

  publishRealtime(input.companyId, {
    type: "segment.updated",
    segmentId: segment.id,
    membershipId: input.actorMembershipId
  });
  return segment;
}

export async function updateSegment(input: {
  companyId: string;
  actorMembershipId: string;
  segmentId: string;
  name?: string;
  description?: string | null;
  definition?: unknown;
  isActive?: boolean;
}) {
  const current = await prisma.contactSegment.findFirst({
    where: { id: input.segmentId, companyId: input.companyId }
  });
  if (!current) throw new AppError("Segmento não encontrado.", 404, "SEGMENT_NOT_FOUND");

  const name = input.name?.trim();
  const definition = input.definition !== undefined ? segmentDefinitionSchema.parse(input.definition) : null;

  await Promise.all([
    definition ? validateReferences(input.companyId, definition) : Promise.resolve(),
    name ? ensureUniqueName({ companyId: input.companyId, name, excludeId: current.id }) : Promise.resolve()
  ]);

  const segment = await prisma.contactSegment.update({
    where: { id: current.id },
    data: {
      ...(name !== undefined ? { name } : {}),
      ...(input.description !== undefined ? { description: input.description?.trim() || null } : {}),
      ...(definition ? { definition: toPrismaJson(definition) } : {}),
      ...(input.isActive !== undefined ? { isActive: input.isActive } : {})
    },
    include: {
      createdByMembership: {
        select: { id: true, user: { select: { id: true, name: true } } }
      }
    }
  });

  publishRealtime(input.companyId, {
    type: "segment.updated",
    segmentId: segment.id,
    membershipId: input.actorMembershipId
  });
  return segment;
}

export async function resolveSavedSegment(input: { companyId: string; segmentId: string; limit: number }) {
  const segment = await prisma.contactSegment.findFirst({
    where: { id: input.segmentId, companyId: input.companyId }
  });
  if (!segment) throw new AppError("Segmento não encontrado.", 404, "SEGMENT_NOT_FOUND");

  const resolved = await resolveSegment({
    companyId: input.companyId,
    definition: segment.definition,
    limit: input.limit
  });
  return { segment, ...resolved };
}

export async function getSegmentContext(companyId: string) {
  const [fields, pipelines] = await Promise.all([
    prisma.contactFieldDefinition.findMany({
      where: { companyId, isActive: true },
      select: { id: true, key: true, label: true, type: true, options: true, required: true, position: true },
      orderBy: [{ position: "asc" }, { label: "asc" }]
    }),
    prisma.crmPipeline.findMany({
      where: { companyId, isActive: true },
      select: {
        id: true,
        name: true,
        description: true,
        position: true,
        stages: {
          where: { isActive: true },
          select: { id: true, name: true, colorKey: true, outcome: true, position: true },
          orderBy: { position: "asc" }
        }
      },
      orderBy: { position: "asc" }
    })
  ]);
  return { fields, pipelines };
}
TS

cat > apps/api/src/modules/segments/segment.routes.ts <<'TS'
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { requirePermission } from "../auth/auth.guard.js";
import { segmentDefinitionSchema } from "./segment.definition.js";
import {
  createSegment,
  getSegmentContext,
  listSegments,
  resolveSavedSegment,
  resolveSegment,
  updateSegment
} from "./segment.service.js";

const idSchema = z.object({ id: z.string().uuid() });
const limitQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(60)
});
const previewSchema = z.object({
  definition: segmentDefinitionSchema,
  limit: z.number().int().min(1).max(100).default(60)
});
const createSchema = z.object({
  name: z.string().trim().min(2).max(140),
  description: z.string().trim().max(500).nullable().optional(),
  definition: segmentDefinitionSchema
});
const updateSchema = z.object({
  name: z.string().trim().min(2).max(140).optional(),
  description: z.string().trim().max(500).nullable().optional(),
  definition: segmentDefinitionSchema.optional(),
  isActive: z.boolean().optional()
}).refine(value => Object.keys(value).length > 0, {
  message: "Informe ao menos uma alteração."
});

export async function segmentRoutes(app: FastifyInstance) {
  app.get("/api/v1/segments", async request => {
    const auth = await requirePermission(request, "segments.read");
    return { segments: await listSegments(auth.companyId) };
  });

  app.get("/api/v1/segments/manage", async request => {
    const auth = await requirePermission(request, "segments.manage");
    return { segments: await listSegments(auth.companyId, true) };
  });

  app.get("/api/v1/segments/context", async request => {
    const auth = await requirePermission(request, "segments.read");
    return getSegmentContext(auth.companyId);
  });

  app.post("/api/v1/segments/preview", async request => {
    const auth = await requirePermission(request, "segments.read");
    const input = previewSchema.parse(request.body);
    return resolveSegment({ companyId: auth.companyId, definition: input.definition, limit: input.limit });
  });

  app.post("/api/v1/segments", async (request, reply) => {
    const auth = await requirePermission(request, "segments.manage");
    const input = createSchema.parse(request.body);
    return reply.status(201).send({
      segment: await createSegment({
        companyId: auth.companyId,
        actorMembershipId: auth.membershipId,
        ...input
      })
    });
  });

  app.patch("/api/v1/segments/:id", async request => {
    const auth = await requirePermission(request, "segments.manage");
    const params = idSchema.parse(request.params);
    const input = updateSchema.parse(request.body);
    return {
      segment: await updateSegment({
        companyId: auth.companyId,
        actorMembershipId: auth.membershipId,
        segmentId: params.id,
        ...input
      })
    };
  });

  app.get("/api/v1/segments/:id/contacts", async request => {
    const auth = await requirePermission(request, "segments.read");
    const params = idSchema.parse(request.params);
    const query = limitQuery.parse(request.query);
    return resolveSavedSegment({ companyId: auth.companyId, segmentId: params.id, limit: query.limit });
  });
}
TS

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
const importLine = 'import { segmentRoutes } from "./modules/segments/segment.routes.js";';
if (!content.includes(importLine)) {
  const anchor = 'import { taskRoutes } from "./modules/tasks/task.routes.js";';
  if (!content.includes(anchor)) throw new Error("taskRoutes import anchor not found.");
  content = content.replace(anchor, `${anchor}\n${importLine}`);
}
if (!content.includes("await app.register(segmentRoutes);")) {
  const anchor = "  await app.register(taskRoutes);";
  if (!content.includes(anchor)) throw new Error("taskRoutes registration anchor not found.");
  content = content.replace(anchor, `${anchor}\n  await app.register(segmentRoutes);`);
}
fs.writeFileSync(path, content);
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/security/permissions.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
const typeStart = content.indexOf("export type WappPermission =");
const typeEnd = content.indexOf(";", typeStart);
if (typeStart < 0 || typeEnd < 0) throw new Error("WappPermission union not found.");
let union = content.slice(typeStart, typeEnd);
for (const permission of ["segments.read", "segments.manage"]) {
  if (!union.includes(`"${permission}"`)) union += `\n  | "${permission}"`;
}
content = content.slice(0, typeStart) + union + content.slice(typeEnd);

function arrayBounds(source, role) {
  const start = source.indexOf(`  ${role}: [`);
  if (start < 0) throw new Error(`${role} permission block not found.`);
  const open = source.indexOf("[", start);
  let depth = 0, inString = false, quote = "", escape = false;
  for (let i = open; i < source.length; i += 1) {
    const c = source[i];
    if (inString) {
      if (escape) escape = false;
      else if (c === "\\") escape = true;
      else if (c === quote) inString = false;
      continue;
    }
    if (c === '"' || c === "'") { inString = true; quote = c; continue; }
    if (c === "[") depth += 1;
    else if (c === "]") {
      depth -= 1;
      if (depth === 0) return { start: open, end: i };
    }
  }
  throw new Error(`${role} permission array end not found.`);
}

const wanted = {
  OWNER: ["segments.read", "segments.manage"],
  ADMIN: ["segments.read", "segments.manage"],
  SUPERVISOR: ["segments.read", "segments.manage"],
  AGENT: ["segments.read"]
};
for (const role of ["AGENT", "SUPERVISOR", "ADMIN", "OWNER"]) {
  const bounds = arrayBounds(content, role);
  const block = content.slice(bounds.start, bounds.end + 1);
  const missing = wanted[role].filter(permission => !block.includes(`"${permission}"`));
  if (missing.length === 0) continue;
  const before = content.slice(0, bounds.end).replace(/\s+$/, "");
  const after = content.slice(bounds.end);
  const separator = before.endsWith("[") ? "\n" : before.endsWith(",") ? "\n" : ",\n";
  content = before + separator + missing.map(permission => `    "${permission}"`).join(",\n") + "\n  " + after;
}
fs.writeFileSync(path, content);
console.log("[P3.4] Backend segment permissions installed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const permissionPath = "apps/api/src/security/permissions.ts";
const testPath = "apps/api/src/security/permissions.test.ts";
const source = fs.readFileSync(permissionPath, "utf8").replace(/\r\n/g, "\n");
let test = fs.readFileSync(testPath, "utf8").replace(/\r\n/g, "\n");
const start = source.indexOf("export type WappPermission =");
const end = source.indexOf(";", start);
const permissions = Array.from(source.slice(start, end).matchAll(/"([^"]+)"/g), match => match[1]);
const declarationStart = test.indexOf("const allPermissions:");
const describeStart = test.indexOf("describe(", declarationStart);
if (declarationStart < 0 || describeStart < 0) throw new Error("permissions.test boundary not found.");
const declaration = `const allPermissions:\n  WappPermission[] = [\n${permissions.map(p => `    "${p}"`).join(",\n")}\n  ];\n\n`;
test = test.slice(0, declarationStart) + declaration + test.slice(describeStart);
if (!test.includes('"saved segments are readable operationally and managed by leaders"')) {
  test += `\n\ndescribe(\n  "contact segment permissions",\n  () => {\n    it(\n      "saved segments are readable operationally and managed by leaders",\n      () => {\n        for (const role of ["OWNER", "ADMIN", "SUPERVISOR"] as const) {\n          assert.equal(roleHasPermission(role, "segments.read"), true);\n          assert.equal(roleHasPermission(role, "segments.manage"), true);\n        }\n        assert.equal(roleHasPermission("AGENT", "segments.read"), true);\n        assert.equal(roleHasPermission("AGENT", "segments.manage"), false);\n      }\n    );\n  }\n);\n`;
}
fs.writeFileSync(testPath, test);
console.log(`[P3.4] permissions.test rebuilt with ${permissions.length} permissions.`);
NODE

node <<'NODE'
const fs = require("node:fs");
function patch(path) {
  let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
  const typeStart = content.indexOf("export type RealtimeEventType =");
  const typeEnd = content.indexOf(";", typeStart);
  if (typeStart < 0 || typeEnd < 0) throw new Error(`RealtimeEventType not found in ${path}`);
  let union = content.slice(typeStart, typeEnd);
  if (!union.includes('"segment.updated"')) union += '\n  | "segment.updated"';
  content = content.slice(0, typeStart) + union + content.slice(typeEnd);
  const interfaceStart = content.indexOf("export interface RealtimeEvent {");
  const interfaceEnd = content.indexOf("\n}", interfaceStart);
  if (interfaceStart < 0 || interfaceEnd < 0) throw new Error(`RealtimeEvent interface not found in ${path}`);
  let block = content.slice(interfaceStart, interfaceEnd);
  if (!block.includes("segmentId?: string;")) block += "\n  segmentId?: string;";
  content = content.slice(0, interfaceStart) + block + content.slice(interfaceEnd);
  fs.writeFileSync(path, content);
}
patch("apps/api/src/modules/realtime/realtime.bus.ts");
patch("apps/web/lib/realtime-types.ts");
console.log("[P3.4] segment.updated realtime contract installed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/lib/permissions.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
const typeStart = content.indexOf("export type UiPermission =");
const typeEnd = content.indexOf(";", typeStart);
if (typeStart < 0 || typeEnd < 0) throw new Error("UiPermission union not found.");
let union = content.slice(typeStart, typeEnd);
for (const permission of ["segments.view", "segments.manage"]) {
  if (!union.includes(`"${permission}"`)) union += `\n  | "${permission}"`;
}
content = content.slice(0, typeStart) + union + content.slice(typeEnd);
function arrayBounds(source, role) {
  const start = source.indexOf(`  ${role}: [`);
  if (start < 0) throw new Error(`${role} UI block not found.`);
  const open = source.indexOf("[", start);
  let depth = 0, inString = false, quote = "", escape = false;
  for (let i = open; i < source.length; i += 1) {
    const c = source[i];
    if (inString) {
      if (escape) escape = false;
      else if (c === "\\") escape = true;
      else if (c === quote) inString = false;
      continue;
    }
    if (c === '"' || c === "'") { inString = true; quote = c; continue; }
    if (c === "[") depth += 1;
    else if (c === "]") { depth -= 1; if (depth === 0) return { start: open, end: i }; }
  }
  throw new Error(`${role} UI array end not found.`);
}
const wanted = {
  OWNER: ["segments.view", "segments.manage"],
  ADMIN: ["segments.view", "segments.manage"],
  SUPERVISOR: ["segments.view", "segments.manage"],
  AGENT: ["segments.view"]
};
for (const role of ["AGENT", "SUPERVISOR", "ADMIN", "OWNER"]) {
  const bounds = arrayBounds(content, role);
  const block = content.slice(bounds.start, bounds.end + 1);
  const missing = wanted[role].filter(p => !block.includes(`"${p}"`));
  if (!missing.length) continue;
  const before = content.slice(0, bounds.end).replace(/\s+$/, "");
  const after = content.slice(bounds.end);
  const sep = before.endsWith("[") ? "\n" : before.endsWith(",") ? "\n" : ",\n";
  content = before + sep + missing.map(p => `    "${p}"`).join(",\n") + "\n  " + after;
}
fs.writeFileSync(path, content);
console.log("[P3.4] UI segment permissions installed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/app/dashboard/page.tsx";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
if (!content.includes('href: "/dashboard/segments"')) {
  const anchor = `  {\n    label: "Tarefas",\n    href: "/dashboard/tasks",\n    permission: "tasks.view"\n  },`;
  if (!content.includes(anchor)) throw new Error("Tasks navigation anchor not found.");
  content = content.replace(anchor, `${anchor}\n  {\n    label: "Segmentos",\n    href: "/dashboard/segments",\n    permission: "segments.view"\n  },`);
}
fs.writeFileSync(path, content);
NODE

cat > apps/web/app/dashboard/segments/page.tsx <<'TSX'
"use client";

import { type FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";
import { roleCan } from "@/lib/permissions";

type BinaryFilter = "ANY" | "YES" | "NO";
type LastSeenFilter = "ANY" | "WITHIN_7D" | "WITHIN_30D" | "WITHIN_90D" | "NEVER";
type FollowUpFilter = "ANY" | "OPEN" | "OVERDUE" | "NONE";
type CustomOperator = "EQ" | "NEQ" | "CONTAINS" | "EMPTY" | "NOT_EMPTY";

interface CustomCriterion {
  fieldId: string;
  operator: CustomOperator;
  value: string | null;
}

interface SegmentDefinition {
  search: string | null;
  hasPhone: BinaryFilter;
  hasEmail: BinaryFilter;
  lastSeen: LastSeenFilter;
  customFields: CustomCriterion[];
  pipeline: { pipelineId: string; stageIds: string[]; includeUnassigned: boolean } | null;
  followUp: FollowUpFilter;
}

interface Field {
  id: string;
  label: string;
  type: "TEXT" | "NUMBER" | "DATE" | "BOOLEAN" | "SELECT";
  options: unknown;
}

interface Stage {
  id: string;
  name: string;
  colorKey: string;
  outcome: "OPEN" | "WON" | "LOST";
}

interface Pipeline {
  id: string;
  name: string;
  description: string | null;
  stages: Stage[];
}

interface Segment {
  id: string;
  name: string;
  description: string | null;
  definition: SegmentDefinition;
  isActive: boolean;
  updatedAt: string;
  createdByMembership: { id: string; user: { id: string; name: string } } | null;
}

interface PreviewContact {
  id: string;
  name: string;
  phoneNumber: string | null;
  email: string | null;
  lastSeenAt: string | null;
  pipelineStates: Array<{
    id: string;
    pipeline: { id: string; name: string };
    stage: { id: string; name: string; colorKey: string; outcome: string };
  }>;
  crmTasks: Array<{ id: string; title: string; priority: string; dueAt: string }>;
  tickets: Array<{ id: string; status: string; lastMessage: string | null; lastMessageAt: string }>;
}

interface Preview {
  count: number;
  truncated: boolean;
  contacts: PreviewContact[];
}

const EMPTY_DEFINITION: SegmentDefinition = {
  search: null,
  hasPhone: "ANY",
  hasEmail: "ANY",
  lastSeen: "ANY",
  customFields: [],
  pipeline: null,
  followUp: "ANY"
};

const operatorLabels: Record<CustomOperator, string> = {
  EQ: "É igual a",
  NEQ: "É diferente de",
  CONTAINS: "Contém",
  EMPTY: "Está vazio",
  NOT_EMPTY: "Está preenchido"
};

function cloneDefinition(value: SegmentDefinition): SegmentDefinition {
  return JSON.parse(JSON.stringify(value)) as SegmentDefinition;
}

function hasCriteria(value: SegmentDefinition) {
  return Boolean(
    value.search?.trim() ||
    value.hasPhone !== "ANY" ||
    value.hasEmail !== "ANY" ||
    value.lastSeen !== "ANY" ||
    value.customFields.length ||
    value.pipeline ||
    value.followUp !== "ANY"
  );
}

function optionsOf(field: Field) {
  return Array.isArray(field.options)
    ? field.options.filter((item): item is string => typeof item === "string")
    : [];
}

function dateTimeLabel(value: string | null) {
  if (!value) return "Nunca";
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}

export default function SegmentsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();
  const [segments, setSegments] = useState<Segment[]>([]);
  const [fields, setFields] = useState<Field[]>([]);
  const [pipelines, setPipelines] = useState<Pipeline[]>([]);
  const [selectedSegmentId, setSelectedSegmentId] = useState<string | null>(null);
  const [segmentName, setSegmentName] = useState("");
  const [description, setDescription] = useState("");
  const [definition, setDefinition] = useState<SegmentDefinition>(() => cloneDefinition(EMPTY_DEFINITION));
  const [customFieldId, setCustomFieldId] = useState("");
  const [customOperator, setCustomOperator] = useState<CustomOperator>("EQ");
  const [customValue, setCustomValue] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [busy, setBusy] = useState(true);
  const [previewing, setPreviewing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const canManage = session ? roleCan(session.role, "segments.manage") : false;
  const selectedSegment = useMemo(
    () => segments.find(segment => segment.id === selectedSegmentId) ?? null,
    [segments, selectedSegmentId]
  );
  const selectedField = useMemo(
    () => fields.find(field => field.id === customFieldId) ?? null,
    [customFieldId, fields]
  );
  const selectedPipeline = useMemo(
    () => pipelines.find(item => item.id === definition.pipeline?.pipelineId) ?? null,
    [definition.pipeline?.pipelineId, pipelines]
  );

  const loadBase = useCallback(async () => {
    const [segmentPayload, context] = await Promise.all([
      request<{ segments: Segment[] }>(canManage ? "/api/v1/segments/manage" : "/api/v1/segments"),
      request<{ fields: Field[]; pipelines: Pipeline[] }>("/api/v1/segments/context")
    ]);
    setSegments(segmentPayload.segments);
    setFields(context.fields);
    setPipelines(context.pipelines);
  }, [canManage, request]);

  const previewDefinition = useCallback(async (value: SegmentDefinition) => {
    if (!hasCriteria(value)) {
      setPreview(null);
      setError("Adicione ao menos um critério antes de visualizar.");
      return;
    }
    setPreviewing(true);
    setError("");
    try {
      const payload = await request<Preview>("/api/v1/segments/preview", {
        method: "POST",
        body: JSON.stringify({ definition: value, limit: 60 })
      });
      setPreview(payload);
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : "Não foi possível calcular o segmento.");
    } finally {
      setPreviewing(false);
    }
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }
    if (session && !roleCan(session.role, "segments.view")) {
      router.replace("/dashboard");
      return;
    }
    if (session) {
      setBusy(true);
      void loadBase()
        .catch(() => setError("Não foi possível carregar os segmentos."))
        .finally(() => setBusy(false));
    }
  }, [loadBase, loading, router, session]);

  useEffect(() => {
    if (!session) return;
    return subscribe("/api/v1/realtime/events", event => {
      if (event.type === "segment.updated") void loadBase();
      if ((event.type === "contact.pipeline.updated" || event.type === "task.updated") && preview && hasCriteria(definition)) {
        void previewDefinition(definition);
      }
    });
  }, [definition, loadBase, preview, previewDefinition, session, subscribe]);

  function resetBuilder() {
    setSelectedSegmentId(null);
    setSegmentName("");
    setDescription("");
    setDefinition(cloneDefinition(EMPTY_DEFINITION));
    setPreview(null);
    setNotice("");
    setError("");
  }

  function selectSegment(segment: Segment) {
    const next = cloneDefinition(segment.definition);
    setSelectedSegmentId(segment.id);
    setSegmentName(segment.name);
    setDescription(segment.description ?? "");
    setDefinition(next);
    setNotice("");
    setError("");
    void previewDefinition(next);
  }

  function setPipelineId(pipelineId: string) {
    setDefinition(current => ({
      ...current,
      pipeline: pipelineId ? { pipelineId, stageIds: [], includeUnassigned: true } : null
    }));
  }

  function toggleStage(stageId: string) {
    setDefinition(current => {
      if (!current.pipeline) return current;
      const exists = current.pipeline.stageIds.includes(stageId);
      return {
        ...current,
        pipeline: {
          ...current.pipeline,
          stageIds: exists
            ? current.pipeline.stageIds.filter(id => id !== stageId)
            : [...current.pipeline.stageIds, stageId]
        }
      };
    });
  }

  function operatorsFor(field: Field): CustomOperator[] {
    return field.type === "TEXT"
      ? ["EQ", "NEQ", "CONTAINS", "EMPTY", "NOT_EMPTY"]
      : ["EQ", "NEQ", "EMPTY", "NOT_EMPTY"];
  }

  function addCustomCriterion(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedField) return;
    if (definition.customFields.some(item => item.fieldId === selectedField.id)) {
      setError("Esse campo já está sendo usado no segmento.");
      return;
    }
    const needsValue = !["EMPTY", "NOT_EMPTY"].includes(customOperator);
    if (needsValue && !customValue.trim()) {
      setError("Informe o valor do campo personalizado.");
      return;
    }
    setDefinition(current => ({
      ...current,
      customFields: [
        ...current.customFields,
        {
          fieldId: selectedField.id,
          operator: customOperator,
          value: needsValue ? customValue.trim() : null
        }
      ]
    }));
    setCustomFieldId("");
    setCustomOperator("EQ");
    setCustomValue("");
    setError("");
  }

  function removeCriterion(fieldId: string) {
    setDefinition(current => ({
      ...current,
      customFields: current.customFields.filter(item => item.fieldId !== fieldId)
    }));
  }

  async function saveSegment() {
    if (!canManage) return;
    if (!segmentName.trim()) {
      setError("Informe um nome para o segmento.");
      return;
    }
    if (!hasCriteria(definition)) {
      setError("Adicione ao menos um critério ao segmento.");
      return;
    }
    setSaving(true);
    setError("");
    setNotice("");
    try {
      const payload = await request<{ segment: Segment }>(
        selectedSegmentId ? `/api/v1/segments/${selectedSegmentId}` : "/api/v1/segments",
        {
          method: selectedSegmentId ? "PATCH" : "POST",
          body: JSON.stringify({
            name: segmentName.trim(),
            description: description.trim() || null,
            definition
          })
        }
      );
      setSelectedSegmentId(payload.segment.id);
      setNotice(selectedSegmentId ? "Segmento atualizado." : "Segmento salvo.");
      await loadBase();
      await previewDefinition(definition);
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : "Não foi possível salvar o segmento.");
    } finally {
      setSaving(false);
    }
  }

  async function toggleArchive() {
    if (!canManage || !selectedSegment) return;
    setSaving(true);
    setError("");
    try {
      await request(`/api/v1/segments/${selectedSegment.id}`, {
        method: "PATCH",
        body: JSON.stringify({ isActive: !selectedSegment.isActive })
      });
      setNotice(selectedSegment.isActive ? "Segmento arquivado." : "Segmento reativado.");
      await loadBase();
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : "Não foi possível alterar o segmento.");
    } finally {
      setSaving(false);
    }
  }

  function renderCustomValue(field: Field) {
    if (["EMPTY", "NOT_EMPTY"].includes(customOperator)) return null;
    if (field.type === "SELECT") {
      return (
        <select value={customValue} onChange={event => setCustomValue(event.target.value)}>
          <option value="">Selecionar…</option>
          {optionsOf(field).map(option => <option key={option} value={option}>{option}</option>)}
        </select>
      );
    }
    if (field.type === "BOOLEAN") {
      return (
        <select value={customValue} onChange={event => setCustomValue(event.target.value)}>
          <option value="">Selecionar…</option>
          <option value="true">Sim</option>
          <option value="false">Não</option>
        </select>
      );
    }
    return (
      <input
        type={field.type === "NUMBER" ? "number" : field.type === "DATE" ? "date" : "text"}
        value={customValue}
        onChange={event => setCustomValue(event.target.value)}
      />
    );
  }

  if (loading || !session) return <main className="dashboard-loading">Carregando segmentos…</main>;

  return (
    <main className="segments-screen">
      <header className="segments-header">
        <div>
          <button className="connections-back" onClick={() => router.push("/dashboard")} type="button">← Visão geral</button>
          <span className="eyebrow">CRM</span>
          <h1>Segmentos</h1>
          <p>Audiências dinâmicas com dados do contato, Perfil 360º, pipeline e follow-ups.</p>
        </div>
        <button className="ghost-button" onClick={resetBuilder} type="button">Novo filtro</button>
      </header>

      {error && <div className="segments-feedback segments-feedback--error">{error}</div>}
      {notice && <div className="segments-feedback">{notice}</div>}

      <section className="segments-layout">
        <aside className="segment-saved-list">
          <header><strong>Salvos</strong><span>{segments.length}</span></header>
          <div>
            {segments.map(segment => (
              <button
                key={segment.id}
                className={
                  selectedSegmentId === segment.id
                    ? "segment-saved-item segment-saved-item--active"
                    : segment.isActive
                      ? "segment-saved-item"
                      : "segment-saved-item segment-saved-item--archived"
                }
                onClick={() => selectSegment(segment)}
                type="button"
              >
                <div><strong>{segment.name}</strong><small>{segment.description ?? "Sem descrição"}</small></div>
                <span>{segment.isActive ? "Ativo" : "Arquivado"}</span>
              </button>
            ))}
            {!busy && segments.length === 0 && <div className="segments-empty">Nenhum segmento salvo.</div>}
          </div>
        </aside>

        <section className="segment-builder">
          <header>
            <div><strong>{selectedSegmentId ? "Editar segmento" : "Construtor"}</strong><span>Os critérios são combinados com “E”.</span></div>
            {canManage && (
              <div>
                {selectedSegment && (
                  <button className="ghost-button" disabled={saving} onClick={() => void toggleArchive()} type="button">
                    {selectedSegment.isActive ? "Arquivar" : "Reativar"}
                  </button>
                )}
                <button className="primary-button" disabled={saving} onClick={() => void saveSegment()} type="button">
                  <span>{saving ? "Salvando…" : selectedSegmentId ? "Salvar alterações" : "Salvar segmento"}</span>
                </button>
              </div>
            )}
          </header>

          {canManage && (
            <div className="segment-identity-fields">
              <label><span>Nome</span><input maxLength={140} value={segmentName} onChange={event => setSegmentName(event.target.value)} placeholder="Ex.: Leads quentes sem follow-up" /></label>
              <label><span>Descrição</span><input maxLength={500} value={description} onChange={event => setDescription(event.target.value)} placeholder="Uso interno opcional" /></label>
            </div>
          )}

          <div className="segment-filter-grid">
            <label><span>Busca</span><input value={definition.search ?? ""} onChange={event => setDefinition(current => ({ ...current, search: event.target.value || null }))} placeholder="Nome, WhatsApp, telefone ou e-mail" /></label>
            <label><span>Telefone</span><select value={definition.hasPhone} onChange={event => setDefinition(current => ({ ...current, hasPhone: event.target.value as BinaryFilter }))}><option value="ANY">Qualquer</option><option value="YES">Com telefone</option><option value="NO">Sem telefone</option></select></label>
            <label><span>E-mail</span><select value={definition.hasEmail} onChange={event => setDefinition(current => ({ ...current, hasEmail: event.target.value as BinaryFilter }))}><option value="ANY">Qualquer</option><option value="YES">Com e-mail</option><option value="NO">Sem e-mail</option></select></label>
            <label><span>Última atividade</span><select value={definition.lastSeen} onChange={event => setDefinition(current => ({ ...current, lastSeen: event.target.value as LastSeenFilter }))}><option value="ANY">Qualquer</option><option value="WITHIN_7D">Últimos 7 dias</option><option value="WITHIN_30D">Últimos 30 dias</option><option value="WITHIN_90D">Últimos 90 dias</option><option value="NEVER">Nunca visto</option></select></label>
            <label><span>Follow-up</span><select value={definition.followUp} onChange={event => setDefinition(current => ({ ...current, followUp: event.target.value as FollowUpFilter }))}><option value="ANY">Qualquer</option><option value="OPEN">Com tarefa aberta</option><option value="OVERDUE">Com tarefa atrasada</option><option value="NONE">Sem tarefa aberta</option></select></label>
            <label><span>Pipeline</span><select value={definition.pipeline?.pipelineId ?? ""} onChange={event => setPipelineId(event.target.value)}><option value="">Não filtrar</option>{pipelines.map(pipeline => <option key={pipeline.id} value={pipeline.id}>{pipeline.name}</option>)}</select></label>
          </div>

          {definition.pipeline && selectedPipeline && (
            <div className="segment-stage-filter">
              <div>
                <strong>Etapas em {selectedPipeline.name}</strong>
                <label><input type="checkbox" checked={definition.pipeline.includeUnassigned} onChange={event => setDefinition(current => current.pipeline ? ({ ...current, pipeline: { ...current.pipeline, includeUnassigned: event.target.checked } }) : current)} /> Sem etapa</label>
              </div>
              <div className="segment-stage-options">
                {selectedPipeline.stages.map(stage => (
                  <label key={stage.id}>
                    <input type="checkbox" checked={definition.pipeline?.stageIds.includes(stage.id) ?? false} onChange={() => toggleStage(stage.id)} />
                    <span className={`pipeline-stage-color pipeline-stage-color--${stage.colorKey.toLowerCase()}`} />
                    {stage.name}
                  </label>
                ))}
              </div>
            </div>
          )}

          <section className="segment-custom-fields">
            <header><div><strong>Campos personalizados</strong><span>Filtros do Perfil 360º.</span></div></header>
            <form className="segment-custom-form" onSubmit={addCustomCriterion}>
              <select value={customFieldId} onChange={event => {
                const fieldId = event.target.value;
                setCustomFieldId(fieldId);
                const field = fields.find(item => item.id === fieldId);
                setCustomOperator(field ? operatorsFor(field)[0] : "EQ");
                setCustomValue("");
              }}>
                <option value="">Escolher campo…</option>
                {fields.filter(field => !definition.customFields.some(item => item.fieldId === field.id)).map(field => <option key={field.id} value={field.id}>{field.label}</option>)}
              </select>
              <select disabled={!selectedField} value={customOperator} onChange={event => {
                const next = event.target.value as CustomOperator;
                setCustomOperator(next);
                if (["EMPTY", "NOT_EMPTY"].includes(next)) setCustomValue("");
              }}>
                {(selectedField ? operatorsFor(selectedField) : ["EQ"] as CustomOperator[]).map(operator => <option key={operator} value={operator}>{operatorLabels[operator]}</option>)}
              </select>
              {selectedField ? renderCustomValue(selectedField) : <input disabled placeholder="Valor" />}
              <button className="ghost-button" disabled={!selectedField} type="submit">Adicionar</button>
            </form>
            <div className="segment-custom-chips">
              {definition.customFields.map(criterion => {
                const field = fields.find(item => item.id === criterion.fieldId);
                return (
                  <span key={criterion.fieldId}>
                    <strong>{field?.label ?? "Campo"}</strong> {operatorLabels[criterion.operator]}{criterion.value ? ` “${criterion.value}”` : ""}
                    <button onClick={() => removeCriterion(criterion.fieldId)} type="button">×</button>
                  </span>
                );
              })}
              {definition.customFields.length === 0 && <small>Nenhum campo personalizado no filtro.</small>}
            </div>
          </section>

          <div className="segment-preview-action">
            <button className="primary-button" disabled={previewing || !hasCriteria(definition)} onClick={() => void previewDefinition(definition)} type="button"><span>{previewing ? "Calculando…" : "Visualizar audiência"}</span></button>
            <small>A audiência é recalculada com os dados atuais; nenhum contato é congelado no segmento.</small>
          </div>
        </section>

        <section className="segment-preview">
          <header>
            <div><strong>Audiência</strong><span>{preview ? `${preview.count} contatos encontrados` : "Aguardando prévia"}</span></div>
            {preview?.truncated && <small>Exibindo os primeiros 60 resultados.</small>}
          </header>
          <div className="segment-preview__list">
            {preview?.contacts.map(contact => (
              <article className="segment-contact-card" key={contact.id}>
                <button className="segment-contact-card__identity" onClick={() => router.push(`/dashboard/contacts?contact=${contact.id}`)} type="button">
                  <span>{contact.name.slice(0, 1).toUpperCase()}</span>
                  <div><strong>{contact.name}</strong><small>{contact.phoneNumber ?? contact.email ?? "Sem telefone/e-mail"}</small></div>
                </button>
                {contact.pipelineStates.length > 0 && <div className="segment-contact-card__stages">{contact.pipelineStates.map(state => <span key={state.id}>{state.pipeline.name}: <strong>{state.stage.name}</strong></span>)}</div>}
                <div className="segment-contact-card__footer">
                  <span>Última atividade: {dateTimeLabel(contact.lastSeenAt)}</span>
                  {contact.crmTasks[0] && <span>Follow-up: <strong>{contact.crmTasks[0].title}</strong></span>}
                </div>
                {contact.tickets[0] && <button className="segment-contact-card__conversation" onClick={() => router.push(`/dashboard/conversations?ticket=${contact.tickets[0].id}`)} type="button">Abrir última conversa</button>}
              </article>
            ))}
            {preview && preview.contacts.length === 0 && <div className="segments-empty">Nenhum contato corresponde a esses critérios.</div>}
            {!preview && <div className="segments-empty">Monte os critérios e clique em “Visualizar audiência”.</div>}
          </div>
        </section>
      </section>
    </main>
  );
}
TSX

if ! grep -Fq -- "WAPP P3.4 / SAVED CONTACT SEGMENTS" "$CSS"; then
cat >> "$CSS" <<'CSS'

/* --- WAPP P3.4 / SAVED CONTACT SEGMENTS ------------------------------ */

.segments-screen {
  min-height: 100vh;
  overflow-x: hidden;
  background: var(--surface-subtle);
  padding: 32px clamp(18px, 4vw, 56px) 56px;
}

.segments-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 20px;
}

.segments-header h1 {
  margin: 6px 0 5px;
  font-size: clamp(32px, 4vw, 48px);
  letter-spacing: -0.05em;
}

.segments-header p {
  max-width: 680px;
  margin: 0;
  color: var(--muted);
  font-size: 10px;
  line-height: 1.5;
}

.segments-feedback {
  margin-top: 12px;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 9px 10px;
  font-size: 8px;
}

.segments-feedback--error {
  background: rgba(163, 59, 50, 0.07);
  color: #973a32;
}

.segments-layout {
  display: grid;
  grid-template-columns: 230px minmax(420px, 1.05fr) minmax(300px, 0.8fr);
  gap: 10px;
  align-items: start;
  margin-top: 14px;
}

.segment-saved-list,
.segment-builder,
.segment-preview {
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
}

.segment-saved-list,
.segment-preview {
  position: sticky;
  top: 14px;
  max-height: calc(100dvh - 165px);
}

.segment-saved-list > header,
.segment-preview > header {
  display: flex;
  min-height: 43px;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  border-bottom: 1px solid var(--line);
  padding: 9px 11px;
}

.segment-saved-list > header strong,
.segment-preview > header strong {
  font-size: 10px;
}

.segment-saved-list > header span,
.segment-preview > header span,
.segment-preview > header small {
  color: var(--muted);
  font-size: 7px;
}

.segment-saved-list > div,
.segment-preview__list {
  max-height: calc(100dvh - 210px);
  overflow-y: auto;
  padding: 6px;
  scrollbar-width: thin;
}

.segment-saved-item {
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

.segment-saved-item:hover,
.segment-saved-item--active {
  border-color: var(--line);
  background: #f7f9f7;
}

.segment-saved-item--active {
  border-color: rgba(31, 122, 80, 0.25);
  background: var(--accent-soft);
}

.segment-saved-item--archived { opacity: 0.52; }

.segment-saved-item > div {
  display: grid;
  min-width: 0;
  gap: 2px;
}

.segment-saved-item strong {
  overflow: hidden;
  color: var(--ink);
  font-size: 8px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.segment-saved-item small {
  display: -webkit-box;
  overflow: hidden;
  color: var(--muted);
  font-size: 7px;
  line-height: 1.35;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.segment-saved-item > span {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 6px;
}

.segment-builder > header {
  display: flex;
  min-height: 51px;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  border-bottom: 1px solid var(--line);
  padding: 10px 12px;
}

.segment-builder > header > div:first-child { display: grid; gap: 2px; }
.segment-builder > header strong { font-size: 10px; }
.segment-builder > header span { color: var(--muted); font-size: 7px; }
.segment-builder > header > div:last-child { display: flex; gap: 6px; align-items: center; }

.segment-identity-fields,
.segment-filter-grid {
  display: grid;
  gap: 8px;
  padding: 11px 12px;
}

.segment-identity-fields {
  grid-template-columns: minmax(160px, 0.8fr) minmax(0, 1.2fr);
  border-bottom: 1px solid var(--line);
  background: #fafbfa;
}

.segment-filter-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); }

.segment-identity-fields label,
.segment-filter-grid label { display: grid; gap: 4px; }

.segment-identity-fields label > span,
.segment-filter-grid label > span {
  color: var(--muted);
  font-size: 7px;
  font-weight: 750;
}

.segment-identity-fields input,
.segment-filter-grid input,
.segment-filter-grid select,
.segment-custom-form input,
.segment-custom-form select {
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

.segment-stage-filter {
  display: grid;
  gap: 8px;
  border-top: 1px solid #edf0ed;
  border-bottom: 1px solid #edf0ed;
  background: #fafbfa;
  padding: 10px 12px;
}

.segment-stage-filter > div:first-child {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.segment-stage-filter strong { font-size: 8px; }
.segment-stage-filter label { display: inline-flex; align-items: center; gap: 5px; color: var(--muted); font-size: 7px; }
.segment-stage-options { display: flex; flex-wrap: wrap; gap: 5px; }
.segment-stage-options label { min-height: 28px; border: 1px solid var(--line); border-radius: 999px; background: white; padding: 0 8px; color: #536059; }

.segment-custom-fields { border-bottom: 1px solid var(--line); padding: 11px 12px; }
.segment-custom-fields > header { margin-bottom: 8px; }
.segment-custom-fields > header > div { display: grid; gap: 2px; }
.segment-custom-fields > header strong { font-size: 9px; }
.segment-custom-fields > header span { color: var(--muted); font-size: 7px; }

.segment-custom-form {
  display: grid;
  grid-template-columns: 1.1fr 0.85fr 1fr auto;
  gap: 6px;
}

.segment-custom-form .ghost-button { min-height: 36px; }
.segment-custom-chips { display: flex; flex-wrap: wrap; gap: 5px; margin-top: 8px; }
.segment-custom-chips > span { display: inline-flex; align-items: center; gap: 3px; border-radius: 999px; background: #f2f5f3; padding: 5px 7px; color: #56615b; font-size: 7px; }
.segment-custom-chips > span strong { color: var(--ink); }
.segment-custom-chips button { border: 0; background: transparent; color: #973a32; padding: 0 1px; font-weight: 850; cursor: pointer; }
.segment-custom-chips > small { color: var(--muted); font-size: 7px; }

.segment-preview-action {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 11px 12px;
}

.segment-preview-action small { max-width: 330px; color: var(--muted); font-size: 7px; line-height: 1.4; }
.segment-preview > header > div { display: grid; gap: 2px; }
.segment-preview__list { padding: 7px; }

.segment-contact-card {
  display: grid;
  gap: 7px;
  margin-bottom: 7px;
  border: 1px solid #e5e9e6;
  border-radius: 10px;
  padding: 9px;
}

.segment-contact-card__identity {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 8px;
  border: 0;
  background: transparent;
  padding: 0;
  text-align: left;
  cursor: pointer;
}

.segment-contact-card__identity > span {
  display: grid;
  width: 31px;
  height: 31px;
  flex: 0 0 31px;
  place-items: center;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 8px;
  font-weight: 850;
}

.segment-contact-card__identity > div { display: grid; min-width: 0; gap: 2px; }
.segment-contact-card__identity strong { overflow: hidden; font-size: 9px; text-overflow: ellipsis; white-space: nowrap; }
.segment-contact-card__identity small { overflow: hidden; color: var(--muted); font-size: 7px; text-overflow: ellipsis; white-space: nowrap; }
.segment-contact-card__stages { display: flex; flex-wrap: wrap; gap: 4px; }
.segment-contact-card__stages > span { border-radius: 999px; background: #f3f5f4; padding: 4px 6px; color: var(--muted); font-size: 6px; }
.segment-contact-card__stages strong { color: #4a554f; }
.segment-contact-card__footer { display: grid; gap: 2px; border-top: 1px solid #edf0ed; padding-top: 6px; }
.segment-contact-card__footer > span { color: var(--muted); font-size: 7px; }
.segment-contact-card__conversation { width: fit-content; border: 0; background: transparent; color: var(--accent-dark); padding: 2px 0; font-size: 7px; font-weight: 760; cursor: pointer; }
.segments-empty { padding: 26px 12px; color: var(--muted); font-size: 8px; line-height: 1.45; text-align: center; }

@media (max-width: 1180px) {
  .segments-layout { grid-template-columns: 210px minmax(0, 1fr); }
  .segment-preview { position: static; grid-column: 2; max-height: none; }
  .segment-preview__list { max-height: 520px; }
}

@media (max-width: 760px) {
  .segments-screen { min-height: 100dvh; padding: 20px 12px calc(82px + env(safe-area-inset-bottom, 0px)); }
  .segments-header { align-items: flex-start; flex-direction: column; }
  .segments-layout { grid-template-columns: 1fr; }
  .segment-saved-list, .segment-preview { position: static; max-height: none; }
  .segment-saved-list > div, .segment-preview__list { max-height: 48dvh; }
  .segment-preview { grid-column: auto; }
  .segment-builder > header { align-items: flex-start; flex-direction: column; }
  .segment-builder > header > div:last-child { width: 100%; }
  .segment-identity-fields, .segment-filter-grid, .segment-custom-form { grid-template-columns: 1fr; }
  .segment-stage-filter > div:first-child, .segment-preview-action { align-items: flex-start; flex-direction: column; }
  .segment-identity-fields input, .segment-filter-grid input, .segment-filter-grid select, .segment-custom-form input, .segment-custom-form select { min-height: 42px; font-size: 16px; }
  .segment-preview-action .primary-button { width: 100%; }
}

/* --- /WAPP P3.4 ------------------------------------------------------ */
CSS
fi

cat > scripts/p3-04-segment-smoke.mjs <<'JS'
import fs from "node:fs";

const schema = fs.readFileSync("apps/api/prisma/schema.prisma", "utf8");
const service = fs.readFileSync("apps/api/src/modules/segments/segment.service.ts", "utf8");
const dashboard = fs.readFileSync("apps/web/app/dashboard/page.tsx", "utf8");
const page = fs.readFileSync("apps/web/app/dashboard/segments/page.tsx", "utf8");
const permissions = fs.readFileSync("apps/api/src/security/permissions.ts", "utf8");

const checks = [
  [schema, "model ContactSegment {"],
  [schema, "definition            Json"],
  [service, "buildSegmentWhere"],
  [service, "isGroup: false"],
  [service, "customFieldValues"],
  [service, "pipelineStates"],
  [service, "crmTasks"],
  [dashboard, 'href: "/dashboard/segments"'],
  [permissions, '"segments.read"'],
  [permissions, '"segments.manage"'],
  [page, "A audiência é recalculada"]
];

for (const [source, marker] of checks) {
  if (!source.includes(marker)) throw new Error(`P3.4 marker missing: ${marker}`);
}

console.log("[P3.4] segment smoke PASS");
JS

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
const current = pkg.scripts?.test;
if (typeof current !== "string") throw new Error("API test script missing.");
const file = "src/modules/segments/segment.definition.test.ts";
if (!current.includes(file)) pkg.scripts.test = `${current} ${file}`;
fs.writeFileSync(path, `${JSON.stringify(pkg, null, 2)}\n`);
NODE

cat > docs/P3_04_SAVED_SEGMENTS.md <<'MD'
# P3.4 Saved contact segments

P3.4 adds dynamic saved audiences. A segment stores a filter definition, not a
frozen list of contact IDs. Every preview or future use resolves the definition
against current database state.

## Safety boundary

P3.4 does not send WhatsApp messages and has no campaign/bulk-send endpoint.
Only direct contacts are eligible (`Contact.isGroup = false`). An empty
"all contacts" segment is rejected; at least one narrowing criterion must be
explicit.

## Criteria

Standard contact data:
- text search across name, WhatsApp name, phone and email;
- has / does not have phone;
- has / does not have email;
- last activity within 7, 30 or 90 days;
- never seen.

P3.1 custom fields:
- equals;
- not equal;
- contains for TEXT fields;
- empty;
- not empty.

P3.2 pipeline:
- one pipeline criterion;
- one or more current stages;
- optionally contacts with no stage in that pipeline.

P3.3 follow-up:
- any;
- has open task;
- has overdue task;
- has no open task.

All configured criteria are combined with AND.

## RBAC

All roles can read active saved segments and run previews. OWNER, ADMIN and
SUPERVISOR can create, edit, archive and reactivate shared segments. AGENT
cannot mutate shared segment definitions.

## API

- GET `/api/v1/segments`
- GET `/api/v1/segments/manage`
- GET `/api/v1/segments/context`
- POST `/api/v1/segments/preview`
- POST `/api/v1/segments`
- PATCH `/api/v1/segments/:id`
- GET `/api/v1/segments/:id/contacts`

Preview responses return a maximum of 100 contact records plus the full dynamic
count and a `truncated` flag.

## UI

`/dashboard/segments` contains the saved list, builder, P3.1/P3.2/P3.3 filters,
dynamic preview and deep links back to Contacts / Conversations.

## Migration

P3.4 introduces `ContactSegment`.
MD

echo "[P3.4] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P3.4] Segment smoke..."
node scripts/p3-04-segment-smoke.mjs

echo "[P3.4] Unit tests..."
pnpm test

echo "[P3.4] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.4] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.4] CODE VALIDATION PASS."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
