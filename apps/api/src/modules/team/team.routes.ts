import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  createCompanyMembership,
  listCompanyMemberships,
  updateCompanyMembership
} from "./team.service.js";

const managedRoleSchema = z.enum([
  "ADMIN",
  "SUPERVISOR",
  "AGENT"
]);

const listSchema = z.object({
  includeInactive: z
    .enum(["true", "false"])
    .optional()
    .transform(value => value === "true")
});

const paramsSchema = z.object({
  id: z.string().uuid()
});

const createSchema = z.object({
  name: z.string().trim().min(2).max(160),
  email: z
    .string()
    .email()
    .transform(value => value.trim().toLowerCase()),
  temporaryPassword: z
    .string()
    .min(12)
    .max(128)
    .optional(),
  role: managedRoleSchema.default("AGENT")
});

const updateSchema = z
  .object({
    role: managedRoleSchema.optional(),
    isActive: z.boolean().optional()
  })
  .refine(
    value =>
      value.role !== undefined ||
      value.isActive !== undefined,
    {
      message: "Informe ao menos uma alteração."
    }
  );

export async function teamRoutes(app: FastifyInstance) {
  app.get(
    "/api/v1/team/memberships",
    async request => {
      const auth = await requirePermission(
        request,
        "team.read"
      );

      const query = listSchema.parse(
        request.query
      );

      return {
        memberships: await listCompanyMemberships(
          auth.companyId,
          query.includeInactive
        )
      };
    }
  );

  app.post(
    "/api/v1/team/memberships",
    async (request, reply) => {
      const auth = await requirePermission(
        request,
        "team.manage"
      );

      const input = createSchema.parse(
        request.body
      );

      const result = await createCompanyMembership({
        actor: {
          companyId: auth.companyId,
          membershipId: auth.membershipId,
          role: auth.role
        },
        ...input
      });

      return reply.status(201).send(result);
    }
  );

  app.patch(
    "/api/v1/team/memberships/:id",
    async request => {
      const auth = await requirePermission(
        request,
        "team.manage"
      );

      const params = paramsSchema.parse(
        request.params
      );

      const input = updateSchema.parse(
        request.body
      );

      return {
        membership: await updateCompanyMembership({
          actor: {
            companyId: auth.companyId,
            membershipId: auth.membershipId,
            role: auth.role
          },
          membershipId: params.id,
          ...input
        })
      };
    }
  );
}
