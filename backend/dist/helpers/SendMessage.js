"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SendMessage = void 0;
const GetWhatsappWbot_1 = __importDefault(require("./GetWhatsappWbot"));
const fs_1 = __importDefault(require("fs"));
const SendWhatsAppMedia_1 = require("../services/WbotServices/SendWhatsAppMedia");
const SendMessage = (whatsapp, messageData) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const wbot = yield (0, GetWhatsappWbot_1.default)(whatsapp);
        const chatId = `${messageData.number}@s.whatsapp.net`;
        let message;
        if (messageData.mediaPath) {
            const options = yield (0, SendWhatsAppMedia_1.getMessageOptions)(messageData.body, messageData.mediaPath);
            if (options) {
                const body = fs_1.default.readFileSync(messageData.mediaPath);
                message = yield wbot.sendMessage(chatId, Object.assign({}, options));
            }
        }
        else {
            const body = `\u200e${messageData.body}`;
            message = yield wbot.sendMessage(chatId, { text: body });
        }
        return message;
    }
    catch (err) {
        throw new Error(err);
    }
});
exports.SendMessage = SendMessage;
