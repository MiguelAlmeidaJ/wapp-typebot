import { timingSafeEqual } from "node:crypto";

import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { ingestEvolutionMessage } from "../messages/message-ingestion.service.js";
import { ingestEvolutionReaction } from "../messages/message-reaction.service.js";
import { ingestEvolutionMessageUpdate } from "../messages/message-status.service.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

const paramsSchema = z.object({
  secret: z.string().min(1)
});

function secretsMatch(received: string, expected: string) {
  const receivedBuffer = Buffer.from(received);
  const expectedBuffer = Buffer.from(expected);

  return (
    receivedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(receivedBuffer, expectedBuffer)
  );
}

function normalizeEvent(value: unknown) {
  return String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/[.\-\s]+/g, "_");
}

function getInstanceName(body: Record<string, unknown>) {
  if (typeof body.instance === "string") {
    return body.instance;
  }

  if (typeof body.instanceName === "string") {
    return body.instanceName;
  }

  const data = body.data;

  if (data && typeof data === "object") {
    const dataRecord = data as Record<string, unknown>;

    if (typeof dataRecord.instance === "string") {
      return dataRecord.instance;
    }

    if (typeof dataRecord.instanceName === "string") {
      return dataRecord.instanceName;
    }
  }

  return undefined;
}

function connectionState(body: Record<string, unknown>) {
  const data = body.data;

  if (!data || typeof data !== "object") {
    return undefined;
  }

  const record = data as Record<string, unknown>;

  if (typeof record.state === "string") {
    return record.state;
  }

  if (typeof record.status === "string") {
    return record.status;
  }

  return undefined;
}

function mapState(state: string | undefined) {
  switch (state?.toLowerCase()) {
    case "open":
    case "connected":
      return "CONNECTED" as const;
    case "connecting":
      return "CONNECTING" as const;
    case "close":
    case "closed":
    case "disconnected":
      return "DISCONNECTED" as const;
    default:
      return undefined;
  }
}

export async function evolutionWebhookRoutes(
  app: FastifyInstance
) {
  app.post(
    "/api/v1/webhooks/evolution/:secret",
    async (request, reply) => {
      const params = paramsSchema.parse(request.params);

      if (
        !secretsMatch(
          params.secret,
          env.EVOLUTION_WEBHOOK_SECRET
        )
      ) {
        throw new AppError(
          "Webhook não autorizado.",
          401,
          "WEBHOOK_UNAUTHORIZED"
        );
      }

      if (!request.body || typeof request.body !== "object") {
        return reply.status(204).send();
      }

      const body = request.body as Record<string, unknown>;
      const event = normalizeEvent(body.event);
      const instance = getInstanceName(body);

      if (!instance) {
        request.log.warn(
          { event },
          "Evolution webhook without instance name"
        );
        return reply.status(204).send();
      }

      const connection = await prisma.whatsAppConnection.findUnique({
        where: {
          instanceName: instance
        }
      });

      if (!connection) {
        request.log.warn(
          { event, instance },
          "Evolution webhook for unknown instance"
        );
        return reply.status(204).send();
      }

      if (event === "CONNECTION_UPDATE") {
        const mappedState = mapState(connectionState(body));

        if (mappedState) {
          const data =
            body.data && typeof body.data === "object"
              ? (body.data as Record<string, unknown>)
              : {};

          const owner =
            typeof data.wuid === "string"
              ? data.wuid
              : typeof data.number === "string"
                ? data.number
                : undefined;

          await prisma.whatsAppConnection.update({
            where: {
              id: connection.id
            },
            data: {
              status:
                mappedState,
              phoneNumber:
                owner?.replace(
                  /\D/g,
                  ""
                ) ||
                undefined,
              lastError:
                null,
              healthStatus:
                mappedState ===
                "CONNECTED"
                  ? "HEALTHY"
                  : "DEGRADED",
              lastHealthCheckAt:
                new Date(),
              ...(mappedState ===
              "CONNECTED"
                ? {
                    lastHealthOkAt:
                      new Date()
                  }
                : {}),
              healthError:
                null,
              consecutiveHealthFailures:
                0,
              lastEventAt:
                new Date()
            }
          });

          publishRealtime(connection.companyId, {
            type: "connection.updated",
            connectionId: connection.id
          });
        }
      } else if (event === "MESSAGES_UPSERT") {
        const reaction =
          await ingestEvolutionReaction(
            body,
            connection
          );

        const result =
          reaction ??
          await ingestEvolutionMessage(
            body,
            connection
          );

        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance,
            result
          },
          reaction
            ? "Evolution reaction processed"
            : "Evolution message processed"
        );
      } else if (event === "MESSAGES_UPDATE") {
        const result =
          await ingestEvolutionMessageUpdate(
            body,
            connection
          );

        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance,
            result
          },
          "Evolution message status processed"
        );
      } else {
        await prisma.whatsAppConnection.update({
          where: {
            id: connection.id
          },
          data: {
            lastEventAt: new Date()
          }
        });
      }

      return {
        received: true
      };
    }
  );
}
