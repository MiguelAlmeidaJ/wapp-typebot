ALTER TABLE `Company`
  ADD COLUMN `typebotWorkspaceId` VARCHAR(190) NULL,
  ADD UNIQUE INDEX `Company_typebotWorkspaceId_key` (`typebotWorkspaceId`);

ALTER TABLE `ChatbotFlow`
  ADD COLUMN `externalTypebotId` VARCHAR(190) NULL,
  ADD UNIQUE INDEX `ChatbotFlow_externalTypebotId_key` (`externalTypebotId`);
