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
exports.remove = exports.updateSchedules = exports.update = exports.list = exports.show = exports.store = exports.index = void 0;
const Yup = __importStar(require("yup"));
// import { getIO } from "../libs/socket";
const AppError_1 = __importDefault(require("../errors/AppError"));
const ListCompaniesService_1 = __importDefault(require("../services/CompanyService/ListCompaniesService"));
const CreateCompanyService_1 = __importDefault(require("../services/CompanyService/CreateCompanyService"));
const UpdateCompanyService_1 = __importDefault(require("../services/CompanyService/UpdateCompanyService"));
const ShowCompanyService_1 = __importDefault(require("../services/CompanyService/ShowCompanyService"));
const UpdateSchedulesService_1 = __importDefault(require("../services/CompanyService/UpdateSchedulesService"));
const DeleteCompanyService_1 = __importDefault(require("../services/CompanyService/DeleteCompanyService"));
const FindAllCompaniesService_1 = __importDefault(require("../services/CompanyService/FindAllCompaniesService"));
const index = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { searchParam, pageNumber } = req.query;
    const { companies, count, hasMore } = yield (0, ListCompaniesService_1.default)({
        searchParam,
        pageNumber
    });
    return res.json({ companies, count, hasMore });
});
exports.index = index;
const store = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const newCompany = req.body;
    const schema = Yup.object().shape({
        name: Yup.string().required()
    });
    try {
        yield schema.validate(newCompany);
    }
    catch (err) {
        throw new AppError_1.default(err.message);
    }
    const company = yield (0, CreateCompanyService_1.default)(newCompany);
    return res.status(200).json(company);
});
exports.store = store;
const show = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    const company = yield (0, ShowCompanyService_1.default)(id);
    return res.status(200).json(company);
});
exports.show = show;
const list = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const companies = yield (0, FindAllCompaniesService_1.default)();
    return res.status(200).json(companies);
});
exports.list = list;
const update = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const companyData = req.body;
    const schema = Yup.object().shape({
        name: Yup.string()
    });
    try {
        yield schema.validate(companyData);
    }
    catch (err) {
        throw new AppError_1.default(err.message);
    }
    const { id } = req.params;
    const company = yield (0, UpdateCompanyService_1.default)(Object.assign({ id }, companyData));
    return res.status(200).json(company);
});
exports.update = update;
const updateSchedules = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { schedules } = req.body;
    const { id } = req.params;
    const company = yield (0, UpdateSchedulesService_1.default)({
        id,
        schedules
    });
    return res.status(200).json(company);
});
exports.updateSchedules = updateSchedules;
const remove = (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { id } = req.params;
    const company = yield (0, DeleteCompanyService_1.default)(id);
    return res.status(200).json(company);
});
exports.remove = remove;
