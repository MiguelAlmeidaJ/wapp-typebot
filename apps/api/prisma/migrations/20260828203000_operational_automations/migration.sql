CREATE TABLE `AutomationRule` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `name` VARCHAR(160) NOT NULL,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `trigger` ENUM('TICKET_CREATED', 'INBOUND_MESSAGE') NOT NULL,
  `keywordContains` VARCHAR(190) NULL,
  `onlyIfUnassigned` BOOLEAN NOT NULL DEFAULT false,
  `conversationType` ENUM('ALL', 'DIRECT', 'GROUP') NOT NULL DEFAULT 'ALL',
  `priority` INTEGER NOT NULL DEFAULT 100,
  `createdByMembershipId` CHAR(36) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  INDEX `AutomationRule_companyId_isActive_trigger_priority_idx`
    (`companyId`, `isActive`, `trigger`, `priority`),
  INDEX `AutomationRule_companyId_updatedAt_idx`
    (`companyId`, `updatedAt`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `AutomationAction` (
  `id` CHAR(36) NOT NULL,
  `ruleId` CHAR(36) NOT NULL,
  `type` ENUM('SET_QUEUE', 'ASSIGN_MEMBERSHIP', 'ADD_TAG', 'SEND_TEXT') NOT NULL,
  `orderIndex` INTEGER NOT NULL DEFAULT 0,
  `queueId` CHAR(36) NULL,
  `membershipId` CHAR(36) NULL,
  `tagId` CHAR(36) NULL,
  `text` TEXT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  INDEX `AutomationAction_ruleId_orderIndex_idx`
    (`ruleId`, `orderIndex`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `AutomationRun` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `ruleId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NOT NULL,
  `sourceMessageId` CHAR(36) NOT NULL,
  `trigger` ENUM('TICKET_CREATED', 'INBOUND_MESSAGE') NOT NULL,
  `status` ENUM('RUNNING', 'SUCCESS', 'FAILED') NOT NULL DEFAULT 'RUNNING',
  `matched` BOOLEAN NOT NULL DEFAULT false,
  `dedupeKey` VARCHAR(190) NOT NULL,
  `details` JSON NULL,
  `error` TEXT NULL,
  `startedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `finishedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  UNIQUE INDEX `AutomationRun_dedupeKey_key` (`dedupeKey`),
  INDEX `AutomationRun_companyId_createdAt_idx`
    (`companyId`, `createdAt`),
  INDEX `AutomationRun_ruleId_createdAt_idx`
    (`ruleId`, `createdAt`),
  INDEX `AutomationRun_ticketId_createdAt_idx`
    (`ticketId`, `createdAt`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
