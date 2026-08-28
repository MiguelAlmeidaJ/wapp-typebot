ALTER TABLE `WhatsAppConnection`
  ADD COLUMN `healthStatus` ENUM('UNKNOWN', 'HEALTHY', 'DEGRADED', 'DOWN') NOT NULL DEFAULT 'UNKNOWN',
  ADD COLUMN `lastHealthCheckAt` DATETIME(3) NULL,
  ADD COLUMN `lastHealthOkAt` DATETIME(3) NULL,
  ADD COLUMN `healthError` TEXT NULL,
  ADD COLUMN `consecutiveHealthFailures` INTEGER NOT NULL DEFAULT 0;

CREATE INDEX `WhatsAppConnection_companyId_healthStatus_idx`
  ON `WhatsAppConnection`(`companyId`, `healthStatus`);
