-- CreateTable
CREATE TABLE `TicketNote` (
    `id` CHAR(36) NOT NULL,
    `companyId` CHAR(36) NOT NULL,
    `ticketId` CHAR(36) NOT NULL,
    `authorMembershipId` CHAR(36) NOT NULL,
    `body` TEXT NOT NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `TicketNote_ticketId_createdAt_idx`(`ticketId`, `createdAt`),
    INDEX `TicketNote_companyId_createdAt_idx`(`companyId`, `createdAt`),
    INDEX `TicketNote_authorMembershipId_createdAt_idx`(`authorMembershipId`, `createdAt`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `TicketNote` ADD CONSTRAINT `TicketNote_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `TicketNote` ADD CONSTRAINT `TicketNote_ticketId_fkey` FOREIGN KEY (`ticketId`) REFERENCES `Ticket`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `TicketNote` ADD CONSTRAINT `TicketNote_authorMembershipId_fkey` FOREIGN KEY (`authorMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
