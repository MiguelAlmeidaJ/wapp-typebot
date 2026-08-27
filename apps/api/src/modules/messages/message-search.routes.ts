import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../auth/auth.guard.js";
import { searchMessageHistory } from "./message-search.service.js";

const searchSchema = z.object({
  q: z
    .string()
    .trim()
    .min(2)
    .max(160),
  ticketId: z
    .string()
    .uuid()
    .optional(),
  page: z.coerce
    .number()
    .int()
    .positive()
    .default(1),
  limit: z.coerce
    .number()
    .int()
    .min(10)
    .max(50)
    .default(30)
});

export async function messageSearchRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/messages/search",
    async request => {
      const auth =
        await requireAuth(request);

      const query =
        searchSchema.parse(
          request.query
        );

      return searchMessageHistory({
        companyId:
          auth.companyId,
        query:
          query.q,
        ticketId:
          query.ticketId,
        page:
          query.page,
        limit:
          query.limit
      });
    }
  );
}
