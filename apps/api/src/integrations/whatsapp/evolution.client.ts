import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import type {
  CreateWhatsAppInstanceInput,
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

function evolutionMessage(body: EvolutionErrorBody | undefined) {
  const responseMessage = body?.response?.message;

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

export class EvolutionWhatsAppClient implements WhatsAppProviderClient {
  private async request<T>(
    path: string,
    init: RequestInit = {}
  ): Promise<T> {
    let response: Response;

    try {
      response = await fetch(`${env.EVOLUTION_BASE_URL}${path}`, {
        ...init,
        headers: {
          apikey: env.EVOLUTION_API_KEY,
          ...(init.body ? { "Content-Type": "application/json" } : {}),
          ...init.headers
        },
        signal: AbortSignal.timeout(15_000)
      });
    } catch (error) {
      throw new AppError(
        "Não foi possível acessar a Evolution API.",
        502,
        "EVOLUTION_UNAVAILABLE",
        error instanceof Error ? error.message : undefined
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
        evolutionMessage(body as EvolutionErrorBody | undefined),
        502,
        "EVOLUTION_ERROR",
        {
          upstreamStatus: response.status
        }
      );
    }

    return body as T;
  }

  async createInstance(
    input: CreateWhatsAppInstanceInput
  ): Promise<WhatsAppQrResult> {
    const response = await this.request<EvolutionCreateResponse>(
      "/instance/create",
      {
        method: "POST",
        body: JSON.stringify({
          instanceName: input.instanceName,
          qrcode: true,
          integration: "WHATSAPP-BAILEYS",
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
      pairingCode: response.qrcode?.pairingCode,
      count: response.qrcode?.count
    };
  }

  async connect(instanceName: string): Promise<WhatsAppQrResult> {
    const response = await this.request<EvolutionConnectResponse>(
      `/instance/connect/${encodeURIComponent(instanceName)}`
    );

    return {
      code: response.code,
      base64: response.base64,
      pairingCode: response.pairingCode,
      count: response.count
    };
  }

  async connectionState(
    instanceName: string
  ): Promise<WhatsAppConnectionState> {
    const response = await this.request<EvolutionStateResponse>(
      `/instance/connectionState/${encodeURIComponent(instanceName)}`
    );

    return {
      state: response.instance?.state ?? "unknown"
    };
  }

  async sendText(input: SendTextInput): Promise<unknown> {
    return this.request(
      `/message/sendText/${encodeURIComponent(input.instanceName)}`,
      {
        method: "POST",
        body: JSON.stringify({
          number: input.number,
          text: input.text
        })
      }
    );
  }
}

export const evolutionWhatsAppClient = new EvolutionWhatsAppClient();
