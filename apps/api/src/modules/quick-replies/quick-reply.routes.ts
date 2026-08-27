import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  createQuickReply,
  listQuickReplies,
  updateQuickReply
} from "./quick-reply.service.js";

const shortcutSchema = z
  .string()
  .trim()
  .transform(value =>
    value.replace(/^\/+/, "")
  )
  .pipe(
    z
      .string()
      .min(1)
      .max(50)
      .regex(
        /^[a-zA-Z0-9][a-zA-Z0-9_-]*$/,
        "Use apenas letras, números, hífen ou underline no atalho."
      )
  );

const listSchema = z.object({
  search: z
    .string()
    .trim()
    .max(160)
    .optional()
});

const idSchema = z.object({
  id: z.string().uuid()
});

const createSchema = z.object({
  shortcut: shortcutSchema,
  title: z
    .string()
    .trim()
    .min(2)
    .max(160),
  body: z
    .string()
    .trim()
    .min(1)
    .max(10_000)
});

const updateSchema = z
  .object({
    shortcut:
      shortcutSchema.optional(),
    title: z
      .string()
      .trim()
      .min(2)
      .max(160)
      .optional(),
    body: z
      .string()
      .trim()
      .min(1)
      .max(10_000)
      .optional(),
    isActive:
      z.boolean().optional()
  })
  .refine(
    value =>
      value.shortcut !== undefined ||
      value.title !== undefined ||
      value.body !== undefined ||
      value.isActive !== undefined,
    {
      message:
        "Informe ao menos uma alteração."
    }
  );

export async function quickReplyRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/quick-replies",
    async request => {
      const auth =
        await requirePermission(
          request,
          "quickReplies.read"
        );

      const query =
        listSchema.parse(
          request.query
        );

      return {
        quickReplies:
          await listQuickReplies({
            companyId:
              auth.companyId,
            search:
              query.search,
            includeInactive:
              false
          })
      };
    }
  );

  app.get(
    "/api/v1/quick-replies/manage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "quickReplies.manage"
        );

      const query =
        listSchema.parse(
          request.query
        );

      return {
        quickReplies:
          await listQuickReplies({
            companyId:
              auth.companyId,
            search:
              query.search,
            includeInactive:
              true
          })
      };
    }
  );

  app.post(
    "/api/v1/quick-replies",
    async (request, reply) => {
      const auth =
        await requirePermission(
          request,
          "quickReplies.manage"
        );

      const input =
        createSchema.parse(
          request.body
        );

      return reply
        .status(201)
        .send({
          quickReply:
            await createQuickReply({
              companyId:
                auth.companyId,
              membershipId:
                auth.membershipId,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/quick-replies/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "quickReplies.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        updateSchema.parse(
          request.body
        );

      return {
        quickReply:
          await updateQuickReply({
            companyId:
              auth.companyId,
            quickReplyId:
              params.id,
            ...input
          })
      };
    }
  );
}
