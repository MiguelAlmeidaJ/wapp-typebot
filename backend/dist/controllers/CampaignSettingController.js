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
exports.store = exports.index = void 0;
const socket_1 = require("../libs/socket");
const ListService_1 = __importDefault(require("../services/CampaignSettingServices/ListService"));
const CreateService_1 = __importDefault(require("../services/CampaignSettingServices/CreateService"));
const index = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { companyId } = req.user;
    const records = yield (0, ListService_1.default)({
        companyId
    });
    return res.json(records);
});
exports.index = index;
const store = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { companyId } = req.user;
    const data = req.body;
    const record = yield (0, CreateService_1.default)(data, companyId);
    const io = (0, socket_1.getIO)();
    io.emit(`company-${companyId}-campaignSettings`, {
        action: "create",
        record
    });
    return res.status(200).json(record);
});
exports.store = store;
