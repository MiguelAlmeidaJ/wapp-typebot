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
  createPipeline,
  createPipelineStage,
  getContactPipelineStates,
  getPipelineBoard,
  listPipelines,
  moveContactStage,
  updatePipeline,
  updatePipelineStage
} from "./pipeline.service.js";
import {
  PIPELINE_COLOR_KEYS
} from "./pipeline.policy.js";

const idSchema =
  z.object({
    id:
      z.string()
        .uuid()
  });

const pipelineIdSchema =
  z.object({
    pipelineId:
      z.string()
        .uuid()
  });

const createPipelineSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(2)
        .max(120),
    description:
      z.string()
        .trim()
        .max(500)
        .nullable()
        .optional(),
    stages:
      z.array(
        z.string()
          .trim()
          .min(1)
          .max(120)
      )
        .min(2)
        .max(20)
  });

const updatePipelineSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(2)
        .max(120)
        .optional(),
    description:
      z.string()
        .trim()
        .max(500)
        .nullable()
        .optional(),
    isActive:
      z.boolean()
        .optional(),
    position:
      z.number()
        .int()
        .min(0)
        .max(10_000)
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

const stageSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(1)
        .max(120),
    colorKey:
      z.enum(
        PIPELINE_COLOR_KEYS
      )
        .default(
          "GRAY"
        ),
    outcome:
      z.enum([
        "OPEN",
        "WON",
        "LOST"
      ])
        .default(
          "OPEN"
        )
  });

const updateStageSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(1)
        .max(120)
        .optional(),
    colorKey:
      z.enum(
        PIPELINE_COLOR_KEYS
      )
        .optional(),
    outcome:
      z.enum([
        "OPEN",
        "WON",
        "LOST"
      ])
        .optional(),
    position:
      z.number()
        .int()
        .min(0)
        .max(10_000)
        .optional(),
    isActive:
      z.boolean()
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

const boardQuerySchema =
  z.object({
    search:
      z.string()
        .trim()
        .max(100)
        .optional()
  });

const moveSchema =
  z.object({
    pipelineId:
      z.string()
        .uuid(),
    stageId:
      z.string()
        .uuid()
        .nullable()
  });

export async function pipelineRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/pipelines",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.read"
        );

      return {
        pipelines:
          await listPipelines(
            auth.companyId
          )
      };
    }
  );

  app.get(
    "/api/v1/pipelines/manage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      return {
        pipelines:
          await listPipelines(
            auth.companyId,
            true
          )
      };
    }
  );

  app.post(
    "/api/v1/pipelines",
    async (
      request,
      reply
    ) => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      const input =
        createPipelineSchema.parse(
          request.body
        );

      return reply
        .status(
          201
        )
        .send({
          pipeline:
            await createPipeline({
              companyId:
                auth.companyId,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/pipelines/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        updatePipelineSchema.parse(
          request.body
        );

      return {
        pipeline:
          await updatePipeline({
            companyId:
              auth.companyId,
            pipelineId:
              params.id,
            ...input
          })
      };
    }
  );

  app.post(
    "/api/v1/pipelines/:id/stages",
    async (
      request,
      reply
    ) => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        stageSchema.parse(
          request.body
        );

      return reply
        .status(
          201
        )
        .send({
          stage:
            await createPipelineStage({
              companyId:
                auth.companyId,
              pipelineId:
                params.id,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/pipeline-stages/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        updateStageSchema.parse(
          request.body
        );

      return {
        stage:
          await updatePipelineStage({
            companyId:
              auth.companyId,
            stageId:
              params.id,
            ...input
          })
      };
    }
  );

  app.get(
    "/api/v1/pipelines/:pipelineId/board",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.read"
        );

      const params =
        pipelineIdSchema.parse(
          request.params
        );

      const query =
        boardQuerySchema.parse(
          request.query
        );

      return getPipelineBoard({
        companyId:
          auth.companyId,
        pipelineId:
          params.pipelineId,
        search:
          query.search
      });
    }
  );

  app.post(
    "/api/v1/contacts/:id/pipeline-stage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.move"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        moveSchema.parse(
          request.body
        );

      return moveContactStage({
        companyId:
          auth.companyId,
        contactId:
          params.id,
        pipelineId:
          input.pipelineId,
        stageId:
          input.stageId,
        actorMembershipId:
          auth.membershipId
      });
    }
  );

  app.get(
    "/api/v1/contacts/:id/pipeline-states",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.read"
        );

      const params =
        idSchema.parse(
          request.params
        );

      return getContactPipelineStates({
        companyId:
          auth.companyId,
        contactId:
          params.id
      });
    }
  );
}
