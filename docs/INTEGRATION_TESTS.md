# P1.25 Isolated integration tests

`pnpm test:integration` starts disposable MySQL 8.4 and Redis containers using
random host ports.

It never points at the normal Wapp database or Redis instance.

The suite applies all Prisma migrations and validates the real Fastify/Prisma
stack for:

- `/health/live`;
- `/health/ready` with MySQL + Redis;
- login and authenticated `/me`;
- OWNER/AGENT RBAC;
- refresh-token rotation;
- logout/session revocation;
- P1.21 newest message page;
- older cursor pagination;
- exact `around=<messageId>` history lookup.

Containers are removed by a shell trap on success or failure.

No named Docker volume is created and no `down -v` command is used.
