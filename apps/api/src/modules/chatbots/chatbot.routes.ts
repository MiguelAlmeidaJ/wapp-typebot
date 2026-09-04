import { timingSafeEqual } from "node:crypto";

import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { TypebotClient } from "../../integrations/typebot/typebot.client.js";
import { mapTypebotOutput } from "../../integrations/typebot/typebot.mapper.js";
import { requirePermission } from "../auth/auth.guard.js";
import { createManagedChatbotFlow } from "./chatbot-management.service.js";
import {
  createChatbotFlow,
  listChatbotFlows,
  transferChatbotToQueue,
  updateChatbotFlow
} from "./chatbot.service.js";

const flowParamsSchema = z.object({ id: z.string().uuid() });
const createFlowSchema = z.object({
  name: z.string().trim().min(2).max(160),
  whatsappConnectionId: z.string().uuid(),
  externalId: z.string().trim().min(1).max(190).optional(),
  isActive: z.boolean().optional()
});
const patchFlowSchema = createFlowSchema.partial().refine(
  value => Object.keys(value).length > 0,
  { message: "Informe ao menos uma alteração." }
);
const actionSchema = z.object({
  ticketId: z.string().uuid(),
  chatbotSessionId: z.string().uuid(),
  externalSessionId: z.string().min(1).max(190).optional(),
  action: z.literal("TRANSFER_QUEUE"),
  queue: z.string().trim().min(1).max(80)
});

function requireWebhookSecret(request: FastifyRequest) {
  if (!env.TYPEBOT_ENABLED || !env.TYPEBOT_WEBHOOK_SECRET) {
    throw new AppError("Integração Typebot desativada.", 503, "TYPEBOT_DISABLED");
  }

  const supplied = request.headers["x-wapp-chatbot-secret"];
  const value = Array.isArray(supplied) ? supplied[0] : supplied;
  const expected = Buffer.from(env.TYPEBOT_WEBHOOK_SECRET);
  const received = Buffer.from(value ?? "");

  if (
    expected.length !== received.length ||
    !timingSafeEqual(expected, received)
  ) {
    throw new AppError("Segredo do chatbot inválido.", 401, "CHATBOT_UNAUTHORIZED");
  }
}

export async function chatbotRoutes(app: FastifyInstance) {
  app.get("/api/v1/chatbots", async request => {
    const auth = await requirePermission(request, "chatbots.read");
    return { chatbots: await listChatbotFlows(auth.companyId) };
  });

  app.post("/api/v1/chatbots", async (request, reply) => {
    const auth = await requirePermission(request, "chatbots.manage");
    const body = createFlowSchema.parse(request.body);

    if (body.externalId) {
      return reply.status(201).send({
        chatbot: await createChatbotFlow({
          companyId: auth.companyId,
          actorMembershipId: auth.membershipId,
          name: body.name,
          whatsappConnectionId: body.whatsappConnectionId,
          externalId: body.externalId,
          isActive: body.isActive
        })
      });
    }

    return reply.status(201).send({
      chatbot: await createManagedChatbotFlow({
        companyId: auth.companyId,
        actorMembershipId: auth.membershipId,
        name: body.name,
        whatsappConnectionId: body.whatsappConnectionId,
        isActive: body.isActive
      })
    });
  });

  app.patch("/api/v1/chatbots/:id", async request => {
    const auth = await requirePermission(request, "chatbots.manage");
    const params = flowParamsSchema.parse(request.params);
    const patch = patchFlowSchema.parse(request.body);

    return {
      chatbot: await updateChatbotFlow({
        companyId: auth.companyId,
        actorMembershipId: auth.membershipId,
        flowId: params.id,
        patch
      })
    };
  });

  app.post("/api/v1/chatbots/:id/test", async request => {
    const auth = await requirePermission(request, "chatbots.manage");
    const params = flowParamsSchema.parse(request.params);
    const flow = (await listChatbotFlows(auth.companyId)).find(
      item => item.id === params.id
    );

    if (!flow) {
      throw new AppError("Chatbot não encontrado.", 404, "CHATBOT_NOT_FOUND");
    }

    if (!env.TYPEBOT_ENABLED) {
      throw new AppError("Integração Typebot desativada.", 503, "TYPEBOT_DISABLED");
    }

    const output = await new TypebotClient(
      env.TYPEBOT_API_URL || "",
      env.TYPEBOT_API_TOKEN || "",
      env.TYPEBOT_REQUEST_TIMEOUT_MS
    ).start({
      externalId: flow.externalId,
      variables: {
        companyId: auth.companyId,
        teste: "true"
      }
    });

    return {
      sessionId: output.externalSessionId,
      messages: mapTypebotOutput(output),
      waitingForInput: output.input !== undefined
    };
  });

  app.post("/internal/chatbot/action", async request => {
    requireWebhookSecret(request);
    const body = actionSchema.parse(request.body);

    return {
      ok: true,
      result: await transferChatbotToQueue({
        ticketId: body.ticketId,
        chatbotSessionId: body.chatbotSessionId,
        queueSlug: body.queue,
        externalSessionId: body.externalSessionId
      })
    };
  });
}
