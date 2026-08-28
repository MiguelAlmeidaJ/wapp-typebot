# P1.24 Production deployment baseline

P1.24 turns the Wapp workspace into a reproducible single-host production
deployment using Docker Compose.

It is provider-neutral: any Linux host with Docker Engine + Docker Compose,
public DNS and ports 80/443 can use the baseline.

## Topology

```text
Internet
   |
80 / 443
   |
 Caddy
  /  \
Web  API
      |
      +---- MySQL 8.4
      +---- Redis 7
      +---- S3-compatible private media storage
      +---- Evolution API
      |
    Worker
```

Only Caddy publishes host ports.

MySQL, Redis, API and Web are not directly exposed to the public host network.

## Containers

### api

Fastify production build.

Healthcheck:

`GET /health/ready`

### worker

Runs:

`node dist/worker.js`

The API has:

`JOBS_EMBEDDED_WORKER=false`

so durable BullMQ jobs are consumed by the dedicated worker.

### migrate

One-shot image target running:

`prisma migrate deploy`

It completes before API/worker startup.

### web

Next.js standalone production server.

`NEXT_PUBLIC_API_URL` is baked as:

`https://<WAPP_DOMAIN>`

### caddy

Terminates TLS automatically and proxies:

- `/api/*` -> API
- `/health*` -> API
- all remaining paths -> Web

DNS must point `WAPP_DOMAIN` to the deployment host before Caddy can obtain a
public certificate.

### mysql / redis

Persistent Docker volumes are used, but volumes are still not backups. Keep the
P1.18 backup/restore policy.

Neither service publishes a host port.

## Shared media

This baseline intentionally forces:

`MEDIA_STORAGE_DRIVER=s3`

Local media storage is not accepted as a production topology because API/worker
or future API replicas must see the same objects.

The bucket must remain private. Wapp continues serving media through its
authenticated message endpoint.

## First configuration

Create the ignored runtime env:

```bash
pnpm prod:init
```

Edit:

`infra/production/.env.production`

Replace every `CHANGE_ME`.

Use strong random values. Do not commit this file.

Then:

```bash
pnpm prod:preflight
```

The preflight checks:

- real public hostname;
- consistent MySQL URL and credentials;
- consistent Redis URL and password;
- JWT length;
- Evolution URL/key/webhook secret;
- S3 bucket and credentials.

It changes no container.

## Build validation

Before first deployment:

```bash
pnpm verify
pnpm prod:preflight
pnpm prod:build
```

This proves both the source production build and Docker production images.

## First deployment

After DNS points to the host and ports 80/443 are allowed:

```bash
pnpm prod:deploy
```

The deploy helper:

1. runs preflight;
2. builds images;
3. starts and waits for MySQL + Redis;
4. executes `prisma migrate deploy`;
5. starts API + dedicated worker + Web + Caddy;
6. waits for service health;
7. prints Compose status.

Then:

```bash
pnpm prod:smoke
```

Expected:

```text
live: OK
ready: OK
health: ok
PASS
```

## Updates

Before a production update:

1. verify the candidate commit with `pnpm verify`;
2. create/verify an off-host database backup according to P1.18;
3. record the currently deployed Git commit/image tag;
4. deploy the new commit;
5. run `pnpm prod:smoke`;
6. validate login and a WhatsApp inbound/outbound message.

Do not use `docker compose down -v`.

`pnpm prod:down` intentionally does not pass `-v`; persistent data remains.

## Logs

```bash
pnpm prod:logs
```

Or isolate a service:

```bash
docker compose \
  --env-file infra/production/.env.production \
  -f infra/production/docker-compose.yml \
  logs -f api worker
```

## Status

```bash
pnpm prod:ps
```

## Evolution

P1.24 does not force Evolution into the same Compose project. It can be the
existing Evolution deployment or a dedicated service.

`EVOLUTION_BASE_URL` must be reachable from the API and worker containers.

Evolution must be able to reach:

`https://<WAPP_DOMAIN>/api/v1/webhooks/evolution/...`

using the existing Wapp webhook contract.

## Secrets

Production secrets live only in:

`infra/production/.env.production`

which is ignored by Git and excluded from Docker build context.

P1.23 `pnpm security:scan` remains part of `pnpm verify`.

## Scaling boundary

This baseline starts one API and one worker.

P1.14 Redis realtime, P1.17 shared storage and P1.19 BullMQ already remove the
main stateful blockers for additional API/worker replicas.

Before horizontal scaling, validate load-balancer/SSE behavior and capacity
under realistic traffic.
