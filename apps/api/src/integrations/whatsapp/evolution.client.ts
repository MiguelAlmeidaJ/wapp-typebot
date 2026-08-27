import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import type {
  CreateWhatsAppInstanceInput,
  DownloadMediaInput,
  DownloadMediaResult,
  SendMediaInput,
  SendTextInput,
  SendWhatsAppAudioInput,
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
    form.append(
      "mimetype",
      input.mimetype
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

    /*
     * Evolution 2.3.7 wires /message/sendMedia through
     * multer upload.single("file"). The binary multipart field
     * must therefore be named "file", not "media".
     */
    form.append(
      "file",
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

  async sendWhatsAppAudio(
    input: SendWhatsAppAudioInput
  ): Promise<unknown> {
    const form = new FormData();

    form.append(
      "number",
      input.number
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

    /*
     * Evolution 2.3.7 exposes a dedicated WhatsApp-audio route.
     * The router uses multer upload.single("file").
     */
    form.append(
      "file",
      blob,
      input.fileName
    );

    return this.request(
      `/message/sendWhatsAppAudio/${encodeURIComponent(
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
