# P1.18 Backup, restore and retention

Docker volumes provide persistence, not a recovery strategy. P1.18 creates
application-level restore points without deleting Docker volumes.

A snapshot looks like:

```text
.backups/wapp-YYYYMMDDTHHMMSSZ/
├── database.sql.gz
├── media/              # only when local media exists
├── manifest.json
└── SHA256SUMS
```

`.backups/` is ignored by Git. Environment files and application secrets are not
copied into snapshots.

## Create

```bash
pnpm backup:create
```

Optional reason:

```bash
pnpm backup:create -- before-release
```

The local development flow uses the existing MySQL 8.4 Compose service and its
container environment. The dump uses a single transaction and gzip.

If `MEDIA_STORAGE_DRIVER=local`, the local media directory is included. If the
driver is `s3`, media objects are not downloaded into every DB backup; bucket
versioning/provider backup must be configured separately.

## Verify

```bash
pnpm backup:verify -- .backups/wapp-YYYYMMDDTHHMMSSZ
```

Verification checks SHA-256 for every snapshot file and validates the gzip SQL
dump. A backup that has never been verified is not a proven restore point.

## Restore

Stop normal application traffic first.

```bash
pnpm backup:restore -- .backups/wapp-YYYYMMDDTHHMMSSZ --confirm RESTORE
```

Before the destructive database restore, Wapp automatically creates a fresh
`pre-restore` safety backup. The SQL dump contains `DROP TABLE` statements, so
newer database state is intentionally replaced by the selected restore point.

Local media is merged back without deleting extra files.

Emergency database-only restore:

```bash
pnpm backup:restore -- .backups/wapp-YYYYMMDDTHHMMSSZ --confirm RESTORE --db-only
```

After restore: restart API processes, check `/health/ready`, then validate login,
an old conversation/media, and WhatsApp inbound/outbound.

P1.18 never runs `docker compose down -v` and never deletes the MySQL volume.

## Retention

Default retention:

- 7 distinct daily restore points;
- 4 distinct weekly restore points;
- 6 distinct monthly restore points;
- always the newest snapshot.

Preview:

```bash
pnpm backup:prune
```

Apply:

```bash
pnpm backup:prune -- --apply
```

Custom:

```bash
pnpm backup:prune -- --daily 14 --weekly 8 --monthly 12 --apply
```

Only directories matching Wapp's timestamp naming convention are candidates.

## Production baseline

`.backups/` on the DB host is not enough for production. Keep an encrypted
off-host copy and configure S3/provider backup for media.

Initial operational targets, to review against business requirements:

- RPO: at most 24 hours with daily DB backups;
- RTO: 2 hours for documented manual restore.

If the business needs a lower RPO, increase backup frequency before promising
it.

At least monthly, perform a restore drill against an isolated test database.
Successful backup creation alone does not prove recoverability.

## Restore drill isolado

Depois de criar e verificar um snapshot, valide que o SQL realmente é
restaurável sem tocar no banco de trabalho:

```bash
pnpm backup:drill -- .backups/wapp-YYYYMMDDTHHMMSSZ
```

O drill:

1. executa novamente `backup:verify`;
2. cria um container temporário `mysql:8.4`;
3. cria um banco isolado `wapp_restore_drill`;
4. importa `database.sql.gz`;
5. confirma que há tabelas restauradas;
6. conta migrations Prisma concluídas quando `_prisma_migrations` existe;
7. executa `mysqlcheck`;
8. mostra uma amostra das tabelas;
9. remove o container temporário automaticamente.

O container não publica porta, não usa volume e não se conecta ao banco Wapp
existente.

Nenhum `docker compose down -v` é executado.

O restore drill deve ser executado periodicamente, especialmente antes de
alterações relevantes de infraestrutura ou banco.
