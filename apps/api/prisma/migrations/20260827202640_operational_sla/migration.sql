-- AlterTable
ALTER TABLE `Company` ADD COLUMN `firstResponseSlaMinutes` INTEGER NOT NULL DEFAULT 15,
    ADD COLUMN `replySlaMinutes` INTEGER NOT NULL DEFAULT 30;

-- AlterTable
ALTER TABLE `Ticket` ADD COLUMN `firstInboundAt` DATETIME(3) NULL,
    ADD COLUMN `firstResponseAt` DATETIME(3) NULL,
    ADD COLUMN `lastInboundAt` DATETIME(3) NULL,
    ADD COLUMN `lastOutboundAt` DATETIME(3) NULL,
    ADD COLUMN `waitingSince` DATETIME(3) NULL;

-- CreateIndex
CREATE INDEX `Ticket_companyId_status_waitingSince_idx` ON `Ticket`(`companyId`, `status`, `waitingSince`);
