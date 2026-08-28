import type {
  FastifyInstance
} from "fastify";

import { env } from "../../config/env.js";
import { requirePermission } from "../auth/auth.guard.js";
import { getOperationalAlerts } from "./alerts.service.js";
import {
  metricsContentType,
  renderMetrics
} from "./metrics.service.js";
import {
  validMetricsAuthorization
} from "./metrics-token.js";

export async function observabilityRoutes(
  app: FastifyInstance
) {
  app.get(
    "/metrics",
    async (
      request,
      reply
    ) => {
      if (
        !env.METRICS_TOKEN
      ) {
        return reply
          .status(404)
          .send({
            error: {
              code:
                "NOT_FOUND",
              message:
                "Not found."
            }
          });
      }

      if (
        !validMetricsAuthorization(
          env.METRICS_TOKEN,
          request.headers
            .authorization
        )
      ) {
        return reply
          .status(401)
          .send({
            error: {
              code:
                "UNAUTHORIZED",
              message:
                "Unauthorized."
            }
          });
      }

      reply.header(
        "Content-Type",
        metricsContentType()
      );

      return reply.send(
        await renderMetrics()
      );
    }
  );

  app.get(
    "/api/v1/observability/alerts",
    async request => {
      const auth =
        await requirePermission(
          request,
          "observability.read"
        );

      return getOperationalAlerts(
        auth.companyId
      );
    }
  );
}
