import { randomBytes } from "node:crypto";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

function normalizeInstancePart(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 45);
}

function instanceName(companySlug: string, name: string) {
  const company = normalizeInstancePart(companySlug) || "company";
  const connection = normalizeInstancePart(name) || "whatsapp";
  const suffix = randomBytes(4).toString("hex");

  return `wapp-${company}-${connection}-${suffix}`.slice(0, 100);
}

function webhookUrl() {
  return `${env.EVOLUTION_WEBHOOK_BASE_URL}/api/v1/webhooks/evolution/${env.EVOLUTION_WEBHOOK_SECRET}`;
}

const WAPP_WEBHOOK_EVENTS = [
  "QRCODE_UPDATED",
  "MESSAGES_UPSERT",
  "MESSAGES_UPDATE",
  "CONNECTION_UPDATE"
];

async function ensureWebhook(
  instanceName: string
) {
  await evolutionWhatsAppClient.configureWebhook({
    instanceName,
    webhookUrl: webhookUrl(),
    events: WAPP_WEBHOOK_EVENTS
  });
}

function mapEvolutionState(
  state: string
): "CREATED" | "CONNECTING" | "CONNECTED" | "DISCONNECTED" | "ERROR" {
  switch (state.toLowerCase()) {
    case "open":
    case "connected":
      return "CONNECTED";
    case "connecting":
      return "CONNECTING";
    case "close":
    case "closed":
    case "disconnected":
      return "DISCONNECTED";
    default:
      return "CREATED";
  }
}

export async function listConnections(companyId: string) {
  return prisma.whatsAppConnection.findMany({
    where: {
      companyId
    },
    include: {
      defaultQueue: {
        select: {
          id: true,
          name: true
        }
      }
    },
    orderBy: {
      createdAt: "desc"
    }
  });
}

export async function createConnection(input: {
  companyId: string;
  companySlug: string;
  name: string;
}) {
  const generatedInstanceName = instanceName(
    input.companySlug,
    input.name
  );

  const connection = await prisma.whatsAppConnection.create({
    data: {
      companyId: input.companyId,
      name: input.name.trim(),
      instanceName: generatedInstanceName,
      provider: "EVOLUTION_BAILEYS",
      status: "CREATED",
      acceptGroups: false
    }
  });

  try {
    const qr = await evolutionWhatsAppClient.createInstance({
      instanceName: generatedInstanceName,
      webhookUrl: webhookUrl()
    });

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: "CONNECTING",
        lastError: null,
        lastEventAt: new Date()
      }
    });

    return {
      connection: {
        ...connection,
        status: "CONNECTING" as const
      },
      qr
    };
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Evolution API error";

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: "ERROR",
        lastError: message,
        lastEventAt: new Date()
      }
    });

    throw error;
  }
}

export async function getCompanyConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await prisma.whatsAppConnection.findFirst({
    where: {
      id: connectionId,
      companyId
    }
  });

  if (!connection) {
    throw new AppError(
      "Conexão WhatsApp não encontrada.",
      404,
      "WHATSAPP_CONNECTION_NOT_FOUND"
    );
  }

  return connection;
}

export async function updateConnectionSettings(input: {
  companyId: string;
  connectionId: string;
  acceptGroups?: boolean;
  defaultQueueId?: string | null;
}) {
  await getCompanyConnection(input.companyId, input.connectionId);

  if (input.defaultQueueId) {
    const queue = await prisma.queue.findFirst({
      where: {
        id: input.defaultQueueId,
        companyId: input.companyId,
        isActive: true
      }
    });

    if (!queue) {
      throw new AppError(
        "Fila padrão não encontrada.",
        404,
        "DEFAULT_QUEUE_NOT_FOUND"
      );
    }
  }

  const connection = await prisma.whatsAppConnection.update({
    where: {
      id: input.connectionId
    },
    data: {
      ...(input.acceptGroups !== undefined
        ? { acceptGroups: input.acceptGroups }
        : {}),
      ...(input.defaultQueueId !== undefined
        ? { defaultQueueId: input.defaultQueueId }
        : {})
    },
    include: {
      defaultQueue: {
        select: {
          id: true,
          name: true
        }
      }
    }
  });

  publishRealtime(input.companyId, {
    type: "connection.updated",
    connectionId: connection.id
  });

  return connection;
}

export async function connectConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await getCompanyConnection(
    companyId,
    connectionId
  );

  await ensureWebhook(
    connection.instanceName
  );

  const qr = await evolutionWhatsAppClient.connect(
    connection.instanceName
  );

  await prisma.whatsAppConnection.update({
    where: {
      id: connection.id
    },
    data: {
      status: "CONNECTING",
      lastError: null,
      lastEventAt: new Date()
    }
  });

  return {
    qr
  };
}

export async function syncConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await getCompanyConnection(
    companyId,
    connectionId
  );

  try {
    await ensureWebhook(
      connection.instanceName
    );

    const state = await evolutionWhatsAppClient.connectionState(
      connection.instanceName
    );

    const updated = await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: mapEvolutionState(state.state),
        lastError: null,
        lastEventAt: new Date()
      }
    });

    publishRealtime(companyId, {
      type: "connection.updated",
      connectionId: connection.id
    });

    return updated;
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Evolution API error";

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        lastError: message,
        lastEventAt: new Date()
      }
    });

    throw error;
  }
}

export async function sendTestMessage(input: {
  companyId: string;
  connectionId: string;
  number: string;
  text: string;
}) {
  const connection = await getCompanyConnection(
    input.companyId,
    input.connectionId
  );

  if (connection.status !== "CONNECTED") {
    throw new AppError(
      "Conecte o WhatsApp antes de enviar mensagens.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  return evolutionWhatsAppClient.sendText({
    instanceName: connection.instanceName,
    number: input.number,
    text: input.text
  });
}
