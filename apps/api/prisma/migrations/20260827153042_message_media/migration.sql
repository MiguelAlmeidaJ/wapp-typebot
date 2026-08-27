-- AlterTable
ALTER TABLE `Message` ADD COLUMN `mediaError` TEXT NULL,
    ADD COLUMN `mediaSize` INTEGER NULL,
    ADD COLUMN `mediaStatus` ENUM('NONE', 'PENDING', 'READY', 'FAILED') NOT NULL DEFAULT 'NONE',
    ADD COLUMN `mediaStorageKey` VARCHAR(500) NULL;

-- CreateIndex
CREATE INDEX `Message_companyId_mediaStatus_idx` ON `Message`(`companyId`, `mediaStatus`);
