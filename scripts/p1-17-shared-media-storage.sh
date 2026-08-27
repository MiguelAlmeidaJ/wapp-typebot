#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.17] Building shared media storage abstraction..."

for required in \
  "apps/api/package.json" \
  "apps/api/.env.example" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/modules/media/media-storage.ts"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/media/storage \
  apps/api/src/scripts \
  docs

# ---------------------------------------------------------------------------
# AWS S3 client dependency
# ---------------------------------------------------------------------------

if ! node -e '
const pkg = require("./apps/api/package.json");
process.exit(pkg.dependencies?.["@aws-sdk/client-s3"] ? 0 : 1);
'; then
  echo "[P1.17] Installing S3 client..."
  pnpm --filter @wapp/api add @aws-sdk/client-s3@^3.0.0
else
  echo "[P1.17] S3 client already installed."
fi

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/config/env.ts";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "MEDIA_STORAGE_DRIVER:"
  )
) {
  const anchor =
    '  MEDIA_STORAGE_PATH: z.string().default(".runtime/media"),';

  if (!content.includes(anchor)) {
    throw new Error(
      "MEDIA_STORAGE_PATH env anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `  MEDIA_STORAGE_DRIVER: z
    .enum(["local", "s3"])
    .default("local"),
${anchor}
  S3_BUCKET: z.string().min(1).optional(),
  S3_REGION: z.string().min(1).default("us-east-1"),
  S3_ENDPOINT: z.string().url().optional().or(z.literal("")),
  S3_FORCE_PATH_STYLE: booleanFromEnv,
  S3_ACCESS_KEY_ID: z.string().min(1).optional(),
  S3_SECRET_ACCESS_KEY: z.string().min(1).optional(),`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Media storage environment installed."
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/.env.example";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "MEDIA_STORAGE_DRIVER="
  )
) {
  const anchor =
    "# Media";

  if (!content.includes(anchor)) {
    throw new Error(
      "Media .env.example section not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
MEDIA_STORAGE_DRIVER=local`
    );
}

if (
  !content.includes(
    "S3_BUCKET="
  )
) {
  const anchor =
    "MEDIA_MAX_BYTES=26214400";

  if (!content.includes(anchor)) {
    throw new Error(
      "MEDIA_MAX_BYTES .env.example anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

# Shared S3-compatible storage (production)
# Set MEDIA_STORAGE_DRIVER=s3 when configured.
S3_BUCKET=
S3_REGION=us-east-1
S3_ENDPOINT=
S3_FORCE_PATH_STYLE=false
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Storage contract
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/media/storage/media-storage.types.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# Local driver
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/media/storage/local-media-storage.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# S3 driver
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/media/storage/s3-media-storage.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# Driver selector
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/media/storage/media-storage.driver.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# Preserve public media-storage API, replace filesystem implementation
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/media/media-storage.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# Migration helper: local filesystem -> configured S3 driver
# ---------------------------------------------------------------------------

cat > apps/api/src/scripts/migrate-local-media-to-s3.ts <<'EOF'
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
      files[index];

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
EOF

# ---------------------------------------------------------------------------
# P1.15 health integration if present
# ---------------------------------------------------------------------------

if [[ -f "apps/api/src/modules/health/health.service.ts" ]]; then
  node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/health/health.service.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  `import {
  checkMediaStorageHealth,
  getMediaStorageMode
} from "../media/media-storage.js";`;

if (
  !content.includes(
    "checkMediaStorageHealth,"
  )
) {
  const anchor =
    'import { getRealtimeTransportStatus } from "../realtime/realtime.bus.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Health realtime import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    "const storage ="
  )
) {
  const anchor =
    `  const readiness =
    await getReadiness();`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Health details readiness anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

  const storage =
    await checkMediaStorageHealth();`
    );
}

if (
  !content.includes(
    "mediaStorage:"
  )
) {
  const anchor =
    `    readiness: {
      ready:
        readiness.ready,
      checks:
        readiness.checks
    },`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Health details readiness output anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
    mediaStorage: {
      driver:
        getMediaStorageMode(),
      status:
        storage.ok
          ? "ok"
          : "error",
      ...(storage.error
        ? {
            error:
              storage.error
          }
        : {})
    },`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Detailed health now reports media storage status."
);
NODE
fi

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/SHARED_MEDIA_STORAGE.md <<'EOF'
# Shared media storage

P1.17 removes the assumption that every API request runs on the same machine
that originally stored a media file.

## Why

The original P1.2 storage writes to:

`.runtime/media`

That is correct for one local API process, but not for horizontally scaled API
replicas.

With local disks:

```text
message arrives -> API A -> disk A

media GET -> load balancer -> API B -> disk B -> file missing
```

P1.17 introduces a storage driver seam.

## Drivers

### local

Default:

`MEDIA_STORAGE_DRIVER=local`

This preserves the current development behavior.

Files remain under:

`MEDIA_STORAGE_PATH=.runtime/media`

### s3

Production/shared mode:

`MEDIA_STORAGE_DRIVER=s3`

Required:

`S3_BUCKET`

Common optional settings:

- `S3_REGION`
- `S3_ENDPOINT`
- `S3_FORCE_PATH_STYLE`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`

If explicit access keys are omitted, the AWS SDK can use its normal credential
provider chain, which is preferred for IAM roles/workload identities.

## S3-compatible providers

The driver uses the standard S3 API and supports AWS S3 and providers exposing
compatible S3 endpoints, including typical MinIO/R2-style deployments.

Provider-specific endpoint, region and path-style requirements must match that
provider's documentation.

## Storage keys

Database storage keys do not change.

Example:

`<companyId>/<messageId>.jpg`

This means existing database records do not require a migration.

## Existing local files

Before switching an existing environment to `MEDIA_STORAGE_DRIVER=s3`, configure
the S3 variables and run:

`pnpm --filter @wapp/api exec tsx src/scripts/migrate-local-media-to-s3.ts`

The migration:

- walks the current local media directory;
- preserves each existing storage key;
- skips objects that already exist in S3;
- does not delete local files;
- is safe to run again.

After verifying media through Wapp, change:

`MEDIA_STORAGE_DRIVER=s3`

and restart the API.

Do not delete the local media directory until the migrated files have been
verified and a backup policy exists.

## Security

Media remains private behind Wapp's authenticated endpoint:

`GET /api/v1/messages/:id/media`

P1.17 does not expose public bucket URLs or presigned URLs.

The bucket should remain private.

## Health

When P1.15 is installed, detailed `/health` also reports the media-storage
driver and its health.

Storage failure is diagnostic/degraded state, not a readiness dependency, so a
provider outage does not make text-only/API functions unavailable.

## Migration

P1.17 requires no Prisma migration.
EOF

echo "[P1.17] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.17] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.17] Shared media storage installed."
echo "No Prisma migration is required."
echo
echo "Local development remains unchanged:"
echo "  MEDIA_STORAGE_DRIVER=local"
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Local validation:"
echo "  1. receive an image/audio/document"
echo "  2. send an attachment"
echo "  3. reopen the conversation and confirm all media still loads"
echo
echo "Do NOT switch to s3 until bucket credentials/configuration are ready."
