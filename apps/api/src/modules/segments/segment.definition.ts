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
