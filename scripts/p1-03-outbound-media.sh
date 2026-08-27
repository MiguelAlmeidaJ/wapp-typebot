#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.3] Building outbound attachments..."

for required in \
  "apps/api/package.json" \
  "apps/api/src/app.ts" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/integrations/whatsapp/provider.ts" \
  "apps/api/src/integrations/whatsapp/evolution.client.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/media/media-storage.ts" \
  "apps/web/lib/api.ts" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -q 'mediaStatus' apps/api/prisma/schema.prisma; then
  echo "ERROR: P1.2 media schema is not present."
  exit 1
fi

if ! grep -q 'conversation-composer' apps/web/app/dashboard/conversations/page.tsx; then
  echo "ERROR: P1.2f canonical conversation layout is not present."
  exit 1
fi

echo "[P1.3] Installing multipart support..."
pnpm --filter @wapp/api add @fastify/multipart@^9.0.3

# ---------------------------------------------------------------------------
# WhatsApp provider contract
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

export type WhatsAppMediaType =
  | "image"
  | "video"
  | "audio"
  | "document";

export interface SendMediaInput {
  instanceName: string;
  number: string;
  mediaType: WhatsAppMediaType;
  mimetype: string;
  fileName: string;
  buffer: Buffer;
  caption?: string;
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

  sendMedia(
    input: SendMediaInput
  ): Promise<unknown>;

  downloadMedia(
    input: DownloadMediaInput
  ): Promise<DownloadMediaResult>;
}
EOF

# ---------------------------------------------------------------------------
# Evolution client
# ---------------------------------------------------------------------------

cat > apps/api/src/integrations/whatsapp/evolution.client.ts <<'EOF'
import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import type {
  CreateWhatsAppInstanceInput,
  DownloadMediaInput,
  DownloadMediaResult,
  SendMediaInput,
  SendTextInput,
  WhatsAppConnectionState,
  WhatsAppProviderClient,
  WhatsAppQrResult
} from "./provider.js";

interface EvolutionErrorBody {
  status?: number;
  error?: string;
  response?: {
    message?: string | string[];
  };
  message?: string;
}

interface EvolutionCreateResponse {
  qrcode?: {
    code?: string;
    base64?: string;
    pairingCode?: string;
    count?: number;
  };
  instance?: {
    instanceName?: string;
    instanceId?: string;
    status?: string;
  };
}

interface EvolutionConnectResponse {
  code?: string;
  base64?: string;
  pairingCode?: string;
  count?: number;
}

interface EvolutionStateResponse {
  instance?: {
    instanceName?: string;
    state?: string;
  };
}

function evolutionMessage(
  body: EvolutionErrorBody | undefined
) {
  const responseMessage =
    body?.response?.message;

  if (Array.isArray(responseMessage)) {
    return responseMessage.join(" ");
  }

  return (
    responseMessage ??
    body?.message ??
    body?.error ??
    "Evolution API request failed."
  );
}

