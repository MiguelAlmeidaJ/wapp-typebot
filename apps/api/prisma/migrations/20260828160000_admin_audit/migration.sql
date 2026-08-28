CREATE TABLE `AuditLog` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `actorMembershipId` CHAR(36) NULL,
  `action` VARCHAR(80) NOT NULL,
  `entityType` VARCHAR(60) NOT NULL,
  `entityId` VARCHAR(190) NULL,
  `beforeData` JSON NULL,
  `afterData` JSON NULL,
  `metadata` JSON NULL,
  `requestId` VARCHAR(100) NULL,
  `ipAddress` VARCHAR(64) NULL,
  `userAgent` VARCHAR(500) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  INDEX `AuditLog_companyId_createdAt_idx` (`companyId`, `createdAt`),
  INDEX `AuditLog_companyId_action_createdAt_idx` (`companyId`, `action`, `createdAt`),
  INDEX `AuditLog_companyId_entityType_entityId_idx` (`companyId`, `entityType`, `entityId`),
  INDEX `AuditLog_actorMembershipId_createdAt_idx` (`actorMembershipId`, `createdAt`),

  CONSTRAINT `AuditLog_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `AuditLog_actorMembershipId_fkey`
    FOREIGN KEY (`actorMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
