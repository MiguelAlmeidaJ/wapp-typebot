import { canonicalRemoteJid } from "./contact-identity.js";

export interface ParsedEvolutionMessage {
  externalId: string;
  remoteJid: string;
  phoneNumber?: string;
  pushName?: string;
  fromMe: boolean;
  isGroup: boolean;
  type:
    | "TEXT"
    | "IMAGE"
    | "AUDIO"
    | "VIDEO"
    | "DOCUMENT"
    | "STICKER"
    | "LOCATION"
    | "CONTACT"
    | "UNKNOWN";
  body?: string;
  mediaMimeType?: string;
  mediaFileName?: string;
  quotedExternalId?: string;
  timestamp: Date;
  rawPayload: Record<string, unknown>;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : undefined;
}

function string(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0
    ? value
    : undefined;
}

function numberFromJid(jid: string | undefined) {
  if (!jid || !jid.includes("@s.whatsapp.net")) {
    return undefined;
  }

  const digits = jid.split("@")[0]?.replace(/\D/g, "");
  return digits || undefined;
}

function epochToDate(value: unknown) {
  const timestamp =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : NaN;

  if (!Number.isFinite(timestamp)) {
    return new Date();
  }

  return new Date(timestamp * 1000);
}

function textFromMessage(
  message: Record<string, unknown>,
  messageType: string | undefined
) {
  const conversation = string(message.conversation);

  if (conversation) {
    return conversation;
  }

  const extended = record(message.extendedTextMessage);
  const extendedText = string(extended?.text);

  if (extendedText) {
    return extendedText;
  }

  const image = record(message.imageMessage);
  const imageCaption = string(image?.caption);

  if (imageCaption) {
    return imageCaption;
  }

  const video = record(message.videoMessage);
  const videoCaption = string(video?.caption);

  if (videoCaption) {
    return videoCaption;
  }

  const document = record(message.documentMessage);
  const documentCaption = string(document?.caption);

  if (documentCaption) {
    return documentCaption;
  }

  const buttons = record(message.buttonsResponseMessage);
  const selectedButton = string(buttons?.selectedDisplayText);

  if (selectedButton) {
    return selectedButton;
  }

  const list = record(message.listResponseMessage);
  const title = string(list?.title);

  if (title) {
    return title;
  }

  switch (messageType) {
    case "imageMessage":
      return "[Imagem]";
    case "audioMessage":
      return "[Áudio]";
    case "videoMessage":
      return "[Vídeo]";
    case "documentMessage":
      return "[Documento]";
    case "stickerMessage":
      return "[Sticker]";
    case "locationMessage":
      return "[Localização]";
    case "contactMessage":
    case "contactsArrayMessage":
      return "[Contato]";
    default:
      return undefined;
  }
}

function mapType(
  message: Record<string, unknown>,
  messageType: string | undefined
): ParsedEvolutionMessage["type"] {
  if (
    messageType === "conversation" ||
    messageType === "extendedTextMessage" ||
    message.conversation ||
    message.extendedTextMessage
  ) {
    return "TEXT";
  }

  if (messageType === "imageMessage" || message.imageMessage) {
    return "IMAGE";
  }

  if (messageType === "audioMessage" || message.audioMessage) {
    return "AUDIO";
  }

  if (messageType === "videoMessage" || message.videoMessage) {
    return "VIDEO";
  }

  if (messageType === "documentMessage" || message.documentMessage) {
    return "DOCUMENT";
  }

  if (messageType === "stickerMessage" || message.stickerMessage) {
    return "STICKER";
  }

  if (messageType === "locationMessage" || message.locationMessage) {
    return "LOCATION";
  }

  if (
    messageType === "contactMessage" ||
    messageType === "contactsArrayMessage" ||
    message.contactMessage ||
    message.contactsArrayMessage
  ) {
    return "CONTACT";
  }

  return "UNKNOWN";
}

function mediaInfo(
  message: Record<string, unknown>,
  type: ParsedEvolutionMessage["type"]
) {
  let media: Record<string, unknown> | undefined;

  switch (type) {
    case "IMAGE":
      media = record(message.imageMessage);
      break;
    case "AUDIO":
      media = record(message.audioMessage);
      break;
    case "VIDEO":
      media = record(message.videoMessage);
      break;
    case "DOCUMENT":
      media = record(message.documentMessage);
      break;
    case "STICKER":
      media = record(message.stickerMessage);
      break;
  }

  return {
    mediaMimeType: string(media?.mimetype),
    mediaFileName: string(media?.fileName)
  };
}

function quotedId(
  message:
    Record<string, unknown>
) {
  const messageContainers = [
    message.extendedTextMessage,
    message.imageMessage,
    message.audioMessage,
    message.videoMessage,
    message.documentMessage,
    message.stickerMessage,
    message.locationMessage,
    message.contactMessage
  ];

  for (
    const container
    of messageContainers
  ) {
    const context =
      record(
        record(
          container
        )?.contextInfo
      );

    const stanzaId =
      string(
        context?.stanzaId
      );

    if (stanzaId) {
      return stanzaId;
    }
  }

  const directContext =
    record(
      message.contextInfo
    );

  return string(
    directContext?.stanzaId
  );
}

export function parseEvolutionMessage(
  payload: Record<string, unknown>
): ParsedEvolutionMessage | null {
  const data = record(payload.data);

  if (!data) {
    return null;
  }

  const key = record(data.key);
  const sourceRemoteJid =
    string(
      key?.remoteJid
    );
  const remoteJidAlt =
    string(
      key?.remoteJidAlt
    );
  const externalId =
    string(
      key?.id
    );

  if (
    !sourceRemoteJid ||
    !externalId
  ) {
    return null;
  }

  if (
    sourceRemoteJid ===
      "status@broadcast" ||
    sourceRemoteJid.endsWith(
      "@broadcast"
    )
  ) {
    return null;
  }

  const remoteJid =
    canonicalRemoteJid({
      remoteJid:
        sourceRemoteJid,
      remoteJidAlt
    });

  const message = record(data.message);

  if (!message) {
    return null;
  }

  const messageType = string(data.messageType);
  const type = mapType(message, messageType);
  const body = textFromMessage(message, messageType);

  // Ignore synchronization/protocol payloads that are not visible messages.
  if (type === "UNKNOWN" && !body) {
    return null;
  }

  const senderPn = string(key?.senderPn);
  const isGroup = remoteJid.endsWith("@g.us");
  const phoneNumber = isGroup
    ? undefined
    : numberFromJid(senderPn) ?? numberFromJid(remoteJid);

  const media = mediaInfo(message, type);

  return {
    externalId,
    remoteJid,
    phoneNumber,
    pushName: string(data.pushName),
    fromMe: key?.fromMe === true,
    isGroup,
    type,
    body,
    mediaMimeType: media.mediaMimeType,
    mediaFileName: media.mediaFileName,
    quotedExternalId: quotedId(message),
    timestamp: epochToDate(data.messageTimestamp),
    rawPayload: payload
  };
}