export class EvolutionWhatsAppClient
  implements WhatsAppProviderClient
{
  private async request<T>(
    path: string,
    init: RequestInit = {},
    timeoutMs = 15_000
  ): Promise<T> {
    let response: Response;

    const isFormData =
      typeof FormData !== "undefined" &&
      init.body instanceof FormData;

    try {
      response = await fetch(
        `${env.EVOLUTION_BASE_URL}${path}`,
        {
          ...init,
          headers: {
            apikey: env.EVOLUTION_API_KEY,
            ...(init.body && !isFormData
              ? {
                  "Content-Type":
                    "application/json"
                }
              : {}),
            ...init.headers
          },
          signal:
            AbortSignal.timeout(timeoutMs)
        }
      );
    } catch (error) {
      throw new AppError(
        "Não foi possível acessar a Evolution API.",
        502,
        "EVOLUTION_UNAVAILABLE",
        error instanceof Error
          ? error.message
          : undefined
      );
    }

    let body: unknown;

    try {
      body = await response.json();
    } catch {
      body = undefined;
    }

    if (!response.ok) {
      throw new AppError(
        evolutionMessage(
          body as EvolutionErrorBody | undefined
        ),
        502,
        "EVOLUTION_ERROR",
        {
          upstreamStatus:
            response.status
        }
      );
    }

    return body as T;
  }

  async createInstance(
    input: CreateWhatsAppInstanceInput
  ): Promise<WhatsAppQrResult> {
    const response =
      await this.request<EvolutionCreateResponse>(
        "/instance/create",
        {
          method: "POST",
          body: JSON.stringify({
            instanceName: input.instanceName,
            qrcode: true,
            integration:
              "WHATSAPP-BAILEYS",
            groupsIgnore: false,
            alwaysOnline: false,
            readMessages: false,
            readStatus: false,
            syncFullHistory: false,
            webhook: {
              url: input.webhookUrl,
              byEvents: false,
              base64: false,
              events: [
                "QRCODE_UPDATED",
                "MESSAGES_UPSERT",
                "CONNECTION_UPDATE"
              ]
            }
          })
        }
      );

    return {
      code: response.qrcode?.code,
      base64: response.qrcode?.base64,
      pairingCode:
        response.qrcode?.pairingCode,
      count: response.qrcode?.count
    };
  }

  async connect(
    instanceName: string
  ): Promise<WhatsAppQrResult> {
    const response =
      await this.request<EvolutionConnectResponse>(
        `/instance/connect/${encodeURIComponent(
          instanceName
        )}`
      );

    return {
      code: response.code,
      base64: response.base64,
      pairingCode:
        response.pairingCode,
      count: response.count
    };
  }

  async connectionState(
    instanceName: string
  ): Promise<WhatsAppConnectionState> {
    const response =
      await this.request<EvolutionStateResponse>(
        `/instance/connectionState/${encodeURIComponent(
          instanceName
        )}`
      );

    return {
      state:
        response.instance?.state ??
        "unknown"
    };
  }

  async sendText(
    input: SendTextInput
  ): Promise<unknown> {
    return this.request(
      `/message/sendText/${encodeURIComponent(
        input.instanceName
      )}`,
      {
        method: "POST",
        body: JSON.stringify({
          number: input.number,
          text: input.text
        })
      }
    );
  }

  async sendMedia(
    input: SendMediaInput
  ): Promise<unknown> {
    const form = new FormData();

    form.append(
      "number",
      input.number
    );
    form.append(
      "mediatype",
      input.mediaType
    );
    form.append(
      "caption",
      input.caption ?? ""
    );
    form.append(
      "fileName",
      input.fileName
    );

    const blob = new Blob(
      [
        new Uint8Array(
          input.buffer
        )
      ],
      {
        type: input.mimetype
      }
    );

    form.append(
      "media",
      blob,
      input.fileName
    );

    return this.request(
      `/message/sendMedia/${encodeURIComponent(
        input.instanceName
      )}`,
      {
        method: "POST",
        body: form
      },
      60_000
    );
  }

  async downloadMedia(
    input: DownloadMediaInput
  ): Promise<DownloadMediaResult> {
    const response =
      await this.request<{
        base64?: string;
        mimetype?: string;
        fileName?: string;
        mediaType?: string;
      }>(
        `/chat/getBase64FromMediaMessage/${encodeURIComponent(
          input.instanceName
        )}`,
        {
          method: "POST",
          body: JSON.stringify({
            message: input.message,
            convertToMp4:
              input.convertToMp4 ??
              false
          })
        },
        30_000
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
      mimetype:
        response.mimetype,
      fileName:
        response.fileName,
      mediaType:
        response.mediaType
    };
  }
}

export const evolutionWhatsAppClient =
  new EvolutionWhatsAppClient();
EOF

# ---------------------------------------------------------------------------
# Ticket media service
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content = fs.readFileSync(path, "utf8");

const storageImport =
  'import { storeMedia } from "../media/media-storage.js";';

if (!content.includes(storageImport)) {
  const anchor =
    'import { publishRealtime } from "../realtime/realtime.bus.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find realtime import in ticket.service.ts."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}\n${storageImport}`
  );
}

