import {
  GetObjectCommand,
  HeadBucketCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client
} from "@aws-sdk/client-s3";

import { env } from "../../../config/env.js";
import { AppError } from "../../../errors/app-error.js";
import type {
  MediaStorageDriver,
  MediaStoragePutInput,
  MediaStorageReadResult
} from "./media-storage.types.js";

function requiredBucket() {
  if (!env.S3_BUCKET) {
    throw new Error(
      "S3_BUCKET is required when MEDIA_STORAGE_DRIVER=s3."
    );
  }

  return env.S3_BUCKET;
}

function credentials() {
  const accessKeyId =
    env.S3_ACCESS_KEY_ID;

  const secretAccessKey =
    env.S3_SECRET_ACCESS_KEY;

  if (
    Boolean(accessKeyId) !==
    Boolean(secretAccessKey)
  ) {
    throw new Error(
      "S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY must be configured together."
    );
  }

  return accessKeyId &&
    secretAccessKey
    ? {
        accessKeyId,
        secretAccessKey
      }
    : undefined;
}

function createClient() {
  return new S3Client({
    region:
      env.S3_REGION,
    ...(env.S3_ENDPOINT
      ? {
          endpoint:
            env.S3_ENDPOINT
        }
      : {}),
    forcePathStyle:
      env.S3_FORCE_PATH_STYLE,
    credentials:
      credentials()
  });
}

function isNotFound(
  error: unknown
) {
  if (
    !error ||
    typeof error !==
      "object"
  ) {
    return false;
  }

  const candidate =
    error as {
      name?: string;
      $metadata?: {
        httpStatusCode?: number;
      };
  };

  return (
    candidate.name ===
      "NoSuchKey" ||
    candidate.name ===
      "NotFound" ||
    candidate.$metadata
      ?.httpStatusCode ===
      404
  );
}

export class S3MediaStorage
  implements MediaStorageDriver
{
  private readonly client =
    createClient();

  private readonly bucket =
    requiredBucket();

  async put(
    input: MediaStoragePutInput
  ) {
    await this.client.send(
      new PutObjectCommand({
        Bucket:
          this.bucket,
        Key:
          input.storageKey,
        Body:
          input.buffer,
        ContentType:
          input.contentType ??
          "application/octet-stream"
      })
    );
  }

  async read(
    storageKey: string
  ): Promise<MediaStorageReadResult> {
    try {
      const response =
        await this.client.send(
          new GetObjectCommand({
            Bucket:
              this.bucket,
            Key:
              storageKey
          })
        );

      if (!response.Body) {
        throw new AppError(
          "Arquivo de mídia não encontrado.",
          404,
          "MEDIA_FILE_NOT_FOUND"
        );
      }

      const bytes =
        await response.Body
          .transformToByteArray();

      const buffer =
        Buffer.from(
          bytes
        );

      return {
        buffer,
        size:
          response.ContentLength ??
          buffer.byteLength
      };
    } catch (error) {
      if (
        error instanceof AppError
      ) {
        throw error;
      }

      if (
        isNotFound(
          error
        )
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
      await this.client.send(
        new HeadObjectCommand({
          Bucket:
            this.bucket,
          Key:
            storageKey
        })
      );

      return true;
    } catch (error) {
      if (
        isNotFound(
          error
        )
      ) {
        return false;
      }

      throw error;
    }
  }

  async healthCheck() {
    try {
      await this.client.send(
        new HeadBucketCommand({
          Bucket:
            this.bucket
        })
      );

      return {
        ok: true,
        driver:
          "s3" as const
      };
    } catch (error) {
      return {
        ok: false,
        driver:
          "s3" as const,
        error:
          error instanceof Error
            ? error.message
            : "s3_storage_error"
      };
    }
  }
}
