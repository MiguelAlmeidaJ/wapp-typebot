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
