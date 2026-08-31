# RH1 — Production Compose and environment hardening

RH1 is a release-hardening milestone. It does not deploy Wapp and does not
modify Docker volumes.

## What RH1 fixes

### Redis Compose structure

`REDIS_PASSWORD` is declared at the Redis service level instead of being nested
under `healthcheck.environment`.

This makes the production Compose structurally valid under `config --quiet`.

### Runtime vs migration images

The API runtime/worker and Prisma migration target no longer publish to the
same image tag.

- runtime + worker: `wapp-api-runtime:${WAPP_IMAGE_TAG}`
- migration target: `wapp-api-migrate:${WAPP_IMAGE_TAG}`

This prevents a multi-target build from overwriting the runtime tag with the
migration image.

`WAPP_IMAGE_TAG` is mandatory in the production preflight and must not be
`local` or `latest`.

### Prisma build configuration

Prisma 7 loads `prisma.config.ts` during `prisma generate`, so both
`DATABASE_URL` and `SHADOW_DATABASE_URL` must exist even during image build.

The API Dockerfile provides non-secret build-only placeholder URLs around
`prisma generate`. They are not production credentials and client generation
does not connect to MySQL.

Runtime/migration containers receive the actual values from the production env.

### Production environment template

`infra/production/.env.production.example` is tracked.

`infra/production/.env.production` remains ignored and must never be committed.

Create the real file with:

```bash
pnpm prod:init
```

The initializer refuses to overwrite an existing production env. On POSIX it
creates the file with mode `600`.

The tracked template deliberately contains `CHANGE_ME` values for every
hostname/credential/secret.

### Production preflight

`pnpm prod:preflight` validates:

- public hostname;
- immutable image tag;
- MySQL credentials and `DATABASE_URL`;
- distinct Prisma `SHADOW_DATABASE_URL`;
- Redis credentials and URL;
- JWT and metrics secrets;
- API/session bounds;
- Evolution URL/secrets/health interval;
- S3 bucket, endpoint, credentials and path-style mode;
- worker concurrency/attempts;
- maintenance/retention ranges;
- optional Typebot URL only when configured.

The preflight never starts or changes containers.

`pnpm prod:config` runs preflight and only then executes Compose
`config --quiet`. It also never starts or removes containers.

## Typebot

RH1 does not enable Typebot.

`TYPEBOT_URL` remains empty in the tracked production template until Typebot is
formally included in the release scope.

## RH1 does not solve yet

RH1 intentionally does not:

- update vulnerable Prisma/transitive dependencies;
- implement MySQL TLS;
- replace development backup scripts with production backup/restore;
- create the first OWNER bootstrap;
- run staging or production deployment.

Those remain subsequent Release Hardening milestones.
