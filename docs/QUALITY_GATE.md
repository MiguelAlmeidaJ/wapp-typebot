# P1.22 Automated quality gate

P1.22 introduces the first automated regression gate for Wapp.

## Local commands

Fast deterministic tests:

```bash
pnpm test
```

Full pre-commit/release verification:

```bash
pnpm verify
```

`verify` runs:

1. Prisma client generation;
2. API regression tests;
3. workspace typecheck;
4. production builds.

No database, Redis or Evolution instance is required by the unit tests.

## Runtime smoke

With the local stack running:

```bash
pnpm smoke
```

The smoke check validates:

- `/health/live`;
- `/health/ready`;
- `/health`.

`/health/ready` must return HTTP 200 with `ready=true`, therefore the smoke
check also exercises the configured MySQL and Redis readiness path.

Override the target API:

```bash
WAPP_SMOKE_API_URL=https://api.example.com pnpm smoke
```

The smoke command does not use credentials and does not mutate application
data.

## Regression coverage

### RBAC

The centralized backend permission matrix is tested for OWNER, ADMIN,
SUPERVISOR and AGENT.

The tests specifically protect the management boundaries around:

- team;
- queues;
- WhatsApp connections;
- quick replies;
- tags;
- SLA;
- admin test operations.

### Message history pagination

P1.21 keyset pagination is protected by tests for:

- older cursor;
- newer cursor;
- deterministic timestamp + UUID tie-break;
- ascending browser order;
- descending newest-page database order.

This prevents duplicate/omitted rows when two WhatsApp messages share the same
timestamp.

## GitHub Actions

`.github/workflows/quality-gate.yml` runs on:

- pull requests;
- pushes to `develop`;
- pushes to `main`.

The job performs the same test/typecheck/build sequence used locally.

The CI workflow intentionally does not require production secrets and does not
start MySQL, Redis or Evolution.

Integration/runtime behavior remains validated by `pnpm smoke` and the manual
feature acceptance checks.

## Rule going forward

A P1/P2 patch should not be treated as complete if it causes:

```bash
pnpm test
pnpm typecheck
```

to fail.

Before a release/deploy candidate, use:

```bash
pnpm verify
```

and then run `pnpm smoke` against the target environment.

## P3.5.1 CI stabilization

The Quality Gate now provides non-secret placeholder `DATABASE_URL` and
`SHADOW_DATABASE_URL` values so Prisma configuration can load during
`prisma generate`. Client generation does not connect to those placeholder
databases.

The workflow also runs `pnpm test:integration`. That integration suite starts
disposable MySQL 8.4 and Redis containers, overrides `DATABASE_URL`, applies
the real migration chain and destroys the disposable containers afterwards.

The P3 integration coverage now crosses:

- Contact 360 custom field persistence;
- pipeline creation and contact stage movement;
- CRM follow-up task creation;
- saved segment resolution;
- explicit campaign consent and campaign audience preview.

A green local unit suite alone is therefore not the release gate for P3.
