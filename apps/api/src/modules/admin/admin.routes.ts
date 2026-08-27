import type { FastifyInstance } from "fastify";

import { requirePermission } from "../auth/auth.guard.js";

export async function adminRoutes(app: FastifyInstance) {
  app.get("/api/v1/admin/ping", async request => {
    const auth = await requirePermission(
      request,
      "admin.test"
    );

    return {
      status: "ok",
      companyId: auth.companyId,
      role: auth.role,
      message: "RBAC funcionando."
    };
  });
}
