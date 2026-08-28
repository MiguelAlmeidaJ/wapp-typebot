# Wapp P1 closure

P1 is considered technically closed after all of the following are green:

- P1.25 isolated integration tests;
- P1.26 administrative audit migration + integration test;
- P1.27 maintenance migration + integration test;
- P1.28 metrics/alerts tests;
- P1.29 isolated staging rehearsal.

Final local closure command:

```bash
pnpm staging:rehearsal
```

The rehearsal uses production Dockerfiles but does NOT use the production
Compose environment, domain, TLS certificate, database, Redis, Evolution
credentials or S3 bucket.

It creates disposable:

- MySQL 8.4;
- Redis 7;
- MinIO S3-compatible storage;
- migration container;
- Fastify API;
- dedicated BullMQ worker;
- Next.js standalone server;
- local Caddy reverse proxy.

Validation includes:

- the complete `pnpm verify` quality gate;
- production Docker image builds;
- Prisma `migrate deploy`;
- MySQL/Redis readiness;
- private shared S3 bucket initialization;
- dedicated worker startup;
- compiled maintenance run;
- API live/ready/health smoke;
- Web `/login` smoke;
- authenticated Prometheus scrape.

Default local URL:

`http://127.0.0.1:18080`

The stack is automatically removed at the end. It uses no named data volumes
and never runs `docker compose down -v`.

For investigation, keep the stack after a run:

```bash
WAPP_STAGING_KEEP=1 pnpm staging:rehearsal
```

This is staging/rehearsal only. P1.24 production deployment remains prepared
but intentionally untested until a real deployment window is approved.
