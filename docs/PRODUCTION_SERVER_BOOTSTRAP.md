# Wapp production server bootstrap (PM2)

This runbook prepares a fresh Linux application server for the PM2 production topology.

The Wapp application processes are:

- `wapp-api` on `127.0.0.1:4401`
- `wapp-worker`
- `wapp-web` on `127.0.0.1:3301`

Only the reverse proxy should expose public HTTP/HTTPS traffic.

## 1. Application directory

Use a dedicated checkout owned by the deploy user, for example:

```bash
sudo mkdir -p /srv/wapp
sudo chown "$USER":"$(id -gn)" /srv/wapp
git clone https://github.com/MiguelAlmeidaJ/wapp-typebot.git /srv/wapp
cd /srv/wapp
```

For the final production release, deploy an approved `main` commit or release tag. `develop` is appropriate only while rehearsing the production path.

## 2. Runtime requirements

Verify:

```bash
node --version
pnpm --version
pm2 --version
git --version
```

Wapp requires Node.js 24. The repository pins pnpm 11.16.0.

Install PM2 globally when needed:

```bash
npm install --global pm2
```

## 3. Persistent application directories

For local media storage on a single PM2 host:

```bash
sudo install -d -o "$USER" -g "$(id -gn)" -m 0750 /var/lib/wapp/media
```

Prepare the MySQL CA directory:

```bash
sudo install -d -o root -g "$(id -gn)" -m 0750 /etc/wapp/mysql
sudo install -o root -g "$(id -gn)" -m 0640 /path/to/mysql-ca.pem /etc/wapp/mysql/ca.pem
```

The deploy/PM2 user must be able to read `/etc/wapp/mysql/ca.pem`.

## 4. MySQL

The production connection is expected to use TLS. The Prisma migration URL and the API runtime use the same CA certificate.

The application needs two databases:

```text
wapp
wapp_shadow
```

A typical dedicated MySQL account is `wapp`. Grant it access only to those databases.

Example SQL, adapting host and credentials to the actual MySQL topology:

```sql
CREATE DATABASE IF NOT EXISTS wapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS wapp_shadow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'wapp'@'127.0.0.1' IDENTIFIED BY 'REPLACE_WITH_STRONG_PASSWORD' REQUIRE SSL;
GRANT ALL PRIVILEGES ON wapp.* TO 'wapp'@'127.0.0.1';
GRANT ALL PRIVILEGES ON wapp_shadow.* TO 'wapp'@'127.0.0.1';
FLUSH PRIVILEGES;
```

Confirm MySQL TLS before deployment:

```sql
SHOW VARIABLES LIKE 'have_ssl';
SHOW VARIABLES LIKE 'require_secure_transport';
```

When MySQL is remote or containerized, adjust the account host and networking instead of copying the local-host example literally.

## 5. Redis

Redis must be reachable from the application server and protected by authentication.

For a same-host Redis installation, keep it bound to loopback and protected from the public network. The production URL is normally similar to:

```text
redis://:STRONG_PASSWORD@127.0.0.1:6379/0
```

Do not expose port `6379` publicly.

## 6. Production environment

Create the ignored environment file:

```bash
pnpm prod:init
```

This generates strong random values for:

- `JWT_SECRET`
- `METRICS_TOKEN`
- `EVOLUTION_WEBHOOK_SECRET`

Edit:

```text
infra/pm2/production.env
```

Replace every remaining `CHANGE_ME` value. Database passwords containing URL-special characters must be percent-encoded in `DATABASE_URL` and `SHADOW_DATABASE_URL`.

Lock down the file:

```bash
chmod 600 infra/pm2/production.env
```

## 7. Static preflight

Run:

```bash
pnpm prod:preflight
```

This blocks common unsafe configurations, including public API/Web binds, weak or placeholder secrets, insecure cookies, missing MySQL CA, mismatched Prisma TLS settings and unsafe environment-file permissions.

## 8. Real server readiness

Run:

```bash
pnpm prod:server:check
```

The server check validates the actual host and network, including:

- Linux / Node.js 24;
- `git`, `pnpm` and `pm2` availability;
- `production.env` permissions;
- MySQL CA readability;
- local media-directory permissions;
- DNS resolution;
- TCP connectivity to MySQL, Redis and Evolution;
- Typebot connectivity when enabled;
- presence of a local HTTPS reverse proxy;
- PM2 startup persistence status.

Reverse-proxy and PM2-startup checks are warnings until those pieces are configured. Database, Redis, Evolution, certificate and filesystem failures are blocking.

## 9. Reverse proxy

An Nginx server-block example is versioned at:

```text
infra/pm2/nginx.conf.example
```

It routes:

```text
/api/*      -> 127.0.0.1:4401
/health*    -> 127.0.0.1:4401
all others  -> 127.0.0.1:3301
```

The API location disables proxy buffering and uses a long read timeout because `/api/v1/realtime/events` is a Server-Sent Events stream.

If using Nginx Proxy Manager, configure the main proxy host to `127.0.0.1:3301`, then add custom locations for `/api/` and `/health` that forward to `127.0.0.1:4401`. Disable buffering for the API/SSE location and keep WebSocket support enabled if the proxy product requires it globally.

Public TLS must be valid before the final smoke test.

## 10. Candidate validation

Before touching PM2:

```bash
pnpm security:dependencies
pnpm verify
pnpm test:integration
pnpm prod:build
```

The GitHub Quality Gate should also be green for the exact candidate commit.

## 11. First deployment

Run:

```bash
pnpm prod:deploy
```

The deploy applies Prisma migrations only after a successful production build, then starts/reloads API, worker and Web through PM2 and runs public smoke checks.

Inspect:

```bash
pnpm prod:ps
pnpm prod:logs
```

## 12. PM2 boot persistence

After the first successful deploy:

```bash
pm2 startup
```

Execute the privileged command printed by PM2, then:

```bash
pm2 save
systemctl status "pm2-$USER" --no-pager
```

Run `pnpm prod:server:check` again. The PM2 startup warning should disappear.

## 13. First OWNER

Check bootstrap state:

```bash
pnpm prod:first-owner:status
```

Then follow the guarded bootstrap/finalize procedure documented in `docs/PRODUCTION_DEPLOYMENT.md`. Never store the final OWNER password in `production.env` or shell history.

## 14. Final acceptance

Before declaring the server production-ready, verify all of these:

```text
Quality Gate                    PASS
pnpm prod:preflight             PASS
pnpm prod:server:check          PASS (no blocking errors)
pnpm prod:deploy                PASS
pnpm prod:smoke                 PASS
PM2 startup persistence         enabled
HTTPS certificate               valid
/login                          reachable
WhatsApp inbound                validated
WhatsApp outbound               validated
media upload/download           validated
backup + restore procedure      validated
```
