ALTER TABLE `Queue`
  ADD COLUMN `slug` VARCHAR(80) NULL;

UPDATE `Queue`
SET `slug` = CONCAT('queue-', LEFT(`id`, 8));

ALTER TABLE `Queue`
  MODIFY `slug` VARCHAR(80) NOT NULL,
  ADD UNIQUE INDEX `Queue_companyId_slug_key` (`companyId`, `slug`);

CREATE TABLE `ChatbotFlow` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `whatsappConnectionId` CHAR(36) NOT NULL,
  `name` VARCHAR(160) NOT NULL,
  `engine` ENUM('TYPEBOT') NOT NULL DEFAULT 'TYPEBOT',
  `externalId` VARCHAR(190) NOT NULL,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `activeKey` VARCHAR(100) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `ChatbotFlow_activeKey_key` (`activeKey`),
  INDEX `ChatbotFlow_companyId_isActive_name_idx` (`companyId`, `isActive`, `name`),
  INDEX `ChatbotFlow_whatsappConnectionId_isActive_idx` (`whatsappConnectionId`, `isActive`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `ChatbotSession` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NOT NULL,
  `flowId` CHAR(36) NOT NULL,
  `engine` ENUM('TYPEBOT') NOT NULL DEFAULT 'TYPEBOT',
  `externalSessionId` VARCHAR(190) NULL,
  `activeKey` VARCHAR(100) NULL,
  `status` ENUM('STARTING', 'ACTIVE', 'FINISHED', 'FAILED') NOT NULL DEFAULT 'STARTING',
  `lastInput` JSON NULL,
  `lastError` TEXT NULL,
  `startedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `finishedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `ChatbotSession_activeKey_key` (`activeKey`),
  INDEX `ChatbotSession_companyId_ticketId_status_idx` (`companyId`, `ticketId`, `status`),
  INDEX `ChatbotSession_flowId_startedAt_idx` (`flowId`, `startedAt`),
  INDEX `ChatbotSession_externalSessionId_idx` (`externalSessionId`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE `ChatbotFlow`
  ADD CONSTRAINT `ChatbotFlow_companyId_fkey`
    FOREIGN KEY (`companyId`) REFERENCES `Company` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `ChatbotFlow_whatsappConnectionId_fkey`
    FOREIGN KEY (`whatsappConnectionId`) REFERENCES `WhatsAppConnection` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `ChatbotSession`
  ADD CONSTRAINT `ChatbotSession_companyId_fkey`
    FOREIGN KEY (`companyId`) REFERENCES `Company` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `ChatbotSession_ticketId_fkey`
    FOREIGN KEY (`ticketId`) REFERENCES `Ticket` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `ChatbotSession_flowId_fkey`
    FOREIGN KEY (`flowId`) REFERENCES `ChatbotFlow` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE;
