-- CreateTable
CREATE TABLE `Contact` (
    `id` CHAR(36) NOT NULL,
    `companyId` CHAR(36) NOT NULL,
    `remoteJid` VARCHAR(190) NOT NULL,
    `phoneNumber` VARCHAR(32) NULL,
    `name` VARCHAR(190) NOT NULL,
    `isGroup` BOOLEAN NOT NULL DEFAULT false,
    `lastSeenAt` DATETIME(3) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    INDEX `Contact_companyId_phoneNumber_idx`(`companyId`, `phoneNumber`),
    INDEX `Contact_companyId_name_idx`(`companyId`, `name`),
    UNIQUE INDEX `Contact_companyId_remoteJid_key`(`companyId`, `remoteJid`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `Ticket` (
    `id` CHAR(36) NOT NULL,
    `companyId` CHAR(36) NOT NULL,
    `whatsappConnectionId` CHAR(36) NOT NULL,
    `contactId` CHAR(36) NOT NULL,
    `activeKey` VARCHAR(100) NULL,
    `status` ENUM('OPEN', 'PENDING', 'CLOSED') NOT NULL DEFAULT 'OPEN',
    `unreadCount` INTEGER NOT NULL DEFAULT 0,
    `lastMessage` TEXT NULL,
    `lastMessageAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `closedAt` DATETIME(3) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    UNIQUE INDEX `Ticket_activeKey_key`(`activeKey`),
    INDEX `Ticket_companyId_status_lastMessageAt_idx`(`companyId`, `status`, `lastMessageAt`),
    INDEX `Ticket_whatsappConnectionId_status_idx`(`whatsappConnectionId`, `status`),
    INDEX `Ticket_contactId_status_idx`(`contactId`, `status`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `Message` (
    `id` CHAR(36) NOT NULL,
    `companyId` CHAR(36) NOT NULL,
    `ticketId` CHAR(36) NOT NULL,
    `whatsappConnectionId` CHAR(36) NOT NULL,
    `sentByUserId` CHAR(36) NULL,
    `externalId` VARCHAR(190) NOT NULL,
    `direction` ENUM('INBOUND', 'OUTBOUND') NOT NULL,
    `type` ENUM('TEXT', 'IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT', 'STICKER', 'LOCATION', 'CONTACT', 'UNKNOWN') NOT NULL DEFAULT 'TEXT',
    `body` TEXT NULL,
    `mediaMimeType` VARCHAR(190) NULL,
    `mediaFileName` VARCHAR(255) NULL,
    `quotedExternalId` VARCHAR(190) NULL,
    `timestamp` DATETIME(3) NOT NULL,
    `rawPayload` JSON NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `Message_ticketId_timestamp_idx`(`ticketId`, `timestamp`),
    INDEX `Message_companyId_timestamp_idx`(`companyId`, `timestamp`),
    UNIQUE INDEX `Message_whatsappConnectionId_externalId_key`(`whatsappConnectionId`, `externalId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `Contact` ADD CONSTRAINT `Contact_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Ticket` ADD CONSTRAINT `Ticket_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Ticket` ADD CONSTRAINT `Ticket_whatsappConnectionId_fkey` FOREIGN KEY (`whatsappConnectionId`) REFERENCES `WhatsAppConnection`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Ticket` ADD CONSTRAINT `Ticket_contactId_fkey` FOREIGN KEY (`contactId`) REFERENCES `Contact`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Message` ADD CONSTRAINT `Message_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Message` ADD CONSTRAINT `Message_ticketId_fkey` FOREIGN KEY (`ticketId`) REFERENCES `Ticket`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Message` ADD CONSTRAINT `Message_whatsappConnectionId_fkey` FOREIGN KEY (`whatsappConnectionId`) REFERENCES `WhatsAppConnection`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Message` ADD CONSTRAINT `Message_sentByUserId_fkey` FOREIGN KEY (`sentByUserId`) REFERENCES `User`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
