export function isPhoneJid(
  value:
    | string
    | undefined
) {
  return Boolean(
    value?.endsWith(
      "@s.whatsapp.net"
    )
  );
}

export function isLidJid(
  value:
    | string
    | undefined
) {
  return Boolean(
    value?.endsWith(
      "@lid"
    )
  );
}

export function canonicalRemoteJid(input: {
  remoteJid: string;
  remoteJidAlt?: string;
}) {
  /*
   * Evolution/Baileys can deliver a user through a LID while also exposing
   * the traditional phone-number JID in remoteJidAlt.
   *
   * Keep group/newsletter/broadcast addresses untouched. For a direct LID
   * conversation, prefer the phone-number JID when Evolution gives it to us.
   */
  if (
    isLidJid(
      input.remoteJid
    ) &&
    isPhoneJid(
      input.remoteJidAlt
    )
  ) {
    return input.remoteJidAlt!;
  }

  return input.remoteJid;
}

export function canUsePushName(input: {
  fromMe: boolean;
  isGroup: boolean;
  pushName?: string;
}) {
  /*
   * For fromMe messages, pushName identifies the sender (our own WhatsApp
   * profile) in common Evolution/Baileys payloads. It must never rename the
   * recipient contact.
   */
  return Boolean(
    !input.fromMe &&
    !input.isGroup &&
    input.pushName
  );
}

export function contactCreationName(input: {
  fromMe: boolean;
  isGroup: boolean;
  pushName?: string;
  phoneNumber?: string;
  remoteJid: string;
}) {
  if (
    input.isGroup
  ) {
    return `Grupo ${
      input.remoteJid
        .split(
          "@"
        )[0]
    }`;
  }

  if (
    canUsePushName(
      input
    )
  ) {
    return input.pushName!;
  }

  return (
    input.phoneNumber ??
    input.remoteJid
      .split(
        "@"
      )[0] ??
    "Contato"
  );
}


function normalizedIdentity(
  value:
    | string
    | null
    | undefined
) {
  return value
    ?.trim()
    .toLocaleLowerCase(
      "pt-BR"
    ) ??
    "";
}

export function shouldPromoteWhatsappName(input: {
  currentName: string;
  currentWhatsappName?:
    | string
    | null;
  remoteJid: string;
  phoneNumber?:
    | string
    | null;
  incomingPushName: string;
}) {
  const currentName =
    normalizedIdentity(
      input.currentName
    );

  const incoming =
    normalizedIdentity(
      input.incomingPushName
    );

  if (
    !incoming ||
    !currentName ||
    currentName ===
      incoming
  ) {
    return false;
  }

  const remoteLocalPart =
    normalizedIdentity(
      input.remoteJid
        .split(
          "@"
        )[0]
    );

  const automaticNames =
    new Set(
      [
        normalizedIdentity(
          input.phoneNumber
        ),
        normalizedIdentity(
          input.remoteJid
        ),
        remoteLocalPart,
        normalizedIdentity(
          input.currentWhatsappName
        ),
        "contato"
      ].filter(
        Boolean
      )
    );

  /*
   * We only replace Contact.name when the current value is demonstrably an
   * automatic identity. A custom/manual Wapp display name is preserved.
   *
   * This fixes the common flow:
   *   outbound first -> Contact.name = phone number
   *   first inbound  -> pushName = real WhatsApp contact name
   */
  return automaticNames.has(
    currentName
  );
}
