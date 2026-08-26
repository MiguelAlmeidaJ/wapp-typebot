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
Object.defineProperty(exports, "__esModule", { value: true });
exports.useMultiFileAuthState = void 0;
const baileys_1 = require("@whiskeysockets/baileys");
const cache_1 = require("../libs/cache");
const logger_1 = require("../utils/logger");
const useMultiFileAuthState = (whatsapp) => __awaiter(void 0, void 0, void 0, function* () {
    const writeData = (data, file) => __awaiter(void 0, void 0, void 0, function* () {
        try {
            yield cache_1.cacheLayer.set(`sessions:${whatsapp.id}:${file}`, JSON.stringify(data, baileys_1.BufferJSON.replacer));
        }
        catch (error) {
            console.log("writeData error", error);
            return null;
        }
    });
    const readData = (file) => __awaiter(void 0, void 0, void 0, function* () {
        try {
            const data = yield cache_1.cacheLayer.get(`sessions:${whatsapp.id}:${file}`);
            if (data) {
                return JSON.parse(data, baileys_1.BufferJSON.reviver);
            }
            return null;
        }
        catch (error) {
            console.log("Read data error", error);
            return null;
        }
    });
    const removeData = (file) => __awaiter(void 0, void 0, void 0, function* () {
        try {
            yield cache_1.cacheLayer.del(`sessions:${whatsapp.id}:${file}`);
        }
        catch (error) {
            console.log("removeData", error);
        }
    });
    const creds = (yield readData("creds")) || (0, baileys_1.initAuthCreds)();
    return {
        state: {
            creds,
            keys: {
                get: (type, ids) => __awaiter(void 0, void 0, void 0, function* () {
                    const data = {};
                    for (let id of ids) {
                        try {
                            let value = yield readData(`${type}-${id}`);
                            if (type === "app-state-sync-key") {
                                value = baileys_1.proto.Message.AppStateSyncKeyData.fromObject(value);
                            }
                            data[id] = value;
                        }
                        catch (error) {
                            logger_1.logger.error(`useMultiFileAuthState (69) -> error: ${error.message}`);
                            logger_1.logger.error(`useMultiFileAuthState (72) -> stack: ${error.stack}`);
                        }
                    }
                    return data;
                }),
                set: (data) => __awaiter(void 0, void 0, void 0, function* () {
                    const tasks = [];
                    // eslint-disable-next-line no-restricted-syntax, guard-for-in
                    for (const category in data) {
                        // eslint-disable-next-line no-restricted-syntax, guard-for-in
                        for (const id in data[category]) {
                            const value = data[category][id];
                            const file = `${category}-${id}`;
                            tasks.push(value ? writeData(value, file) : removeData(file));
                        }
                    }
                    yield Promise.all(tasks);
                })
            }
        },
        saveCreds: () => {
            return writeData(creds, "creds");
        }
    };
});
exports.useMultiFileAuthState = useMultiFileAuthState;
