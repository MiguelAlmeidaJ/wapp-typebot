import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  requirePermission
} from "../auth/auth.guard.js";
import {
  createContactField,
  getContactCrmProfile,
  listContactFields,
  saveContactFieldValues,
  updateContactField
} from "./contact-crm.service.js";

const idSchema =
  z.object({
    id:
      z.string()
        .uuid()
  });

const createFieldSchema =
  z.object({
    label:
      z.string()
        .trim()
        .min(2)
        .max(120),
    type:
      z.enum([
        "TEXT",
        "NUMBER",
        "DATE",
        "BOOLEAN",
        "SELECT"
      ]),
    required:
      z.boolean()
        .default(
          false
        ),
    options:
      z.array(
        z.string()
          .trim()
          .min(1)
          .max(80)
      )
        .max(50)
        .optional()
  });

const updateFieldSchema =
  z.object({
    label:
      z.string()
        .trim()
        .min(2)
        .max(120)
        .optional(),
    required:
      z.boolean()
        .optional(),
    isActive:
      z.boolean()
        .optional(),
    position:
      z.number()
        .int()
        .min(0)
        .max(10_000)
        .optional(),
    options:
      z.array(
        z.string()
          .trim()
          .min(1)
          .max(80)
      )
        .max(50)
        .optional()
  })
    .refine(
      value =>
        Object.keys(
          value
        ).length >
        0,
      {
        message:
          "Informe ao menos uma alteração."
      }
    );

const saveValuesSchema =
  z.object({
    values:
      z.array(
        z.object({
          fieldId:
            z.string()
              .uuid(),
          value:
            z.string()
              .max(2_000)
              .nullable()
        })
      )
        .max(100)
  });

export async function contactCrmRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/contact-crm/fields",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contacts.read"
        );

      return {
        fields:
          await listContactFields(
            auth.companyId
          )
      };
    }
  );

  app.get(
    "/api/v1/contact-crm/fields/manage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contactFields.manage"
        );

      return {
        fields:
          await listContactFields(
            auth.companyId,
            true
          )
      };
    }
  );

  app.post(
    "/api/v1/contact-crm/fields",
    async (
      request,
      reply
    ) => {
      const auth =
        await requirePermission(
          request,
          "contactFields.manage"
        );

      const input =
        createFieldSchema.parse(
          request.body
        );

      return reply
        .status(
          201
        )
        .send({
          field:
            await createContactField({
              companyId:
                auth.companyId,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/contact-crm/fields/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contactFields.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        updateFieldSchema.parse(
          request.body
        );

      return {
        field:
          await updateContactField({
            companyId:
              auth.companyId,
            fieldId:
              params.id,
            ...input
          })
      };
    }
  );

  app.get(
    "/api/v1/contacts/:id/crm",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contacts.read"
        );

      const params =
        idSchema.parse(
          request.params
        );

      return getContactCrmProfile(
        auth.companyId,
        params.id
      );
    }
  );

  app.put(
    "/api/v1/contacts/:id/crm-fields",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contacts.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        saveValuesSchema.parse(
          request.body
        );

      return saveContactFieldValues({
        companyId:
          auth.companyId,
        contactId:
          params.id,
        values:
          input.values
      });
    }
  );
}
