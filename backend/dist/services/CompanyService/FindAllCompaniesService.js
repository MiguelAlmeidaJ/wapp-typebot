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
const Company_1 = __importDefault(require("../../models/Company"));
const Plan_1 = __importDefault(require("../../models/Plan"));
const Setting_1 = __importDefault(require("../../models/Setting"));
const FindAllCompanyService = () => __awaiter(void 0, void 0, void 0, function* () {
    const companies = yield Company_1.default.findAll({
        order: [["name", "ASC"]],
        include: [
            { model: Plan_1.default, as: "plan", attributes: ["id", "name", "value"] },
            { model: Setting_1.default, as: "settings" }
        ]
    });
    return companies;
});
exports.default = FindAllCompanyService;
