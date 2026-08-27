import {
  readdir,
  readFile
} from "node:fs/promises";
import {
  relative,
  resolve,
  sep
} from "node:path";

import { env } from "../config/env.js";
import { LocalMediaStorage } from "../modules/media/storage/local-media-storage.js";
import { S3MediaStorage } from "../modules/media/storage/s3-media-storage.js";

async function listFiles(
  directory: string
): Promise<string[]> {
  const entries =
    await readdir(
      directory,
      {
        withFileTypes:
          true
      }
    );

  const files:
    string[] = [];

  for (const entry of entries) {
    const absolute =
      resolve(
        directory,
        entry.name
      );

    if (
      entry.isDirectory()
    ) {
      files.push(
        ...(
          await listFiles(
            absolute
          )
        )
      );
      continue;
    }

    if (
      entry.isFile()
    ) {
      files.push(
        absolute
      );
    }
  }

  return files;
}

async function main() {
  if (
    !env.S3_BUCKET
  ) {
    throw new Error(
      "Configure S3_BUCKET before migration."
    );
  }

  const source =
    new LocalMediaStorage();

  const destination =
    new S3MediaStorage();

  const health =
    await destination
      .healthCheck();

  if (!health.ok) {
    throw new Error(
      `S3 health check failed: ${health.error ?? "unknown"}`
    );
  }

  const root =
    resolve(
      process.cwd(),
      env.MEDIA_STORAGE_PATH
    );

  let files:
    string[];

  try {
    files =
      await listFiles(
        root
      );
  } catch (error) {
    if (
      error &&
      typeof error ===
        "object" &&
      "code" in error &&
      error.code ===
        "ENOENT"
    ) {
      console.log(
        "[media-migrate] No local media directory found."
      );
      return;
    }

    throw error;
  }

  let uploaded = 0;
  let skipped = 0;

  for (
    let index = 0;
    index < files.length;
    index += 1
  ) {
    const absolute =
      files[index]!;

    const storageKey =
      relative(
        root,
        absolute
      )
        .split(sep)
        .join("/");

    const alreadyExists =
      await destination
        .exists(
          storageKey
        );

    if (alreadyExists) {
      skipped += 1;
      continue;
    }

    /*
     * Resolve through the local driver before reading so the same
     * path-containment protection remains in effect.
     */
    const local =
      await source.read(
        storageKey
      );

    await destination.put({
      storageKey,
      buffer:
        local.buffer
    });

    uploaded += 1;

    if (
      uploaded % 25 === 0
    ) {
      console.log(
        `[media-migrate] ${uploaded} uploaded, ${skipped} skipped, ${index + 1}/${files.length} scanned`
      );
    }
  }

  console.log(
    `[media-migrate] Complete. uploaded=${uploaded} skipped=${skipped} total=${files.length}`
  );
}

main()
  .catch(error => {
    console.error(
      "[media-migrate] failed",
      error
    );

    process.exitCode = 1;
  });