if (!content.includes("export async function sendTicketMedia(")) {
  content += `

const documentMimeTypes = new Set([
  "application/pdf",
  "text/plain",
  "application/zip",
  "application/x-zip-compressed",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-powerpoint",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "application/octet-stream"
]);

const imageMimeTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif"
]);

const audioMimeTypes = new Set([
  "audio/ogg",
  "audio/mpeg",
  "audio/mp4",
  "audio/webm",
  "audio/wav",
  "audio/x-wav"
]);

const videoMimeTypes = new Set([
  "video/mp4",
  "video/webm"
]);

function outboundMediaDescriptor(
  mimetype: string
): {
  providerType:
    | "image"
    | "video"
    | "audio"
    | "document";
  messageType:
    | "IMAGE"
    | "VIDEO"
    | "AUDIO"
    | "DOCUMENT";
  preview: string;
} {
  const normalized = mimetype
    .split(";")[0]
    ?.trim()
    .toLowerCase();

  if (
    normalized &&
    imageMimeTypes.has(normalized)
  ) {
    return {
      providerType: "image",
      messageType: "IMAGE",
      preview: "[Imagem]"
    };
  }

  if (
    normalized &&
    audioMimeTypes.has(normalized)
  ) {
    return {
      providerType: "audio",
      messageType: "AUDIO",
      preview: "[Áudio]"
    };
  }

  if (
    normalized &&
    videoMimeTypes.has(normalized)
  ) {
    return {
      providerType: "video",
      messageType: "VIDEO",
      preview: "[Vídeo]"
    };
  }

  if (
    normalized &&
    documentMimeTypes.has(normalized)
  ) {
    return {
      providerType: "document",
      messageType: "DOCUMENT",
      preview: "[Documento]"
    };
  }

  throw new AppError(
    "Este tipo de arquivo não é suportado para envio.",
    422,
    "UNSUPPORTED_MEDIA_TYPE",
    {
      mimetype
    }
  );
}

function safeOutboundFileName(
  value: string
) {
  const sanitized = value
    .replace(/[\\\\/\\0\\r\\n]/g, "_")
    .trim()
    .slice(0, 180);

  return sanitized || "arquivo";
}

export async function sendTicketMedia(input: {
  companyId: string;
  ticketId: string;
  userId: string;
  membershipId: string;
  role: WappRole;
  buffer: Buffer;
  mimetype: string;
  fileName: string;
  caption?: string;
}) {
  let ticket = await getTicket(
    input.companyId,
    input.ticketId
  );

  if (ticket.status === "CLOSED") {
    throw new AppError(
      "Este atendimento já foi encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.membershipId,
    input.role
  );

  if (!ticket.assignedMembershipId) {
    await claimTicket({
      companyId: input.companyId,
      ticketId: ticket.id,
      membershipId: input.membershipId,
      role: input.role
    });

    ticket = await getTicket(
      input.companyId,
      input.ticketId
    );
  }

  if (
    ticket.whatsappConnection.status !==
    "CONNECTED"
  ) {
    throw new AppError(
      "A conexão WhatsApp deste atendimento está offline.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  const descriptor =
    outboundMediaDescriptor(
      input.mimetype
    );

  const fileName =
    safeOutboundFileName(
      input.fileName
    );

  const caption =
    input.caption?.trim() || null;

  const result =
    await evolutionWhatsAppClient.sendMedia({
      instanceName:
        ticket.whatsappConnection.instanceName,
      number:
        ticket.contact.remoteJid,
      mediaType:
        descriptor.providerType,
      mimetype:
        input.mimetype,
      fileName,
      buffer:
        input.buffer,
      caption:
        caption ?? ""
    });

  const timestamp =
    sentTimestamp(result);

  const externalId =
    sentExternalId(result);

  const message =
    await prisma.message.upsert({
      where: {
        whatsappConnectionId_externalId: {
          whatsappConnectionId:
            ticket.whatsappConnectionId,
          externalId
        }
      },
      update: {
        sentByUserId:
          input.userId,
        direction: "OUTBOUND",
        type:
          descriptor.messageType,
        body: caption,
        mediaMimeType:
          input.mimetype,
        mediaFileName:
          fileName,
        mediaStatus: "PENDING",
        mediaError: null
      },
      create: {
        companyId:
          input.companyId,
        ticketId:
          ticket.id,
        whatsappConnectionId:
          ticket.whatsappConnectionId,
        sentByUserId:
          input.userId,
        externalId,
        direction: "OUTBOUND",
        type:
          descriptor.messageType,
        body: caption,
        mediaMimeType:
          input.mimetype,
        mediaFileName:
          fileName,
        mediaStatus: "PENDING",
        timestamp,
        rawPayload:
          toPrismaJson(result)
      }
    });

  let readyMessage = message;

  try {
    const stored = await storeMedia({
      companyId:
        input.companyId,
      messageId:
        message.id,
      buffer:
        input.buffer,
      mimetype:
        input.mimetype,
      fileName
    });

    readyMessage =
      await prisma.message.update({
        where: {
          id: message.id
        },
        data: {
          mediaStatus: "READY",
          mediaStorageKey:
            stored.storageKey,
          mediaSize:
            stored.size,
          mediaError: null
        }
      });
  } catch (error) {
    readyMessage =
      await prisma.message.update({
        where: {
          id: message.id
        },
        data: {
          mediaStatus: "FAILED",
          mediaError:
            (
              error instanceof Error
                ? error.message
                : "Falha ao armazenar a cópia local da mídia."
            ).slice(0, 2_000)
        }
      });
  }

  await prisma.ticket.update({
    where: {
      id: ticket.id
    },
    data: {
      lastMessage:
        caption ??
        descriptor.preview,
      lastMessageAt:
        timestamp
    }
  });

  publishRealtime(
    input.companyId,
    {
      type: "message.created",
      ticketId:
        ticket.id,
      messageId:
        readyMessage.id
    }
  );

  return readyMessage;
}
`;
}

