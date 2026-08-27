-- AlterTable
ALTER TABLE `Contact` ADD COLUMN `email` VARCHAR(190) NULL,
    ADD COLUMN `notes` TEXT NULL,
    ADD COLUMN `whatsappName` VARCHAR(190) NULL;

-- CreateIndex
CREATE INDEX `Contact_companyId_email_idx` ON `Contact`(`companyId`, `email`);
