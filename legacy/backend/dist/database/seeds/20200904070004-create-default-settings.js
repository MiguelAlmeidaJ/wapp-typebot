"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
module.exports = {
    up: (queryInterface) => {
        return queryInterface.bulkInsert("Settings", [
            {
                key: "userCreation",
                value: "enabled",
                createdAt: new Date(),
                updatedAt: new Date()
            },
            {
                key: "call",
                value: "enabled",
                createdAt: new Date(),
                updatedAt: new Date()
            },
            {
                key: "timeCreateNewTicket",
                value: "43200",
                createdAt: new Date(),
                updatedAt: new Date()
            },
            {
                key: "CheckMsgIsGroup",
                value: "enabled",
                createdAt: new Date(),
                updatedAt: new Date()
            }
        ], {});
    },
    down: (queryInterface) => {
        return queryInterface.bulkDelete("Settings", {});
    }
};
