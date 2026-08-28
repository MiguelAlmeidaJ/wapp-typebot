import type {
  FastifyInstance
} from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import { listAuditLogs } from "./audit.service.js";

const querySchema =
  z.object({
    limit: z.coerce
      .number()
      .int()
      .min(20)
      .max(200)
      .default(100),
    cursor:
      z.string()
        .uuid()
        .optional(),
    action:
      z.string()
        .trim()
        .min(1)
        .max(80)
        .optional(),
    entityType:
      z.string()
        .trim()
        .min(1)
        .max(60)
        .optional(),
    actorMembershipId:
      z.string()
        .uuid()
        .optional()
  });

export async function auditRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/audit",
    async request => {
      const auth =
        await requirePermission(
          request,
          "audit.read"
        );

      const query =
        querySchema.parse(
          request.query
        );

      return listAuditLogs({
        companyId:
          auth.companyId,
        ...query
      });
    }
  );
}
