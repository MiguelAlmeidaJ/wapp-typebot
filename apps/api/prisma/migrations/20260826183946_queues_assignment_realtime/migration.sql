-- AlterTable
ALTER TABLE `Ticket` ADD COLUMN `assignedMembershipId` CHAR(36) NULL,
    ADD COLUMN `queueId` CHAR(36) NULL;

-- AlterTable
ALTER TABLE `WhatsAppConnection` ADD COLUMN `acceptGroups` BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN `defaultQueueId` CHAR(36) NULL;

-- CreateTable
CREATE TABLE `Queue` (
    `id` CHAR(36) NOT NULL,
    `companyId` CHAR(36) NOT NULL,
    `name` VARCHAR(120) NOT NULL,
    `isActive` BOOLEAN NOT NULL DEFAULT true,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `Queue_companyId_isActive_idx`(`companyId`, `isActive`),
    UNIQUE INDEX `Queue_companyId_name_key`(`companyId`, `name`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `QueueMember` (
    `id` CHAR(36) NOT NULL,
    `queueId` CHAR(36) NOT NULL,
    `membershipId` CHAR(36) NOT NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `QueueMember_membershipId_idx`(`membershipId`),
    UNIQUE INDEX `QueueMember_queueId_membershipId_key`(`queueId`, `membershipId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateIndex
CREATE INDEX `Ticket_companyId_queueId_status_idx` ON `Ticket`(`companyId`, `queueId`, `status`);

-- CreateIndex
CREATE INDEX `Ticket_companyId_assignedMembershipId_status_idx` ON `Ticket`(`companyId`, `assignedMembershipId`, `status`);

-- CreateIndex
CREATE INDEX `WhatsAppConnection_companyId_defaultQueueId_idx` ON `WhatsAppConnection`(`companyId`, `defaultQueueId`);

-- AddForeignKey
ALTER TABLE `WhatsAppConnection` ADD CONSTRAINT `WhatsAppConnection_defaultQueueId_fkey` FOREIGN KEY (`defaultQueueId`) REFERENCES `Queue`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Ticket` ADD CONSTRAINT `Ticket_queueId_fkey` FOREIGN KEY (`queueId`) REFERENCES `Queue`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Ticket` ADD CONSTRAINT `Ticket_assignedMembershipId_fkey` FOREIGN KEY (`assignedMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Queue` ADD CONSTRAINT `Queue_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `QueueMember` ADD CONSTRAINT `QueueMember_queueId_fkey` FOREIGN KEY (`queueId`) REFERENCES `Queue`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `QueueMember` ADD CONSTRAINT `QueueMember_membershipId_fkey` FOREIGN KEY (`membershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
