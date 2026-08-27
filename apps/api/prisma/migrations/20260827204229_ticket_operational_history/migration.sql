-- CreateTable
CREATE TABLE `TicketEvent` (
    `id` CHAR(36) NOT NULL,
    `companyId` CHAR(36) NOT NULL,
    `ticketId` CHAR(36) NOT NULL,
    `actorMembershipId` CHAR(36) NULL,
    `type` VARCHAR(40) NOT NULL,
    `metadata` JSON NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `TicketEvent_ticketId_createdAt_idx`(`ticketId`, `createdAt`),
    INDEX `TicketEvent_companyId_createdAt_idx`(`companyId`, `createdAt`),
    INDEX `TicketEvent_actorMembershipId_createdAt_idx`(`actorMembershipId`, `createdAt`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `TicketEvent` ADD CONSTRAINT `TicketEvent_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `TicketEvent` ADD CONSTRAINT `TicketEvent_ticketId_fkey` FOREIGN KEY (`ticketId`) REFERENCES `Ticket`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `TicketEvent` ADD CONSTRAINT `TicketEvent_actorMembershipId_fkey` FOREIGN KEY (`actorMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
