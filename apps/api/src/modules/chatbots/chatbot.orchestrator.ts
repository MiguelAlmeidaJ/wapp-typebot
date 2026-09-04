import { env } from "../../config/env.js";
import { TypebotClient } from "../../integrations/typebot/typebot.client.js";
import {
  mapTypebotAnswer,
  mapTypebotOutput
} from "../../integrations/typebot/typebot.mapper.js";
import type { ChatbotOutput } from "../../integrations/typebot/typebot.types.js";
import { Prisma } from "../../generated/prisma/client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import {
  finishChatbotSessionForTicket,
  sendChatbotText
} from "./chatbot.service.js";

function provider() {
  return new TypebotClient(
    env.TYPEBOT_API_URL || "",
    env.TYPEBOT_API_TOKEN || "",
    env.TYPEBOT_REQUEST_TIMEOUT_MS
  );
}

async function persistOutput(
  sessionId: string,
  externalSessionId: string,
  output: ChatbotOutput
) {
  const result = await prisma.chatbotSession.updateMany({
    where: {
      id: sessionId,
      activeKey: { not: null }
    },
    data: {
      externalSessionId,
      status: "ACTIVE",
      lastInput: output.input === undefined
        ? Prisma.DbNull
        : toPrismaJson(output.input),
      lastError: null,
      finishReason: null
    }
  });

  return result.count > 0;
}

async function deliverOutput(input: {
  sessionId: string;
  companyId: string;
  ticketId: string;
  output: ChatbotOutput;
}) {
  for (const text of mapTypebotOutput(input.output)) {
    const sent = await sendChatbotText({
      sessionId: input.sessionId,
      companyId: input.companyId,
      ticketId: input.ticketId,
      text
    });

    if (!sent) return false;
  }

  return true;
}

async function failSession(sessionId: string, error: unknown) {
  await prisma.chatbotSession.updateMany({
    where: {
      id: sessionId,
      activeKey: { not: null }
    },
    data: {
      status: "FAILED",
      activeKey: null,
      finishedAt: new Date(),
      finishReason: "PROVIDER_ERROR",
      lastError: (
        error instanceof Error ? error.message : "Chatbot execution failed."
      ).slice(0, 2_000)
    }
  });
}

export async function handleInboundChatbot(input: {
  ticketId: string;
  message: string;
}) {
  if (!env.TYPEBOT_ENABLED || !input.message.trim()) {
    return { handled: false, reason: "disabled_or_empty" };
  }

  const ticket = await prisma.ticket.findUnique({
    where: { id: input.ticketId },
    include: {
      contact: {
        select: {
          id: true,
          name: true,
          phoneNumber: true,
          remoteJid: true
        }
      }
    }
  });

  if (!ticket || ticket.status === "CLOSED") {
    return { handled: false, reason: "ticket_unavailable" };
  }

  if (ticket.assignedMembershipId) {
    await finishChatbotSessionForTicket(ticket.id, "HUMAN_TAKEOVER");
    return { handled: false, reason: "human_takeover" };
  }

  const flow = await prisma.chatbotFlow.findUnique({
    where: { activeKey: ticket.whatsappConnectionId }
  });

  if (!flow || flow.companyId !== ticket.companyId) {
    return { handled: false, reason: "flow_not_found" };
  }

  let session = await prisma.chatbotSession.findUnique({
    where: { activeKey: ticket.id }
  });
  let createdSession = false;

  if (!session) {
    try {
      session = await prisma.chatbotSession.create({
        data: {
          companyId: ticket.companyId,
          ticketId: ticket.id,
          flowId: flow.id,
          engine: flow.engine,
          activeKey: ticket.id,
          status: "STARTING"
        }
      });
      createdSession = true;
    } catch {
      session = await prisma.chatbotSession.findUnique({
        where: { activeKey: ticket.id }
      });
    }
  }

  if (!session) {
    return { handled: false, reason: "session_race" };
  }

  if (session.status === "STARTING" && !createdSession) {
    return { handled: false, reason: "session_starting" };
  }

  try {
    const client = provider();
    const output = session.externalSessionId
      ? await client.continue(
          session.externalSessionId,
          mapTypebotAnswer(input.message, session.lastInput)
        )
      : await client.start({
          externalId: flow.externalId,
          message: input.message,
          variables: {
            nome: ticket.contact.name,
            telefone: ticket.contact.phoneNumber ?? ticket.contact.remoteJid,
            ticketId: ticket.id,
            companyId: ticket.companyId,
            chatbotSessionId: session.id
          }
        });

    const externalSessionId = output.externalSessionId ??
      session.externalSessionId;

    if (!externalSessionId) {
      throw new Error("Typebot sessionId is missing.");
    }

    const stillActive = await persistOutput(
      session.id,
      externalSessionId,
      output
    );

    if (!stillActive) {
      return { handled: false, reason: "human_takeover" };
    }
    const delivered = await deliverOutput({
      sessionId: session.id,
      companyId: ticket.companyId,
      ticketId: ticket.id,
      output
    });

    if (!delivered) {
      return { handled: false, reason: "human_takeover" };
    }

    if (output.input === undefined) {
      await finishChatbotSessionForTicket(ticket.id, "FLOW_COMPLETED");
    }

    return {
      handled: true,
      sessionId: session.id,
      completed: output.input === undefined
    };
  } catch (error) {
    await failSession(session.id, error);
    return {
      handled: false,
      reason: "provider_error",
      error: error instanceof Error ? error.message : "Chatbot execution failed."
    };
  }
}
