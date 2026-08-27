import type { FastifyInstance } from "fastify";

import {
  getHealthDetails,
  getLiveness,
  getReadiness
} from "./health.service.js";

export async function healthRoutes(
  app: FastifyInstance
) {
  app.get(
    "/health/live",
    async () =>
      getLiveness()
  );

  app.get(
    "/health/ready",
    async (
      _request,
      reply
    ) => {
      const readiness =
        await getReadiness();

      return reply
        .status(
          readiness.ready
            ? 200
            : 503
        )
        .send(
          readiness
        );
    }
  );

  /*
   * Backward-compatible detailed endpoint.
   *
   * /health intentionally remains diagnostic and returns 200 while the
   * process itself can answer HTTP. Load balancers/orchestrators should use
   * /health/ready for admission decisions.
   */
  app.get(
    "/health",
    async () =>
      getHealthDetails()
  );
}
