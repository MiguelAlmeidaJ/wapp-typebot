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

function requiredPrismaJson(
  value:
    unknown
):
  Prisma.InputJsonValue {
  const json =
    toPrismaJson(
      value
    );

  if (
    json ===
    undefined
  ) {
    throw new AppError(
      "A definição do segmento não pôde ser serializada.",
      500,
      "SEGMENT_DEFINITION_SERIALIZATION_FAILED"
    );
  }

  return json;
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
      definition: requiredPrismaJson(definition)
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
      ...(definition ? { definition: requiredPrismaJson(definition) } : {}),
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
