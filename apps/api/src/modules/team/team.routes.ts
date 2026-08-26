import type { FastifyInstance } from "fastify";

import { requireAuth } from "../auth/auth.guard.js";
import { listCompanyMemberships } from "./team.service.js";

export async function teamRoutes(app: FastifyInstance) {
  app.get("/api/v1/team/memberships", async request => {
    const auth = await requireAuth(request);

    return {
      memberships: await listCompanyMemberships(auth.companyId)
    };
  });
}
