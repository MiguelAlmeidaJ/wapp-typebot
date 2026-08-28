CREATE TABLE `MaintenanceRun` (
  `id` CHAR(36) NOT NULL,
  `source` VARCHAR(20) NOT NULL,
  `status` VARCHAR(20) NOT NULL,
  `result` JSON NULL,
  `error` TEXT NULL,
  `startedAt` DATETIME(3) NOT NULL,
  `finishedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  INDEX `MaintenanceRun_status_createdAt_idx` (`status`, `createdAt`),
  INDEX `MaintenanceRun_createdAt_idx` (`createdAt`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
