import assert from "node:assert/strict";
import { test } from "node:test";

import {
  canUsePushName,
  canonicalRemoteJid,
  contactCreationName
} from "./contact-identity.js";

test(
  "direct LID prefers Evolution phone-number alternate JID",
  () => {
    assert.equal(
      canonicalRemoteJid({
        remoteJid:
          "123456789012345@lid",
        remoteJidAlt:
          "5511999999999@s.whatsapp.net"
      }),
      "5511999999999@s.whatsapp.net"
    );
  }
);

test(
  "group JID is never replaced by participant/alternate identity",
  () => {
    assert.equal(
      canonicalRemoteJid({
        remoteJid:
          "120363000000000000@g.us",
        remoteJidAlt:
          "5511999999999@s.whatsapp.net"
      }),
      "120363000000000000@g.us"
    );
  }
);

test(
  "fromMe pushName must not identify the recipient",
  () => {
    assert.equal(
      canUsePushName({
        fromMe:
          true,
        isGroup:
          false,
        pushName:
          "Miguel Almeida"
      }),
      false
    );

    assert.equal(
      contactCreationName({
        fromMe:
          true,
        isGroup:
          false,
        pushName:
          "Miguel Almeida",
        phoneNumber:
          "5511888888888",
        remoteJid:
          "5511888888888@s.whatsapp.net"
      }),
      "5511888888888"
    );
  }
);

test(
  "inbound pushName remains valid WhatsApp identity",
  () => {
    assert.equal(
      contactCreationName({
        fromMe:
          false,
        isGroup:
          false,
        pushName:
          "Cliente correto",
        phoneNumber:
          "5511888888888",
        remoteJid:
          "5511888888888@s.whatsapp.net"
      }),
      "Cliente correto"
    );
  }
);

test(
  "incoming WhatsApp name promotes an automatic phone-number display name",
  async () => {
    const {
      shouldPromoteWhatsappName
    } =
      await import(
        "./contact-identity.js"
      );

    assert.equal(
      shouldPromoteWhatsappName({
        currentName:
          "553299254233",
        currentWhatsappName:
          null,
        remoteJid:
          "553299254233@s.whatsapp.net",
        phoneNumber:
          "553299254233",
        incomingPushName:
          "Jozias Souza"
      }),
      true
    );
  }
);

test(
  "incoming WhatsApp name can replace the previous automatic WhatsApp name",
  async () => {
    const {
      shouldPromoteWhatsappName
    } =
      await import(
        "./contact-identity.js"
      );

    assert.equal(
      shouldPromoteWhatsappName({
        currentName:
          "Jozias",
        currentWhatsappName:
          "Jozias",
        remoteJid:
          "553299254233@s.whatsapp.net",
        phoneNumber:
          "553299254233",
        incomingPushName:
          "Jozias Souza"
      }),
      true
    );
  }
);

test(
  "manual Wapp display name is never overwritten by incoming pushName",
  async () => {
    const {
      shouldPromoteWhatsappName
    } =
      await import(
        "./contact-identity.js"
      );

    assert.equal(
      shouldPromoteWhatsappName({
        currentName:
          "Cliente VIP - Jozias",
        currentWhatsappName:
          "Jozias Souza",
        remoteJid:
          "553299254233@s.whatsapp.net",
        phoneNumber:
          "553299254233",
        incomingPushName:
          "Jozias S."
      }),
      false
    );
  }
);
