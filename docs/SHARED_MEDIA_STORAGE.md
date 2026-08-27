# Shared media storage

P1.17 removes the assumption that every API request runs on the same machine
that originally stored a media file.

## Why

The original P1.2 storage writes to:

`.runtime/media`

That is correct for one local API process, but not for horizontally scaled API
replicas.

With local disks:

```text
message arrives -> API A -> disk A

media GET -> load balancer -> API B -> disk B -> file missing
```

P1.17 introduces a storage driver seam.

## Drivers

### local

Default:

`MEDIA_STORAGE_DRIVER=local`

This preserves the current development behavior.

Files remain under:

`MEDIA_STORAGE_PATH=.runtime/media`

### s3

Production/shared mode:

`MEDIA_STORAGE_DRIVER=s3`

Required:

`S3_BUCKET`

Common optional settings:

- `S3_REGION`
- `S3_ENDPOINT`
- `S3_FORCE_PATH_STYLE`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`

If explicit access keys are omitted, the AWS SDK can use its normal credential
provider chain, which is preferred for IAM roles/workload identities.

## S3-compatible providers

The driver uses the standard S3 API and supports AWS S3 and providers exposing
compatible S3 endpoints, including typical MinIO/R2-style deployments.

Provider-specific endpoint, region and path-style requirements must match that
provider's documentation.

## Storage keys

Database storage keys do not change.

Example:

`<companyId>/<messageId>.jpg`

This means existing database records do not require a migration.

## Existing local files

Before switching an existing environment to `MEDIA_STORAGE_DRIVER=s3`, configure
the S3 variables and run:

`pnpm --filter @wapp/api exec tsx src/scripts/migrate-local-media-to-s3.ts`

The migration:

- walks the current local media directory;
- preserves each existing storage key;
- skips objects that already exist in S3;
- does not delete local files;
- is safe to run again.

After verifying media through Wapp, change:

`MEDIA_STORAGE_DRIVER=s3`

and restart the API.

Do not delete the local media directory until the migrated files have been
verified and a backup policy exists.

## Security

Media remains private behind Wapp's authenticated endpoint:

`GET /api/v1/messages/:id/media`

P1.17 does not expose public bucket URLs or presigned URLs.

The bucket should remain private.

## Health

When P1.15 is installed, detailed `/health` also reports the media-storage
driver and its health.

Storage failure is diagnostic/degraded state, not a readiness dependency, so a
provider outage does not make text-only/API functions unavailable.

## Migration

P1.17 requires no Prisma migration.
