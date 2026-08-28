CREATE TABLE `ContactFieldDefinition` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `key` VARCHAR(50) NOT NULL,
  `label` VARCHAR(120) NOT NULL,
  `type` ENUM(
    'TEXT',
    'NUMBER',
    'DATE',
    'BOOLEAN',
    'SELECT'
  ) NOT NULL,
  `options` JSON NULL,
  `required` BOOLEAN NOT NULL DEFAULT false,
  `position` INTEGER NOT NULL DEFAULT 0,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),

  UNIQUE INDEX `ContactFieldDefinition_companyId_key_key`
    (`companyId`, `key`),

  INDEX `ContactFieldDefinition_companyId_isActive_position_idx`
    (`companyId`, `isActive`, `position`),

  CONSTRAINT `ContactFieldDefinition_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `ContactFieldValue` (
  `id` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `fieldId` CHAR(36) NOT NULL,
  `value` TEXT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),

  UNIQUE INDEX `ContactFieldValue_contactId_fieldId_key`
    (`contactId`, `fieldId`),

  INDEX `ContactFieldValue_fieldId_updatedAt_idx`
    (`fieldId`, `updatedAt`),

  INDEX `ContactFieldValue_contactId_updatedAt_idx`
    (`contactId`, `updatedAt`),

  CONSTRAINT `ContactFieldValue_contactId_fkey`
    FOREIGN KEY (`contactId`)
    REFERENCES `Contact`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactFieldValue_fieldId_fkey`
    FOREIGN KEY (`fieldId`)
    REFERENCES `ContactFieldDefinition`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
