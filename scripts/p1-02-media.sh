#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.2] Building media ingestion and protected delivery..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/integrations/whatsapp/provider.ts" \
  "apps/api/src/integrations/whatsapp/evolution.client.ts" \
  "apps/api/src/modules/messages/message-ingestion.service.ts" \
  "apps/api/src/modules/messages/evolution-message.parser.ts" \
  "apps/api/src/modules/realtime/realtime.bus.ts" \
  "apps/web/components/auth-provider.tsx" \
  "apps/web/lib/realtime-types.ts" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/media \
  apps/web/components/messages \
  docs

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

append_env_if_missing() {
  local file="$1"
  local key="$2"
  local value="$3"

  touch "$file"

  if ! grep -Eq "^${key}=" "$file"; then
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

append_env_if_missing \
  "apps/api/.env" \
  "MEDIA_STORAGE_PATH" \
  ".runtime/media"

append_env_if_missing \
  "apps/api/.env" \
  "MEDIA_MAX_BYTES" \
  "26214400"

if ! grep -Eq "^MEDIA_STORAGE_PATH=" apps/api/.env.example; then
  cat >> apps/api/.env.example <<'EOF'

# Media
MEDIA_STORAGE_PATH=.runtime/media
MEDIA_MAX_BYTES=26214400
EOF
fi

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/config/env.ts";
let content = fs.readFileSync(path, "utf8");

if (!content.includes("MEDIA_STORAGE_PATH:")) {
  const anchor =
    '  WHATSAPP_SESSION_PATH: z.string().default(".runtime/whatsapp"),';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find WHATSAPP_SESSION_PATH env anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  MEDIA_STORAGE_PATH: z.string().default(".runtime/media"),
  MEDIA_MAX_BYTES: z.coerce
    .number()
    .int()
    .positive()
    .default(26_214_400),`
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Prisma
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

if (!schema.includes("enum MessageMediaStatus")) {
  const anchor = "enum MessageDirection {";

  if (!schema.includes(anchor)) {
    throw new Error(
      "Could not find MessageDirection enum anchor."
    );
  }

  schema = schema.replace(
    anchor,
    `enum MessageMediaStatus {
  NONE
  PENDING
  READY
  FAILED
}

${anchor}`
  );
}

const match = schema.match(
  /model Message \{[\s\S]*?\n\}/
);

if (!match) {
  throw new Error("Message model not found.");
}

let model = match[0];

if (!/^\s*mediaStatus\s+MessageMediaStatus/m.test(model)) {
  const anchor =
    /^(\s*mediaFileName\s+String\?\s+@db\.VarChar\(255\)\s*)$/m;

  if (!anchor.test(model)) {
    throw new Error(
      "Could not find Message.mediaFileName."
    );
  }

  model = model.replace(
    anchor,
    `$1
  mediaStatus           MessageMediaStatus @default(NONE)
  mediaStorageKey       String?            @db.VarChar(500)
  mediaSize             Int?
  mediaError            String?            @db.Text`
  );
}

if (!model.includes("@@index([companyId, mediaStatus])")) {
  const anchor =
    "  @@index([companyId, timestamp])";

  if (!model.includes(anchor)) {
    throw new Error(
      "Could not find Message company timestamp index."
    );
  }

  model = model.replace(
    anchor,
    `${anchor}
  @@index([companyId, mediaStatus])`
  );
}

schema = schema.replace(match[0], model);
fs.writeFileSync(path, schema);
NODE

# ---------------------------------------------------------------------------
# WhatsApp provider
# ---------------------------------------------------------------------------

cat > apps/api/src/integrations/whatsapp/provider.ts <<'EOF'
export interface CreateWhatsAppInstanceInput {
  instanceName: string;
  webhookUrl: string;
}

export interface WhatsAppQrResult {
  code?: string;
  base64?: string;
  pairingCode?: string;
  count?: number;
}

export interface WhatsAppConnectionState {
  state: string;
}

export interface SendTextInput {
  instanceName: string;
  number: string;
  text: string;
}

export interface DownloadMediaInput {
  instanceName: string;
  message: Record<string, unknown>;
  convertToMp4?: boolean;
}

export interface DownloadMediaResult {
  base64: string;
  mimetype?: string;
  fileName?: string;
  mediaType?: string;
}

export interface WhatsAppProviderClient {
  createInstance(
    input: CreateWhatsAppInstanceInput
  ): Promise<WhatsAppQrResult>;

  connect(
    instanceName: string
  ): Promise<WhatsAppQrResult>;

  connectionState(
    instanceName: string
  ): Promise<WhatsAppConnectionState>;

  sendText(
    input: SendTextInput
  ): Promise<unknown>;

  downloadMedia(
    input: DownloadMediaInput
  ): Promise<DownloadMediaResult>;
}
EOF

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/evolution.client.ts";

let content = fs.readFileSync(path, "utf8");

content = content.replace(
  `  CreateWhatsAppInstanceInput,
  SendTextInput,`,
  `  CreateWhatsAppInstanceInput,
  DownloadMediaInput,
  DownloadMediaResult,
  SendTextInput,`
);

if (!content.includes("async downloadMedia(")) {
  const anchor = `  async sendText(input: SendTextInput): Promise<unknown> {
    return this.request(
      \`/message/sendText/\${encodeURIComponent(input.instanceName)}\`,
      {
        method: "POST",
        body: JSON.stringify({
          number: input.number,
          text: input.text
        })
      }
    );
  }`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find Evolution sendText method."
    );
  }

  const replacement = `${anchor}

  async downloadMedia(
    input: DownloadMediaInput
  ): Promise<DownloadMediaResult> {
    const response = await this.request<{
      base64?: string;
      mimetype?: string;
      fileName?: string;
      mediaType?: string;
    }>(
      \`/chat/getBase64FromMediaMessage/\${encodeURIComponent(
        input.instanceName
      )}\`,
      {
        method: "POST",
        body: JSON.stringify({
          message: input.message,
          convertToMp4: input.convertToMp4 ?? false
        })
      }
    );

    if (!response.base64) {
      throw new AppError(
        "A Evolution não retornou o conteúdo da mídia.",
        502,
        "EVOLUTION_MEDIA_EMPTY"
      );
    }

    return {
      base64: response.base64,
      mimetype: response.mimetype,
      fileName: response.fileName,
      mediaType: response.mediaType
    };
  }`;

  content = content.replace(
    anchor,
    replacement
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Parser: stickers have media too
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/evolution-message.parser.ts";

let content = fs.readFileSync(path, "utf8");

const anchor = `    case "DOCUMENT":
      media = record(message.documentMessage);
      break;`;

if (
  content.includes(anchor) &&
  !content.includes(
    'case "STICKER":\n      media = record(message.stickerMessage);'
  )
) {
  content = content.replace(
    anchor,
    `${anchor}
    case "STICKER":
      media = record(message.stickerMessage);
      break;`
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Local media storage
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/media/media-storage.ts <<'EOF'
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

  return (
    (mimetype
      ? mimeExtensions[
          mimetype
            .split(";")[0]
            ?.trim()
            .toLowerCase()
        ]
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
EOF

# ---------------------------------------------------------------------------
# Media capture service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/media/media-capture.service.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# Media routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/media/media.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { requireAuth } from "../auth/auth.guard.js";
import { captureMessageMedia } from "./media-capture.service.js";
import { readMedia } from "./media-storage.js";

const messageIdSchema = z.object({
  id: z.string().uuid()
});

function safeFileName(
  value: string | null,
  messageId: string
) {
  return (
    value
      ?.replace(/[\r\n"]/g, "_")
      .slice(0, 180) ??
    `wapp-${messageId}`
  );
}

export async function mediaRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/messages/:id/media",
    async (request, reply) => {
      const auth = await requireAuth(request);
      const params = messageIdSchema.parse(
        request.params
      );

      const message =
        await prisma.message.findFirst({
          where: {
            id: params.id,
            companyId: auth.companyId
          },
          select: {
            id: true,
            mediaStatus: true,
            mediaStorageKey: true,
            mediaMimeType: true,
            mediaFileName: true
          }
        });

      if (!message) {
        throw new AppError(
          "Mensagem não encontrada.",
          404,
          "MESSAGE_NOT_FOUND"
        );
      }

      if (
        message.mediaStatus !== "READY" ||
        !message.mediaStorageKey
      ) {
        throw new AppError(
          "A mídia ainda não está disponível.",
          409,
          "MEDIA_NOT_READY"
        );
      }

      const media = await readMedia(
        message.mediaStorageKey
      );

      const fileName = safeFileName(
        message.mediaFileName,
        message.id
      );

      reply.header(
        "Content-Type",
        message.mediaMimeType ??
          "application/octet-stream"
      );

      reply.header(
        "Content-Length",
        String(media.size)
      );

      reply.header(
        "Content-Disposition",
        `inline; filename="${fileName}"; filename*=UTF-8''${encodeURIComponent(
          fileName
        )}`
      );

      return reply.send(media.buffer);
    }
  );

  app.post(
    "/api/v1/messages/:id/media/retry",
    async request => {
      const auth = await requireAuth(request);
      const params = messageIdSchema.parse(
        request.params
      );

      const message =
        await prisma.message.findFirst({
          where: {
            id: params.id,
            companyId: auth.companyId
          },
          select: {
            id: true
          }
        });

      if (!message) {
        throw new AppError(
          "Mensagem não encontrada.",
          404,
          "MESSAGE_NOT_FOUND"
        );
      }

      return {
        message:
          await captureMessageMedia(
            message.id
          )
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Ingestion schedules media capture
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/message-ingestion.service.ts";

let content = fs.readFileSync(path, "utf8");

const importLine =
  'import { scheduleMessageMediaCapture } from "../media/media-capture.service.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { publishRealtime } from "../realtime/realtime.bus.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find realtime import in ingestion."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (!content.includes("const hasMedia =")) {
  const anchor =
    "  const message = await prisma.message.create({";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find Message create block."
    );
  }

  content = content.replace(
    anchor,
    `  const hasMedia = [
    "IMAGE",
    "AUDIO",
    "VIDEO",
    "DOCUMENT",
    "STICKER"
  ].includes(parsed.type);

${anchor}`
  );
}

const typeAnchor =
  "      type: parsed.type,\n      body: parsed.body,";

if (
  content.includes(typeAnchor) &&
  !content.includes(
    "mediaStatus: hasMedia ?"
  )
) {
  content = content.replace(
    typeAnchor,
    `      type: parsed.type,
      body: parsed.body,
      mediaStatus: hasMedia
        ? "PENDING"
        : "NONE",`
  );
}

const publishBlock = `  publishRealtime(connection.companyId, {
    type: "message.created",
    ticketId: ticket.id,
    messageId: message.id
  });`;

if (
  content.includes(publishBlock) &&
  !content.includes(
    "scheduleMessageMediaCapture(message.id)"
  )
) {
  content = content.replace(
    publishBlock,
    `${publishBlock}

  if (hasMedia) {
    scheduleMessageMediaCapture(
      message.id
    );
  }`
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Realtime event
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

for (const path of [
  "apps/api/src/modules/realtime/realtime.bus.ts",
  "apps/web/lib/realtime-types.ts"
]) {
  let content = fs.readFileSync(path, "utf8");

  if (
    content.includes('| "message.created"') &&
    !content.includes('| "message.updated"')
  ) {
    content = content.replace(
      '| "message.created"',
      '| "message.created"\n  | "message.updated"'
    );
  }

  fs.writeFileSync(path, content);
}
NODE

# ---------------------------------------------------------------------------
# Register media routes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8");

const importLine =
  'import { mediaRoutes } from "./modules/media/media.routes.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { ticketRoutes } from "./modules/tickets/ticket.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticketRoutes import."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (!content.includes("await app.register(mediaRoutes);")) {
  const anchor =
    "  await app.register(ticketRoutes);";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticketRoutes registration."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  await app.register(mediaRoutes);`
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Auth provider exposes protected raw responses for blobs
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/components/auth-provider.tsx";

let content = fs.readFileSync(path, "utf8");

content = content.replace(
  `  ApiError,
  apiFetch,
  expectJson`,
  `  ApiError,
  apiFetch,
  expectJson,
  parseApiError`
);

if (!content.includes("requestRaw(")) {
  const interfaceAnchor =
    "  request<T>(path: string, init?: RequestInit): Promise<T>;";

  if (!content.includes(interfaceAnchor)) {
    throw new Error(
      "Could not find AuthContext request signature."
    );
  }

  content = content.replace(
    interfaceAnchor,
    `${interfaceAnchor}
  requestRaw(path: string, init?: RequestInit): Promise<Response>;`
  );
}

if (!content.includes("const requestRaw = useCallback(")) {
  const anchor = `  const request = useCallback(
    async <T,>(path: string, init: RequestInit = {}) => {
      const response = await authenticatedFetch(path, init);
      return expectJson<T>(response);
    },
    [authenticatedFetch]
  );`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find authenticated request hook."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

  const requestRaw = useCallback(
    async (path: string, init: RequestInit = {}) => {
      const response = await authenticatedFetch(
        path,
        init
      );

      if (!response.ok) {
        throw await parseApiError(response);
      }

      return response;
    },
    [authenticatedFetch]
  );`
  );
}

content = content.replace(
  `      request,
      subscribe`,
  `      request,
      requestRaw,
      subscribe`
);

content = content.replace(
  `[session, loading, login, logout, request, subscribe]`,
  `[session, loading, login, logout, request, requestRaw, subscribe]`
);

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Media renderer
# ---------------------------------------------------------------------------

cat > apps/web/components/messages/message-media.tsx <<'EOF'
"use client";

import {
  useEffect,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type MessageType =
  | "IMAGE"
  | "AUDIO"
  | "VIDEO"
  | "DOCUMENT"
  | "STICKER"
  | "TEXT"
  | "LOCATION"
  | "CONTACT"
  | "UNKNOWN";

type MediaStatus =
  | "NONE"
  | "PENDING"
  | "READY"
  | "FAILED";

export function MessageMedia({
  messageId,
  type,
  status,
  fileName,
  mimeType
}: {
  messageId: string;
  type: MessageType;
  status: MediaStatus;
  fileName: string | null;
  mimeType: string | null;
}) {
  const {
    request,
    requestRaw
  } = useAuth();

  const [objectUrl, setObjectUrl] =
    useState<string | null>(null);
  const [error, setError] =
    useState("");
  const [retrying, setRetrying] =
    useState(false);

  useEffect(() => {
    if (status !== "READY") {
      setObjectUrl(null);
      return;
    }

    let active = true;
    let currentUrl: string | null = null;

    void requestRaw(
      `/api/v1/messages/${messageId}/media`
    )
      .then(response => response.blob())
      .then(blob => {
        if (!active) {
          return;
        }

        currentUrl =
          URL.createObjectURL(blob);

        setObjectUrl(currentUrl);
        setError("");
      })
      .catch(() => {
        if (active) {
          setError(
            "Não foi possível abrir a mídia."
          );
        }
      });

    return () => {
      active = false;

      if (currentUrl) {
        URL.revokeObjectURL(currentUrl);
      }
    };
  }, [
    messageId,
    requestRaw,
    status
  ]);

  async function retry() {
    setRetrying(true);
    setError("");

    try {
      await request(
        `/api/v1/messages/${messageId}/media/retry`,
        {
          method: "POST"
        }
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Falha ao recuperar mídia."
      );
    } finally {
      setRetrying(false);
    }
  }

  if (
    ![
      "IMAGE",
      "AUDIO",
      "VIDEO",
      "DOCUMENT",
      "STICKER"
    ].includes(type)
  ) {
    return null;
  }

  if (status === "PENDING") {
    return (
      <div className="message-media-state">
        Processando mídia…
      </div>
    );
  }

  if (
    status === "FAILED" ||
    error
  ) {
    return (
      <div className="message-media-state message-media-state--error">
        <span>
          {error ||
            "Mídia indisponível."}
        </span>
        <button
          disabled={retrying}
          onClick={retry}
          type="button"
        >
          {retrying
            ? "Tentando…"
            : "Tentar novamente"}
        </button>
      </div>
    );
  }

  if (
    status !== "READY" ||
    !objectUrl
  ) {
    return null;
  }

  if (
    type === "IMAGE" ||
    type === "STICKER"
  ) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        alt={fileName ?? "Imagem recebida"}
        className={
          type === "STICKER"
            ? "message-media-image message-media-image--sticker"
            : "message-media-image"
        }
        src={objectUrl}
      />
    );
  }

  if (type === "AUDIO") {
    return (
      <audio
        className="message-media-audio"
        controls
        preload="metadata"
        src={objectUrl}
      />
    );
  }

  if (type === "VIDEO") {
    return (
      <video
        className="message-media-video"
        controls
        preload="metadata"
        src={objectUrl}
      />
    );
  }

  return (
    <a
      className="message-media-document"
      download={fileName ?? true}
      href={objectUrl}
    >
      <span>Documento</span>
      <strong>
        {fileName ??
          mimeType ??
          "Baixar arquivo"}
      </strong>
    </a>
  );
}
EOF

# ---------------------------------------------------------------------------
# Conversations uses media component
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

const importLine =
  'import { MessageMedia } from "@/components/messages/message-media";';

if (!content.includes(importLine)) {
  const anchor =
    'import { useAuth } from "@/components/auth-provider";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find auth-provider import in Conversations."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

const interfaceAnchor = `  mediaMimeType: string | null;
  mediaFileName: string | null;
  timestamp: string;`;

if (
  content.includes(interfaceAnchor) &&
  !content.includes(
    "mediaStatus: \"NONE\""
  )
) {
  content = content.replace(
    interfaceAnchor,
    `  mediaMimeType: string | null;
  mediaFileName: string | null;
  mediaStatus: "NONE" | "PENDING" | "READY" | "FAILED";
  mediaSize: number | null;
  timestamp: string;`
  );
}

if (
  !content.includes(
    "<MessageMedia"
  )
) {
  const paragraph = `                      <p>
                        {message.body ?? messageFallback(message.type)}
                      </p>`;

  if (!content.includes(paragraph)) {
    throw new Error(
      "Could not find message body render block in Conversations."
    );
  }

  content = content.replace(
    paragraph,
    `                      <MessageMedia
                        fileName={message.mediaFileName}
                        messageId={message.id}
                        mimeType={message.mediaMimeType}
                        status={message.mediaStatus}
                        type={message.type}
                      />

${paragraph}`
  );
}

content = content.replace(
  `        event.type === "message.created" ||`,
  `        event.type === "message.created" ||
        event.type === "message.updated" ||`
);

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Media UI
# ---------------------------------------------------------------------------

cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.2 / Media ------------------------------------------------- */

.message-media-image,
.message-media-video {
  display: block;
  width: min(440px, 100%);
  max-height: 420px;
  object-fit: contain;
  border-radius: 12px;
  background: #f0f2f0;
}

.message-media-image--sticker {
  width: min(180px, 55vw);
  max-height: 180px;
  background: transparent;
}

.message-media-video {
  background: #111;
}

.message-media-audio {
  display: block;
  width: min(360px, 72vw);
  margin: 2px 0;
}

.message-media-document {
  display: grid;
  gap: 4px;
  min-width: min(300px, 65vw);
  border: 1px solid var(--line);
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.72);
  color: inherit;
  padding: 12px;
  text-decoration: none;
}

.message-media-document span {
  color: var(--accent-dark);
  font-size: 8px;
  font-weight: 800;
  text-transform: uppercase;
}

.message-media-document strong {
  overflow: hidden;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.message-media-state {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  min-width: 210px;
  border-radius: 9px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 9px 10px;
  font-size: 9px;
}

.message-media-state--error {
  background: var(--danger-soft);
  color: var(--danger);
}

.message-media-state button {
  border: 0;
  background: transparent;
  color: inherit;
  font-size: 9px;
  font-weight: 800;
  text-decoration: underline;
}
EOF

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/MEDIA.md <<'EOF'
# Media pipeline

P1.2 adds binary media handling without storing files inside MySQL.

```text
Evolution MESSAGES_UPSERT
        |
        v
Message row
mediaStatus=PENDING
        |
        v
background capture
        |
        +--> Evolution getBase64FromMediaMessage
        |
        v
.runtime/media/<company>/<message>.<ext>
        |
        v
mediaStatus=READY
        |
        v
authenticated GET /api/v1/messages/:id/media
```

## Stored in MySQL

- mediaStatus
- mediaStorageKey
- mediaSize
- mediaMimeType
- mediaFileName
- mediaError

The binary is not stored in the database.

## Local storage

Development uses `.runtime/media`.

Production should replace the storage adapter with S3-compatible object
storage. The domain does not expose the local path to the browser.

## Security

Media delivery checks the authenticated user's company before reading the file.
The browser retrieves media through an authenticated fetch and creates a
temporary object URL.

## Retry

A failed media message can be retried with:

`POST /api/v1/messages/:id/media/retry`

Some Evolution/Baileys media edge cases can still fail upstream. A failure must
never prevent the text/message metadata from reaching the inbox.
EOF

echo "[P1.2] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.2] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.2] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.2] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.2] Media pipeline created."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name message_media"
echo "  pnpm dev"
echo
echo "Then send an image, audio and document to the connected WhatsApp."
