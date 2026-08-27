import { env } from "../../../config/env.js";
import type { MediaStorageDriver } from "./media-storage.types.js";
import { LocalMediaStorage } from "./local-media-storage.js";
import { S3MediaStorage } from "./s3-media-storage.js";

let storage:
  | MediaStorageDriver
  | null =
  null;

export function getMediaStorage():
  MediaStorageDriver {
  if (storage) {
    return storage;
  }

  storage =
    env.MEDIA_STORAGE_DRIVER ===
      "s3"
      ? new S3MediaStorage()
      : new LocalMediaStorage();

  return storage;
}

export function getMediaStorageMode() {
  return env.MEDIA_STORAGE_DRIVER;
}
