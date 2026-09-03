-- RH5: the first production OWNER is sealed until its final password is initialized.
ALTER TABLE `User`
  ADD COLUMN `mustChangePassword` BOOLEAN NOT NULL DEFAULT false;
