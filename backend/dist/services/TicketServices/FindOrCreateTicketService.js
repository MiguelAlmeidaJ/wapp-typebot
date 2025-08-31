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
// import { subHours } from "date-fns";
const add = require('date-fns/add');
const sequelize_1 = require("sequelize");
const Ticket_1 = __importDefault(require("../../models/Ticket"));
const ShowTicketService_1 = __importDefault(require("./ShowTicketService"));
const ListSettingsServiceOne_1 = __importDefault(require("../SettingServices/ListSettingsServiceOne"));
const UpdateTicketService_1 = __importDefault(require("../TicketServices/UpdateTicketService"));

const FindOrCreateTicketService = (contact, whatsappId, unreadMessages, groupContact) => __awaiter(void 0, void 0, void 0, function* () {
    let ticket = yield Ticket_1.default.findOne({
        where: {
            status: {
                [sequelize_1.Op.or]: ["open", "pending"]
            },
            contactId: groupContact ? groupContact.id : contact.id
        }
    });
    if (ticket) {
        yield ticket.update({ unreadMessages });


    }
    if (!ticket && groupContact) {
        ticket = yield Ticket_1.default.findOne({
            where: {
                contactId: groupContact.id
            },
            order: [["updatedAt", "DESC"]]
        });
        if (ticket) {
            yield ticket.update({
                status: "pending",
                userId: null,
                unreadMessages
            });
        }
    }
    if (!ticket && !groupContact) {
        const listSettingsService = yield ListSettingsServiceOne_1.default({ key: "timeCreateNewTicket" });
        var timeCreateNewTicket = listSettingsService === null || listSettingsService === void 0 ? void 0 : listSettingsService.value;
        ticket = yield Ticket_1.default.findOne({
            where: {
                updatedAt: {
                    [sequelize_1.Op.between]: [+add(new Date(), { seconds: timeCreateNewTicket }), +new Date()]
                },
                contactId: contact.id
            },
            order: [["updatedAt", "DESC"]]
        });
        if (ticket) {
            yield ticket.update({
                status: "pending",
                userId: null,
                unreadMessages
            });
        }
    }

    if (!ticket) {
        //ATIVA/DESATIVA BOTPRESS
        var botpress = true;
        if (botpress) {
            if(groupContact){
            ticket = yield Ticket_1.default.create({
                contactId: groupContact ? groupContact.id : contact.id,
                //status: "pending",
                //Abre ticket com status open para o userId BOT (id = 2)
                status: "open",
                userId: 2,
                isGroup: !!groupContact,
                unreadMessages,
                whatsappId
            });
        }
        else{
            ticket = yield Ticket_1.default.create({
                contactId: groupContact ? groupContact.id : contact.id,
                //status: "pending",
                //Abre ticket com status open para o userId BOT (id = 2)
                status: "open",
                userId: 2,
                isGroup: !!groupContact,
                unreadMessages,
                whatsappId
            });
        }
        }
        else {
            ticket = yield Ticket_1.default.create({
                contactId: groupContact ? groupContact.id : contact.id,
                status: "pending",
                isGroup: !!groupContact,
                unreadMessages,
                whatsappId
            });
        }
        let ticket_all = yield Ticket_1.default.findAll({
            where: {
                status: {
                    [sequelize_1.Op.or]: ["open", "pending"]
                },
                id: { [sequelize_1.Op.not]: ticket.id },
                contactId: groupContact ? groupContact.id : contact.id
            }
        }).then((result) => {
            if (result) {
                result.forEach(function (r) {
                    r.update({ status: 'close' });
                    r.save();
                });
            }
        });
    }
    ticket = yield ShowTicketService_1.default(ticket.id);
    return ticket;
});
exports.default = FindOrCreateTicketService;
