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
const Contact_1 = __importDefault(require("../../models/Contact"));
const AppError_1 = __importDefault(require("../../errors/AppError"));

// Função para excluir um único contato
const DeleteContactService = (id) => __awaiter(void 0, void 0, void 0, function* () {
    const contact = yield Contact_1.default.findOne({
        where: { id }
    });
    if (!contact) {
        throw new AppError_1.default("ERR_NO_CONTACT_FOUND", 404);
    }
    yield contact.destroy();
});

// Função para excluir contatos, seja um único ou todos
const DeleteContacts = (id) => __awaiter(void 0, void 0, void 0, function* () {
    if (id === 'all') {
        // Se o id for 'all', exclui todos os contatos
        const contacts = yield Contact_1.default.findAll();
        if (contacts.length === 0) {
            throw new AppError_1.default("ERR_NO_CONTACTS_FOUND", 404);
        }

        // Excluir todos os contatos um por um usando a lógica já existente
        for (let contact of contacts) {
            yield DeleteContactService(contact.id); // Chama a função de exclusão para cada contato
        }
    } else {
        // Caso contrário, exclui o contato com o ID específico
        yield DeleteContactService(id);
    }
});

exports.default = DeleteContacts;
