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
const CheckContactOpenTickets_1 = __importDefault(require("../../helpers/CheckContactOpenTickets"));
const SetTicketMessagesAsRead_1 = __importDefault(require("../../helpers/SetTicketMessagesAsRead"));
const socket_1 = require("../../libs/socket");
const ShowTicketService_1 = __importDefault(require("./ShowTicketService"));
const SendWhatsAppMessage_1 = __importDefault(require("../../services/WbotServices/SendWhatsAppMessage"));

const CreateTicketService_1 = __importDefault(require("../../services/TicketServices/CreateTicketService"));
const DeleteTicketService_1 = __importDefault(require("../../services/TicketServices/DeleteTicketService"));
const ListTicketsService_1 = __importDefault(require("../../services/TicketServices/ListTicketsService"));
const UpdateTicketService_1 = __importDefault(require("../../services/TicketServices/UpdateTicketService"));
const ShowWhatsAppService_1 = __importDefault(require("../../services/WhatsappService/ShowWhatsAppService"));



const mysql = require('mysql');
const UpdateTicketService = ({ ticketData, ticketId }) => __awaiter(void 0, void 0, void 0, function* () {
    var _a, _b;
    const { status, userId, queueId } = ticketData;
    const ticket = yield ShowTicketService_1.default(ticketId);
    yield SetTicketMessagesAsRead_1.default(ticket);
    const oldStatus = ticket.status;
//    const oldUserId = (_a = ticket.user) === null || _a === void 0 ? void 0 : _a.id;
	const oldUserId = ticket.userId;
    if (oldStatus === "closed") {
        yield CheckContactOpenTickets_1.default(ticket.contact.id);

    }
    yield ticket.update({
        status,
        queueId,
        userId
    });
    yield ticket.reload();
    const io = socket_1.getIO();
	{    if (ticket.status !== oldStatus || ((_b = ticket.user) === null || _b === void 0 ? void 0 : _b.id) !== oldUserId) {
        io.to(oldStatus).emit("ticket", {
            action: "delete",
            ticketId: ticket.id
        });
    }
    
    ;}
    const connection = mysql.createConnection({
        host: process.env.DB_HOST,        // Usando a variável DB_HOST do .env
        user: process.env.DB_USER,        // Usando a variável DB_USER do .env
        password: process.env.DB_PASS,    // Usando a variável DB_PASSWORD do .env
        database: process.env.DB_NAME,    // Usando a variável DB_NAME do .env
        charset: process.env.DB_CHARSET   // Usando a variável DB_CHARSET do .env
        });

    if (status === "open"){
// CONTEXTO QUANDO O TICKET E ATENDIDO PELO USUARIO!!!
        console.log("Atendente *"+ticket.user.name+"* iniciou seu atendimento");
//        const msgtxt = "Olá, tudo bem?\nMeu nome é *"+ticket.user.name+"*...\n\nComo posso te *Ajudar* hoje?";
//        yield SendWhatsAppMessage_1.default({ body: msgtxt, ticket });

	    {/*	 if (ticket.status !== oldStatus || ((_b = ticket.user) === null || _b === void 0 ? void 0 : _b.id) !== oldUserId) {
        io.to(oldStatus).emit("ticket", {
            action: "delete",
            ticketId: ticket.id
        });
    }

    io.to(ticket.status)
        .to("notification")
        .to(ticketId.toString())
        .emit("ticket", {
        action: "update",
        ticket
    });*/}

	//return { ticket, oldStatus, oldUserId };
        }
        else if(status === "pending"){

        connection.query("UPDATE Contacts SET tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE id = '"+ticket.contact.id+"'");
        console.log('ticket Transferido com sucesso: '+ ticket.contact.id);
//	console.log(ticket.id, ticket.status, oldStatus);
    console.log("AQUI ACONTECE A TRANSFERENCIA CORRETA PELO FRONTEND")
		if (ticket.status !== oldStatus || ((_b = ticket.user) === null || _b === void 0 ? void 0 : _b.id) !== oldUserId) {

io.to(oldStatus).emit("ticket", {
    action: "delete",
    ticketId: ticket.id
});

}
//                         console.log(ticket.status, ticket.id, ticketId);		

    }

        else{

        connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE id = '"+ticket.contact.id+"'");
        console.log('ticket fechado com sucesso: '+ ticket.contact.id);
		{/*     if (ticket.status !== oldStatus || ((_b = ticket.user) === null || _b === void 0 ? void 0 : _b.id) !== oldUserId) {
        io.to(oldStatus).emit("ticket", {
            action: "delete",
            ticketId: ticket.id
        });
    }
    
    return { ticket, oldStatus, oldUserId };*/}
}
    
     if (ticket.status !== oldStatus || ticket.userId !== oldUserId) {
        io.to(oldStatus).emit("ticket", {
            action: "delete",
            ticketId: ticket.id
        });
    }

    io.to(ticket.status)
        .to("notification")
        .to(ticketId.toString())
        .emit("ticket", {
        action: "update",
        ticket
    });
 return { ticket, oldStatus, oldUserId };
});
exports.default = UpdateTicketService;
