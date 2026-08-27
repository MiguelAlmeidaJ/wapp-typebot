import {
  mkdir,
  readFile,
  stat,
  writeFile
} from "node:fs/promises";
import {
  extname,
  resolve,
  sep
} from "node:path";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";

const root = resolve(
  process.cwd(),
  env.MEDIA_STORAGE_PATH
);

const mimeExtensions: Record<string, string> = {
  "image/jpeg": ".jpg",
  "image/png": ".png",
  "image/webp": ".webp",
  "image/gif": ".gif",
  "audio/ogg": ".ogg",
  "audio/mpeg": ".mp3",
  "audio/mp4": ".m4a",
  "video/mp4": ".mp4",
  "video/webm": ".webm",
  "application/pdf": ".pdf",
  "text/plain": ".txt",
  "application/zip": ".zip",
  "application/octet-stream": ".bin"
};

function safeExtension(
  fileName?: string,
  mimetype?: string
) {
  const fromName = fileName
    ? extname(fileName).toLowerCase()
    : "";

  if (
    fromName &&
    /^\.[a-z0-9]{1,8}$/.test(fromName)
  ) {
    return fromName;
  }

  const normalizedMime = mimetype
    ?.split(";")[0]
    ?.trim()
    .toLowerCase();

  return (
    (normalizedMime
      ? mimeExtensions[normalizedMime]
      : undefined) ?? ".bin"
  );
}

function resolveStorageKey(
  storageKey: string
) {
  const absolute = resolve(root, storageKey);

  if (
    absolute !== root &&
    !absolute.startsWith(`${root}${sep}`)
  ) {
    throw new AppError(
      "Chave de mídia inválida.",
      400,
      "MEDIA_KEY_INVALID"
    );
  }

  return absolute;
}

export async function storeMedia(input: {
  companyId: string;
  messageId: string;
  buffer: Buffer;
  mimetype?: string;
  fileName?: string;
}) {
  if (input.buffer.byteLength > env.MEDIA_MAX_BYTES) {
    throw new AppError(
      `A mídia excede o limite de ${env.MEDIA_MAX_BYTES} bytes.`,
      413,
      "MEDIA_TOO_LARGE"
    );
  }

  const extension = safeExtension(
    input.fileName,
    input.mimetype
  );

  const storageKey =
    `${input.companyId}/${input.messageId}${extension}`;

  const absolutePath =
    resolveStorageKey(storageKey);

  await mkdir(
    resolve(root, input.companyId),
    {
      recursive: true
    }
  );

  await writeFile(
    absolutePath,
    input.buffer
  );

  return {
    storageKey,
    size: input.buffer.byteLength
  };
}

export async function readMedia(
  storageKey: string
) {
  const absolutePath =
    resolveStorageKey(storageKey);

  const [buffer, info] =
    await Promise.all([
      readFile(absolutePath),
      stat(absolutePath)
    ]);

  return {
    buffer,
    size: info.size
  };
}
