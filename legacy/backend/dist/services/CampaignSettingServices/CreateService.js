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
const CampaignSetting_1 = __importDefault(require("../../models/CampaignSetting"));
const lodash_1 = require("lodash");
const CreateService = (data, companyId) => __awaiter(void 0, void 0, void 0, function* () {
    const settings = [];
    for (let settingKey of Object.keys(data.settings)) {
        const value = (0, lodash_1.isArray)(data.settings[settingKey]) || (0, lodash_1.isObject)(data.settings[settingKey])
            ? JSON.stringify(data.settings[settingKey])
            : data.settings[settingKey];
        const [record, created] = yield CampaignSetting_1.default.findOrCreate({
            where: {
                key: settingKey,
                companyId
            },
            defaults: { key: settingKey, value, companyId }
        });
        if (!created) {
            yield record.update({ value });
        }
        settings.push(record);
    }
    return settings;
});
exports.default = CreateService;
