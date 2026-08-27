import {
  access,
  mkdir,
  readFile,
  stat,
  writeFile
} from "node:fs/promises";
import {
  resolve,
  sep
} from "node:path";

import { env } from "../../../config/env.js";
import { AppError } from "../../../errors/app-error.js";
import type {
  MediaStorageDriver,
  MediaStoragePutInput,
  MediaStorageReadResult
} from "./media-storage.types.js";

export const localMediaRoot =
  resolve(
    process.cwd(),
    env.MEDIA_STORAGE_PATH
  );

export function resolveLocalStorageKey(
  storageKey: string
) {
  const absolute =
    resolve(
      localMediaRoot,
      storageKey
    );

  if (
    absolute !==
      localMediaRoot &&
    !absolute.startsWith(
      `${localMediaRoot}${sep}`
    )
  ) {
    throw new AppError(
      "Chave de mídia inválida.",
      400,
      "MEDIA_KEY_INVALID"
    );
  }

  return absolute;
}

export class LocalMediaStorage
  implements MediaStorageDriver
{
  async put(
    input: MediaStoragePutInput
  ) {
    const absolutePath =
      resolveLocalStorageKey(
        input.storageKey
      );

    const companyDirectory =
      resolveLocalStorageKey(
        input.storageKey
          .split("/")
          .slice(0, -1)
          .join("/")
      );

    await mkdir(
      companyDirectory,
      {
        recursive: true
      }
    );

    await writeFile(
      absolutePath,
      input.buffer
    );
  }

  async read(
    storageKey: string
  ): Promise<MediaStorageReadResult> {
    const absolutePath =
      resolveLocalStorageKey(
        storageKey
      );

    try {
      const [
        buffer,
        info
      ] =
        await Promise.all([
          readFile(
            absolutePath
          ),
          stat(
            absolutePath
          )
        ]);

      return {
        buffer,
        size:
          info.size
      };
    } catch (error) {
      if (
        error &&
        typeof error ===
          "object" &&
        "code" in error &&
        error.code ===
          "ENOENT"
      ) {
        throw new AppError(
          "Arquivo de mídia não encontrado.",
          404,
          "MEDIA_FILE_NOT_FOUND"
        );
      }

      throw error;
    }
  }

  async exists(
    storageKey: string
  ) {
    try {
      await access(
        resolveLocalStorageKey(
          storageKey
        )
      );

      return true;
    } catch {
      return false;
    }
  }

  async healthCheck() {
    try {
      await mkdir(
        localMediaRoot,
        {
          recursive: true
        }
      );

      await access(
        localMediaRoot
      );

      return {
        ok: true,
        driver:
          "local" as const
      };
    } catch (error) {
      return {
        ok: false,
        driver:
          "local" as const,
        error:
          error instanceof Error
            ? error.message
            : "local_storage_error"
      };
    }
  }
}
