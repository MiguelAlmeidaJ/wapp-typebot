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
exports.findList = exports.remove = exports.update = exports.show = exports.store = exports.index = void 0;
const Yup = __importStar(require("yup"));
const socket_1 = require("../libs/socket");
const ListService_1 = __importDefault(require("../services/ContactListItemService/ListService"));
const CreateService_1 = __importDefault(require("../services/ContactListItemService/CreateService"));
const ShowService_1 = __importDefault(require("../services/ContactListItemService/ShowService"));
const UpdateService_1 = __importDefault(require("../services/ContactListItemService/UpdateService"));
const DeleteService_1 = __importDefault(require("../services/ContactListItemService/DeleteService"));
const FindService_1 = __importDefault(require("../services/ContactListItemService/FindService"));
const AppError_1 = __importDefault(require("../errors/AppError"));
const index = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { searchParam, pageNumber, contactListId } = req.query;
    const { companyId } = req.user;
    const { contacts, count, hasMore } = yield (0, ListService_1.default)({
        searchParam,
        pageNumber,
        companyId,
        contactListId
    });
    return res.json({ contacts, count, hasMore });
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
    io.emit(`company-${companyId}-ContactListItem`, {
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
    io.emit(`company-${companyId}-ContactListItem`, {
        action: "update",
        record
    });
    return res.status(200).json(record);
});
exports.update = update;
const remove = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    const { companyId } = req.user;
    yield (0, DeleteService_1.default)(id);
    const io = (0, socket_1.getIO)();
    io.emit(`company-${companyId}-ContactListItem`, {
        action: "delete",
        id
    });
    return res.status(200).json({ message: "Contact deleted" });
});
exports.remove = remove;
const findList = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const params = req.query;
    const records = yield (0, FindService_1.default)(params);
    return res.status(200).json(records);
});
exports.findList = findList;
