-- AlterTable
ALTER TABLE `Message` ADD COLUMN `deliveredAt` DATETIME(3) NULL,
    ADD COLUMN `deliveryError` TEXT NULL,
    ADD COLUMN `deliveryStatus` ENUM('NONE', 'PENDING', 'SENT', 'DELIVERED', 'READ', 'PLAYED', 'FAILED') NOT NULL DEFAULT 'NONE',
    ADD COLUMN `playedAt` DATETIME(3) NULL,
    ADD COLUMN `readAt` DATETIME(3) NULL;

-- CreateIndex
CREATE INDEX `Message_companyId_deliveryStatus_idx` ON `Message`(`companyId`, `deliveryStatus`);
