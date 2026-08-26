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

export interface WhatsAppProviderClient {
  createInstance(
    input: CreateWhatsAppInstanceInput
  ): Promise<WhatsAppQrResult>;

  connect(instanceName: string): Promise<WhatsAppQrResult>;

  connectionState(
    instanceName: string
  ): Promise<WhatsAppConnectionState>;

  sendText(input: SendTextInput): Promise<unknown>;
}
