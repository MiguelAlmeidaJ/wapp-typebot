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
  quoted?: {
    externalId: string;
  };
}

export interface SendReactionInput {
  instanceName: string;
  key: {
    id: string;
    remoteJid: string;
    fromMe: boolean;
  };
  reaction: string;
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

export interface SendWhatsAppAudioInput {
  instanceName: string;
  number: string;
  mimetype: string;
  fileName: string;
  buffer: Buffer;
}

export interface ConfigureWebhookInput {
  instanceName: string;
  webhookUrl: string;
  events: string[];
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

  configureWebhook(
    input: ConfigureWebhookInput
  ): Promise<unknown>;

  sendText(
    input: SendTextInput
  ): Promise<unknown>;

  sendReaction(
    input: SendReactionInput
  ): Promise<unknown>;

  sendMedia(
    input: SendMediaInput
  ): Promise<unknown>;

  sendWhatsAppAudio(
    input: SendWhatsAppAudioInput
  ): Promise<unknown>;

  downloadMedia(
    input: DownloadMediaInput
  ): Promise<DownloadMediaResult>;
}
