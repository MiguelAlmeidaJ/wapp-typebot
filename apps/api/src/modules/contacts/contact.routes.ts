import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  getContact,
  listContacts,
  updateContact
} from "./contact.service.js";

const contactIdSchema = z.object({
  id: z.string().uuid()
});

const listSchema = z.object({
  search: z
    .string()
    .trim()
    .max(100)
    .optional(),
  type: z
    .enum(["ALL", "PEOPLE", "GROUPS"])
    .default("ALL"),
  page: z.coerce
    .number()
    .int()
    .positive()
    .default(1),
  limit: z.coerce
    .number()
    .int()
    .min(10)
    .max(100)
    .default(30)
});

const updateSchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(2)
      .max(190)
      .optional(),
    email: z
      .string()
      .trim()
      .email()
      .max(190)
      .nullable()
      .optional(),
    notes: z
      .string()
      .trim()
      .max(10_000)
      .nullable()
      .optional()
  })
  .refine(
    value =>
      value.name !== undefined ||
      value.email !== undefined ||
      value.notes !== undefined,
    {
      message: "Informe ao menos uma alteração."
    }
  );

export async function contactRoutes(
  app: FastifyInstance
) {
  app.get("/api/v1/contacts", async request => {
    const auth = await requirePermission(
      request,
      "contacts.read"
    );

    const query = listSchema.parse(request.query);

    return listContacts({
      companyId: auth.companyId,
      search: query.search,
      type: query.type,
      page: query.page,
      limit: query.limit
    });
  });

  app.get(
    "/api/v1/contacts/:id",
    async request => {
      const auth = await requirePermission(
        request,
        "contacts.read"
      );

      const params = contactIdSchema.parse(
        request.params
      );

      return getContact(
        auth.companyId,
        params.id
      );
    }
  );

  app.patch(
    "/api/v1/contacts/:id",
    async request => {
      const auth = await requirePermission(
        request,
        "contacts.manage"
      );

      const params = contactIdSchema.parse(
        request.params
      );

      const input = updateSchema.parse(
        request.body
      );

      return {
        contact: await updateContact({
          companyId: auth.companyId,
          contactId: params.id,
          ...input
        })
      };
    }
  );
}
