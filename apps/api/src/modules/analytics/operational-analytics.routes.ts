import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import { getOperationalAnalytics } from "./operational-analytics.service.js";

const querySchema = z.object({
  days: z.coerce
    .number()
    .int()
    .refine(
      (
        value
      ): value is
        | 7
        | 30
        | 90 =>
        [
          7,
          30,
          90
        ].includes(value),
      {
        message:
          "days deve ser 7, 30 ou 90."
      }
    )
    .default(7)
});

export async function operationalAnalyticsRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/analytics/operational",
    async request => {
      const auth =
        await requirePermission(
          request,
          "sla.read"
        );

      const query =
        querySchema.parse(
          request.query
        );

      return getOperationalAnalytics({
        companyId:
          auth.companyId,
        days:
          query.days
      });
    }
  );
}
