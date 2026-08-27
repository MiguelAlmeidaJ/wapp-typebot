import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  createQueue,
  listQueues,
  replaceQueueMembers
} from "./queue.service.js";

const queueIdSchema = z.object({
  id: z.string().uuid()
});

const createQueueSchema = z.object({
  name: z.string().trim().min(2).max(120)
});

const queueMembersSchema = z.object({
  membershipIds: z.array(z.string().uuid()).max(500)
});

export async function queueRoutes(app: FastifyInstance) {
  app.get("/api/v1/queues", async request => {
    const auth = await requirePermission(
      request,
      "queues.read"
    );

    return {
      queues: await listQueues(auth.companyId)
    };
  });

  app.post("/api/v1/queues", async (request, reply) => {
    const auth = await requirePermission(
      request,
      "queues.manage"
    );

    const input = createQueueSchema.parse(request.body);

    return reply.status(201).send({
      queue: await createQueue({
        companyId: auth.companyId,
        name: input.name
      })
    });
  });

  app.put(
    "/api/v1/queues/:id/members",
    async request => {
      const auth = await requirePermission(
        request,
        "queues.manage"
      );

      const params = queueIdSchema.parse(request.params);
      const input = queueMembersSchema.parse(
        request.body
      );

      return {
        queues: await replaceQueueMembers({
          companyId: auth.companyId,
          queueId: params.id,
          membershipIds: input.membershipIds
        })
      };
    }
  );
}
