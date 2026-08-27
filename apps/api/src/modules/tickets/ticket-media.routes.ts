import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { requireAuth } from "../auth/auth.guard.js";
import { sendTicketMedia } from "./ticket.service.js";

const paramsSchema = z.object({
  id: z.string().uuid()
});

const captionSchema = z
  .string()
  .trim()
  .max(4096);

const voiceNoteSchema = z
  .enum(["true", "false"])
  .default("false")
  .transform(value => value === "true");

function record(
  value: unknown
): Record<string, unknown> | undefined {
  return value &&
    typeof value === "object" &&
    !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function multipartField(
  fields: unknown,
  key: string
) {
  const collection = record(fields);
  const field = record(
    collection?.[key]
  );
  const value = field?.value;

  return typeof value === "string"
    ? value
    : "";
}

export async function ticketMediaRoutes(
  app: FastifyInstance
) {
  app.post(
    "/api/v1/tickets/:id/media",
    async request => {
      const auth =
        await requireAuth(request);

      const params =
        paramsSchema.parse(
          request.params
        );

      let upload;

      try {
        upload =
          await request.file({
            limits: {
              fileSize:
                env.MEDIA_MAX_BYTES,
              files: 1,
              fields: 4,
              parts: 5
            }
          });
      } catch (error) {
        if (
          error instanceof
          app.multipartErrors
            .RequestFileTooLargeError
        ) {
          throw new AppError(
            `O arquivo excede o limite de ${Math.floor(
              env.MEDIA_MAX_BYTES /
                1024 /
                1024
            )} MB.`,
            413,
            "MEDIA_TOO_LARGE"
          );
        }

        throw error;
      }

      if (
        !upload ||
        upload.fieldname !== "file"
      ) {
        throw new AppError(
          "Arquivo não informado.",
          422,
          "MEDIA_FILE_REQUIRED"
        );
      }

      let buffer: Buffer;

      try {
        buffer =
          await upload.toBuffer();
      } catch (error) {
        if (
          error instanceof
          app.multipartErrors
            .RequestFileTooLargeError
        ) {
          throw new AppError(
            `O arquivo excede o limite de ${Math.floor(
              env.MEDIA_MAX_BYTES /
                1024 /
                1024
            )} MB.`,
            413,
            "MEDIA_TOO_LARGE"
          );
        }

        throw error;
      }

      if (buffer.byteLength === 0) {
        throw new AppError(
          "O arquivo está vazio.",
          422,
          "MEDIA_FILE_EMPTY"
        );
      }

      const caption =
        captionSchema.parse(
          multipartField(
            upload.fields,
            "caption"
          )
        );

      const voiceNote =
        voiceNoteSchema.parse(
          multipartField(
            upload.fields,
            "voiceNote"
          ) || "false"
        );

      return {
        message:
          await sendTicketMedia({
            companyId:
              auth.companyId,
            ticketId:
              params.id,
            userId:
              auth.userId,
            membershipId:
              auth.membershipId,
            role:
              auth.role,
            buffer,
            mimetype:
              upload.mimetype ||
              "application/octet-stream",
            fileName:
              upload.filename ||
              "arquivo",
            caption:
              caption || undefined,
            voiceNote
          })
      };
    }
  );
}
