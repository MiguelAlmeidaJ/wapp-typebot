import type { FastifyInstance } from "fastify";
import { z } from "zod";

import {
  requireAuth,
  requireRoles
} from "../auth/auth.guard.js";
import {
  connectConnection,
  createConnection,
  listConnections,
  sendTestMessage,
  syncConnection,
  updateConnectionSettings
} from "./whatsapp.service.js";

const connectionIdSchema = z.object({
  id: z.string().uuid()
});

const createConnectionSchema = z.object({
  name: z.string().trim().min(2).max(120)
});

const connectionSettingsSchema = z.object({
  acceptGroups: z.boolean().optional(),
  defaultQueueId: z.string().uuid().nullable().optional()
});

const testMessageSchema = z.object({
  number: z
    .string()
    .trim()
    .regex(/^\d{10,15}$/, "Use somente números com DDI e DDD."),
  text: z.string().trim().min(1).max(4096)
});

export async function whatsappRoutes(app: FastifyInstance) {
  app.get("/api/v1/whatsapp/connections", async request => {
    const auth = await requireAuth(request);

    return {
      connections: await listConnections(auth.companyId)
    };
  });

  app.post("/api/v1/whatsapp/connections", async (request, reply) => {
    const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
    const input = createConnectionSchema.parse(request.body);

    const result = await createConnection({
      companyId: auth.companyId,
      companySlug: auth.company.slug,
      name: input.name
    });

    return reply.status(201).send(result);
  });

  app.patch(
    "/api/v1/whatsapp/connections/:id/settings",
    async request => {
      const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
      const params = connectionIdSchema.parse(request.params);
      const input = connectionSettingsSchema.parse(request.body);

      return {
        connection: await updateConnectionSettings({
          companyId: auth.companyId,
          connectionId: params.id,
          ...input
        })
      };
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/connect",
    async request => {
      const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
      const params = connectionIdSchema.parse(request.params);

      return connectConnection(auth.companyId, params.id);
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/sync",
    async request => {
      const auth = await requireAuth(request);
      const params = connectionIdSchema.parse(request.params);

      return {
        connection: await syncConnection(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/test-message",
    async request => {
      const auth = await requireRoles(request, [
        "OWNER",
        "ADMIN",
        "SUPERVISOR"
      ]);

      const params = connectionIdSchema.parse(request.params);
      const input = testMessageSchema.parse(request.body);

      return {
        result: await sendTestMessage({
          companyId: auth.companyId,
          connectionId: params.id,
          number: input.number,
          text: input.text
        })
      };
    }
  );
}
