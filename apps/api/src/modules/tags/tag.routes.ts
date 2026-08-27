import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  createTag,
  listTags,
  tagColorKeys,
  updateTag
} from "./tag.service.js";

const colorSchema =
  z.enum(tagColorKeys);

const idSchema = z.object({
  id: z.string().uuid()
});

const createSchema = z.object({
  name: z
    .string()
    .trim()
    .min(1)
    .max(80),
  colorKey:
    colorSchema.default("GREEN")
});

const updateSchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(1)
      .max(80)
      .optional(),
    colorKey:
      colorSchema.optional(),
    isActive:
      z.boolean().optional()
  })
  .refine(
    value =>
      value.name !== undefined ||
      value.colorKey !== undefined ||
      value.isActive !== undefined,
    {
      message:
        "Informe ao menos uma alteração."
    }
  );

export async function tagRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/tags",
    async request => {
      const auth =
        await requirePermission(
          request,
          "tags.read"
        );

      return {
        tags:
          await listTags({
            companyId:
              auth.companyId
          })
      };
    }
  );

  app.get(
    "/api/v1/tags/manage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "tags.manage"
        );

      return {
        tags:
          await listTags({
            companyId:
              auth.companyId,
            includeInactive:
              true
          })
      };
    }
  );

  app.post(
    "/api/v1/tags",
    async (request, reply) => {
      const auth =
        await requirePermission(
          request,
          "tags.manage"
        );

      const input =
        createSchema.parse(
          request.body
        );

      return reply
        .status(201)
        .send({
          tag:
            await createTag({
              companyId:
                auth.companyId,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/tags/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "tags.manage"
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
        tag:
          await updateTag({
            companyId:
              auth.companyId,
            tagId:
              params.id,
            ...input
          })
      };
    }
  );
}
