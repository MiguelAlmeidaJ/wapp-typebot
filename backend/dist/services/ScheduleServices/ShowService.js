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
const Schedule_1 = __importDefault(require("../../models/Schedule"));
const AppError_1 = __importDefault(require("../../errors/AppError"));
const Contact_1 = __importDefault(require("../../models/Contact"));
const User_1 = __importDefault(require("../../models/User"));
const ScheduleService = (id, companyId) => __awaiter(void 0, void 0, void 0, function* () {
    const schedule = yield Schedule_1.default.findByPk(id, {
        include: [
            { model: Contact_1.default, as: "contact", attributes: ["id", "name"] },
            { model: User_1.default, as: "user", attributes: ["id", "name"] },
        ]
    });
    if ((schedule === null || schedule === void 0 ? void 0 : schedule.companyId) !== companyId) {
        throw new AppError_1.default("Não é possível excluir registro de outra empresa");
    }
    if (!schedule) {
        throw new AppError_1.default("ERR_NO_SCHEDULE_FOUND", 404);
    }
    return schedule;
});
exports.default = ScheduleService;
