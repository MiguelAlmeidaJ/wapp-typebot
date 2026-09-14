# Wapp production deployment with PM2

PM2 is the primary Wapp runtime on the application server.

The production topology is intentionally simple:

```text
Internet
   |
80 / 443
   |
Reverse proxy (Nginx or Caddy)
   |----------------------|
127.0.0.1:3301       127.0.0.1:4401
   Web                    API
                           |
                           +-- MySQL
                           +-- Redis
                           +-- Evolution API
                           +-- media storage
                           |
                        PM2 worker
```

PM2 owns these processes:

- `wapp-api`
- `wapp-worker`
- `wapp-web`

MySQL, Redis, Evolution and the reverse proxy may run on the same host or on
separate infrastructure. They are not managed by the Wapp PM2 ecosystem.

## Host requirements

- Linux server
- Node.js 24
- pnpm 11.x
- PM2 installed globally and available in `PATH`
- MySQL reachable through `DATABASE_URL`
- Redis reachable through `REDIS_URL`
- valid MySQL CA certificate for production TLS
- reverse proxy terminating public HTTPS
- DNS pointing the public Wapp hostname to the reverse proxy

Install PM2 if needed:

```bash
npm install --global pm2
```

## Production environment

Create the ignored environment file:

```bash
pnpm prod:init
```

This creates:

```text
infra/pm2/production.env
```

Edit the file and replace every `CHANGE_ME` value.

The template keeps API and Web bound to loopback by default:

```text
API  127.0.0.1:4401
Web  127.0.0.1:3301
```

The reverse proxy is the only public HTTP entrypoint.

## MySQL TLS

`NODE_ENV=production` requires `DATABASE_TLS_CA_PATH`.

The same CA path is also present in the Prisma URLs through the TLS query
parameters so `prisma migrate deploy` uses encrypted transport as well.

Example:

```text
DATABASE_TLS_CA_PATH=/etc/wapp/mysql/ca.pem
```

The file must be readable by the user running PM2.

## Media storage

Single-host PM2 deployment supports local shared media storage because API and
worker use the same filesystem.

Prefer an absolute path outside the Git checkout:

```text
MEDIA_STORAGE_DRIVER=local
MEDIA_STORAGE_PATH=/var/lib/wapp/media
```

S3-compatible storage remains supported and is preferable before horizontal
scaling or when off-host durability is required.

## Preflight

Before any build or deployment:

```bash
pnpm prod:preflight
```

The preflight blocks deployment when it finds, among other things:

- wrong Node.js major version;
- missing pnpm or PM2;
- `NODE_ENV` different from `production`;
- non-HTTPS public URLs;
- placeholder secrets;
- short JWT / Evolution secrets;
- missing MySQL TLS CA;
- insecure production cookies;
- embedded jobs enabled while a dedicated worker is configured;
- invalid media storage configuration.

## Build only

Validate a production candidate without touching PM2:

```bash
pnpm prod:build
```

This performs:

1. production preflight;
2. `pnpm install --frozen-lockfile`;
3. repository security scan;
4. Prisma client generation;
5. typecheck;
6. full production build.

If any step fails, running PM2 processes are untouched.

## Quality gate

Before promotion to production, the repository quality gate should be green.

Locally:

```bash
pnpm security:dependencies
pnpm verify
pnpm test:integration
```

`test:integration` creates disposable MySQL 8.4 and Redis containers, applies
real migrations, runs the integration suite and removes the containers when the
run ends.

## Deployment

Run:

```bash
pnpm prod:deploy
```

The deployment pipeline performs:

1. preflight;
2. dependency installation with frozen lockfile;
3. security scan;
4. Prisma generation;
5. typecheck;
6. production build;
7. `prisma migrate deploy`;
8. `pm2 startOrReload ecosystem.config.cjs --update-env`;
9. `pm2 save`;
10. public smoke checks.

PM2 is only changed after build and migration succeed.

The smoke test validates:

```text
/health/live
/health/ready
/health
/login
```

Run it manually with:

```bash
pnpm prod:smoke
```

## PM2 operations

Status:

```bash
pnpm prod:ps
```

Logs:

```bash
pnpm prod:logs
```

Stop and remove only the Wapp application processes:

```bash
pnpm prod:down
```

After the first successful deployment, configure PM2 startup persistence for
the server's init system:

```bash
pm2 startup
pm2 save
```

Follow the command printed by `pm2 startup` when it requires elevated
privileges.

## First OWNER

The application already contains a guarded one-time production bootstrap for
the first OWNER.

Check current state:

```bash
pnpm prod:first-owner:status
```

Create the sealed first identity by supplying only non-secret identity values
as process environment variables:

```bash
BOOTSTRAP_OWNER_EMAIL=owner@example.com \
BOOTSTRAP_OWNER_NAME="Owner" \
BOOTSTRAP_COMPANY_NAME="Company" \
pnpm prod:first-owner:bootstrap
```

Then finalize the password through standard input. Do not store the final
password in `production.env`.

The finalize command requires `BOOTSTRAP_OWNER_EMAIL` and reads the new password
from stdin:

```bash
BOOTSTRAP_OWNER_EMAIL=owner@example.com pnpm prod:first-owner:finalize
```

Use a secure method to provide stdin on the server and avoid placing the real
password directly in shell history.

## Reverse proxy

The reverse proxy should route application traffic to the loopback services.

Typical routing:

```text
/api/*      -> 127.0.0.1:4401
/health*    -> 127.0.0.1:4401
all others  -> 127.0.0.1:3301
```

The public hostname used by the proxy must match `WEB_URL`,
`NEXT_PUBLIC_API_URL` and normally `EVOLUTION_WEBHOOK_BASE_URL`.

## Update procedure

For each release:

1. confirm the candidate commit passed the quality gate;
2. create and verify a database backup;
3. record the currently deployed Git commit;
4. pull/checkout the new release on the server;
5. run `pnpm prod:build` if you want a dry deployment check;
6. run `pnpm prod:deploy`;
7. validate login and one inbound/outbound WhatsApp flow;
8. monitor `pnpm prod:logs` after release.

## Docker production stack

`infra/production/` is retained as an optional Docker Compose deployment model.
It is not the primary server runtime.

The explicit Docker commands are namespaced as:

```bash
pnpm prod:docker:config
pnpm prod:docker:build
pnpm prod:docker:up
pnpm prod:docker:down
```

Do not run the PM2 and Docker application runtimes simultaneously against the
same ports and production identity unless that topology is intentionally being
tested.
