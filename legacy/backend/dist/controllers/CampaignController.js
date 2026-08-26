"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
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
exports.deleteMedia = exports.mediaUpload = exports.findList = exports.remove = exports.restart = exports.cancel = exports.update = exports.show = exports.store = exports.index = void 0;
const Yup = __importStar(require("yup"));
const socket_1 = require("../libs/socket");
const lodash_1 = require("lodash");
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const ListService_1 = __importDefault(require("../services/CampaignService/ListService"));
const CreateService_1 = __importDefault(require("../services/CampaignService/CreateService"));
const ShowService_1 = __importDefault(require("../services/CampaignService/ShowService"));
const UpdateService_1 = __importDefault(require("../services/CampaignService/UpdateService"));
const DeleteService_1 = __importDefault(require("../services/CampaignService/DeleteService"));
const FindService_1 = __importDefault(require("../services/CampaignService/FindService"));
const Campaign_1 = __importDefault(require("../models/Campaign"));
const AppError_1 = __importDefault(require("../errors/AppError"));
const CancelService_1 = require("../services/CampaignService/CancelService");
const RestartService_1 = require("../services/CampaignService/RestartService");
const index = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { searchParam, pageNumber } = req.query;
    const { companyId } = req.user;
    const { records, count, hasMore } = yield (0, ListService_1.default)({
        searchParam,
        pageNumber,
        companyId
    });
    return res.json({ records, count, hasMore });
});
exports.index = index;
const store = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { companyId } = req.user;
    const data = req.body;
    const schema = Yup.object().shape({
        name: Yup.string().required()
    });
    try {
        yield schema.validate(data);
    }
    catch (err) {
        throw new AppError_1.default(err.message);
    }
    const record = yield (0, CreateService_1.default)(Object.assign(Object.assign({}, data), { companyId }));
    const io = (0, socket_1.getIO)();
    io.emit(`company-${companyId}-campaign`, {
        action: "create",
        record
    });
    return res.status(200).json(record);
});
exports.store = store;
const show = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    const record = yield (0, ShowService_1.default)(id);
    return res.status(200).json(record);
});
exports.show = show;
const update = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const data = req.body;
    const { companyId } = req.user;
    const schema = Yup.object().shape({
        name: Yup.string().required()
    });
    try {
        yield schema.validate(data);
    }
    catch (err) {
        throw new AppError_1.default(err.message);
    }
    const { id } = req.params;
    const record = yield (0, UpdateService_1.default)(Object.assign(Object.assign({}, data), { id }));
    const io = (0, socket_1.getIO)();
    io.emit(`company-${companyId}-campaign`, {
        action: "update",
        record
    });
    return res.status(200).json(record);
});
exports.update = update;
const cancel = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    yield (0, CancelService_1.CancelService)(+id);
    return res.status(204).json({ message: "Cancelamento realizado" });
});
exports.cancel = cancel;
const restart = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    yield (0, RestartService_1.RestartService)(+id);
    return res.status(204).json({ message: "Reinício dos disparos" });
});
exports.restart = restart;
const remove = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    const { companyId } = req.user;
    yield (0, DeleteService_1.default)(id);
    const io = (0, socket_1.getIO)();
    io.emit(`company-${companyId}-campaign`, {
        action: "delete",
        id
    });
    return res.status(200).json({ message: "Campaign deleted" });
});
exports.remove = remove;
const findList = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const params = req.query;
    const records = yield (0, FindService_1.default)(params);
    return res.status(200).json(records);
});
exports.findList = findList;
const mediaUpload = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    const files = req.files;
    const file = (0, lodash_1.head)(files);
    try {
        const campaign = yield Campaign_1.default.findByPk(id);
        campaign.mediaPath = file.filename;
        campaign.mediaName = file.originalname;
        yield campaign.save();
        return res.send({ mensagem: "Mensagem enviada" });
    }
    catch (err) {
        throw new AppError_1.default(err.message);
    }
});
exports.mediaUpload = mediaUpload;
const deleteMedia = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    try {
        const campaign = yield Campaign_1.default.findByPk(id);
        const filePath = path_1.default.resolve("public", campaign.mediaPath);
        const fileExists = fs_1.default.existsSync(filePath);
        if (fileExists) {
            fs_1.default.unlinkSync(filePath);
        }
        campaign.mediaPath = null;
        campaign.mediaName = null;
        yield campaign.save();
        return res.send({ mensagem: "Arquivo excluído" });
    }
    catch (err) {
        throw new AppError_1.default(err.message);
    }
});
exports.deleteMedia = deleteMedia;
