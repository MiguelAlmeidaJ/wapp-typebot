import type {
  FastifyInstance
} from "fastify";
import { z } from "zod";

import {
  requirePermission
} from "../auth/auth.guard.js";
import {
  createAutomationRule,
  listAutomationRules,
  listAutomationRuns,
  updateAutomationRule
} from "./automation.service.js";

const actionSchema =
  z.object({
    type:
      z.enum([
        "SET_QUEUE",
        "ASSIGN_MEMBERSHIP",
        "ADD_TAG",
        "SEND_TEXT"
      ]),
    queueId:
      z.string()
        .uuid()
        .optional(),
    membershipId:
      z.string()
        .uuid()
        .optional(),
    tagId:
      z.string()
        .uuid()
        .optional(),
    text:
      z.string()
        .max(4096)
        .optional()
  });

const createSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(2)
        .max(160),
    isActive:
      z.boolean()
        .optional(),
    trigger:
      z.enum([
        "TICKET_CREATED",
        "INBOUND_MESSAGE"
      ]),
    keywordContains:
      z.string()
        .trim()
        .max(190)
        .nullable()
        .optional(),
    onlyIfUnassigned:
      z.boolean()
        .optional(),
    conversationType:
      z.enum([
        "ALL",
        "DIRECT",
        "GROUP"
      ])
        .optional(),
    priority:
      z.coerce
        .number()
        .int()
        .min(0)
        .max(10000)
        .optional(),
    actions:
      z.array(
        actionSchema
      )
        .min(1)
        .max(8)
  });

const patchSchema =
  createSchema
    .partial()
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

const paramsSchema =
  z.object({
    id:
      z.string()
        .uuid()
  });

const runsQuerySchema =
  z.object({
    limit:
      z.coerce
        .number()
        .int()
        .min(1)
        .max(100)
        .default(50)
  });

export async function automationRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/automations",
    async request => {
      const auth =
        await requirePermission(
          request,
          "automations.read"
        );

      return {
        automations:
          await listAutomationRules(
            auth.companyId
          )
      };
    }
  );

  app.get(
    "/api/v1/automations/runs",
    async request => {
      const auth =
        await requirePermission(
          request,
          "automations.read"
        );

      const query =
        runsQuerySchema.parse(
          request.query
        );

      return {
        runs:
          await listAutomationRuns(
            auth.companyId,
            query.limit
          )
      };
    }
  );

  app.post(
    "/api/v1/automations",
    async request => {
      const auth =
        await requirePermission(
          request,
          "automations.manage"
        );

      const input =
        createSchema.parse(
          request.body
        );

      return {
        automation:
          await createAutomationRule({
            companyId:
              auth.companyId,
            actorMembershipId:
              auth.membershipId,
            rule:
              input
          })
      };
    }
  );

  app.patch(
    "/api/v1/automations/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "automations.manage"
        );

      const params =
        paramsSchema.parse(
          request.params
        );

      const patch =
        patchSchema.parse(
          request.body
        );

      return {
        automation:
          await updateAutomationRule({
            companyId:
              auth.companyId,
            actorMembershipId:
              auth.membershipId,
            ruleId:
              params.id,
            patch
          })
      };
    }
  );
}
