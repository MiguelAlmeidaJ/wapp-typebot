import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  getSlaSettings,
  updateSlaSettings
} from "./sla.service.js";

const updateSchema = z.object({
  firstResponseSlaMinutes: z
    .number()
    .int()
    .min(1)
    .max(1440),
  replySlaMinutes: z
    .number()
    .int()
    .min(1)
    .max(1440)
});

export async function slaRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/sla/settings",
    async request => {
      const auth =
        await requirePermission(
          request,
          "sla.read"
        );

      return {
        settings:
          await getSlaSettings(
            auth.companyId
          )
      };
    }
  );

  app.put(
    "/api/v1/sla/settings",
    async request => {
      const auth =
        await requirePermission(
          request,
          "sla.manage"
        );

      const input =
        updateSchema.parse(
          request.body
        );

      return {
        settings:
          await updateSlaSettings({
            companyId:
              auth.companyId,
            ...input
          })
      };
    }
  );
}
