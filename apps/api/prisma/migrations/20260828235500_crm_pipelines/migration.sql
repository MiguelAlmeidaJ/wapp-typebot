CREATE TABLE `CrmPipeline` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `name` VARCHAR(120) NOT NULL,
  `description` VARCHAR(500) NULL,
  `position` INTEGER NOT NULL DEFAULT 0,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `CrmPipeline_companyId_name_key`
    (`companyId`, `name`),
  INDEX `CrmPipeline_companyId_isActive_position_idx`
    (`companyId`, `isActive`, `position`),

  CONSTRAINT `CrmPipeline_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `CrmStage` (
  `id` CHAR(36) NOT NULL,
  `pipelineId` CHAR(36) NOT NULL,
  `name` VARCHAR(120) NOT NULL,
  `colorKey` VARCHAR(20) NOT NULL DEFAULT 'GRAY',
  `outcome` ENUM('OPEN', 'WON', 'LOST') NOT NULL DEFAULT 'OPEN',
  `position` INTEGER NOT NULL DEFAULT 0,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `CrmStage_pipelineId_name_key`
    (`pipelineId`, `name`),
  INDEX `CrmStage_pipelineId_isActive_position_idx`
    (`pipelineId`, `isActive`, `position`),

  CONSTRAINT `CrmStage_pipelineId_fkey`
    FOREIGN KEY (`pipelineId`)
    REFERENCES `CrmPipeline`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `ContactPipelineState` (
  `id` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `pipelineId` CHAR(36) NOT NULL,
  `stageId` CHAR(36) NOT NULL,
  `updatedByMembershipId` CHAR(36) NULL,
  `enteredAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `ContactPipelineState_contactId_pipelineId_key`
    (`contactId`, `pipelineId`),
  INDEX `ContactPipelineState_pipelineId_stageId_updatedAt_idx`
    (`pipelineId`, `stageId`, `updatedAt`),
  INDEX `ContactPipelineState_contactId_updatedAt_idx`
    (`contactId`, `updatedAt`),

  CONSTRAINT `ContactPipelineState_contactId_fkey`
    FOREIGN KEY (`contactId`)
    REFERENCES `Contact`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactPipelineState_pipelineId_fkey`
    FOREIGN KEY (`pipelineId`)
    REFERENCES `CrmPipeline`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactPipelineState_stageId_fkey`
    FOREIGN KEY (`stageId`)
    REFERENCES `CrmStage`(`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT `ContactPipelineState_updatedByMembershipId_fkey`
    FOREIGN KEY (`updatedByMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `ContactStageTransition` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `pipelineId` CHAR(36) NOT NULL,
  `fromStageId` CHAR(36) NULL,
  `toStageId` CHAR(36) NULL,
  `actorMembershipId` CHAR(36) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  INDEX `ContactStageTransition_companyId_createdAt_idx`
    (`companyId`, `createdAt`),
  INDEX `ContactStageTransition_contactId_createdAt_idx`
    (`contactId`, `createdAt`),
  INDEX `ContactStageTransition_pipelineId_createdAt_idx`
    (`pipelineId`, `createdAt`),

  CONSTRAINT `ContactStageTransition_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_contactId_fkey`
    FOREIGN KEY (`contactId`)
    REFERENCES `Contact`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_pipelineId_fkey`
    FOREIGN KEY (`pipelineId`)
    REFERENCES `CrmPipeline`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_fromStageId_fkey`
    FOREIGN KEY (`fromStageId`)
    REFERENCES `CrmStage`(`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_toStageId_fkey`
    FOREIGN KEY (`toStageId`)
    REFERENCES `CrmStage`(`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_actorMembershipId_fkey`
    FOREIGN KEY (`actorMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