fs.writeFileSync(path, content);
console.log("sendTicketMedia service installed.");
NODE

# ---------------------------------------------------------------------------
# Multipart ticket route
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tickets/ticket-media.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { requireAuth } from "../auth/auth.guard.js";
import { sendTicketMedia } from "./ticket.service.js";

const paramsSchema = z.object({
  id: z.string().uuid()
});

const captionSchema = z
  .string()
  .trim()
  .max(4096);

function record(
  value: unknown
): Record<string, unknown> | undefined {
  return value &&
    typeof value === "object" &&
    !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function multipartField(
  fields: unknown,
  key: string
) {
  const collection = record(fields);
  const field = record(
    collection?.[key]
  );
  const value = field?.value;

  return typeof value === "string"
    ? value
    : "";
}

export async function ticketMediaRoutes(
  app: FastifyInstance
) {
  app.post(
    "/api/v1/tickets/:id/media",
    async request => {
      const auth =
        await requireAuth(request);

      const params =
        paramsSchema.parse(
          request.params
        );

      let upload;

      try {
        upload =
          await request.file({
            limits: {
              fileSize:
                env.MEDIA_MAX_BYTES,
              files: 1,
              fields: 4,
              parts: 5
            }
          });
      } catch (error) {
        if (
          error instanceof
          app.multipartErrors
            .RequestFileTooLargeError
        ) {
          throw new AppError(
            `O arquivo excede o limite de ${Math.floor(
              env.MEDIA_MAX_BYTES /
                1024 /
                1024
            )} MB.`,
            413,
            "MEDIA_TOO_LARGE"
          );
        }

        throw error;
      }

      if (
        !upload ||
        upload.fieldname !== "file"
      ) {
        throw new AppError(
          "Arquivo não informado.",
          422,
          "MEDIA_FILE_REQUIRED"
        );
      }

      let buffer: Buffer;

      try {
        buffer =
          await upload.toBuffer();
      } catch (error) {
        if (
          error instanceof
          app.multipartErrors
            .RequestFileTooLargeError
        ) {
          throw new AppError(
            `O arquivo excede o limite de ${Math.floor(
              env.MEDIA_MAX_BYTES /
                1024 /
                1024
            )} MB.`,
            413,
            "MEDIA_TOO_LARGE"
          );
        }

        throw error;
      }

      if (buffer.byteLength === 0) {
        throw new AppError(
          "O arquivo está vazio.",
          422,
          "MEDIA_FILE_EMPTY"
        );
      }

      const caption =
        captionSchema.parse(
          multipartField(
            upload.fields,
            "caption"
          )
        );

      return {
        message:
          await sendTicketMedia({
            companyId:
              auth.companyId,
            ticketId:
              params.id,
            userId:
              auth.userId,
            membershipId:
              auth.membershipId,
            role:
              auth.role,
            buffer,
            mimetype:
              upload.mimetype ||
              "application/octet-stream",
            fileName:
              upload.filename ||
              "arquivo",
            caption:
              caption || undefined
          })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Fastify multipart + route registration
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8");

if (
  !content.includes(
    'import multipart from "@fastify/multipart";'
  )
) {
  const anchor =
    'import cors from "@fastify/cors";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find @fastify/cors import."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}\nimport multipart from "@fastify/multipart";`
  );
}

const routeImport =
  'import { ticketMediaRoutes } from "./modules/tickets/ticket-media.routes.js";';

if (!content.includes(routeImport)) {
  const anchor =
    'import { ticketRoutes } from "./modules/tickets/ticket.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticketRoutes import."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}\n${routeImport}`
  );
}

if (
  !content.includes(
    "await app.register(multipart"
  )
) {
  const anchor =
    "  await app.register(cookie);";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find cookie registration."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

  await app.register(multipart, {
    limits: {
      fileSize: env.MEDIA_MAX_BYTES,
      files: 1,
      fields: 4,
      parts: 5
    }
  });`
  );
}

if (
  !content.includes(
    "await app.register(ticketMediaRoutes);"
  )
) {
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
  await app.register(ticketMediaRoutes);`
  );
}

fs.writeFileSync(path, content);
console.log("Multipart plugin and route registered.");
NODE

# ---------------------------------------------------------------------------
# Browser API: do not force application/json on FormData
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/web/lib/api.ts";
let content = fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "const isFormData ="
  )
) {
  const oldBlock = `export async function apiFetch(
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  return fetch(\`\${API_URL}\${path}\`, {
    ...init,
    credentials: "include",
    headers: {
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers
    }
  });
}`;

  const newBlock = `export async function apiFetch(
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  const isFormData =
    typeof FormData !== "undefined" &&
    init.body instanceof FormData;

  return fetch(\`\${API_URL}\${path}\`, {
    ...init,
    credentials: "include",
    headers: {
      ...(init.body && !isFormData
        ? {
            "Content-Type":
              "application/json"
          }
        : {}),
      ...init.headers
    }
  });
}`;

  if (!content.includes(oldBlock)) {
    throw new Error(
      "Could not find apiFetch implementation."
    );
  }

  content = content.replace(
    oldBlock,
    newBlock
  );
}

