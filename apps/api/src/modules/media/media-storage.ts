import { extname } from "node:path";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import {
  getMediaStorage,
  getMediaStorageMode
} from "./storage/media-storage.driver.js";

const mimeExtensions:
  Record<
    string,
    string
  > = {
    "image/jpeg":
      ".jpg",
    "image/png":
      ".png",
    "image/webp":
      ".webp",
    "image/gif":
      ".gif",
    "audio/ogg":
      ".ogg",
    "audio/mpeg":
      ".mp3",
    "audio/mp4":
      ".m4a",
    "audio/webm":
      ".webm",
    "video/mp4":
      ".mp4",
    "video/webm":
      ".webm",
    "application/pdf":
      ".pdf",
    "text/plain":
      ".txt",
    "application/zip":
      ".zip",
    "application/octet-stream":
      ".bin"
  };

function safeExtension(
  fileName?: string,
  mimetype?: string
) {
  const fromName =
    fileName
      ? extname(
          fileName
        ).toLowerCase()
      : "";

  if (
    fromName &&
    /^\.[a-z0-9]{1,8}$/.test(
      fromName
    )
  ) {
    return fromName;
  }

  const normalizedMime =
    mimetype
      ?.split(";")[0]
      ?.trim()
      .toLowerCase();

  return (
    (
      normalizedMime
        ? mimeExtensions[
            normalizedMime
          ]
        : undefined
    ) ??
    ".bin"
  );
}

function validateStorageKey(
  storageKey: string
) {
  if (
    !storageKey ||
    storageKey.startsWith("/") ||
    storageKey.includes("\\") ||
    storageKey.includes("..") ||
    !/^[a-zA-Z0-9._/-]+$/.test(
      storageKey
    )
  ) {
    throw new AppError(
      "Chave de mídia inválida.",
      400,
      "MEDIA_KEY_INVALID"
    );
  }

  return storageKey;
}

export async function storeMedia(input: {
  companyId: string;
  messageId: string;
  buffer: Buffer;
  mimetype?: string;
  fileName?: string;
}) {
  if (
    input.buffer.byteLength >
    env.MEDIA_MAX_BYTES
  ) {
    throw new AppError(
      `A mídia excede o limite de ${env.MEDIA_MAX_BYTES} bytes.`,
      413,
      "MEDIA_TOO_LARGE"
    );
  }

  const extension =
    safeExtension(
      input.fileName,
      input.mimetype
    );

  const storageKey =
    validateStorageKey(
      `${input.companyId}/${input.messageId}${extension}`
    );

  await getMediaStorage()
    .put({
      storageKey,
      buffer:
        input.buffer,
      contentType:
        input.mimetype
    });

  return {
    storageKey,
    size:
      input.buffer.byteLength
  };
}

export async function readMedia(
  storageKey: string
) {
  return getMediaStorage()
    .read(
      validateStorageKey(
        storageKey
      )
    );
}

export async function mediaExists(
  storageKey: string
) {
  return getMediaStorage()
    .exists(
      validateStorageKey(
        storageKey
      )
    );
}

export async function checkMediaStorageHealth() {
  return getMediaStorage()
    .healthCheck();
}

export {
  getMediaStorageMode
};
