# RH3 — MySQL production security

RH3 closes the production MySQL authentication/transport gap.

The production database remains MySQL 8.4 and continues to use the default
`caching_sha2_password` authentication plugin. RH3 does not enable the
deprecated `mysql_native_password` compatibility plugin.

## Production transport model

The production MySQL service starts with:

```text
require_secure_transport=ON
tls-version=TLSv1.2,TLSv1.3
```

The server is configured with a dedicated CA-signed certificate whose SAN
contains `DNS:mysql`.

Unencrypted TCP connections are rejected by the server.

## Prisma runtime

The Wapp runtime uses `@prisma/adapter-mariadb`.

In production:

- `allowPublicKeyRetrieval` is disabled;
- `DATABASE_TLS_CA_PATH` is mandatory;
- the adapter receives the trusted CA;
- `rejectUnauthorized` is enabled;
- normal Node.js hostname verification checks the MySQL certificate identity.

In development, the existing local-Docker flow remains available with public
key retrieval and TLS disabled.

## Prisma migrations

Prisma CLI migrations do not use Wapp's runtime driver-adapter configuration.

For that reason, the production `DATABASE_URL` and `SHADOW_DATABASE_URL`
explicitly include:

```text
sslcert=/etc/wapp/mysql-tls/ca.pem
sslaccept=strict
```

The migration container receives the same CA file as the API and worker.

## Certificate material

Run on the Linux production deployment host:

```bash
pnpm prod:mysql:tls:init
```

This creates:

```text
infra/production/mysql-tls/ca-key.pem
infra/production/mysql-tls/ca.pem
infra/production/mysql-tls/server-key.pem
infra/production/mysql-tls/server-cert.pem
```

The entire directory is ignored by Git.

The CA private key is host-only and is never mounted into MySQL, API, worker or
migration containers.

The initializer refuses to overwrite an existing certificate set. Rotation is
therefore an explicit future operation rather than an accidental side effect of
deploy.

Validate the certificate set with:

```bash
pnpm prod:mysql:tls:check
```

The check verifies the chain, the `DNS:mysql` SAN and that the server
certificate does not expire within 30 days.

## Disposable rehearsal

RH3 includes:

```bash
pnpm rh3:mysql:rehearsal
```

The rehearsal:

1. creates a disposable CA and server certificate;
2. starts an ephemeral MySQL 8.4 container;
3. requires TLS 1.2/1.3 and secure transport;
4. confirms the Wapp user uses `caching_sha2_password`;
5. proves a plaintext TCP login is rejected;
6. runs the actual Wapp Prisma adapter under `NODE_ENV=production`;
7. verifies the Prisma session has a non-empty `Ssl_cipher`;
8. removes the temporary MySQL container and TLS material.

No named database volume is used by the rehearsal.

## Post-deploy verification

After a real deployment:

```bash
pnpm prod:mysql:verify
```

This checks:

- `@@require_secure_transport`;
- the application account authentication plugin;
- rejection of plaintext TCP;
- the TLS cipher used by the running API Prisma connection.

## Production environment update

RH3 changes the tracked production template. An existing
`infra/production/.env.production` is intentionally not modified.

Before the next production preflight, update the real environment so that:

```text
DATABASE_TLS_CA_PATH=/etc/wapp/mysql-tls/ca.pem
DATABASE_URL=.../wapp?sslcert=/etc/wapp/mysql-tls/ca.pem&sslaccept=strict
SHADOW_DATABASE_URL=.../wapp_shadow?sslcert=/etc/wapp/mysql-tls/ca.pem&sslaccept=strict
```

Do not copy development database settings into production.

## RH3 does not deploy production

The installer does not generate or rotate real production certificates and
does not start the production Compose stack.

The only container started by RH3 validation is the disposable TLS rehearsal
MySQL instance, which is deleted automatically.

No production volume is modified.
