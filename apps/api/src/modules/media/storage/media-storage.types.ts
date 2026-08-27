export interface MediaStoragePutInput {
  storageKey: string;
  buffer: Buffer;
  contentType?: string;
}

export interface MediaStorageReadResult {
  buffer: Buffer;
  size: number;
}

export interface MediaStorageDriver {
  put(
    input: MediaStoragePutInput
  ): Promise<void>;

  read(
    storageKey: string
  ): Promise<MediaStorageReadResult>;

  exists(
    storageKey: string
  ): Promise<boolean>;

  healthCheck(): Promise<{
    ok: boolean;
    driver: "local" | "s3";
    error?: string;
  }>;
}
