import { randomUUID } from "node:crypto";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import {
  TypebotManagementClient
} from "../../integrations/typebot/typebot-management.client.js";
import { prisma } from "../../lib/database.js";
import { createChatbotFlow } from "./chatbot.service.js";

function publicIdSegment(value: string) {
  const normalized = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-")
    .slice(0, 80);

  return normalized || "empresa";
}

function managementClient() {
  if (
    !env.TYPEBOT_ENABLED ||
    !env.TYPEBOT_URL ||
    !env.TYPEBOT_API_TOKEN
  ) {
    throw new AppError(
      "Gerenciamento do Typebot não está configurado. Defina TYPEBOT_URL e TYPEBOT_API_TOKEN.",
      503,
      "TYPEBOT_MANAGEMENT_NOT_CONFIGURED"
    );
  }

  return new TypebotManagementClient(
    env.TYPEBOT_URL,
    env.TYPEBOT_API_TOKEN,
    env.TYPEBOT_REQUEST_TIMEOUT_MS
  );
}

async function ensureCompanyWorkspace(
  companyId: string,
  client: TypebotManagementClient
) {
  const company = await prisma.company.findUnique({
    where: { id: companyId },
    select: {
      id: true,
      name: true,
      slug: true,
      typebotWorkspaceId: true
    }
  });

  if (!company) {
    throw new AppError("Empresa não encontrada.", 404, "COMPANY_NOT_FOUND");
  }

  if (company.typebotWorkspaceId) {
    return {
      workspaceId: company.typebotWorkspaceId,
      companySlug: company.slug
    };
  }

  const workspace = await client.createWorkspace(`Wapp - ${company.name}`);

  const claimed = await prisma.company.updateMany({
    where: {
      id: company.id,
      typebotWorkspaceId: null
    },
    data: {
      typebotWorkspaceId: workspace.id
    }
  });

  if (claimed.count === 1) {
    return {
      workspaceId: workspace.id,
      companySlug: company.slug
    };
  }

  const winner = await prisma.company.findUnique({
    where: { id: company.id },
    select: { typebotWorkspaceId: true }
  });

  if (winner?.typebotWorkspaceId) {
    await client.deleteWorkspace(workspace.id).catch(() => undefined);

    return {
      workspaceId: winner.typebotWorkspaceId,
      companySlug: company.slug
    };
  }

  throw new AppError(
    "Não foi possível vincular o workspace do Typebot à empresa.",
    500,
    "TYPEBOT_WORKSPACE_LINK_FAILED"
  );
}

export async function createManagedChatbotFlow(input: {
  companyId: string;
  actorMembershipId: string;
  name: string;
  whatsappConnectionId: string;
  isActive?: boolean;
}) {
  const client = managementClient();
  const { workspaceId, companySlug } = await ensureCompanyWorkspace(
    input.companyId,
    client
  );

  const publicId = [
    "wapp",
    publicIdSegment(companySlug),
    randomUUID().replace(/-/g, "").slice(0, 10)
  ].join("-");

  const remote = await client.createTypebot({
    workspaceId,
    name: input.name.trim(),
    publicId
  });

  try {
    await client.publishTypebot(remote.id);

    return await createChatbotFlow({
      companyId: input.companyId,
      actorMembershipId: input.actorMembershipId,
      name: input.name,
      whatsappConnectionId: input.whatsappConnectionId,
      externalId: remote.publicId ?? publicId,
      externalTypebotId: remote.id,
      // Bots criados pelo Wapp nascem inativos até o editor possuir conteúdo.
      isActive: input.isActive ?? false
    });
  } catch (error) {
    await client.deleteTypebot(remote.id).catch(() => undefined);
    throw error;
  }
}
