"use strict";
/**
 * Monitor compatível com Baileys e com legado (whatsapp-web.js).
 * - Se for Baileys (sock.ev.on), não usa wbot.on (evita "wbot.on is not a function").
 * - Mantém compat com legado, caso ainda exista alguma sessão antiga.
 */
Object.defineProperty(exports, "__esModule", { value: true });
const logger_1 = require("../../utils/logger");

function wbotMonitor(wbot, whatsapp) {
  try {
    // ===== Caminho Baileys (WASocket) =====
    if (wbot && wbot.ev && typeof wbot.ev.on === "function") {
      // Já tratamos QR/status dentro do initWbot.
      // Aqui, opcionalmente, só logamos algumas mudanças.
      wbot.ev.on("connection.update", (update) => {
        try {
          const { connection } = update || {};
          if (connection) {
            logger_1.logger.info(`[monitor:${whatsapp?.id}] connection=${connection}`);
          }
        } catch (e) {
          logger_1.logger.error(e);
        }
      });

      // Também dá pra monitorar credenciais, só por log:
      // wbot.ev.on("creds.update", () => logger_1.logger.info(`[monitor:${whatsapp?.id}] creds.update`));

      return; // nada além disso é necessário para Baileys
    }

    // ===== Caminho legado (whatsapp-web.js) =====
    if (wbot && typeof wbot.on === "function") {
      try {
        wbot.on("qr", () => {
          logger_1.logger.info(`[monitor:${whatsapp?.id}] QR recebido (legacy)`);
        });
        wbot.on("ready", () => {
          logger_1.logger.info(`[monitor:${whatsapp?.id}] READY (legacy)`);
        });
        wbot.on("authenticated", () => {
          logger_1.logger.info(`[monitor:${whatsapp?.id}] AUTHENTICATED (legacy)`);
        });
        wbot.on("auth_failure", (m) => {
          logger_1.logger.info(`[monitor:${whatsapp?.id}] AUTH FAILURE (legacy): ${m || ""}`);
        });
        wbot.on("disconnected", (r) => {
          logger_1.logger.info(`[monitor:${whatsapp?.id}] DISCONNECTED (legacy): ${r || ""}`);
        });
      } catch (e) {
        logger_1.logger.error(e);
      }
      return;
    }

    // Se chegou aqui, não é nem Baileys (sem .ev.on) nem legado (.on)
    logger_1.logger.warn(`[monitor:${whatsapp?.id}] socket sem interface de eventos conhecida`);
  } catch (err) {
    logger_1.logger.error(err);
  }
}

exports.default = wbotMonitor;
