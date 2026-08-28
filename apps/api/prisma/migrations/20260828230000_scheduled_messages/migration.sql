CREATE TABLE `ScheduledMessage` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NOT NULL,
  `createdByMembershipId` CHAR(36) NOT NULL,
  `body` TEXT NOT NULL,
  `scheduledFor` DATETIME(3) NOT NULL,
  `status` ENUM(
    'PENDING',
    'PROCESSING',
    'SENT',
    'CANCELLED',
    'FAILED'
  ) NOT NULL DEFAULT 'PENDING',
  `claimedAt` DATETIME(3) NULL,
  `sentAt` DATETIME(3) NULL,
  `cancelledAt` DATETIME(3) NULL,
  `sentMessageId` CHAR(36) NULL,
  `error` TEXT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),

  INDEX `ScheduledMessage_companyId_status_scheduledFor_idx`
    (`companyId`, `status`, `scheduledFor`),

  INDEX `ScheduledMessage_ticketId_status_scheduledFor_idx`
    (`ticketId`, `status`, `scheduledFor`),

  INDEX `ScheduledMessage_createdByMembershipId_createdAt_idx`
    (`createdByMembershipId`, `createdAt`),

  CONSTRAINT `ScheduledMessage_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ScheduledMessage_ticketId_fkey`
    FOREIGN KEY (`ticketId`)
    REFERENCES `Ticket`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ScheduledMessage_createdByMembershipId_fkey`
    FOREIGN KEY (`createdByMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
