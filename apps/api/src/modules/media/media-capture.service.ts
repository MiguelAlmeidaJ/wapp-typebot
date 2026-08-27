import { setImmediate } from "node:timers";

import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import { storeMedia } from "./media-storage.js";

const mediaTypes = new Set([
  "IMAGE",
  "AUDIO",
  "VIDEO",
  "DOCUMENT",
  "STICKER"
]);

function record(
  value: unknown
): Record<string, unknown> | undefined {
  return value &&
    typeof value === "object" &&
    !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function decodeBase64(value: string) {
  const normalized = value.includes(",")
    ? value.slice(value.indexOf(",") + 1)
    : value;

  return Buffer.from(
    normalized,
    "base64"
  );
}

export async function captureMessageMedia(
  messageId: string
) {
  const message =
    await prisma.message.findUnique({
      where: {
        id: messageId
      },
      include: {
        whatsappConnection: true
      }
    });

  if (!message) {
    throw new AppError(
      "Mensagem não encontrada.",
      404,
      "MESSAGE_NOT_FOUND"
    );
  }

  if (!mediaTypes.has(message.type)) {
    return message;
  }

  const raw = record(message.rawPayload);
  const webMessage = record(raw?.data);

  if (!webMessage) {
    const failed =
      await prisma.message.update({
        where: {
          id: message.id
        },
        data: {
          mediaStatus: "FAILED",
          mediaError:
            "Payload original da mensagem não está disponível."
        }
      });

    publishRealtime(message.companyId, {
      type: "message.updated",
      ticketId: message.ticketId,
      messageId: message.id
    });

    return failed;
  }

  await prisma.message.update({
    where: {
      id: message.id
    },
    data: {
      mediaStatus: "PENDING",
      mediaError: null
    }
  });

  try {
    const downloaded =
      await evolutionWhatsAppClient.downloadMedia({
        instanceName:
          message.whatsappConnection.instanceName,
        message: webMessage,
        convertToMp4: false
      });

    const buffer =
      decodeBase64(downloaded.base64);

    const stored = await storeMedia({
      companyId: message.companyId,
      messageId: message.id,
      buffer,
      mimetype:
        downloaded.mimetype ??
        message.mediaMimeType ??
        undefined,
      fileName:
        downloaded.fileName ??
        message.mediaFileName ??
        undefined
    });

    const updated =
      await prisma.message.update({
        where: {
          id: message.id
        },
        data: {
          mediaStatus: "READY",
          mediaStorageKey:
            stored.storageKey,
          mediaSize: stored.size,
          mediaMimeType:
            downloaded.mimetype ??
            message.mediaMimeType,
          mediaFileName:
            downloaded.fileName ??
            message.mediaFileName,
          mediaError: null
        }
      });

    publishRealtime(message.companyId, {
      type: "message.updated",
      ticketId: message.ticketId,
      messageId: message.id
    });

    return updated;
  } catch (error) {
    const messageText =
      error instanceof Error
        ? error.message
        : "Falha ao recuperar mídia.";

    const failed =
      await prisma.message.update({
        where: {
          id: message.id
        },
        data: {
          mediaStatus: "FAILED",
          mediaError:
            messageText.slice(0, 2_000)
        }
      });

    publishRealtime(message.companyId, {
      type: "message.updated",
      ticketId: message.ticketId,
      messageId: message.id
    });

    return failed;
  }
}

export function scheduleMessageMediaCapture(
  messageId: string
) {
  setImmediate(() => {
    void captureMessageMedia(
      messageId
    ).catch(() => {
      // The capture service persists its own failure state.
    });
  });
}
