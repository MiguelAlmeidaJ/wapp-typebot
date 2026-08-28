CREATE TABLE `MessageReaction` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NOT NULL,
  `messageId` CHAR(36) NOT NULL,
  `reactedByMembershipId` CHAR(36) NULL,
  `reactorKey` VARCHAR(190) NOT NULL,
  `reactorJid` VARCHAR(190) NULL,
  `fromMe` BOOLEAN NOT NULL DEFAULT false,
  `emoji` VARCHAR(32) NOT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `MessageReaction_messageId_reactorKey_key` (`messageId`, `reactorKey`),
  INDEX `MessageReaction_companyId_ticketId_idx` (`companyId`, `ticketId`),
  INDEX `MessageReaction_ticketId_updatedAt_idx` (`ticketId`, `updatedAt`),
  INDEX `MessageReaction_reactedByMembershipId_idx` (`reactedByMembershipId`),

  CONSTRAINT `MessageReaction_messageId_fkey`
    FOREIGN KEY (`messageId`)
    REFERENCES `Message`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `MessageReaction_reactedByMembershipId_fkey`
    FOREIGN KEY (`reactedByMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
