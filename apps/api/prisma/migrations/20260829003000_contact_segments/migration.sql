CREATE TABLE `ContactSegment` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `createdByMembershipId` CHAR(36) NULL,
  `name` VARCHAR(140) NOT NULL,
  `description` VARCHAR(500) NULL,
  `definition` JSON NOT NULL,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `ContactSegment_companyId_name_key` (`companyId`, `name`),
  INDEX `ContactSegment_companyId_isActive_updatedAt_idx` (`companyId`, `isActive`, `updatedAt`),
  INDEX `ContactSegment_createdByMembershipId_updatedAt_idx` (`createdByMembershipId`, `updatedAt`),
  CONSTRAINT `ContactSegment_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ContactSegment_createdByMembershipId_fkey` FOREIGN KEY (`createdByMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
