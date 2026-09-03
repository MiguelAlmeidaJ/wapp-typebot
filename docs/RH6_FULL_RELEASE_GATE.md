# RH6 — Full release gate

RH6 is the final code/release-candidate gate after RH1 through RH5.

It does not deploy production automatically.

A successful RH6 means the repository is an approved release candidate and can
enter the explicit production deployment procedure.

## What RH6 validates

The final gate validates:

- RH2 dependency floors and `pnpm audit` at `moderate`;
- repository security scan;
- Prisma schema and client generation;
- complete unit test suite;
- TypeScript typechecks;
- production application build;
- production environment template;
- production Compose structure;
- RH3 MySQL 8.4 TLS hardening;
- RH4 encrypted backup/restore design;
- RH5 one-shot first OWNER bootstrap;
- full integration suite;
- disposable MySQL TLS rehearsal;
- destructive encrypted backup/restore drill;
- first OWNER lifecycle drill;
- Node 24 / pnpm 11 baseline;
- expected Prisma migration history;
- clean Git working tree for the final gate.

Untracked `.patch` delivery artifacts are ignored by the clean-tree check because
they are not part of the repository.

## Commands

Fast static topology check:

```bash
pnpm release:gate:static
```

CI-compatible release gate:

```bash
pnpm release:gate:ci
```

CI mode runs the compile/test/security checks but skips the Docker staging
drills.

Full release-candidate gate:

```bash
pnpm release:gate:final
```

This is the command that must pass before creating a production release.

## Isolated staging rehearsal

```bash
pnpm rh6:staging
```

The rehearsal does not use the production Compose project or production named
volumes.

It executes:

1. production Compose structural validation;
2. Wapp integration suite;
3. RH3 disposable MySQL 8.4 mandatory-TLS rehearsal;
4. RH4 encrypted backup + destructive restore drill;
5. RH5 first OWNER lifecycle drill.

Each database container is disposable.

## Production pre-deployment gate

RH6 also adds:

```bash
pnpm prod:release:preflight
```

Unlike the repository release gate, this command is intended for the real
production deployment host.

It requires the real ignored:

```text
infra/production/.env.production
```

and checks:

- no tracked Git changes;
- no production placeholders;
- production environment semantics;
- real MySQL TLS certificate material;
- real external backup directory;
- real backup passphrase file;
- retention settings;
- production Compose resolution.

It does not start or modify production containers.

## Production activation remains explicit

RH6 deliberately does not automate the real production cutover.

After the code release candidate passes, the deployment procedure still
requires the operator to:

1. provision the real production `.env.production`;
2. provision/validate MySQL TLS certificates;
3. provision external backup storage and backup passphrase;
4. run `pnpm prod:release:preflight`;
5. deploy the approved image/tag;
6. execute production migrations through the controlled deploy workflow;
7. validate `pnpm prod:mysql:verify`;
8. initialize the first OWNER only on a new empty installation;
9. create and verify the first real encrypted production backup;
10. perform application smoke checks before opening user traffic.

Production is not considered activated merely because RH6 passed on a
development workstation.

## Transient installer cleanup

RH6 removes RH1-RH5 installation/recovery scripts.

Those scripts were patch-application mechanisms, not permanent operational
commands. Keeping old recovery installers in the final tree creates ambiguity,
especially where an earlier recovery script referenced an obsolete dependency
version.

The permanent `prod:*`, `release:*`, drill and static-gate commands remain.

Git history preserves the removed installers.

## Release decision

After:

```bash
pnpm release:gate:final
```

returns:

```text
[RH6] FULL RELEASE GATE PASS.
```

the codebase is a GO release candidate for the controlled production deployment
workflow.

Any failure in RH6 is a NO-GO until corrected and rerun.
