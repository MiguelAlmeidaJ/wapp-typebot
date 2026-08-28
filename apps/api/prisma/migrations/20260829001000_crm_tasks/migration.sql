ALTER TABLE `Notification` ADD COLUMN `contactId` CHAR(36) NULL;
CREATE INDEX `Notification_contactId_updatedAt_idx` ON `Notification`(`contactId`, `updatedAt`);
ALTER TABLE `Notification`
  ADD CONSTRAINT `Notification_contactId_fkey`
  FOREIGN KEY (`contactId`) REFERENCES `Contact`(`id`)
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE `CrmTask` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NULL,
  `assigneeMembershipId` CHAR(36) NOT NULL,
  `createdByMembershipId` CHAR(36) NOT NULL,
  `title` VARCHAR(190) NOT NULL,
  `description` TEXT NULL,
  `status` ENUM('OPEN','DONE','CANCELLED') NOT NULL DEFAULT 'OPEN',
  `priority` ENUM('LOW','NORMAL','HIGH','URGENT') NOT NULL DEFAULT 'NORMAL',
  `dueAt` DATETIME(3) NOT NULL,
  `reminderAt` DATETIME(3) NULL,
  `reminderClaimedAt` DATETIME(3) NULL,
  `reminderSentAt` DATETIME(3) NULL,
  `reminderFailedAt` DATETIME(3) NULL,
  `reminderError` VARCHAR(500) NULL,
  `completedAt` DATETIME(3) NULL,
  `cancelledAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `CrmTask_companyId_status_dueAt_idx` (`companyId`,`status`,`dueAt`),
  INDEX `CrmTask_assigneeMembershipId_status_dueAt_idx` (`assigneeMembershipId`,`status`,`dueAt`),
  INDEX `CrmTask_contactId_status_dueAt_idx` (`contactId`,`status`,`dueAt`),
  INDEX `CrmTask_ticketId_status_dueAt_idx` (`ticketId`,`status`,`dueAt`),
  INDEX `CrmTask_status_reminderAt_reminderSentAt_reminderFailedAt_idx`
    (`status`,`reminderAt`,`reminderSentAt`,`reminderFailedAt`),
  CONSTRAINT `CrmTask_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CrmTask_contactId_fkey` FOREIGN KEY (`contactId`) REFERENCES `Contact`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CrmTask_ticketId_fkey` FOREIGN KEY (`ticketId`) REFERENCES `Ticket`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `CrmTask_assigneeMembershipId_fkey` FOREIGN KEY (`assigneeMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `CrmTask_createdByMembershipId_fkey` FOREIGN KEY (`createdByMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `CrmTaskEvent` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `taskId` CHAR(36) NOT NULL,
  `actorMembershipId` CHAR(36) NULL,
  `type` ENUM('CREATED','UPDATED','REASSIGNED','COMPLETED','CANCELLED','REMINDER_SENT','REMINDER_FAILED') NOT NULL,
  `metadata` JSON NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  INDEX `CrmTaskEvent_companyId_createdAt_idx` (`companyId`,`createdAt`),
  INDEX `CrmTaskEvent_taskId_createdAt_idx` (`taskId`,`createdAt`),
  CONSTRAINT `CrmTaskEvent_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CrmTaskEvent_taskId_fkey` FOREIGN KEY (`taskId`) REFERENCES `CrmTask`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CrmTaskEvent_actorMembershipId_fkey` FOREIGN KEY (`actorMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