fs.writeFileSync(path, content);
console.log("apiFetch now supports browser FormData.");
NODE

# ---------------------------------------------------------------------------
# Conversations: attachment state, preview and submit
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "const [attachment, setAttachment]"
  )
) {
  const anchor =
    '  const [text, setText] = useState("");';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find composer text state."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [attachment, setAttachment] =
    useState<File | null>(null);
  const [attachmentPreviewUrl, setAttachmentPreviewUrl] =
    useState<string | null>(null);`
  );
}

if (
  !content.includes(
    "const attachmentInputRef ="
  )
) {
  const anchor =
    "  const bottomRef = useRef<HTMLDivElement | null>(null);";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find bottomRef."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const attachmentInputRef =
    useRef<HTMLInputElement | null>(null);`
  );
}

if (
  !content.includes(
    "[P1.3 attachment preview]"
  )
) {
  const anchor =
    /  useEffect\(\(\) => \{\s*bottomRef\.current\?\.scrollIntoView\(\{[\s\S]*?\}\);\s*\}, \[messages\]\);/;

  const match =
    content.match(anchor);

  if (!match) {
    throw new Error(
      "Could not find message scroll effect."
    );
  }

  const effect = `${match[0]}

  // [P1.3 attachment preview]
  useEffect(() => {
    if (!attachment) {
      setAttachmentPreviewUrl(null);
      return;
    }

    if (
      !attachment.type.startsWith("image/")
    ) {
      setAttachmentPreviewUrl(null);
      return;
    }

    const url =
      URL.createObjectURL(attachment);

    setAttachmentPreviewUrl(url);

    return () => {
      URL.revokeObjectURL(url);
    };
  }, [attachment]);`;

  content = content.replace(
    anchor,
    effect
  );
}

