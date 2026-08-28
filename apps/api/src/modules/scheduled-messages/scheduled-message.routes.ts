import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  enqueueScheduledMessageDelivery,
  removeScheduledMessageJob
} from "../../jobs/scheduled-message.queue.js";
import {
  requireAuth
} from "../auth/auth.guard.js";
import {
  cancelScheduledMessage,
  createScheduledMessage,
  listTicketScheduledMessages
} from "./scheduled-message.service.js";

const ticketParams =
  z.object({
    id:
      z.string()
        .uuid()
  });

const scheduleParams =
  z.object({
    id:
      z.string()
        .uuid()
  });

const createSchema =
  z.object({
    body:
      z.string()
        .trim()
        .min(1)
        .max(4096),
    scheduledFor:
      z.string()
        .datetime({
          offset:
            true
        })
  });

export async function scheduledMessageRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/tickets/:id/scheduled-messages",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        ticketParams.parse(
          request.params
        );

      return {
        scheduledMessages:
          await listTicketScheduledMessages({
            companyId:
              auth.companyId,
            ticketId:
              params.id
          })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/scheduled-messages",
    async (
      request,
      reply
    ) => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        ticketParams.parse(
          request.params
        );

      const input =
        createSchema.parse(
          request.body
        );

      const scheduledMessage =
        await createScheduledMessage({
          companyId:
            auth.companyId,
          ticketId:
            params.id,
          actorMembershipId:
            auth.membershipId,
          role:
            auth.role,
          body:
            input.body,
          scheduledFor:
            new Date(
              input.scheduledFor
            )
        });

      let queued =
        false;

      try {
        queued =
          await enqueueScheduledMessageDelivery({
            scheduledMessageId:
              scheduledMessage.id,
            scheduledFor:
              scheduledMessage
                .scheduledFor
          });
      } catch (error) {
        request.log.error(
          {
            error,
            scheduledMessageId:
              scheduledMessage.id
          },
          "scheduled-message enqueue failed; database reconciliation will retry"
        );
      }

      return reply
        .status(
          201
        )
        .send({
          scheduledMessage,
          queued
        });
    }
  );

  app.delete(
    "/api/v1/scheduled-messages/:id",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        scheduleParams.parse(
          request.params
        );

      const scheduledMessage =
        await cancelScheduledMessage({
          companyId:
            auth.companyId,
          scheduledMessageId:
            params.id,
          actorMembershipId:
            auth.membershipId,
          role:
            auth.role
        });

      try {
        await removeScheduledMessageJob(
          scheduledMessage.id
        );
      } catch (error) {
        request.log.warn(
          {
            error,
            scheduledMessageId:
              scheduledMessage.id
          },
          "scheduled-message queue cleanup failed"
        );
      }

      return {
        scheduledMessage
      };
    }
  );
}
