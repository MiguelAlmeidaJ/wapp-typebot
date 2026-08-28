import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  requireAuth
} from "../auth/auth.guard.js";
import {
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead
} from "./notification.service.js";

const querySchema =
  z.object({
    limit:
      z.coerce
        .number()
        .int()
        .min(1)
        .max(100)
        .default(40),
    unreadOnly:
      z.enum([
        "true",
        "false"
      ])
        .default(
          "false"
        )
        .transform(
          value =>
            value ===
            "true"
        )
  });

const paramsSchema =
  z.object({
    id:
      z.string()
        .uuid()
  });

export async function notificationRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/notifications",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const query =
        querySchema.parse(
          request.query
        );

      return listNotifications({
        companyId:
          auth.companyId,
        membershipId:
          auth.membershipId,
        limit:
          query.limit,
        unreadOnly:
          query.unreadOnly
      });
    }
  );

  app.post(
    "/api/v1/notifications/:id/read",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        paramsSchema.parse(
          request.params
        );

      return {
        notification:
          await markNotificationRead({
            companyId:
              auth.companyId,
            membershipId:
              auth.membershipId,
            notificationId:
              params.id
          })
      };
    }
  );

  app.post(
    "/api/v1/notifications/read-all",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      return markAllNotificationsRead({
        companyId:
          auth.companyId,
        membershipId:
          auth.membershipId
      });
    }
  );
}