if (
  !content.includes(
    "function chooseAttachment("
  )
) {
  const anchor =
    "  async function handleSend(event: FormEvent<HTMLFormElement>)";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find handleSend."
    );
  }

  const helper = `  function chooseAttachment(
    file: File | undefined
  ) {
    if (!file) {
      return;
    }

    const maxBytes =
      25 * 1024 * 1024;

    if (file.size > maxBytes) {
      setError(
        "O arquivo excede o limite de 25 MB."
      );
      return;
    }

    setError("");
    setAttachment(file);
  }

`;

  content = content.replace(
    anchor,
    `${helper}${anchor}`
  );
}

const sendRegex =
  /  async function handleSend\(event: FormEvent<HTMLFormElement>\) \{[\s\S]*?\n  \}\n\n  async function handleClose/;

const sendMatch =
  content.match(sendRegex);

if (!sendMatch) {
  throw new Error(
    "Could not isolate handleSend."
  );
}

const newSend = `  async function handleSend(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !selectedId ||
      (!text.trim() && !attachment)
    ) {
      return;
    }

    setSending(true);
    setError("");

    try {
      if (attachment) {
        const form = new FormData();

        // Put value fields before the file so Fastify multipart
        // has them available while consuming the upload.
        form.append(
          "caption",
          text.trim()
        );
        form.append(
          "file",
          attachment,
          attachment.name
        );

        await request(
          \`/api/v1/tickets/\${selectedId}/media\`,
          {
            method: "POST",
            body: form
          }
        );

        setAttachment(null);

        if (
          attachmentInputRef.current
        ) {
          attachmentInputRef.current.value =
            "";
        }
      } else {
        await request(
          \`/api/v1/tickets/\${selectedId}/messages\`,
          {
            method: "POST",
            body: JSON.stringify({
              text: text.trim()
            })
          }
        );
      }

      setText("");

      await Promise.all([
        loadMessages(selectedId),
        loadTickets()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : attachment
            ? "Não foi possível enviar o anexo."
            : "Não foi possível enviar a mensagem."
      );
    } finally {
      setSending(false);
    }
  }

  async function handleClose`;

content = content.replace(
  sendRegex,
  newSend
);

if (
  !content.includes(
    'className="composer__attach"'
  )
) {
  const formRegex =
    /<form className="conversation-composer" onSubmit=\{handleSend\}>\s*<textarea/;

  if (!formRegex.test(content)) {
    throw new Error(
      "Could not find canonical conversation composer."
    );
  }

  const formStart = `<form
                  className="conversation-composer conversation-composer--attachments"
                  onSubmit={handleSend}
                >
                  <input
                    accept="image/jpeg,image/png,image/webp,image/gif,audio/ogg,audio/mpeg,audio/mp4,audio/webm,audio/wav,video/mp4,video/webm,application/pdf,text/plain,application/zip,.doc,.docx,.xls,.xlsx,.ppt,.pptx"
                    className="composer-file-input"
                    onChange={event =>
                      chooseAttachment(
                        event.target.files?.[0]
                      )
                    }
                    ref={attachmentInputRef}
                    type="file"
                  />

                  {attachment && (
                    <div className="composer-attachment-preview">
                      {attachmentPreviewUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          alt="Prévia do anexo"
                          src={attachmentPreviewUrl}
                        />
                      ) : (
                        <div className="composer-attachment-preview__icon">
                          ARQ
                        </div>
                      )}

                      <div className="composer-attachment-preview__copy">
                        <strong>
                          {attachment.name}
                        </strong>
                        <span>
                          {(attachment.size / 1024 / 1024).toFixed(2)} MB
                          {" · "}
                          {attachment.type || "arquivo"}
                        </span>
                      </div>

                      <button
                        aria-label="Remover anexo"
                        className="composer-attachment-preview__remove"
                        disabled={sending}
                        onClick={() => {
                          setAttachment(null);

                          if (
                            attachmentInputRef.current
                          ) {
                            attachmentInputRef.current.value =
                              "";
                          }
                        }}
                        type="button"
                      >
                        ×
                      </button>
                    </div>
                  )}

                  <button
                    aria-label="Anexar arquivo"
                    className="composer__attach"
                    disabled={sending}
                    onClick={() =>
                      attachmentInputRef.current?.click()
                    }
                    type="button"
                  >
                    +
                  </button>

                  <textarea`;

  content = content.replace(
    formRegex,
    formStart
  );
}

