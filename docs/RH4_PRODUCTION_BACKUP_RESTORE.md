# RH4 — Production backup / restore

RH4 replaces the development-oriented backup path with an explicit production
disaster-recovery flow.

No existing development backup command is repurposed. Production uses dedicated
`prod:backup:*` commands.

## Backup scope

The authoritative RH4 backup is the MySQL database.

Redis is intentionally not restored from an old snapshot. After a database
restore, RH4 flushes Redis so stale sessions, caches and queued operational
state cannot point at a different database timeline.

Production media is already stored in the external S3-compatible object store.
RH4 does not duplicate those objects into the SQL backup. The object-storage
provider must have its own versioning/retention/backup policy.

## External backup target

Production requires:

```text
WAPP_BACKUP_DIR=/mnt/wapp-backups
WAPP_BACKUP_PASSPHRASE_FILE=/etc/wapp/secrets/backup-passphrase
WAPP_BACKUP_RETENTION_DAYS=30
WAPP_BACKUP_MIN_KEEP=7
WAPP_BACKUP_AUTO_PRUNE=true
```

`WAPP_BACKUP_DIR` must be outside the application repository.

For a real production host, `/mnt/wapp-backups` should be an off-host or
externally managed mount such as NFS, encrypted block storage, backup appliance,
or an object-storage gateway. A directory on the same physical disk does not
provide sufficient disaster isolation.

The passphrase file must also live outside the repository and, on Linux, must
have permissions `400` or `600`.

Production backup/restore operations use a non-blocking `flock` in the external
backup directory. A second backup, prune or restore operation is refused while
one is already active.

Generate a high-entropy value without putting it in shell history, for example
with your secret manager. RH4 requires at least 32 characters.

## Backup creation

```bash
pnpm prod:backup:create
```

The flow:

1. validates the production environment and MySQL TLS;
2. creates a `mysqldump` with `--single-transaction`;
3. uses `VERIFY_IDENTITY` against the RH3 MySQL CA;
4. writes the plaintext dump only to ephemeral host storage;
5. encrypts it with AES-256-GCM;
6. derives the encryption key with scrypt;
7. creates a SHA-256 manifest with database, timestamp and Git commit;
8. persists only the encrypted file + manifest to the external backup target;
9. decrypts/validates the artifact after creation;
10. applies retention when auto-prune is enabled.

Backup file example:

```text
wapp-db-20260902T183000Z-scheduled.wappbak
wapp-db-20260902T183000Z-scheduled.manifest.json
```

The encrypted format is versioned as `WAPPBK1`.

## Verification

```bash
pnpm prod:backup:verify -- /mnt/wapp-backups/<backup>.wappbak
```

Verification checks:

- manifest type/version;
- expected database;
- encrypted file size;
- SHA-256;
- AES-GCM authentication tag;
- successful decryption;
- basic MySQL logical-dump structure.

A modified encrypted payload is rejected.

## Retention

Dry-run:

```bash
pnpm prod:backup:prune
```

Apply:

```bash
pnpm prod:backup:prune:apply
```

The policy never removes the newest `WAPP_BACKUP_MIN_KEEP` backup files,
regardless of age.

Only files matching Wapp's production backup filename format are eligible for
deletion.

## Production restore

Restore is intentionally destructive and strongly guarded.

The default workflow refuses to restore a backup created from a different Git
commit. Prefer checking out the commit recorded in the backup manifest before
restoring.

To restore:

```bash
WAPP_PROD_RESTORE_CONFIRM='RESTORE PRODUCTION DATABASE' \
pnpm prod:backup:restore -- /mnt/wapp-backups/<backup>.wappbak
```

Before dropping the current database, the restore command creates a mandatory
`pre-restore` safety backup.

Then it:

1. decrypts the selected verified backup into ephemeral storage;
2. stops API and worker;
3. drops/recreates only `MYSQL_DATABASE`;
4. imports the logical dump over verified MySQL TLS;
5. validates that the restored schema contains tables;
6. flushes Redis operational state;
7. starts API and worker;
8. executes the RH3 production database transport check.

It never removes the MySQL Docker volume.

If restore fails after API/worker are stopped, they remain stopped. This is
intentional so Wapp cannot serve a partially restored database. The script
prints the pre-restore safety backup path for manual recovery.

### Commit mismatch

Only after explicit compatibility review:

```text
WAPP_PROD_RESTORE_ALLOW_COMMIT_MISMATCH=true
```

This is an emergency override, not the normal restore workflow.

## Restore drill

```bash
pnpm rh4:backup:drill
```

The automated drill uses an ephemeral MySQL 8.4 container with no named volume.

It:

1. creates known data;
2. creates a logical dump;
3. encrypts and manifests it;
4. proves tampering is rejected by AES-GCM;
5. destroys the source database;
6. decrypts/restores the backup;
7. validates exact restored row count/value;
8. removes the disposable container and files.

The drill never touches production.

## Scheduling

A real deployment should schedule at least daily:

```bash
pnpm prod:backup:create
```

The scheduler should alert on a non-zero exit code.

Also schedule periodic `prod:backup:verify` and a restore drill in an isolated
environment. A backup that has never been restored is not a validated disaster
recovery path.
