CREATE TABLE `Notification` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `membershipId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NULL,
  `messageId` CHAR(36) NULL,
  `type` VARCHAR(40) NOT NULL,
  `title` VARCHAR(180) NOT NULL,
  `body` VARCHAR(500) NOT NULL,
  `dedupeKey` VARCHAR(190) NOT NULL,
  `occurrenceCount` INTEGER NOT NULL DEFAULT 1,
  `readAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),

  UNIQUE INDEX `Notification_companyId_membershipId_dedupeKey_key`
    (`companyId`, `membershipId`, `dedupeKey`),

  INDEX `Notification_membershipId_readAt_updatedAt_idx`
    (`membershipId`, `readAt`, `updatedAt`),

  INDEX `Notification_companyId_updatedAt_idx`
    (`companyId`, `updatedAt`),

  INDEX `Notification_ticketId_updatedAt_idx`
    (`ticketId`, `updatedAt`),

  CONSTRAINT `Notification_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `Notification_membershipId_fkey`
    FOREIGN KEY (`membershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `Notification_ticketId_fkey`
    FOREIGN KEY (`ticketId`)
    REFERENCES `Ticket`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