content = content.replace(
  /disabled=\{sending \|\| !text\.trim\(\)\}/,
  "disabled={sending || (!text.trim() && !attachment)}"
);

fs.writeFileSync(path, content);
console.log("Conversation attachment composer installed.");
NODE

# ---------------------------------------------------------------------------
# Composer attachment styles
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.3 / Outbound attachments" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.3 / Outbound attachments --------------------------------- */

.conversation-composer--attachments {
  grid-template-columns:
    42px
    minmax(0, 1fr)
    46px !important;
}

.composer-file-input {
  position: fixed;
  width: 1px;
  height: 1px;
  overflow: hidden;
  opacity: 0;
  pointer-events: none;
}

.composer__attach {
  display: grid;
  width: 42px;
  height: 46px;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: var(--surface-subtle);
  color: var(--ink);
  font-size: 24px;
  font-weight: 350;
}

.composer__attach:hover:not(:disabled) {
  border-color: var(--line-strong);
  background: #fff;
}

.composer__attach:disabled {
  opacity: 0.4;
}

.composer-attachment-preview {
  display: grid;
  grid-column: 1 / -1;
  grid-template-columns:
    52px
    minmax(0, 1fr)
    32px;
  align-items: center;
  gap: 10px;
  min-width: 0;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: var(--surface-subtle);
  padding: 8px;
}

.composer-attachment-preview > img,
.composer-attachment-preview__icon {
  width: 52px;
  height: 52px;
  border-radius: 9px;
}

.composer-attachment-preview > img {
  display: block;
  object-fit: cover;
}

.composer-attachment-preview__icon {
  display: grid;
  place-items: center;
  background: #e7ece8;
  color: var(--muted);
  font-size: 8px;
  font-weight: 800;
  letter-spacing: 0.08em;
}

.composer-attachment-preview__copy {
  display: grid;
  min-width: 0;
  gap: 4px;
}

.composer-attachment-preview__copy strong,
.composer-attachment-preview__copy span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.composer-attachment-preview__copy strong {
  font-size: 10px;
}

.composer-attachment-preview__copy span {
  color: var(--muted);
  font-size: 8px;
}

.composer-attachment-preview__remove {
  display: grid;
  width: 30px;
  height: 30px;
  place-items: center;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--muted);
  font-size: 20px;
}

.composer-attachment-preview__remove:hover:not(:disabled) {
  background: #e3e7e4;
  color: var(--ink);
}

@media (max-width: 620px) {
  .conversation-composer--attachments {
    grid-template-columns:
      38px
      minmax(0, 1fr)
      44px !important;
  }

  .composer__attach {
    width: 38px;
    height: 44px;
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/OUTBOUND_MEDIA.md <<'EOF'
# Outbound media

P1.3 adds attachment sending from the Wapp operator composer.

Supported initial categories:

- image
- audio file
- video
- document

Browser audio recording is intentionally not part of P1.3.

## Flow

```text
operator selects file
        |
        v
browser preview
        |
        v
multipart/form-data
POST /api/v1/tickets/:id/media
        |
        v
ticket assignment + connection validation
        |
        v
Evolution /message/sendMedia/:instance
        |
        v
WhatsApp
        |
        v
Message OUTBOUND
mediaStatus=READY
        |
        v
local media storage + realtime
```

## Security and limits

The route reuses the authenticated ticket context and ticket assignment rules.

The default maximum upload size is `MEDIA_MAX_BYTES` (25 MiB in the current
development configuration).

The API accepts a conservative list of image, audio, video and document MIME
types. HTML and SVG are intentionally not accepted as uploadable documents.

## Failure semantics

The selected browser file is only cleared after the API succeeds.

If Evolution rejects the send, the operator keeps the selected attachment and
can try again.

If WhatsApp accepted the media but local storage fails afterward, the message
is persisted with `mediaStatus=FAILED`. The incoming media recovery path from
P1.2 can still be used as a fallback.
EOF

echo "[P1.3] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.3] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.3] Outbound attachment sending installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Test in this order:"
echo "  1. JPEG/PNG"
echo "  2. PDF"
echo "  3. audio file"
echo "  4. MP4"
