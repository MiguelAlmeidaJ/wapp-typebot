"use strict";
// TOPO DO ARQUIVO
const ultimoAtendimento = new Map();

var __createBinding = (this && this.__createBinding) || (Object.create ? (function (o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    Object.defineProperty(o, k2, { enumerable: true, get: function () { return m[k]; } });
}) : (function (o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function (o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function (o, v) {
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
var __asyncValues = (this && this.__asyncValues) || function (o) {
    if (!Symbol.asyncIterator) throw new TypeError("Symbol.asyncIterator is not defined.");
    var m = o[Symbol.asyncIterator], i;
    return m ? m.call(o) : (o = typeof __values === "function" ? __values(o) : o[Symbol.iterator](), i = {}, verb("next"), verb("throw"), verb("return"), i[Symbol.asyncIterator] = function () { return this; }, i);
    function verb(n) { i[n] = o[n] && function (v) { return new Promise(function (resolve, reject) { v = o[n](v), settle(resolve, reject, v.done, v.value); }); }; }
    function settle(resolve, reject, d, v) { Promise.resolve(v).then(function (v) { resolve({ value: v, done: d }); }, reject); }
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.handleMessage = exports.wbotMessageListener = void 0;
const Ticket_1 = __importDefault(require("../../models/Ticket"));
const sequelize_1 = require("sequelize");

const axios = require('axios');
const ffmpeg = require('fluent-ffmpeg');
const path = require('path');
const fs = require('fs');
const path_1 = require("path");
const util_1 = require("util");
const fs_1 = require("fs");
const dotenv_1 = __importDefault(require("dotenv"));
const Sentry = __importStar(require("@sentry/node"));
const ListSettingsServiceOne_1 = __importDefault(require("../SettingServices/ListSettingsServiceOne"));
const Setting_1 = __importDefault(require("../../models/Setting"));
const Message_1 = __importDefault(require("../../models/Message"));
const socket_1 = require("../../libs/socket");
const CreateMessageService_1 = __importDefault(require("../MessageServices/CreateMessageService"));
const logger_1 = require("../../utils/logger");
const CreateOrUpdateContactService_1 = __importDefault(require("../ContactServices/CreateOrUpdateContactService"));
const CreateTicketService_1 = __importDefault(require("../TicketServices/CreateTicketService"));
const DeleteTicketService_1 = __importDefault(require("../TicketServices/DeleteTicketService"));
const ListTicketsService_1 = __importDefault(require("../TicketServices/ListTicketsService"));
const ShowTicketService_1 = __importDefault(require("../TicketServices/ShowTicketService"));
const UpdateTicketService_1 = __importDefault(require("../TicketServices/UpdateTicketService"));
const FindOrCreateTicketService_1 = __importDefault(require("../TicketServices/FindOrCreateTicketService"));
const ShowWhatsAppService_1 = __importDefault(require("../WhatsappService/ShowWhatsAppService"));
const Debounce_1 = require("../../helpers/Debounce");
const CreateContactService_1 = __importDefault(require("../ContactServices/CreateContactService"));
const Mustache_1 = __importDefault(require("../../helpers/Mustache"));
dotenv_1.default.config();
const { exec } = require('child_process');

const writeFileAsync = util_1.promisify(fs_1.writeFile);
const mysql = require('mysql');
const { MessageMedia } = require("whatsapp-web.js");
const connection = mysql.createConnection({
    host: process.env.DB_HOST,        // Usando a variável DB_HOST do .env
    user: process.env.DB_USER,        // Usando a variável DB_USER do .env
    password: process.env.DB_PASS,    // Usando a variável DB_PASSWORD do .env
    database: process.env.DB_NAME,    // Usando a variável DB_NAME do .env
    charset: process.env.DB_CHARSET   // Usando a variável DB_CHARSET do .env
});

// Verifica a conexão
connection.connect((err) => {
    if (err) {
        console.error("Erro ao conectar ao MySQL:", err.message);
        return;
    }
    console.log("Conexão com o MySQL bem-sucedida.");
});

const verifyContact = (msgContact) => __awaiter(void 0, void 0, void 0, function* () {
    /* const profilePicUrl = await msgContact.getProfilePicUrl();
  
    const contactData = {
      name: msgContact.name || msgContact.pushname || msgContact.id.user,
      number: msgContact.id.user,
      profilePicUrl,
      isGroup: msgContact.isGroup
    };
  
    const contact = CreateOrUpdateContactService(contactData);
  
    return contact;
  }; */
    try {
        const profilePicUrl = yield msgContact.getProfilePicUrl();
        const contactData = {
            name: msgContact.name || msgContact.pushname || msgContact.id.user,
            number: msgContact.id.user,
            profilePicUrl,
            isGroup: msgContact.isGroup
        };
        const contact = CreateOrUpdateContactService_1.default(contactData);
        return contact;
    }
    catch (err) {
        const profilePicUrl = "/default-profile.png"; // Foto de perfil padrão
        const contactData = {
            name: msgContact.name || msgContact.pushname || msgContact.id.user,
            number: msgContact.id.user,
            profilePicUrl,
            isGroup: msgContact.isGroup
        };
        const contact = CreateOrUpdateContactService_1.default(contactData);
        return contact;
    }
});
const verifyQuotedMessage = (msg) => __awaiter(void 0, void 0, void 0, function* () {

    if (!msg.hasQuotedMsg)
        return null;
    const wbotQuotedMsg = yield msg.getQuotedMessage();
    const quotedMsg = yield Message_1.default.findOne({
        where: { id: wbotQuotedMsg.id.id }
    });
    if (!quotedMsg)
        return null;
    return quotedMsg;
});
const verifyMediaMessage = (msg, ticket, contact) => __awaiter(void 0, void 0, void 0, function* () {
    const quotedMsg = yield verifyQuotedMessage(msg);
    const media = yield msg.downloadMedia();








    if (!media) {

        throw new Error("ERR_WAPP_DOWNLOAD_MEDIA");
    }
    let originalFilename = media.filename ? `-${media.filename}` : '';
    // Always write a random filename
    const ext = media.mimetype.split("/")[1].split(";")[0];

    //    if (msg.id.fromMe === false && msg.type === 'ptt') {



    media.filename = `${new Date().getTime()}${originalFilename}.${ext}`;


    //    }
    //    else {
    //        media.filename = `${new Date().getTime()}${originalFilename}.${ext}`;
    //    }
    try {
        yield writeFileAsync(path_1.join(__dirname, "..", "..", "..", "public", media.filename), media.data, "base64");
    }
    catch (err) {
        Sentry.captureException(err);
        logger_1.logger.error(err);
    }


    var audio = `${new Date().getTime()}${originalFilename}.${ext}`;


    console.log(ext)

    // =========================================================================================
    if (ext === "mpeg") {
        // Arquivo de entrada (OGG) e de saída (WAV)
        var filename = "public/" + media.filename;

        const inputFilePath = filename;
        const outputFilePath = `public/${new Date().getTime()}${originalFilename}.wav`;

        // Executa a conversão de OGG para WAV
        ffmpeg()
            .input(inputFilePath)
            .output(outputFilePath)
            .on('end', () => {
                console.log('Conversão concluída com sucesso.');
                exec(`python3 transcribe.py ${outputFilePath}`, (error, stdout, stderr) => {
                    if (error) {
                        return;
                    }
                    let primeiraPalavra = stdout.split(' ')[0];




                    if (primeiraPalavra === "Google") {
                        const messageData = {
                            id: msg.id.id,
                            ticketId: ticket.id,
                            contactId: msg.fromMe ? undefined : contact.id,
                            body: msg.body || "O reconhecimento não conseguiu entender o áudio",
                            fromMe: msg.fromMe,
                            read: msg.fromMe,
                            mediaUrl: media.filename,
                            mediaType: media.mimetype.split("/")[0],
                            quotedMsgId: quotedMsg == null || quotedMsg == void 0 ? void 0 : quotedMsg.id
                        };


                        ticket.update({ lastMessage: msg.body || media.filename });
                        const newMessage = CreateMessageService_1.default({ messageData });
                        return newMessage;
                    }
                    else {
                        const messageData = {
                            id: msg.id.id,
                            ticketId: ticket.id,
                            contactId: msg.fromMe ? undefined : contact.id,
                            body: msg.body || `${stdout}`,
                            fromMe: msg.fromMe,
                            read: msg.fromMe,
                            mediaUrl: media.filename,
                            mediaType: media.mimetype.split("/")[0],
                            quotedMsgId: quotedMsg == null || quotedMsg == void 0 ? void 0 : quotedMsg.id
                        };


                        ticket.update({ lastMessage: msg.body || media.filename });
                        const newMessage = CreateMessageService_1.default({ messageData });
                        return newMessage;

                    }
                });
            })
            .on('error', (err) => {
                console.error('Erro durante a conversão:', err);
            })
            .run();

    }

    // =========================================================================================
    if (ext === "ogg") {
        // Arquivo de entrada (OGG) e de saída (WAV)
        var filename = "public/" + media.filename;

        const inputFilePath = filename;
        const outputFilePath = `public/${new Date().getTime()}${originalFilename}.wav`;

        // Executa a conversão de OGG para WAV
        ffmpeg()
            .input(inputFilePath)
            .output(outputFilePath)
            .on('end', () => {
                console.log('Conversão concluída com sucesso.');
                exec(`python3 transcribe.py ${outputFilePath}`, (error, stdout, stderr) => {
                    if (error) {
                        return;
                    }
                    let primeiraPalavra = stdout.split(' ')[0];




                    if (primeiraPalavra === "Google") {
                        const messageData = {
                            id: msg.id.id,
                            ticketId: ticket.id,
                            contactId: msg.fromMe ? undefined : contact.id,
                            body: msg.body || "O reconhecimento não conseguiu entender o áudio",
                            fromMe: msg.fromMe,
                            read: msg.fromMe,
                            mediaUrl: media.filename,
                            mediaType: media.mimetype.split("/")[0],
                            quotedMsgId: quotedMsg == null || quotedMsg == void 0 ? void 0 : quotedMsg.id
                        };


                        ticket.update({ lastMessage: msg.body || media.filename });
                        const newMessage = CreateMessageService_1.default({ messageData });
                        return newMessage;
                    }
                    else {
                        const messageData = {
                            id: msg.id.id,
                            ticketId: ticket.id,
                            contactId: msg.fromMe ? undefined : contact.id,
                            body: msg.body || `${stdout}`,
                            fromMe: msg.fromMe,
                            read: msg.fromMe,
                            mediaUrl: media.filename,
                            mediaType: media.mimetype.split("/")[0],
                            quotedMsgId: quotedMsg == null || quotedMsg == void 0 ? void 0 : quotedMsg.id
                        };


                        ticket.update({ lastMessage: msg.body || media.filename });
                        const newMessage = CreateMessageService_1.default({ messageData });
                        return newMessage;

                    }
                });
            })
            .on('error', (err) => {
                console.error('Erro durante a conversão:', err);
            })
            .run();

    }
    // =====================================================================================================
    // =====================================================================================================

    else {
        const messageData = {
            id: msg.id.id,
            ticketId: ticket.id,
            contactId: msg.fromMe ? undefined : contact.id,
            body: msg.body || media.filename,
            fromMe: msg.fromMe,
            read: msg.fromMe,
            mediaUrl: media.filename,
            mediaType: media.mimetype.split("/")[0],
            quotedMsgId: quotedMsg == null || quotedMsg == void 0 ? void 0 : quotedMsg.id
        };


        ticket.update({ lastMessage: msg.body || media.filename });
        const newMessage = CreateMessageService_1.default({ messageData });
        return newMessage;

    }



});

const verifyMessage = (msg, ticket, contact) => __awaiter(void 0, void 0, void 0, function* () {
    if (msg.type === 'location')
        msg = prepareLocation(msg);
    const quotedMsg = yield verifyQuotedMessage(msg);
    const messageData = {
        id: msg.id.id,
        ticketId: ticket.id,
        contactId: msg.fromMe ? undefined : contact.id,
        body: msg.body,
        fromMe: msg.fromMe,
        mediaType: msg.type,
        read: msg.fromMe,
        quotedMsgId: quotedMsg === null || quotedMsg === void 0 ? void 0 : quotedMsg.id
    };
    yield ticket.update({ lastMessage: msg.type === "location" ? msg.location.description ? "Localization - " + msg.location.description.split('\\n')[0] : "Localization" : msg.body });
    yield CreateMessageService_1.default({ messageData });
});
const prepareLocation = (msg) => {
    let gmapsUrl = "https://maps.google.com/maps?q=" + msg.location.latitude + "%2C" + msg.location.longitude + "&z=17&hl=pt-BR";
    msg.body = "data:image/png;base64," + msg.body + "|" + gmapsUrl;
    msg.body += "|" + (msg.location.description ? msg.location.description : (msg.location.latitude + ", " + msg.location.longitude));
    return msg;
};
const verifyQueue = (wbot, msg, ticket, contact) => __awaiter(void 0, void 0, void 0, function* () {
    const { queues, greetingMessage } = yield ShowWhatsAppService_1.default(wbot.id);
    if (queues.length === 1) {
        yield UpdateTicketService_1.default({
            ticketData: { queueId: queues[0].id },
            ticketId: ticket.id
        });
        return;
    }
    const selectedOption = msg.body;
    const choosenQueue = queues[+selectedOption - 1];
    if (choosenQueue) {
        yield UpdateTicketService_1.default({
            ticketData: { queueId: choosenQueue.id },
            ticketId: ticket.id
        });
        //        const body = Mustache_1.default(`\u200e${choosenQueue.greetingMessage}`, contact);
        const body = Mustache_1.default(`${choosenQueue.greetingMessage}`, contact);
        const sentMessage = yield wbot.sendMessage(`${contact.number}@c.us`, body);
        yield verifyMessage(sentMessage, ticket, contact);
        console.log("Finalizando Atendimento");

    }
    else {
        let options = "";
        queues.forEach((queue, index) => {
            options += `*${index + 1}* - ${queue.name}\n`;
        });
        //        const body = Mustache_1.default(`\u200e${choosenQueue.greetingMessage}`, contact);
        const body = Mustache_1.default(`${greetingMessage}\n${options}`, contact);
        const debouncedSentMessage = Debounce_1.debounce(() => __awaiter(void 0, void 0, void 0, function* () {
            const sentMessage = yield wbot.sendMessage(`${contact.number}@c.us`, body);
            verifyMessage(sentMessage, ticket, contact);
        }), 3000, ticket.id);
        debouncedSentMessage();
        console.log("Finalizando Atendimento");
    }
});
const isValidMsg = (msg) => {

    if (msg.from === "status@broadcast")
        return false;
    if (msg.type === "chat" ||
        msg.type === "audio" ||
        msg.type === "call_log" ||
        msg.type === "ptt" ||
        msg.type === "video" ||
        msg.type === "image" ||
        msg.type === "document" ||
        msg.type === "vcard" ||
        //msg.type === "multi_vcard" ||
        msg.type === "sticker" ||
        msg.type === "e2e_notification" || // Ignore Empty Messages Generated When Someone Changes His Account from Personal to Business or vice-versa
        msg.type === "notification_template" || // Ignore Empty Messages Generated When Someone Changes His Account from Personal to Business or vice-versa
        msg.author != null || // Ignore Group Messages
        msg.type === "location")
        return true;
    return false;
};
const handleMessage = (msg, wbot) => __awaiter(void 0, void 0, void 0, function* () {
const agora = Date.now();
const numeroCliente = msg.from;

// Verificação para evitar múltiplas respostas em menos de 5 segundos
if (ultimoAtendimento.has(numeroCliente)) {
  const ultimoTempo = ultimoAtendimento.get(numeroCliente);
  if ((agora - ultimoTempo) < 5000) {
    console.log(`[${numeroCliente}] Ignorado: menos de 5s`);
    return;
  }
}
ultimoAtendimento.set(numeroCliente, agora);


    var e_1, _a;
    const contact = {}
    if (msg.from.length > 19) {
        msg.author = msg.from;
        const number = msg.author.match(/[\d-]+/g);
        contact.isGroup = true;

        connection.query("SELECT * FROM Contacts WHERE number = ?", [number], async function (err, Contact) {
            if (err) {
                console.error('Erro na consulta Contacts:', err);
                return;
            }
            if (!Contact || Contact.length === 0) {
                console.log('Nenhum contato encontrado para o número:', number);
                return;
            }

            connection.query("SELECT * FROM Tickets WHERE contactId = ?", [Contact[0].id], async function (err, ticket) {
                if (err) {
                    console.error('Erro na consulta Tickets:', err);
                    return;
                }
                try {
                    connection.query("UPDATE Tickets SET isGroup = 1, userId = 1 WHERE contactId = ?", [Contact[0].id]);
                } catch (err) {
                    console.error('Erro ao atualizar o ticket:', err);
                }
                console.log(Contact[0].id);
            });
        });
    }

    if (!isValidMsg(msg)) {
        return;
    }
    // Ignorar Mensagens de Grupo
    const Settingdb = yield Setting_1.default.findOne({
        where: { key: 'CheckMsgIsGroup' }
    });
    if ((Settingdb === null || Settingdb === void 0 ? void 0 : Settingdb.value) == 'enabled') {
        if (msg.from === "status@broadcast" ||
            msg.type === "e2e_notification" ||
            msg.type === "notification_template" ||
            msg.author != null) {
            return;
        }
    }
    try {
        let msgContact;
        let groupContact;
        if (msg.fromMe) {
            // messages sent automatically by wbot have a special character in front of it
            // if so, this message was already been stored in database;
            if (/\u200e/.test(msg.body[0]))
                return;
            // media messages sent from me from cell phone, first comes with "hasMedia = false" and type = "image/ptt/etc"
            // in this case, return and let this message be handled by "media_uploaded" event, when it will have "hasMedia = true"
            if (!msg.hasMedia && msg.type !== "location" && msg.type !== "chat" && msg.type !== "vcard"
                //&& msg.type !== "multi_vcard"
            )
                return;
            msgContact = yield wbot.getContactById(msg.to);
        }
        else {
            // Verifica se Cliente fez ligação/vídeo pelo wpp
            const listSettingsService = yield ListSettingsServiceOne_1.default({ key: "call" });
            var callSetting = listSettingsService === null || listSettingsService === void 0 ? void 0 : listSettingsService.value;
            msgContact = yield msg.getContact();
        }
        const chat = yield msg.getChat();
        if (chat.isGroup) {
            let msgGroupContact;
            if (msg.fromMe) {
                msgGroupContact = yield wbot.getContactById(msg.to);
            }
            else {
                msgGroupContact = yield wbot.getContactById(msg.from);
            }
            groupContact = yield verifyContact(msgGroupContact);
        }
        const whatsapp = yield ShowWhatsAppService_1.default(wbot.id);
        const unreadMessages = msg.fromMe ? 0 : chat.unreadCount;
        const contact = yield verifyContact(msgContact);
        if (unreadMessages === 0 &&
            whatsapp.farewellMessage &&
            Mustache_1.default(whatsapp.farewellMessage, contact) === msg.body)
            return;
        //SETA SE A MENSAGEM E DE ENTRADA (in) OU DE SAIDA (out)
        const direction = msg.fromMe;
        //console.log(quotedMsg)
        /*const ticket = await FindOrCreateTicketService(
          contact,
          wbot.id!,
          unreadMessages,
          groupContact
        );*/




        // AQUI E ONDE EU ESTOU COMENTANDO HOJE DIA 25/11/2024 POR CONTA QUE O WHATSAPP NAO CONSEGUIU MAIS 
        // DIFERENCIAR O  GRUPO DOS CONTATOS


        let ticket;
        let findticket = yield Ticket_1.default.findOne({
            where: {
                status: {
                    [sequelize_1.Op.or]: ["open", "pending"]
                },
                contactId: groupContact ? groupContact.id : contact.id
            }
        });

        if (!findticket && msg.fromMe) {
            logger_1.logger.error('Whatsapp message sent by mobile:');
            return;
        } else {
            ticket = yield FindOrCreateTicketService_1.default(contact, wbot.id, unreadMessages, groupContact);
        }

        if (msg.hasMedia) {
            yield verifyMediaMessage(msg, ticket, contact);
        }
        else {
            yield verifyMessage(msg, ticket, contact);
        }
        if (!ticket.queue &&
            !chat.isGroup &&
            !msg.fromMe &&
            !ticket.userId &&
            whatsapp.queues.length >= 1) {
            yield verifyQueue(wbot, msg, ticket, contact);
        }
        if (msg.type === "vcard") {
            try {
                const array = msg.body.split("\n");
                const obj = [];
                let contact = "";
                for (let index = 0; index < array.length; index++) {
                    const v = array[index];
                    const values = v.split(":");
                    for (let ind = 0; ind < values.length; ind++) {
                        if (values[ind].indexOf("+") !== -1) {
                            obj.push({ number: values[ind] });
                        }
                        if (values[ind].indexOf("FN") !== -1) {
                            contact = values[ind + 1];
                        }
                    }
                }
                try {
                    for (var obj_1 = __asyncValues(obj), obj_1_1; obj_1_1 = yield obj_1.next(), !obj_1_1.done;) {
                        const ob = obj_1_1.value;
                        const cont = yield CreateContactService_1.default({
                            name: contact,
                            number: ob.number.replace(/\D/g, "")
                        });
                    }
                }
                catch (e_1_1) { e_1 = { error: e_1_1 }; }
                finally {
                    try {
                        if (obj_1_1 && !obj_1_1.done && (_a = obj_1.return)) yield _a.call(obj_1);
                    }
                    finally { if (e_1) throw e_1.error; }
                }
            }
            catch (error) {
                console.log(error);
            }
        }




        /* if (msg.type === "multi_vcard") {
          try {
            const array = msg.vCards.toString().split("\n");
            let name = "";
            let number = "";
            const obj = [];
            const conts = [];
            for (let index = 0; index < array.length; index++) {
              const v = array[index];
              const values = v.split(":");
              for (let ind = 0; ind < values.length; ind++) {
                if (values[ind].indexOf("+") !== -1) {
                  number = values[ind];
                }
                if (values[ind].indexOf("FN") !== -1) {
                  name = values[ind + 1];
                }
                if (name !== "" && number !== "") {
                  obj.push({
                    name,
                    number
                  });
                  name = "";
                  number = "";
                }
              }
            }
    
            // eslint-disable-next-line no-restricted-syntax
            for await (const ob of obj) {
              try {
                const cont = await CreateContactService({
                  name: ob.name,
                  number: ob.number.replace(/\D/g, "")
                });
                conts.push({
                  id: cont.id,
                  name: cont.name,
                  number: cont.number
                });
              } catch (error) {
                if (error.message === "ERR_DUPLICATED_CONTACT") {
                  const cont = await GetContactService({
                    name: ob.name,
                    number: ob.number.replace(/\D/g, ""),
                    email: ""
                  });
                  conts.push({
                    id: cont.id,
                    name: cont.name,
                    number: cont.number
                  });
                }
              }
            }
            msg.body = JSON.stringify(conts);
          } catch (error) {
            console.log(error);
          }
        } */
        /**********************************************************************************************************/
        //INTEGRAÇÃO WHATICKET BOTPRESS
        //userId ==> é o id do usuario bot no whaticket
        //direction ==> false - mensagens de entrada1	
        //WhatsappId = whatsapp.id


        // ********************************* INICIADO POR DANIEL  *********************************************************
        // FUNÇÃO ENCAMINHA CHAMADO PARA ATENDIMENTO






        async function atdFisico(opc) {
            const io = (0, socket_1.getIO)();
            connection.query("SELECT * FROM Queues WHERE id = '" + opc + "'", async function (err, Queues) {
                connection.query("UPDATE Contacts SET categoria = '5' WHERE number = '" + contact.number + "'");




                const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/TRANSFERINDO-ATENDIMENTO.mp3", { encoding: "base64", });
                const media = new MessageMedia("audio/mpeg", audio);
                await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });


                //                await wbot.sendMessage(msg.from, "*Mensagem Automática:* \n\nestamos transferido seu *Atendimento* para o *" + Queues[0].name + "*\nAguarde um momento, iremos atende-lo(a)!");
            });

            UpdateTicketService_1.default({ ticketData: { queueId: opc, status: "pending" }, ticketId: ticket.id });
            await ticket.update({
                queueId: opc,
                userId: null,
                status: "pending",
            });

        }


        function SelecionaMkAuth(cpfcnpj) {
            const url = 'http://100.64.0.126/ura/cliente.php?cpf_cnpj=';

            axios.get(url + cpfcnpj + '&contrato=1').then(function (resposta) {

                // CONSULTANDO CLIENTE
                if (resposta.data.id > 0) {
                    const url2via = 'http://100.64.0.126/ura/boletos.php?cpf_cnpj=';
                    axios.get(url2via + cpfcnpj).then(function (res2via) {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'INFO-MENU-CLIENTE'", async function (err, resp) {
                            if (res2via.data[0] === undefined) {

                                console.log("CONTRATO SEM TITULO!")
                                if (resposta.data.conectado === 'sim') {
                                    connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "' WHERE number = '" + contact.number + "'");
                                    wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                }
                                else {
                                    connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "' WHERE number = '" + contact.number + "'");
                                    wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                }

                            }
                            else {
                                //CLIENTE COM TITULO

                                if (resposta.data.bloqueado === 'Bloqueado') {
                                    if (resposta.data.conectado === 'sim') {
                                        connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', titulo = '" + res2via.data[-0].titulo + "', linha_digitavel = '" + res2via.data[-0].linha_digitavel + "', copiacola = '" + res2via.data[-0].copiacola + "', valor = '" + res2via.data[-0].valor + "', data_vencimento = '" + res2via.data[-0].data_vencimento + "' WHERE number = '" + contact.number + "'");
                                        wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via Fatura*\n2️⃣ *Desbloqueio Confiança*\n3️⃣ *Falar com Financeiro*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                    }
                                    else {
                                        connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', titulo = '" + res2via.data[-0].titulo + "', linha_digitavel = '" + res2via.data[-0].linha_digitavel + "', copiacola = '" + res2via.data[-0].copiacola + "', valor = '" + res2via.data[-0].valor + "', data_vencimento = '" + res2via.data[-0].data_vencimento + "' WHERE number = '" + contact.number + "'");
                                        wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via Fatura*\n2️⃣ *Desbloqueio Confiança*\n3️⃣ *Falar com Financeiro*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                    }
                                }
                                else {
                                    if (resposta.data.conectado === 'sim') {
                                        connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', titulo = '" + res2via.data[-0].titulo + "', linha_digitavel = '" + res2via.data[-0].linha_digitavel + "', copiacola = '" + res2via.data[-0].copiacola + "', valor = '" + res2via.data[-0].valor + "', data_vencimento = '" + res2via.data[-0].data_vencimento + "' WHERE number = '" + contact.number + "'");
                                        wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                    }
                                    else {
                                        connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', titulo = '" + res2via.data[-0].titulo + "', linha_digitavel = '" + res2via.data[-0].linha_digitavel + "', copiacola = '" + res2via.data[-0].copiacola + "', valor = '" + res2via.data[-0].valor + "', data_vencimento = '" + res2via.data[-0].data_vencimento + "' WHERE number = '" + contact.number + "'");
                                        wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                    }
                                }


                                console.log("bloqueado: " + resposta.data.bloqueado);
                                console.log("id_cliente: " + resposta.data.id);
                            }
                        });
                    });
                }
                else {
                    console.log("CONTRATO NAO LOCALIZADO!")
                    connection.query("SELECT * FROM Contacts WHERE number = '" + contact.number + "'", async function (err, Contact) {

                        if (Contact[0].tentativas === "0") {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-CPF-INV-1'", async function (err, resposta) {
                                await wbot.sendMessage(msg.from, resposta[0].message);
                                connection.query("UPDATE Contacts SET tentativas = '1' WHERE number = '" + contact.number + "'");
                            })
                        }
                        else if (Contact[0].tentativas === "1") {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-CPF-INV-2'", async function (err, resposta) {
                                connection.query("UPDATE Contacts SET tentativas = '2' WHERE number = '" + contact.number + "'");
                                await wbot.sendMessage(msg.from, resposta[0].message);
                            })
                        }
                        else if (Contact[0].tentativas === "2") {
                            connection.query("UPDATE Contacts SET tentativas = '0' WHERE number = '" + contact.number + "'");
                            connection.query("UPDATE Contacts SET categoria = '0' WHERE number = '" + contact.number + "'");
                            atdFisico('1')
                        }
                    });
                }
            })
        }

        function SelecionaGps(cpfcnpj) {
            const url = 'http://100.64.0.126/ura/cliente.php?cpf_cnpj=';

            axios.get(url + cpfcnpj + '&contrato=2').then(function (resposta) {
                connection.query("UPDATE Contacts SET categoria = '7', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', linha_digitavel = '" + resposta.data.linha_digitavel + "', copiacola = '" + resposta.data.copiacola + "', titulo = '" + resposta.data.id_fatura + "', valor = '" + resposta.data.valor + "', data_vencimento = '" + resposta.data.data_vencimento + "' WHERE number = '" + contact.number + "'");
                wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *Plataforma GPS*\nStatus: *" + resposta.data.bloqueado + "*\n\n1️⃣ *Segunda Via Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");
            })
        }


        // ###################### CONSULTA CLIENTE APARTI DA OPÇÃO 1 DO INICIO DO MENU #######################################

        function ConsultaCliente(cpfcnpj, cliId) {
            const url = 'http://100.64.0.126/ura/cliente.php?cpf_cnpj=';

            axios.get(url + cpfcnpj).then(function (resposta) {

                if (resposta.data.contrato === '2') {
                    const nomeCompleto = resposta.data.nome;
                    const primeiroNome = nomeCompleto.split(' ')[0]; // Extrai o primeiro nome
                    const nomeFormatado = primeiroNome.charAt(0).toUpperCase() + primeiroNome.slice(1).toLowerCase(); // Capitaliza a primeira letra
                    connection.query("UPDATE Contacts SET categoria = '6', cpfcnpj = '" + cpfcnpj + "' WHERE number = '" + contact.number + "'");

                    const $msg = 'Olá, *' + nomeFormatado + '!*\n\n';
                    console.log(resposta.data.nome);

                    connection.query("SELECT * FROM Chatbot WHERE shortcut = 'MENU-INFO-CONTRATOS'", async function (err, respostaBanco) {
                        if (err) {
                            console.error('Erro ao consultar o banco:', err);
                            return;
                        }

                        // Verifique se a resposta contém dados
                        if (respostaBanco && respostaBanco.length > 0) {
                            await wbot.sendMessage(msg.from, $msg + respostaBanco[0].message);

                        }
                    })
                }


                // QUANDO O CLIENTE E SOMENTE DE PLATAFORMA MKAUTH
                else if (resposta.data.plataforma === 'mkauth') {
                    const url2via = 'http://100.64.0.126/ura/boletos.php?cpf_cnpj=';
                    axios.get(url2via + cpfcnpj).then(function (res2via) {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'INFO-MENU-CLIENTE'", async function (err, resp) {
                            if (res2via.data[0] === undefined) {

                                console.log("CONTRATO SEM TITULO!")
                                if (resposta.data.conectado === 'sim') {
                                    connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "' WHERE number = '" + contact.number + "'");
                                    wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                }
                                else {
                                    connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "' WHERE number = '" + contact.number + "'");
                                    wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                }

                            }
                            else {
                                //CLIENTE COM TITULO

                                if (resposta.data.bloqueado === 'Bloqueado') {
                                    if (resposta.data.conectado === 'sim') {
                                        connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', titulo = '" + res2via.data[-0].titulo + "', linha_digitavel = '" + res2via.data[-0].linha_digitavel + "', copiacola = '" + res2via.data[-0].copiacola + "', valor = '" + res2via.data[-0].valor + "', data_vencimento = '" + res2via.data[-0].data_vencimento + "' WHERE number = '" + contact.number + "'");
                                        wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via Fatura*\n2️⃣ *Desbloqueio Confiança*\n3️⃣ *Falar com Financeiro*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                    }
                                    else {
                                        console.log('CLIENTE BLOQUEADO E DESATIVADO');

                                        // Envia o áudio
                                        const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/INFO-BLOQUEIO.mp3", { encoding: "base64" });
                                        const media = new MessageMedia("audio/mpeg", audio);
                                        await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });

                                        // Aguarda 10 segundos
                                        await new Promise(resolve => setTimeout(resolve, 14000));

                                        // Formata a data de vencimento
                                        const venc = res2via.data[0].data_vencimento.replace(/[^0-9]/g, '');
                                        const dia = venc.substr(6, 2);
                                        const mes = venc.substr(4, 2);
                                        const ano = venc.substr(0, 4);
                                        const data_venc = `${dia}/${mes}/${ano}`;


                                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'INFO-BLOQUEIO-MENU'", async function (err, resposta_m) {


                                            // Envia dados do boleto
                                            await wbot.sendMessage(msg.from, `📄 *Dados do seu boleto:*\n\n📅 *Vencimento:* ${data_venc}\n💰 *Valor:* R$ ${res2via.data[0].valor}\n\n*Segue abaixo o código de barras:*`);

                                            // Envia a linha digitável
                                            await wbot.sendMessage(msg.from, res2via.data[0].linha_digitavel);

                                            // Aguarda 2 segundos
                                            await new Promise(resolve => setTimeout(resolve, 2000));

                                            // Envia aviso do PIX copia e cola
                                            await wbot.sendMessage(msg.from, `🔁 *Segue abaixo o PIX copia e cola:*`);

                                            // Envia o código PIX
                                            await wbot.sendMessage(msg.from, res2via.data[0].copiacola);

                                            // Aguarda mais 2 segundos
                                            await new Promise(resolve => setTimeout(resolve, 3000));

                                            // Envia aviso do PIX copia e cola
                                            await wbot.sendMessage(msg.from, `🔁 *Agora vai o link do Boleto:*`);

                                            // Aguarda mais 2 segundos
                                            await new Promise(resolve => setTimeout(resolve, 2000));

                                            // Envia o código PIX
                                            await wbot.sendMessage(msg.from, `https://skynetfibra.net.br/boleto/boleto.hhvm?titulo=${res2via.data[0].titulo}&contrato=${resposta.data.login}`);

                                            // Aguarda mais 2 segundos
                                            await new Promise(resolve => setTimeout(resolve, 2000));

                                            await wbot.sendMessage(msg.from, `${resposta_m[0].message}`);


                                            wbot.sendMessage(msg.from, `
*M E N U    C L I E N T E*

*${resposta.data.nome.trim()}*
Login: *${resposta.data.login}*
Plano: *${resposta.data.plano}*
Status: *${resposta.data.bloqueado}*

INFORMAÇÕES DE CONEXÃO:
Status: *${resposta.data.conectado}*
Dia: *${resposta.data.acctstarttime}*

1️⃣ *Segunda Via Fatura*
2️⃣ *Desbloqueio Confiança*
3️⃣ *Falar com Financeiro*

_${resp[0].message}_

0️⃣ *Encerrar Atendimento*
`);

                                            connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', titulo = '" + res2via.data[-0].titulo + "', linha_digitavel = '" + res2via.data[-0].linha_digitavel + "', copiacola = '" + res2via.data[-0].copiacola + "', valor = '" + res2via.data[-0].valor + "', data_vencimento = '" + res2via.data[-0].data_vencimento + "' WHERE number = '" + contact.number + "'");
                                            //                                        wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via Fatura*\n2️⃣ *Desbloqueio Confiança*\n3️⃣ *Falar com Financeiro*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                        });
                                    }
                                }
                                else {
                                    if (resposta.data.conectado === 'sim') {
                                        connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', titulo = '" + res2via.data[-0].titulo + "', linha_digitavel = '" + res2via.data[-0].linha_digitavel + "', copiacola = '" + res2via.data[-0].copiacola + "', valor = '" + res2via.data[-0].valor + "', data_vencimento = '" + res2via.data[-0].data_vencimento + "' WHERE number = '" + contact.number + "'");
                                        wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                    }
                                    else {
                                        connection.query("UPDATE Contacts SET categoria = '3', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', titulo = '" + res2via.data[-0].titulo + "', linha_digitavel = '" + res2via.data[-0].linha_digitavel + "', copiacola = '" + res2via.data[-0].copiacola + "', valor = '" + res2via.data[-0].valor + "', data_vencimento = '" + res2via.data[-0].data_vencimento + "' WHERE number = '" + contact.number + "'");
                                        wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *" + resposta.data.plano + "*\nStatus: *" + resposta.data.bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + resposta.data.conectado + "*\nDia: *" + resposta.data.acctstarttime + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n_" + resp[0].message + "_\n\n0️⃣ *Encerrar Atendimento*");
                                    }
                                }


                                console.log("Status: " + resposta.data.bloqueado);
                                console.log("id_cliente: " + resposta.data.id);
                            }
                        });
                    });
                }

                // QUANDO O CLIENTE E SOMENTE DE PLATAFORMA GPS
                else if (resposta.data.plataforma === 'gps') {
                    console.log("Cliente GPS");
                    connection.query("UPDATE Contacts SET categoria = '7', nome = '" + resposta.data.nome.trim() + "', conectado = '" + resposta.data.conectado + "',acctstarttime = '" + resposta.data.acctstarttime + "', acctstoptime = '" + resposta.data.acctstoptime + "', clienteId = '" + resposta.data.id + "', plano = '" + resposta.data.plano + "', login = '" + resposta.data.login + "', bloqueado = '" + resposta.data.bloqueado + "', cpfcnpj = '" + cpfcnpj + "', linha_digitavel = '" + resposta.data.linha_digitavel + "', copiacola = '" + resposta.data.copiacola + "', titulo = '" + resposta.data.id_fatura + "', valor = '" + resposta.data.valor + "', data_vencimento = '" + resposta.data.data_vencimento + "' WHERE number = '" + contact.number + "'");
                    wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + resposta.data.nome.trim() + "*\nLogin: *" + resposta.data.login + "*\nPlano: *Plataforma GPS*\nStatus: *" + resposta.data.bloqueado + "*\n\n1️⃣ *Segunda Via Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");
                }

                else {
                    console.log("CONTRATO NAO LOCALIZADO!")
                    connection.query("SELECT * FROM Contacts WHERE number = '" + contact.number + "'", async function (err, Contact) {

                        if (Contact[0].tentativas === "0") {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-CPF-INV-1'", async function (err, resposta) {
                                await wbot.sendMessage(msg.from, resposta[0].message);
                                connection.query("UPDATE Contacts SET tentativas = '1' WHERE number = '" + contact.number + "'");
                            })
                        }
                        else if (Contact[0].tentativas === "1") {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-CPF-INV-2'", async function (err, resposta) {
                                connection.query("UPDATE Contacts SET tentativas = '2' WHERE number = '" + contact.number + "'");
                                await wbot.sendMessage(msg.from, resposta[0].message);
                            })
                        }
                        else if (Contact[0].tentativas === "2") {
                            connection.query("UPDATE Contacts SET tentativas = '0' WHERE number = '" + contact.number + "'");
                            connection.query("UPDATE Contacts SET categoria = '0' WHERE number = '" + contact.number + "'");
                            atdFisico('1')
                        }
                    });
                }
            })
        }

        // ###################### FIM DA CONSULTA CLIENTE APARTI DA OPÇÃO 1 DO INICIO DO MENU ################################

        switch (whatsapp.id) {
            default:
            //                console.log(urlBot);
            //                console.log(ticket.userId, direction, msg.type, ticketId);
        }



















        // ############### FIM DO ESPAÇO DEDICADO A CENTRAL DO TECNICO ###################




        // ****************************** MENSAGEM DE AGUARDANDO ATENDIMENTO FISICO ******************************************
        if (msg.body === '#menu') {
            // Função auxiliar para extrair primeiro nome
            function getPrimeiroNome(nomeCompleto) {
                return nomeCompleto.split(' ')[0];
            }

            // Função que retorna a mensagem com opções para o técnico
            function mensagemOpcoes(nomeTecnico) {
                return `Olá, *${nomeTecnico}!*\n\n_Informe o número da opção desejada._\n\n` +
                    `1️⃣ Consultar ordem\n` +
                    `2️⃣ Falar com Atendente\n` +
                    `\n` +
                    `0️⃣ Encerrar atendimento`;
            }

            const consultaTecnicoUrl = 'http://100.64.0.126/dctapi/consulta_tecnicoForCelular.php?celular=';

            // Extrai celular só com números e remove o 55 do início se existir
            let celular = msg.from.replace(/\D/g, '');
            if (celular.startsWith('55')) {
                celular = celular.slice(2);
            }

            axios.get(consultaTecnicoUrl + encodeURIComponent(celular))
                .then(async function (response) {
                    const tecnicoData = response.data;

                    if (!tecnicoData || tecnicoData.erro || Object.keys(tecnicoData).length === 0) {
                        // NÃO encontrou técnico — seu fluxo original
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-INICIO'", async function (err, resposta) {
                            if (err) {
                                console.error('Erro na consulta do chatbot:', err);
                                return;
                            }

                            const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-INICIAL.mp3", { encoding: "base64" });
                            const media = new MessageMedia("audio/mpeg", audio);
                            await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                            connection.query("UPDATE Contacts SET categoria = '1' WHERE number = '" + contact.number + "'");
                            UpdateTicketService_1.default({ ticketData: { userId: '2', status: "open" }, ticketId: ticket.id });

                            setTimeout(async () => {
                                await wbot.sendMessage(msg.from, resposta[0].message + "\n\n_*Protocolo de Atendimento: " + ticket.id + "*_");
                            }, 5000);

                        });
                    } else {
                        // Encontrou técnico — envia mensagem com opções
                        const primeiroNome = getPrimeiroNome(tecnicoData.nome);
                        const textoOpcoes = mensagemOpcoes(primeiroNome);
                        await wbot.sendMessage(msg.from, textoOpcoes);
                        connection.query("UPDATE Contacts SET categoria = 'T1', nome = '" + tecnicoData.nome + "', tecnico = '" + response.data.id + "', nome_tecnico = '" + response.data.nome + "' WHERE number = '" + contact.number + "'");
                        UpdateTicketService_1.default({ ticketData: { userId: '2', status: "open" }, ticketId: ticket.id });
                        console.log(response.data)
                    }
                })
                .catch(function (error) {
                    console.error('Erro na consulta do técnico:', error);
                });
        }

        if (ticket.status === 'pending' && direction == false && msg.type !== "call_log" && msg.body !== '#menu') {
            connection.query("SELECT * FROM Contacts WHERE id = '" + ticket.contactId + "'", async function (err, Contact) {
                if (Contact[0] === undefined) {
                    console.log("nao encontrado")
                }
                else if (Contact[0].transferido === '0') {
                    console.log("encontrado")
                    wbot.sendMessage(msg.from, "Desculpe, *" + msg._data.notifyName + "*\n_ainda nao consegui transferir...😞_\nSó mais um instante que ja iremos lhe *Atender.🤚🏽*\n\n*_[Mensagem Automática]_*")
                    console.log(ticket.queueId);
                    connection.query("UPDATE Contacts SET transferido = '1' WHERE number = '" + contact.number + "'");

                }
                else {

                }
            });
        }
        // *******************************************************************************************************************        



        if (msg.body !== '#menu' && !ticket.isGroup && ticket.status === 'open' && ticket.userId === 2 && direction == false && msg.type !== "call_log") {
            connection.query("SELECT * FROM Contacts WHERE number = '" + contact.number + "' AND isGroup = '0'", async function (err, cliente) {

                if (cliente[0] === undefined) {
                }
                else {
                    //                console.log(ticket.userId, direction, msg.type);
                    //                console.log(contact.number, cliente[0].categoria, cliente[0].tentativas);
                    // ************************************************ INICIO COM AUDIO ************************************************
                    if (msg.body !== '#menu' && cliente[0].categoria === '0') {
                        if (msg.from.length > 18) {
                            UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });
                        }
                        else {

                            // Função auxiliar para extrair primeiro nome
                            function getPrimeiroNome(nomeCompleto) {
                                return nomeCompleto.split(' ')[0];
                            }

                            // Função que retorna a mensagem com opções para o técnico
                            function mensagemOpcoes(nomeTecnico) {
                                return `Olá, *${nomeTecnico}!*\n\n_Informe o número da opção desejada._\n\n` +
                                    `1️⃣ Consultar ordem\n` +
                                    `2️⃣ Falar com Atendente\n` +
                                    `\n` +
                                    `0️⃣ Encerrar atendimento`;
                            }

                            const consultaTecnicoUrl = 'http://100.64.0.126/dctapi/consulta_tecnicoForCelular.php?celular=';

                            // Extrai celular só com números e remove o 55 do início se existir
                            let celular = msg.from.replace(/\D/g, '');
                            if (celular.startsWith('55')) {
                                celular = celular.slice(2);
                            }

                            axios.get(consultaTecnicoUrl + encodeURIComponent(celular))
                                .then(async function (response) {
                                    const tecnicoData = response.data;

                                    if (!tecnicoData || tecnicoData.erro || Object.keys(tecnicoData).length === 0) {
                                        // NÃO encontrou técnico — seu fluxo original
                                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-INICIO'", async function (err, resposta) {
                                            if (err) {
                                                console.error('Erro na consulta do chatbot:', err);
                                                return;
                                            }

                                            const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-INICIAL.mp3", { encoding: "base64" });
                                            const media = new MessageMedia("audio/mpeg", audio);
                                            await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                                            connection.query("UPDATE Contacts SET categoria = '1' WHERE number = '" + contact.number + "'");

                                            setTimeout(async () => {
                                                await wbot.sendMessage(msg.from, resposta[0].message + "\n\n_*Protocolo de Atendimento: " + ticket.id + "*_");
                                            }, 5000);

                                        });
                                    } else {
                                        // Encontrou técnico — envia mensagem com opções
                                        const primeiroNome = getPrimeiroNome(tecnicoData.nome);
                                        const textoOpcoes = mensagemOpcoes(primeiroNome);
                                        await wbot.sendMessage(msg.from, textoOpcoes);
                                        connection.query("UPDATE Contacts SET categoria = 'T1', nome_tecnico = '" + tecnicoData.nome + "', tecnico = '" + tecnicoData.id + "' WHERE number = '" + contact.number + "'");
                                    }
                                })
                                .catch(function (error) {
                                    console.error('Erro na consulta do técnico:', error);
                                });

                        }
                    }

                    // ################### ESPAÇO DEDICADO A CENTRAL DO TECNICO ####################

                    // CONTEÚDO DO INICIO DO ATENDIMENTO DO TECNICO

                    // CHECANDO SE EXISTE  CHAMADOS EM ABERTO PARA O TECNICO ATUAL
                    if (cliente[0].categoria === 'T1' && ticket.status === 'open' && msg.body === '1') {
                        function mensagemOpcoes() {
                            return `Por favor, informe o *PPPoE* do *cliente* para o qual deseja atendimento.\n\n`;
                        }
                        connection.query("UPDATE Contacts SET categoria = 'T2' WHERE number = '" + cliente[0].number + "'");
                        wbot.sendMessage(msg.from, mensagemOpcoes())
                            .then(() => console.log(''))
                            .catch(err => console.error(err));
                    }
                    // TRANSFERINDO PARA O ATENDIMENTO
                    if (cliente[0].categoria === 'T1' && ticket.status === 'open' && msg.body === '2') {
                        atdFisico('2')
                    }

                    if (cliente[0].categoria === 'T1' && ticket.status === 'open' && msg.body === '0') {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                            connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");

                            function mensagem() {
                                return resposta[0].message;
                            }
                            UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });
                            wbot.sendMessage(msg.from, mensagem())
                                .then(() => console.log(''))
                                .catch(err => console.error(err));
                        });
                    }

                    else if (cliente[0].categoria === 'T1' && ticket.status === 'open' && msg.body !== '1' && msg.body !== '2' && msg.body !== '0') {
                        function mensagemOpcoes() {
                            return `_Informe o número da opção desejada._\n\n` +
                                `1️⃣ Consultar ordem\n` +
                                `2️⃣ Falar com Atendente\n` +
                                `\n` +
                                `0️⃣ Encerrar atendimento`;
                        }
                        wbot.sendMessage(msg.from, mensagemOpcoes())
                            .then(() => console.log(''))
                            .catch(err => console.error(err));
                    }

                    // FIM DO CONTEÚDO DO INICIO DO ATENDIMENTO DO TECNICO


                    async function chamado(numeroChamado) {
                        const consultaTecnicoUrl = `http://100.64.0.126/dctapi/consulta_chamadoForChamado.php?chamado=${numeroChamado}`;

                        try {
                            const response = await axios.get(consultaTecnicoUrl);
                            const data = response.data;

                            // Verifica se o chamado é válido (por exemplo, checando se tem id e chamado não vazio)
                            if (!data || !data.id || !data.chamado) {
                                // Chamado inválido ou não encontrado
                                const msgErro = `Chamado não encontrado ou inválido. Por favor, verifique o número e tente novamente.\n\n` +
                                    `Caso deseje voltar ao menu inicial, envie:\n#menu`;
                                await wbot.sendMessage(msg.from, msgErro);
                            }
                            else {
                                function formatarDataBR(dataISO) {
                                    if (!dataISO) return '';
                                    const data = new Date(dataISO);
                                    const dia = String(data.getDate()).padStart(2, '0');
                                    const mes = String(data.getMonth() + 1).padStart(2, '0');
                                    const ano = data.getFullYear();
                                    const horas = String(data.getHours()).padStart(2, '0');
                                    const minutos = String(data.getMinutes()).padStart(2, '0');
                                    const segundos = String(data.getSeconds()).padStart(2, '0');
                                    return `${dia}/${mes}/${ano} ${horas}:${minutos}:${segundos}`;
                                }

                                // Monta mensagem de sucesso com dados do chamado
                                function mensagemOpcoes(chamadoData) {
                                    return `Chamado n: ${chamadoData.chamado}\n` +
                                        `Assunto: ${chamadoData.assunto}\n` +
                                        `Aberto em: ${formatarDataBR(chamadoData.abertura)}\n` +
                                        `Status: ${chamadoData.status}\n` +
                                        `Nome do Cliente: ${chamadoData.nome}\n` +
                                        `Atendente: ${chamadoData.atendente}\n\n` +
                                        `1️⃣ Instalar Equipamento Novo\n` +
                                        `2️⃣ Trocar Equipamento\n` +
                                        `3️⃣ Trocar Produtos\n` +
                                        `4️⃣ Falar com Atendente\n` +
                                        `\n` +
                                        `0️⃣ Encerrar atendimento`;
                                }

                                // Envia mensagem ao usuário
                                await wbot.sendMessage(msg.from, mensagemOpcoes(data));

                                // Atualiza os dados na tabela Contacts de forma segura
                                const sqlUpdate = `
            UPDATE Contacts SET
                categoria = ?,
                chamado = ?,
                assunto = ?,
                abertura = ?,
                status = ?,
                nome = ?,
                atendente = ?,
                visita = ?,
                id_cliente = ?
            WHERE number = ?
        `;

                                const params = [
                                    'T3',
                                    data.chamado,
                                    data.assunto,
                                    data.abertura,
                                    data.status,
                                    data.nome,
                                    data.atendente,
                                    data.visita,
                                    data.id_cliente,
                                    cliente[0].number // garanta que está definido e correto no escopo
                                ];

                                connection.query(sqlUpdate, params, (err, result) => {
                                    if (err) {
                                        console.error('Erro ao atualizar Contacts:', err);
                                        return;
                                    }
                                    console.log('Dados atualizados com sucesso na tabela Contacts');
                                });

                                return mensagemOpcoes(data);

                            }
                        } catch (error) {
                            console.error('Erro ao consultar chamado:', error);
                            const msgErro = 'Erro ao consultar chamado. Por favor, tente novamente.';
                            await wbot.sendMessage(msg.from, msgErro);
                        }
                    }

                    if (cliente[0].categoria === 'T2' && ticket.status === 'open') {
                        chamado(msg.body).then(mensagem => {
                            // faça algo com a mensagem, como mostrar na tela ou enviar para chat
                            console.log(mensagem);
                        });

                    }
                    // FIM DA CONSULTA DO CHAMADO





                    // CHECANDO SE EXISTE  CHAMADOS EM ABERTO PARA O TECNICO ATUAL
                    if (cliente[0].categoria === 'T3' && ticket.status === 'open' && msg.body === '1') {
                        function mensagemOpcoes() {
                            return `Para prosseguir com a instalação, por favor, nos envie o *número de série* (Serial) da ONU/ONT que será instalado. \n\n_Esse número pode ser encontrado na etiqueta do equipamento._`;
                        }
                        connection.query("UPDATE Contacts SET categoria = 'T4' WHERE number = '" + cliente[0].number + "'");
                        wbot.sendMessage(msg.from, mensagemOpcoes())
                            .then(() => console.log(''))
                            .catch(err => console.error(err));
                    }
                    // TRANSFERINDO PARA TROCA DE EQUIPAMENTO O ATENDIMENTO
                    if (cliente[0].categoria === 'T3' && ticket.status === 'open' && msg.body === '2') {
                        function mensagemOpcoes() {
                            return `Para prosseguir com a troca, por favor, nos envie o *número de série* (Serial) da ONU/ONT que será instalado. \n\n_Esse número pode ser encontrado na etiqueta do equipamento._`;
                        }
                        connection.query("UPDATE Contacts SET categoria = 'T5' WHERE number = '" + cliente[0].number + "'");
                        wbot.sendMessage(msg.from, mensagemOpcoes())
                            .then(() => console.log(''))
                            .catch(err => console.error(err));

                    }


                    // TROCA DE PRODUTO PARA O CLIENTE
                    if (cliente[0].categoria === 'T3' && ticket.status === 'open' && msg.body === '3') {
                        connection.query("UPDATE Contacts SET categoria = 'T8' WHERE number = '" + cliente[0].number + "'");

                        await wbot.sendMessage(msg.from,
                            '*CABO DROP OPTICO*?\n\n' +
                            'Informe a quantidade utilizada do produto acima, caso não tenha utilizado, informar *0*.'
                        );
                    }



                    // TRANSFERINDO PARA O ATENDIMENTO
                    if (cliente[0].categoria === 'T3' && ticket.status === 'open' && msg.body === '4') {
                        atdFisico('2')
                    }


                    if (cliente[0].categoria === 'T3' && ticket.status === 'open' && msg.body === '0') {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                            connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");

                            function mensagem() {
                                return resposta[0].message;
                            }
                            UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });
                            wbot.sendMessage(msg.from, mensagem())
                                .then(() => console.log(''))
                                .catch(err => console.error(err));
                        });
                    }


                    else if (cliente[0].categoria === 'T3' && ticket.status === 'open' && msg.body !== '1' && msg.body !== '2' && msg.body !== '3' && msg.body !== '4' && msg.body !== '0') {
                        function formatarDataBR(dataISO) {
                            if (!dataISO) return '';
                            const data = new Date(dataISO);
                            const dia = String(data.getDate()).padStart(2, '0');
                            const mes = String(data.getMonth() + 1).padStart(2, '0');
                            const ano = data.getFullYear();
                            const horas = String(data.getHours()).padStart(2, '0');
                            const minutos = String(data.getMinutes()).padStart(2, '0');
                            const segundos = String(data.getSeconds()).padStart(2, '0');
                            return `${dia}/${mes}/${ano} ${horas}:${minutos}:${segundos}`;
                        }

                        // Monta mensagem de sucesso com dados do chamado
                        function mensagemOpcoes() {
                            return `Chamado n: ${cliente[0].chamado}\n` +
                                `Assunto: ${cliente[0].assunto}\n` +
                                `Aberto em: ${formatarDataBR(cliente[0].abertura)}\n` +
                                `Status: ${cliente[0].status}\n` +
                                `Nome do Cliente: ${cliente[0].nome}\n` +
                                `Atendente: ${cliente[0].atendente}\n\n` +
                                `1️⃣ Instalar Equipamento Novo\n` +
                                `2️⃣ Trocar Equipamento\n` +
                                `3️⃣ Trocar Produtos\n` +
                                `4️⃣ Falar com Atendente\n` +
                                `\n` +
                                `0️⃣ Encerrar atendimento`;
                        }

                        // Envia mensagem ao usuário
                        await wbot.sendMessage(msg.from, mensagemOpcoes());

                    }



                    if (cliente[0].categoria === 'T3' && ticket.status === 'open' && msg.body === '0') {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                            connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");

                            function mensagem() {
                                return resposta[0].message;
                            }
                            UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });
                            wbot.sendMessage(msg.from, mensagem())
                                .then(() => console.log(''))
                                .catch(err => console.error(err));
                        });
                    }


                    async function buscarEquipamento(idTecnico, serial) {
                        const url = `http://100.64.0.126/dctapi/buscar_equipamentoFromTecnico.php?id_tecnico=${idTecnico}&serial=${serial}`;

                        try {
                            // Faz a requisição GET à API
                            const response = await axios.get(url);
                            const data = response.data;

                            // Verifica se a resposta contém dados válidos
                            if (data && data.length > 0) {
                                var categoria = 'T6'
                                const equipamento = data[0];  // Assume que a resposta é um array com um único objeto
                                connection.query("UPDATE Contacts SET categoria = '" + categoria + "',serial = '" + equipamento.serial + "',id_equipamento = '" + equipamento.id + "' WHERE number = '" + cliente[0].number + "'");

                                // Formatação para enviar a mensagem
                                const mensagem = `Confirma a instalação do equipamento,\n${equipamento.categoria} - ${equipamento.nome} com serial ${equipamento.serial}\npara o cadastro do cliente ${cliente[0].nome}?\n\n` +
                                    `1️⃣ SIM\n` +
                                    `2️⃣ NÃO\n`;

                                // Exibe a mensagem com os dados do equipamento
                                return mensagem;

                            } else {
                                // Caso o equipamento não seja encontrado
                                return `Equipamento com serial ${serial} não encontrado para o técnico *${cliente[0].nome_tecnico}.*`;
                            }
                        } catch (error) {
                            console.error('Erro ao consultar equipamento:', error);
                            return 'Erro ao consultar equipamento. Por favor, tente novamente.';
                        }
                    }


                    if (cliente[0].categoria === 'T4' && ticket.status === 'open') {
                        try {
                            // Converte msg.body para maiúsculas
                            const mensagemMaiuscula = msg.body.toUpperCase();

                            const resultado = await buscarEquipamento(cliente[0].tecnico, mensagemMaiuscula);
                            console.log(resultado);  // Exibe as informações do equipamento
                            await wbot.sendMessage(msg.from, resultado);  // Usando await diretamente
                            console.log('Mensagem enviada com sucesso');
                        } catch (err) {
                            console.error('Erro ao buscar equipamento ou enviar mensagem:', err);
                        }
                    }




                    async function migrarEquipamento(idEquipamento, idCliente) {
                        const url = `http://100.64.0.126/dctapi/migrar_equipamento.php?situacao=cliente&equipamento_id=${idEquipamento}&id_cliente=${idCliente}`;

                        try {
                            // Faz a requisição GET à API
                            const response = await axios.get(url);
                            const data = response.data;

                            // Verifica se a resposta contém dados válidos (assumindo que a resposta seja um objeto)
                            if (data && data.success) {
                                // Retorna o response da migração
                                return `Equipamento migrado com sucesso: ${data.message}`;
                            } else {
                                // Caso haja erro na resposta da migração
                                return `${data.message}`;
                            }
                        } catch (error) {
                            console.error('Erro ao migrar equipamento:', error);
                            return 'Erro ao migrar equipamento. Por favor, tente novamente.';
                        }
                    }

                    if (cliente[0].categoria === 'T6' && ticket.status === 'open') {
                        try {
                            // Verifica o valor de msg.body
                            if (msg.body === '1') {
                                // Se msg.body for 1, realiza a migração do equipamento
                                const resultado = await migrarEquipamento(cliente[0].id_equipamento, cliente[0].id_cliente);
                                await wbot.sendMessage(msg.from, resultado);  // Envia a mensagem para o usuário

                                // Envia a segunda mensagem após 2 segundos
                                setTimeout(async () => {
                                    connection.query("UPDATE Contacts SET categoria = 'T7' WHERE number = '" + cliente[0].number + "'");

                                    await wbot.sendMessage(msg.from,
                                        'Nesta Ordem de Serviço, foi necessário o uso de materiais adicionais, como *CABO DROP OPTICO OPTICO*, *CONECTOR SC/APC VERDE*, *CONECTOR SC/UPC AZUL* ou *SPLITTER OPTICO 1/2*?\n\nPor favor, confirme para atualizarmos o cadastro.\n\n' +
                                        `1️⃣ SIM\n` +
                                        `2️⃣ NÃO\n`
                                    );
                                }, 2500); // 2000 milissegundos = 2 segundos

                            } else if (msg.body === '2') {
                                // Se msg.body for 2, realiza a finalização
                                connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                    if (err) {
                                        console.error('Erro ao buscar mensagem de finalização:', err);
                                        return;
                                    }

                                    // Atualiza o cliente e envia a mensagem de finalização
                                    connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL',bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");

                                    await wbot.sendMessage(msg.from, resposta[0].message);
                                    UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                                    console.log('Finalização realizada com sucesso');
                                });
                            } else {
                                // Caso a resposta seja diferente de 1 ou 2
                                await wbot.sendMessage(msg.from,
                                    'Não entendi sua resposta,\n\n' +
                                    `Confirma a instalação do equipamento?\n\n` +
                                    `1️⃣ SIM\n` +
                                    `2️⃣ NÃO\n\n` +
                                    'Ou envie *#menu* para reiniciar o *Atendimento*.'
                                );

                            }
                        } catch (err) {
                            await wbot.sendMessage(msg.from,
                                'Não entendi sua resposta,\n\n' +
                                `Confirma a instalação do equipamento?\n\n` +
                                `1️⃣ SIM\n` +
                                `2️⃣ NÃO\n\n` +
                                'Ou envie *#menu* para reiniciar o *Atendimento*.'
                            );

                        }
                    }


                    if (cliente[0].categoria === 'T7' && ticket.status === 'open') {
                        if (msg.body === '1') {
                            connection.query("UPDATE Contacts SET categoria = 'T8' WHERE number = '" + cliente[0].number + "'");

                            await wbot.sendMessage(msg.from,
                                '*CABO DROP OPTICO*?\n\n' +
                                'Informe a quantidade utilizada do produto acima, caso não tenha utilizado, informar *0*.'
                            );

                        } else if (msg.body === '2') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                if (err) {
                                    console.error('Erro ao buscar mensagem de finalização:', err);
                                    return;
                                }

                                connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL', plano = 'NULL', login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");

                                await wbot.sendMessage(msg.from, resposta[0].message);
                                UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                                console.log('Finalização realizada com sucesso');
                            });
                        } else {
                            await wbot.sendMessage(msg.from,
                                'Nesta Ordem de Serviço, foi necessário o uso de materiais adicionais, como CABO DROP OPTICO, conector óptico ou fixador de cabo?\n\n' +
                                'Por favor, confirme para atualizarmos o cadastro.\n\n' +
                                `1️⃣ SIM\n` +
                                `2️⃣ NÃO\n`
                            );
                        }
                    }


                    if (cliente[0].categoria === 'T8' && ticket.status === 'open') {
                        if (!isNaN(msg.body) && msg.body.trim() !== '') {
                            connection.query("UPDATE Contacts SET categoria = 'T9', qtd_cabo = '" + msg.body + "' WHERE number = '" + cliente[0].number + "'");
                            await wbot.sendMessage(msg.from,
                                '*CONECTOR SC/APC VERDE*?\n\n' +
                                'Informe a quantidade utilizada do produto acima. Caso não tenha utilizado, informe *0*.'
                            );

                        } else {
                            // Caso a resposta tenha letras ou não seja numérica
                            await wbot.sendMessage(msg.from,
                                `Não entendi sua resposta.\n\nResponda somente com o *número* referente à quantidade utilizada.`
                            );
                        }
                    }


                    if (cliente[0].categoria === 'T9' && ticket.status === 'open') {
                        if (!isNaN(msg.body) && msg.body.trim() !== '') {
                            connection.query("UPDATE Contacts SET categoria = 'T10', qtd_conector_verde = '" + msg.body + "' WHERE number = '" + cliente[0].number + "'");
                            await wbot.sendMessage(msg.from,
                                '*CONECTOR SC/UPC AZUL*?\n\n' +
                                'Informe a quantidade utilizada do produto acima. Caso não tenha utilizado, informe *0*.'
                            );

                        } else {
                            // Caso a resposta tenha letras ou não seja numérica
                            await wbot.sendMessage(msg.from,
                                `Não entendi sua resposta.\n\nResponda somente com o *número* referente à quantidade utilizada.`
                            );
                        }
                    }


                    if (cliente[0].categoria === 'T10' && ticket.status === 'open') {
                        if (!isNaN(msg.body) && msg.body.trim() !== '') {
                            connection.query("UPDATE Contacts SET categoria = 'T11', qtd_conector_azul = '" + msg.body + "' WHERE number = '" + cliente[0].number + "'");
                            await wbot.sendMessage(msg.from,
                                '*SPLITTER OPTICO 1/2*?\n\n' +
                                'Informe a quantidade utilizada do produto acima. Caso não tenha utilizado, informe *0*.'
                            );

                        } else {
                            // Caso a resposta tenha letras ou não seja numérica
                            await wbot.sendMessage(msg.from,
                                `Não entendi sua resposta.\n\nResponda somente com o *número* referente à quantidade utilizada.`
                            );
                        }
                    }

                    // Novo IF para categoria T11, atualizando para T12
                    if (cliente[0].categoria === 'T11' && ticket.status === 'open') {
                        if (!isNaN(msg.body) && msg.body.trim() !== '') {
                            connection.query("UPDATE Contacts SET categoria = 'T12', nome_splitter = 'SPLITTER ÓPTICO 1/2', qtd_splitter = '" + msg.body + "' WHERE number = '" + cliente[0].number + "'");

                            // Resumo com os valores anteriores
                            connection.query("SELECT * FROM Contacts WHERE number = '" + cliente[0].number + "'", async function (err, result) {
                                if (err) {
                                    console.error('Erro ao buscar os dados do cliente:', err);
                                    return;
                                }

                                const clienteData = result[0]; // Dados do cliente
                                const resumo = `Resumo dos *Produtos* utilizados na O.S:
CABO DROP OPTICO: ${clienteData.qtd_cabo}
Conector SC/APC Verde: ${clienteData.qtd_conector_verde}
Conector SC/UPC Azul: ${clienteData.qtd_conector_azul}
Splitter Óptico 1/2: ${clienteData.qtd_splitter}

Por favor, confirme se a lista de materiais está correta antes de prosseguir.\n\n` +
                                    `1️⃣ SIM\n` +
                                    `2️⃣ NÃO`;

                                // Envia a mensagem de resumo com a pergunta de confirmação
                                await wbot.sendMessage(msg.from, resumo);
                            });
                        } else {
                            await wbot.sendMessage(msg.from,
                                `Não entendi sua resposta.\n\nResponda somente com o *número* referente à quantidade utilizada.`
                            );
                        }
                    }




                    if (cliente[0].categoria === 'T12' && ticket.status === 'open') {
                        if (msg.body === '1') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                if (err) {
                                    console.error('Erro ao buscar mensagem de finalização:', err);
                                    return;
                                }

                                const produtos = [];

                                if (cliente[0].qtd_cabo > 0) {
                                    produtos.push({ nome_produto: 'CABO DROP OPTICO', quantidade: cliente[0].qtd_cabo });
                                }
                                if (cliente[0].qtd_conector_verde > 0) {
                                    produtos.push({ nome_produto: 'CONECTOR SC/APC VERDE', quantidade: cliente[0].qtd_conector_verde });
                                }
                                if (cliente[0].qtd_conector_azul > 0) {
                                    produtos.push({ nome_produto: 'CONECTOR SC/UPC AZUL', quantidade: cliente[0].qtd_conector_azul });
                                }
                                if (cliente[0].qtd_splitter > 0) {
                                    produtos.push({ nome_produto: 'SPLITTER ÓPTICO 1/2', quantidade: cliente[0].qtd_splitter });
                                }

                                const axios = require('axios');
                                try {
                                    for (const produto of produtos) {
                                        const params = new URLSearchParams({
                                            nome_tecnico: cliente[0].nome_tecnico.toUpperCase(),
                                            nome_produto: produto.nome_produto.toUpperCase(),
                                            quantidade: produto.quantidade,
                                            id_cliente: cliente[0].id_cliente
                                        });

                                        const url = `http://100.64.0.126/dctapi/movimenta_quantidade_tecnico_produto.php?${params.toString()}`;

                                        const response = await axios.get(url);

                                        if (!response.data.success) {
                                            // Se algum erro na resposta da API, interrompe e envia mensagem
                                            await wbot.sendMessage(msg.from, `Erro ao processar ${produto.nome_produto}: ${response.data.error || 'Erro desconhecido'}`);
                                            console.error(`Erro na API para ${produto.nome_produto}:`, response.data);
                                            return; // Sai da função para não continuar
                                        }

                                        console.log(`Resposta para ${produto.nome_produto}:`, response.data);
                                    }

                                    // Se todas chamadas deram sucesso, atualiza e finaliza
                                    connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL', plano = 'NULL', login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");

                                    await wbot.sendMessage(msg.from, 'Ordem de serviço atualizada com sucesso.\n\n' + resposta[0].message);
                                    UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                                    console.log('Finalização realizada com sucesso');

                                } catch (apiError) {
                                    console.error('Erro na chamada API:', apiError);
                                    await wbot.sendMessage(msg.from, 'Erro ao processar a atualização dos produtos.');
                                }
                            });

                        } else if (msg.body === '2') {
                            // Se msg.body for 2, realiza a finalização
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                if (err) {
                                    console.error('Erro ao buscar mensagem de finalização:', err);
                                    return;
                                }

                                // Atualiza o cliente e envia a mensagem de finalização
                                connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL', plano = 'NULL', login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");

                                await wbot.sendMessage(msg.from, resposta[0].message);
                                UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                                console.log('Finalização realizada com sucesso');
                            });
                        } else {
                            // Caso a resposta seja diferente de 1 ou 2
                            await wbot.sendMessage(msg.from,
                                `Não entendi sua resposta.\n\nPor favor, confirme se a lista de materiais está correta antes de prosseguir.\n\n` +


                                `1️⃣ SIM\n` +
                                `2️⃣ NÃO`
                            );
                        }
                    }



                    // Verificando se a categoria é 'T5' (aguardando a consulta de serial para troca de equipamento)
                    if (cliente[0].categoria === 'T5' && ticket.status === 'open') {
                        // Função para realizar a consulta se o serial informado está associado ao técnico
                        async function verificarSerialAssociado(serial, idTecnico) {
                            const url = `http://100.64.0.126/dctapi/buscar_equipamentoFromTecnico.php?id_tecnico=${idTecnico}&serial=${serial}`;

                            try {
                                // Realiza a consulta no backend para verificar o serial
                                const response = await axios.get(url);
                                const data = response.data;

                                // Verifica se o serial foi encontrado e está associado ao técnico
                                if (data && data.length > 0) {
                                    // Se o serial estiver associado ao técnico, realiza o update na tabela Contacts
                                    connection.query("UPDATE Contacts SET serial = ?, categoria = 'T14' WHERE number = ?", [serial, cliente[0].number], function (err) {
                                        if (err) {
                                            console.error('Erro ao atualizar serial e categoria:', err);
                                            wbot.sendMessage(msg.from, `Erro ao atualizar o número de série. Tente novamente.`);
                                            return;
                                        }

                                        // Se o update for bem-sucedido, gera a mensagem de confirmação
                                        const equipamento = data[0]; // Assume que a resposta é um array com um único objeto
                                        const mensagemConfirmacao = `Confirma a troca do equipamento,\n` +
                                            `${equipamento.categoria} - ${equipamento.nome} com serial ${equipamento.serial}\n` +
                                            `para o cadastro do cliente *${cliente[0].nome}*?\n\n` +
                                            `⿡ SIM\n` +
                                            `⿢ NÃO`;

                                        // Envia a mensagem de confirmação para o cliente
                                        wbot.sendMessage(msg.from, mensagemConfirmacao);
                                        console.log('Mensagem de confirmação de troca enviada');
                                    });
                                } else {
                                    // Caso o serial não seja encontrado ou não esteja associado ao técnico
                                    wbot.sendMessage(msg.from, `O número de série informado não está associado ao técnico. Por favor, verifique o serial e tente novamente.`);
                                }

                            } catch (error) {
                                console.error('Erro ao verificar o serial:', error);
                                wbot.sendMessage(msg.from, `Erro ao verificar o serial. Tente novamente.`);
                            }
                        }

                        // Aguardar o serial do novo equipamento
                        const serial = msg.body; // O serial informado pelo cliente
                        verificarSerialAssociado(serial, cliente[0].tecnico);
                    }






























                    // Verificando se a categoria é 'T14' e se a mensagem do cliente não é '1' ou '2'
                    if (cliente[0].categoria === 'T14' && ticket.status === 'open') {
                        // Caso o cliente digite algo que não seja '1' ou '2', reenviar a mensagem de confirmação
                        if (msg.body !== '1' && msg.body !== '2') {
                            const mensagemConfirmacao = `Confirma a troca do equipamento,\n` +
                                `ONT - HUAWEI com serial ${cliente[0].serial}\n` +  // Usando o serial do cliente
                                `para o cadastro do cliente *${cliente[0].nome}*?\n\n` + // Usando o nome do cliente
                                `⿡ SIM\n` +
                                `⿢ NÃO`;

                            // Envia a mensagem de confirmação novamente
                            await wbot.sendMessage(msg.from, mensagemConfirmacao);
                        }

                        // Se a resposta for '1', realiza o procedimento de troca de equipamento
                        if (msg.body === '1') {
                            async function realizarTrocaEquipamento(idTecnico, idCliente, serial) {
                                const url = `http://100.64.0.126/dctapi/trocar_equipamento.php?situacao=troca&id_tecnico=${idTecnico}&id_cliente=${idCliente}&serial=${serial}`;

                                console.log('Requisição para URL:', url); // Log da URL gerada

                                try {
                                    // Faz a requisição para a URL da API
                                    const response = await axios.get(url);

                                    console.log('Resposta da API:', response.data); // Log da resposta

                                    if (response.data && response.data.status === 'success') {
                                        // Se a troca for bem-sucedida
                                        await wbot.sendMessage(msg.from, `Equipamento trocado com sucesso!`);

                                        // Atualiza a categoria para a próxima fase, por exemplo, T15
                                        await connection.query("UPDATE Contacts SET categoria = 'T15' WHERE number = ?", [cliente[0].number]);

                                        // Envia mensagem final após a troca
                                        setTimeout(async () => {
                                            connection.query("UPDATE Contacts SET categoria = 'T7' WHERE number = '" + cliente[0].number + "'");

                                            await wbot.sendMessage(msg.from,
                                                'Nesta Ordem de Serviço, foi necessário o uso de materiais adicionais, como *CABO DROP OPTICO OPTICO*, *CONECTOR SC/APC VERDE*, *CONECTOR SC/UPC AZUL* ou *SPLITTER OPTICO 1/2*?\n\nPor favor, confirme para atualizarmos o cadastro.\n\n' +
                                                `1️⃣ SIM\n` +
                                                `2️⃣ NÃO\n`
                                            );
                                        }, 2500); // 2000 milissegundos = 2 segundos
                                    } else {
                                        await wbot.sendMessage(msg.from, `Erro ao realizar a troca do equipamento. Por favor, tente novamente.`);
                                    }

                                } catch (error) {
                                    console.error('Erro ao realizar a troca de equipamento:', error);
                                    await wbot.sendMessage(msg.from, `Erro ao processar a troca de equipamento. Tente novamente.`);
                                }
                            }

                            // Chama a função de realizar a troca com os parâmetros do cliente
                            await realizarTrocaEquipamento(cliente[0].tecnico, cliente[0].id_cliente, cliente[0].serial);
                        }

                        // Se a resposta for '2', realiza a finalização do atendimento
                        if (msg.body === '2') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                if (err) {
                                    console.error('Erro ao buscar mensagem de finalização:', err);
                                    return;
                                }

                                // Atualiza o cliente e envia a mensagem de finalização
                                connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL', plano = 'NULL', login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = ?", [cliente[0].number]);

                                // Envia a resposta de finalização para o cliente
                                await wbot.sendMessage(msg.from, resposta[0].message);

                                // Atualiza o status do ticket para "closed"
                                UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                                console.log('Finalização realizada com sucesso');
                            });
                        }
                    }




                    // PAREI PELAQUI NA CENTRAL DO TECNICO                    //

                    // ###################### RESERVADO PARA OS MENUS DA CDNTV ###################

                    if (cliente[0].categoria === 'N1') {

                        if (msg.body == '1') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'OP1-CDNTV'", async function (err, resposta) {
                                await wbot.sendMessage(msg.from, resposta[0].message);

                            });
                        }
                        else if (msg.body == '2') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'OP2-CDNTV'", async function (err, resposta) {
                                await wbot.sendMessage(msg.from, resposta[0].message);

                            });
                        }
                        else if (msg.body == '3') {
                            connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                            atdFisico('1');
                        }

                        else if (msg.body == '0') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                                await wbot.sendMessage(msg.from, resposta[0].message);
                                UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });
                            });
                        }




                        else {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'MENU-CDNTV'", async function (err, resposta) {
                                await wbot.sendMessage(msg.from, resposta[0].message);

                            });
                        }
                    }
                    // ############################ FIM DA CDNTV #################################





                    // ************************************************ CENTRAL DO ASSINANTE ************************************************
                    if (ticket.status === 'open' && msg.body === '1' && cliente[0].categoria === '3') {
                        if (cliente[0].titulo === 'NULL') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                                await wbot.sendMessage(msg.from, "Não foi achada nenhuma cobrança em aberto para o CPF/CNPJ informado!\n\n" + resposta[0].message);
                                UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                            });
                        }
                        else {
                            connection.query("UPDATE Contacts SET categoria = '4' WHERE number = '" + cliente[0].number + "'");
                            await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Linha Digitavel*\n2️⃣ *PIX Copia/Cola*\n3️⃣ *Link do Boleto*\n\n0️⃣ *Voltar*");
                        }
                    }





                    // ******************************** DESBLOQUEIO CONFIANÇA ************************************                               
                    if (ticket.status === 'open' && msg.body === '2' && cliente[0].categoria === '3' && cliente[0].bloqueado === 'Bloqueado') {
                        const url = 'http://100.64.0.126/ura/desbloquear.php?id_cliente=';

                        axios.get(url + cliente[0].clienteId).then(function (resposta) {

                            if (resposta.data.sucesso === 1) {
                                connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, respost) {
                                    connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                                    await wbot.sendMessage(msg.from, "Seu acesso foi *" + resposta.data.mensagem + "*\n\n" + respost[0].message);
                                    UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                                });

                            }
                            else {
                                connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                                console.log("negado")
                                wbot.sendMessage(msg.from, resposta.data.mensagem);
                                atdFisico('2')
                            }
                        })
                    }

                    // ******************************** ENCAMINHANDO PARA ATENDIMENTO FISICO ************************************                               
                    if (ticket.status === 'open' && msg.body === '2' && cliente[0].categoria === '3' && cliente[0].bloqueado === 'Ativo') {
                        atdFisico('1')

                    } else
                        if (ticket.status === 'open' && msg.body === '3' && cliente[0].categoria === '3' && cliente[0].bloqueado === 'Ativo') {
                            atdFisico('2')
                        } else
                            if (ticket.status === 'open' && msg.body === '4' && cliente[0].categoria === '3' && cliente[0].bloqueado === 'Ativo') {
                                atdFisico('3')
                            }
                    // *********************************************************************************************************                               


                    // ******************************** ENCAMINHANDO PARA ATENDIMENTO FISICO ************************************                               
                    if (ticket.status === 'open' && msg.body === '3' && cliente[0].categoria === '3' && cliente[0].bloqueado === 'Bloqueado') {
                        atdFisico('2')

                    }
                    // *********************************************************************************************************                               


                    else if (
                        ticket.status === 'open' &&
                        !["1", "2", "3", "0"].includes(msg.body.trim()) &&
                        cliente[0].categoria === '3' &&
                        cliente[0].bloqueado === 'Bloqueado'
                    ) {
                        const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-CLIENTE-ERR1.mp3", { encoding: "base64" });
                        const media = new MessageMedia("audio/mpeg", audio);
                        await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });

                        first(function () {
                            second();
                        });

                        function first(callback) {
                            setTimeout(function () {
                                console.log('Chamando o callback...');
                                callback();
                            }, 5000);
                        }

                        async function second() {
                            console.log('Função `second` invocada.');
                            await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente['0'].nome.trim() + "*\nLogin: *" + cliente['0'].login + "*\nPlano: *" + cliente['0'].plano + "*\nStatus: *" + cliente['0'].bloqueado + "*\n\nINFORMAÇÕES DE CONEXÃO:\nStatus: *" + cliente['0'].conectado + "*\nDia: *" + cliente['0'].acctstarttime + "*\n\n1️⃣ *Segunda Via Fatura*\n2️⃣ *Desbloqueio Confiança*\n3️⃣ *Falar com Financeiro*\n\n0️⃣ *Encerrar Atendimento*");
                        }
                    }





                    // ********************************* OPÇÂO INVALIDA ****************************************************************                               
                    else if (ticket.status === 'open' && msg.body > 4 && msg.body < 10 && cliente[0].categoria === '3' && cliente[0].bloqueado === 'Ativo') {
                        //              connection.query("UPDATE Contacts SET categoria = '3' WHERE number = '"+cliente[0].number+"'");
                        const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-CLIENTE-ERR1.mp3", { encoding: "base64", });
                        const media = new MessageMedia("audio/mpeg", audio);
                        await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                        UpdateTicketService_1.default({ ticketData: { userId: '2', status: "open" }, ticketId: ticket.id });

                        first(function () {
                            second();
                            // Chame outras funções aqui...
                        });

                        function first(callback) {
                            setTimeout(function () {
                                console.log('Chamando o callback...');
                                callback();
                            }, 5000);
                        }

                        async function second() {
                            console.log('Função `second` invocada.');
                            await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");

                        }
                    }



                    // *********************************************************************************************************                               
                    else if (ticket.status === 'open' && msg.body > 10 && cliente[0].categoria === '3' && cliente[0].bloqueado === 'Ativo') {
                        //              connection.query("UPDATE Contacts SET categoria = '3' WHERE number = '"+cliente[0].number+"'");
                        const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-CLIENTE-ERR1.mp3", { encoding: "base64", });
                        const media = new MessageMedia("audio/mpeg", audio);
                        await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                        UpdateTicketService_1.default({ ticketData: { userId: '2', status: "open" }, ticketId: ticket.id });

                        first(function () {
                            second();
                            // Chame outras funções aqui...
                        });

                        function first(callback) {
                            setTimeout(function () {
                                console.log('Chamando o callback...');
                                callback();
                            }, 5000);
                        }

                        async function second() {
                            console.log('Função `second` invocada.');
                            await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");

                        }
                    }


                    else if (ticket.status === 'open' && msg.body > '2' && msg.body < '9' && cliente[0].categoria === '3') {
                        //              connection.query("UPDATE Contacts SET categoria = '3' WHERE number = '"+cliente[0].number+"'");
                        const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-CLIENTE-ERR1.mp3", { encoding: "base64", });
                        const media = new MessageMedia("audio/mpeg", audio);
                        await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                        UpdateTicketService_1.default({ ticketData: { userId: '2', status: "open" }, ticketId: ticket.id });

                        first(function () {
                            second();
                            // Chame outras funções aqui...
                        });

                        function first(callback) {
                            setTimeout(function () {
                                console.log('Chamando o callback...');
                                callback();
                            }, 5000);
                        }

                        async function second() {
                            console.log('Função `second` invocada.');
                            await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");

                        }
                    }

                    // ************************************************ FINALIZA ATENDIMENTO ************************************************
                    else if (ticket.status === 'open' && msg.body === '0' && cliente[0].categoria === '3') {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                            connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                            UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });
                            await wbot.sendMessage(msg.from, resposta[0].message);
                        });
                    }
                    // ***************************************** CENTRAL DO ASSINANTE SEM RESPOSTA ********************************************


                    else if (ticket.status === 'open' && msg.body > '9' && cliente[0].categoria === '3') {
                        if (cliente[0].bloqueado === 'Bloqueado') {
                            const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-CLIENTE-ERR1.mp3", { encoding: "base64", });
                            const media = new MessageMedia("audio/mpeg", audio);
                            await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                            UpdateTicketService_1.default({ ticketData: { userId: '2', status: "open" }, ticketId: ticket.id });

                            first(function () {
                                second();
                                // Chame outras funções aqui...
                            });

                            function first(callback) {
                                setTimeout(function () {
                                    console.log('Chamando o callback...');
                                    callback();
                                }, 5000);
                            }

                            async function second() {
                                console.log('Função `second` invocada.');
                                await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");

                            }

                        }
                        else {
                            const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-CLIENTE-ERR1.mp3", { encoding: "base64", });
                            const media = new MessageMedia("audio/mpeg", audio);
                            await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                            UpdateTicketService_1.default({ ticketData: { userId: '2', status: "open" }, ticketId: ticket.id });

                            first(function () {
                                second();
                                // Chame outras funções aqui...
                            });

                            function first(callback) {
                                setTimeout(function () {
                                    console.log('Chamando o callback...');
                                    callback();
                                }, 5000);
                            }

                            async function second() {
                                console.log('Função `second` invocada.');
                                await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");

                            }
                        }

                    }

                    else if (ticket.status === 'open' && msg.body > '3' && msg.body < '9' && cliente[0].categoria === '4') {
                        await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Linha Digitavel*\n2️⃣ *PIX Copia/Cola*\n3️⃣ *Link do Boleto*\n\n0️⃣ *Voltar*");
                        console.log('*M E N U    C L I E N T E*');

                    }

                    // ***************************************** CENTRAL DO ASSINANTE CODIGO DE BARRAS ********************************************
                    else if (msg.body === '1' && cliente[0].categoria === '4') {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {

                            var venc = cliente[0].data_vencimento.replace(/[^0-9]/g, '');
                            var dia = venc.substr(6, 2);
                            var mes = venc.substr(4, 2);
                            var ano = venc.substr(0, 4);

                            var data_venc = dia + '/' + mes + '/' + ano;
                            await wbot.sendMessage(msg.from, "Segue os dados do seu boleto:\n\nVencimento: " + data_venc + "\nValor R$: " + cliente[0].valor + "\n\nAqui vai seu código de barras...");
                            await wbot.sendMessage(msg.from, cliente[0].linha_digitavel);
                            await wbot.sendMessage(msg.from, resposta[0].message);
                        });
                        first(function () {
                            second();
                            // Chame outras funções aqui...
                        });

                        function first(callback) {
                            setTimeout(function () {
                                console.log('Chamando o callback...');
                                callback();
                            }, 1000);
                        }

                        function second() {
                            console.log('Função `second` invocada.');
                            connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                            UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                        }
                    }
                    // ***************************************** CENTRAL DO ASSINANTE COPIA E COLA ********************************************
                    else if (ticket.status === 'open' && msg.body === '2' && cliente[0].categoria === '4') {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {

                            var venc = cliente[0].data_vencimento.replace(/[^0-9]/g, '');
                            var dia = venc.substr(6, 2);
                            var mes = venc.substr(4, 2);
                            var ano = venc.substr(0, 4);

                            var data_venc = dia + '/' + mes + '/' + ano;
                            await wbot.sendMessage(msg.from, "Segue os dados do seu boleto:\n\nVencimento: " + data_venc + "\nValor R$: " + cliente[0].valor + "\n\nAqui vai seu copia e cola do PIX...");
                            await wbot.sendMessage(msg.from, cliente[0].copiacola);
                            await wbot.sendMessage(msg.from, resposta[0].message);

                        });
                        first(function () {
                            second();
                            // Chame outras funções aqui...
                        });

                        function first(callback) {
                            setTimeout(function () {
                                console.log('Chamando o callback...');
                                callback();
                            }, 1000);
                        }

                        function second() {
                            console.log('Função `second` invocada.');
                            connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                            UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                        }
                    }
                    // ***************************************** CENTRAL DO ASSINANTE LINK ********************************************
                    else if (ticket.status === 'open' && msg.body === '3' && cliente[0].categoria === '4') {
                        connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {

                            var venc = cliente[0].data_vencimento.replace(/[^0-9]/g, '');
                            var dia = venc.substr(6, 2);
                            var mes = venc.substr(4, 2);
                            var ano = venc.substr(0, 4);

                            var data_venc = dia + '/' + mes + '/' + ano;
                            await wbot.sendMessage(msg.from, "Segue os dados do seu boleto:\n\nVencimento: " + data_venc + "\nValor R$: " + cliente[0].valor + "\n\nPara visualizar o boleto clique no link abaixo:\n\nhttps://skynetfibra.net.br/boleto/boleto.hhvm?titulo=" + cliente[0].titulo + "&contrato=" + cliente[0].login + "\n\n" + resposta[0].message);
                        });
                        first(function () {
                            second();
                            // Chame outras funções aqui...
                        });

                        function first(callback) {
                            setTimeout(function () {
                                console.log('Chamando o callback...');
                                callback();
                            }, 8000);
                        }

                        function second() {
                            console.log('Função `second` invocada.');
                            connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                            UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                        }
                    }

                    // ************************************************ VOLTAR PARA CENTRAL ************************************************
                    else if (ticket.status === 'open' && msg.body === '0' && cliente[0].categoria === '4') {
                        connection.query("UPDATE Contacts SET categoria = '3' WHERE number = '" + contact.number + "'");
                        await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Segunda Via de Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");
                    }
                    // ***************************************** CENTRAL DO ASSINANTE SEM RESPOSTA ********************************************
                    else if (ticket.status === 'open' && msg.body > '9' && cliente[0].categoria === '4') {
                        await wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome + "*\nLogin: *" + cliente[0].login + "*\nPlano: *" + cliente[0].plano + "*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Linha Digitavel*\n2️⃣ *PIX Copia/Cola*\n3️⃣ *Link do Boleto*\n\n0️⃣ *Voltar*");
                    }

                    // INFORMA CPF PRA CONSULTA
                    if (msg.body !== '#menu' && cliente[0].categoria === '2') {
                        ConsultaCliente(msg.body.replace(/[^0-9]/g, ''), cliente[0].id)
                    }

                    /// ########################## CAMADA QUE TRATA A ESCOLHA DO CONTRATO ############################
                    if (cliente[0].categoria === '6') {
                        if (msg.body === '1') {
                            console.log("Escolheu MKAUTH: " + cliente[0].cpfcnpj)
                            SelecionaMkAuth(cliente[0].cpfcnpj)
                        }
                        else if (msg.body === '2') {
                            console.log("Escolheu GPS " + cliente[0].cpfcnpj)
                            SelecionaGps(cliente[0].cpfcnpj)

                        }
                        else {

                            console.log('deve exibir o menu contrato')
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'MENU-INFO-CONTRATOS'", async function (err, resposta) {
                                await wbot.sendMessage(msg.from, resposta[0].message);
                            });
                        }

                    }


                    /// ########################## FIM DA CAMADA QUE TRATA A ESCOLHA DO CONTRATO ############################





                    /// ########################## CAMADA QUE TRATA SETOR DE GPS ############################
                    if (cliente[0].categoria === '7') {
                        if (msg.body === '1') {
                            console.log("Escolheu 2Via")
                            if (cliente[0].titulo === 'null') {
                                connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                    await wbot.sendMessage(msg.from, "Não foi achada nenhuma cobrança em aberto para o CPF/CNPJ informado!\n\n" + resposta[0].message);
                                    UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });
                                });
                            }
                            else {

                                connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {

                                    var venc = cliente[0].data_vencimento.replace(/[^0-9]/g, '');
                                    var dia = venc.substr(6, 2);
                                    var mes = venc.substr(4, 2);
                                    var ano = venc.substr(0, 4);

                                    var data_venc = dia + '/' + mes + '/' + ano;
                                    await wbot.sendMessage(msg.from, "Segue os dados do seu boleto:\n\nVencimento: " + data_venc + "\nValor R$: " + cliente[0].valor + "\n\nLink do boleto:\n" + cliente[0].linha_digitavel + "\n\nLink do PIX:\nhttps://skynetfibra.net.br/pix/?titgps=" + cliente[0].titulo + "\n\n" + resposta[0].message);
                                });
                                first(function () {
                                    second();
                                    // Chame outras funções aqui...
                                });

                                function first(callback) {
                                    setTimeout(function () {
                                        console.log('Chamando o callback...');
                                        callback();
                                    }, 1000);
                                }

                                function second() {
                                    console.log('Função `second` invocada.');
                                    connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                                    UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });

                                }






















                            }
                        }
                        else if (msg.body === '2') {
                            console.log("Escolheu Atendimento Comercial")
                            atdFisico('1');
                        }
                        else if (msg.body === '3') {
                            console.log("Escolheu Atendimento Financeiro")
                            atdFisico('2');
                        }
                        else if (msg.body === '4') {
                            console.log("Escolheu Atendimento Suporte")
                            atdFisico('1');
                        }
                        else if (msg.body === '0') {
                            console.log("Escolheu Finaliza Atendimento")

                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-FINALIZAR'", async function (err, resposta) {
                                connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                                await wbot.sendMessage(msg.from, resposta[0].message);
                                UpdateTicketService_1.default({ ticketData: { status: "closed" }, ticketId: ticket.id });
                            });

                        }
                        else {
                            wbot.sendMessage(msg.from, "*M E N U    C L I E N T E*\n\n*" + cliente[0].nome.trim() + "*\nLogin: *" + cliente[0].login + "*\nPlano: *Plataforma GPS*\nStatus: *" + cliente[0].bloqueado + "*\n\n1️⃣ *Segunda Via Fatura*\n2️⃣ *Falar com Comercial*\n3️⃣ *Falar com Financeiro*\n4️⃣ *Falar com Suporte*\n\n0️⃣ *Encerrar Atendimento*");

                        }

                    }


                    /// ########################## FIM DA CAMADA QUE TRATA SETOR DE GPS ############################




                    if (cliente[0].categoria === '1') {

                        // INFORMA QUE É CLIENTE SOLICITA CPF OP 1 - SET CATEGORIA = 2                        
                        if (ticket.status === 'open' && msg.body === '1')
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-INFO-CPF'", async function (err, resposta) {
                                connection.query("UPDATE Contacts SET categoria = '2' WHERE number = '" + cliente[0].number + "'");
                                await wbot.sendMessage(msg.from, resposta[0].message);
                            });
                        // SOLICITA PLANOS                         
                        else if (ticket.status === 'open' && msg.body === '2') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-PLANOS'", async function (err, resposta) {
                                const image = fs.readFileSync("/home/deploy/dct/financeiro/" + resposta[0].url, { encoding: "base64" });
                                const media_ = new MessageMedia("image/jpeg", image);
                                const caption = resposta[0].message;
                                await wbot.sendMessage(msg.from, media_, { caption: caption });
                                //                                await wbot.sendMessage(msg.from, resposta[0].message);
                                const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-PLANOS.mp3", { encoding: "base64", });
                                const media = new MessageMedia("audio/mpeg", audio);
                                wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });

                            });
                            first(function () {
                                second();
                            });

                            function first(tempo) {
                                setTimeout(function () {
                                    console.log('Chamando o callback...');
                                    tempo();
                                }, 5000);
                            }

                            function second() {
                                atdFisico('1');

                            }

                        }


                        // RESERVADO PARA CDNTV
                        // SOLICITA CDNTV                         
                        else if (ticket.status === 'open' && msg.body === '3') {
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'MENU-CDNTV'", async function (err, resposta) {
                                await wbot.sendMessage(msg.from, resposta[0].message);
                            });
                            connection.query("UPDATE Contacts SET categoria = 'N1' WHERE number = '" + cliente[0].number + "'");
                        }











                        else if (ticket.status === 'open' && cliente[0].tentativas === '0') {

                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-INICIO-ERR1'", async function (err, resposta) {
                                const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-INICIAL-ERR1.mp3", { encoding: "base64", });
                                const media = new MessageMedia("audio/mpeg", audio);
                                await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                                connection.query("UPDATE Contacts SET tentativas = '1' WHERE number = '" + cliente[0].number + "'");
                                first(function () {
                                    second();
                                    // Chame outras funções aqui...
                                });

                                function first(callback) {
                                    setTimeout(function () {
                                        console.log('Chamando o callback...');
                                        callback();
                                    }, 5000);
                                }

                                async function second() {
                                    console.log('Função `second` invocada.');
                                    await wbot.sendMessage(msg.from, resposta[0].message);
                                }




                            });
                        }
                        else if (msg.body !== '#menu' && ticket.status === 'open' && cliente[0].tentativas === '1') {
                            const audio = fs.readFileSync("/home/deploy/dct/financeiro/assets/audioBot/MENU-INICIAL-ERR2.mp3", { encoding: "base64", });
                            const media = new MessageMedia("audio/mpeg", audio);
                            await wbot.sendMessage(msg.from, media, { sendAudioAsVoice: true });
                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-INICIO-ERR2'", async function (err, resposta) {
                                connection.query("UPDATE Contacts SET tentativas = '2' WHERE number = '" + cliente[0].number + "'");
                                first(function () {
                                    second();
                                    // Chame outras funções aqui...
                                });

                                function first(callback) {
                                    setTimeout(function () {
                                        console.log('Chamando o callback...');
                                        callback();
                                    }, 5000);
                                }

                                async function second() {
                                    console.log('Função `second` invocada.');
                                    await wbot.sendMessage(msg.from, resposta[0].message);
                                }

                            });
                        }

                        else if (msg.body !== '#menu' && ticket.status === 'open' && cliente[0].tentativas === '2') {

                            connection.query("SELECT * FROM Chatbot WHERE shortcut = 'BOT-INICIO-ERRT'", async function (err, resposta) {
                                connection.query("UPDATE Contacts SET categoria = '0', tentativas = '0', nome = 'NULL',plano = 'NULL',login = 'NULL', bloqueado = 'NULL', cpfcnpj = 'NULL', titulo = 'NULL', linha_digitavel = 'NULL', copiacola = 'NULL', valor = 'NULL', data_vencimento = 'NULL' WHERE number = '" + cliente[0].number + "'");
                                atdFisico('1');


                            });
                        }






                    }

                }
            })
        }
        /**********************************************************************************************************/
        if (msg.type === "call_log" && callSetting === "disabled") {
            const sentMessage = yield wbot.sendMessage(`${contact.number}@c.us`, "*Mensagem Automática:*\nAs chamadas de voz e vídeo estão desabilitas para esse WhatsApp, favor enviar uma mensagem de texto. Obrigado");
            yield verifyMessage(sentMessage, ticket, contact);
        }
    }
    catch (err) {
        Sentry.captureException(err);
        logger_1.logger.error(`Error handling whatsapp message: Err: ${err}`);
    }
});
exports.handleMessage = handleMessage;
const handleMsgAck = (msg, ack) => __awaiter(void 0, void 0, void 0, function* () {
    yield new Promise(r => setTimeout(r, 500));
    const io = socket_1.getIO();
    try {
        const messageToUpdate = yield Message_1.default.findByPk(msg.id.id, {
            include: [
                "contact",
                {
                    model: Message_1.default,
                    as: "quotedMsg",
                    include: ["contact"]
                }
            ]
        });
        if (!messageToUpdate) {
            return;
        }
        yield messageToUpdate.update({ ack });
        io.to(messageToUpdate.ticketId.toString()).emit("appMessage", {
            action: "update",
            message: messageToUpdate
        });
    }
    catch (err) {
        Sentry.captureException(err);
        logger_1.logger.error(`Error handling message ack. Err: ${err}`);
    }
});
const wbotMessageListener = (wbot) => {
    wbot.on("message_create", (msg) => __awaiter(void 0, void 0, void 0, function* () {
        handleMessage(msg, wbot);
    }));
    wbot.on("media_uploaded", (msg) => __awaiter(void 0, void 0, void 0, function* () {
        handleMessage(msg, wbot);
    }));
    wbot.on("message_ack", (msg, ack) => __awaiter(void 0, void 0, void 0, function* () {
        handleMsgAck(msg, ack);
    }));
};
exports.wbotMessageListener = wbotMessageListener;
