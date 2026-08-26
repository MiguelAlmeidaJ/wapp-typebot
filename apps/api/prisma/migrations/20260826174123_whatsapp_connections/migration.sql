-- CreateTable
CREATE TABLE `WhatsAppConnection` (
    `id` CHAR(36) NOT NULL,
    `companyId` CHAR(36) NOT NULL,
    `name` VARCHAR(120) NOT NULL,
    `provider` ENUM('EVOLUTION_BAILEYS', 'META_CLOUD') NOT NULL DEFAULT 'EVOLUTION_BAILEYS',
    `instanceName` VARCHAR(120) NOT NULL,
    `status` ENUM('CREATED', 'CONNECTING', 'CONNECTED', 'DISCONNECTED', 'ERROR') NOT NULL DEFAULT 'CREATED',
    `phoneNumber` VARCHAR(32) NULL,
    `profileName` VARCHAR(160) NULL,
    `lastError` TEXT NULL,
    `lastEventAt` DATETIME(3) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    UNIQUE INDEX `WhatsAppConnection_instanceName_key`(`instanceName`),
    INDEX `WhatsAppConnection_companyId_status_idx`(`companyId`, `status`),
    INDEX `WhatsAppConnection_companyId_createdAt_idx`(`companyId`, `createdAt`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `WhatsAppConnection` ADD CONSTRAINT `WhatsAppConnection_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
