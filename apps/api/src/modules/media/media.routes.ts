import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { requireAuth } from "../auth/auth.guard.js";
import { captureMessageMedia } from "./media-capture.service.js";
import { readMedia } from "./media-storage.js";

const messageIdSchema = z.object({
  id: z.string().uuid()
});

function safeFileName(
  value: string | null,
  messageId: string
) {
  return (
    value
      ?.replace(/[\r\n"]/g, "_")
      .slice(0, 180) ??
    `wapp-${messageId}`
  );
}

export async function mediaRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/messages/:id/media",
    async (request, reply) => {
      const auth = await requireAuth(request);
      const params = messageIdSchema.parse(
        request.params
      );

      const message =
        await prisma.message.findFirst({
          where: {
            id: params.id,
            companyId: auth.companyId
          },
          select: {
            id: true,
            mediaStatus: true,
            mediaStorageKey: true,
            mediaMimeType: true,
            mediaFileName: true
          }
        });

      if (!message) {
        throw new AppError(
          "Mensagem não encontrada.",
          404,
          "MESSAGE_NOT_FOUND"
        );
      }

      if (
        message.mediaStatus !== "READY" ||
        !message.mediaStorageKey
      ) {
        throw new AppError(
          "A mídia ainda não está disponível.",
          409,
          "MEDIA_NOT_READY"
        );
      }

      const media = await readMedia(
        message.mediaStorageKey
      );

      const fileName = safeFileName(
        message.mediaFileName,
        message.id
      );

      reply.header(
        "Content-Type",
        message.mediaMimeType ??
          "application/octet-stream"
      );

      reply.header(
        "Content-Length",
        String(media.size)
      );

      reply.header(
        "Content-Disposition",
        `inline; filename="${fileName}"; filename*=UTF-8''${encodeURIComponent(
          fileName
        )}`
      );

      return reply.send(media.buffer);
    }
  );

  app.post(
    "/api/v1/messages/:id/media/retry",
    async request => {
      const auth = await requireAuth(request);
      const params = messageIdSchema.parse(
        request.params
      );

      const message =
        await prisma.message.findFirst({
          where: {
            id: params.id,
            companyId: auth.companyId
          },
          select: {
            id: true
          }
        });

      if (!message) {
        throw new AppError(
          "Mensagem não encontrada.",
          404,
          "MESSAGE_NOT_FOUND"
        );
      }

      return {
        message:
          await captureMessageMedia(
            message.id
          )
      };
    }
  );
}
