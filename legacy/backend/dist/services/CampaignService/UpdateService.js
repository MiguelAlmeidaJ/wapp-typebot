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
const AppError_1 = __importDefault(require("../../errors/AppError"));
const Campaign_1 = __importDefault(require("../../models/Campaign"));
const ContactList_1 = __importDefault(require("../../models/ContactList"));
const Whatsapp_1 = __importDefault(require("../../models/Whatsapp"));
const UpdateService = (data) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = data;
    const record = yield Campaign_1.default.findByPk(id);
    if (!record) {
        throw new AppError_1.default("ERR_NO_CAMPAIGN_FOUND", 404);
    }
    if (["INATIVA", "PROGRAMADA", "CANCELADA"].indexOf(data.status) === -1) {
        throw new AppError_1.default("Só é permitido alterar campanha Inativa e Programada", 400);
    }
    if (data.scheduledAt != null &&
        data.scheduledAt != "" &&
        data.status === "INATIVA") {
        data.status = "PROGRAMADA";
    }
    yield record.update(data);
    yield record.reload({
        include: [
            { model: ContactList_1.default },
            { model: Whatsapp_1.default, attributes: ["id", "name"] }
        ]
    });
    return record;
});
exports.default = UpdateService;
