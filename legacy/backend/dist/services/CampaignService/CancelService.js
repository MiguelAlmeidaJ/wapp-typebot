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
exports.CancelService = void 0;
const sequelize_1 = require("sequelize");
const Campaign_1 = __importDefault(require("../../models/Campaign"));
const CampaignShipping_1 = __importDefault(require("../../models/CampaignShipping"));
const queues_1 = require("../../queues");
function CancelService(id) {
    return __awaiter(this, void 0, void 0, function* () {
        const campaign = yield Campaign_1.default.findByPk(id);
        yield campaign.update({ status: "CANCELADA" });
        const recordsToCancel = yield CampaignShipping_1.default.findAll({
            where: {
                campaignId: campaign.id,
                jobId: { [sequelize_1.Op.not]: null },
                deliveredAt: null
            }
        });
        const promises = [];
        for (let record of recordsToCancel) {
            const job = yield queues_1.campaignQueue.getJob(+record.jobId);
            promises.push(job.remove());
        }
        yield Promise.all(promises);
    });
}
exports.CancelService = CancelService;
