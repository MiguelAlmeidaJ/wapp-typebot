import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../auth/auth.guard.js";
import {
  claimTicket,
  closeTicket,
  listTicketMessages,
  listTickets,
  markTicketRead,
  sendTicketText,
  transferTicket
} from "./ticket.service.js";

const ticketIdSchema = z.object({
  id: z.string().uuid()
});

const listSchema = z.object({
  status: z
    .enum(["ACTIVE", "OPEN", "PENDING", "CLOSED"])
    .default("ACTIVE")
});

const sendTextSchema = z.object({
  text: z.string().trim().min(1).max(4096)
});

const transferSchema = z.object({
  queueId: z.string().uuid().nullable().optional(),
  membershipId: z.string().uuid().nullable().optional()
});

export async function ticketRoutes(app: FastifyInstance) {
  app.get("/api/v1/tickets", async request => {
    const auth = await requireAuth(request);
    const query = listSchema.parse(request.query);

    return {
      tickets: await listTickets(auth.companyId, query.status)
    };
  });

  app.get(
    "/api/v1/tickets/:id/messages",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        messages: await listTicketMessages(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/read",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        ticket: await markTicketRead(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/claim",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        ticket: await claimTicket({
          companyId: auth.companyId,
          ticketId: params.id,
          membershipId: auth.membershipId,
          role: auth.role
        })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/transfer",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);
      const input = transferSchema.parse(request.body);

      return {
        ticket: await transferTicket({
          companyId: auth.companyId,
          ticketId: params.id,
          actorMembershipId: auth.membershipId,
          role: auth.role,
          ...input
        })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/close",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        ticket: await closeTicket({
          companyId: auth.companyId,
          ticketId: params.id,
          membershipId: auth.membershipId,
          role: auth.role
        })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/messages",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);
      const input = sendTextSchema.parse(request.body);

      return {
        message: await sendTicketText({
          companyId: auth.companyId,
          ticketId: params.id,
          userId: auth.userId,
          membershipId: auth.membershipId,
          role: auth.role,
          text: input.text
        })
      };
    }
  );
}
