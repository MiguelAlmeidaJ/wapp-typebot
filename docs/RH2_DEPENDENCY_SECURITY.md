# RH2 — Dependency security

RH2 hardens Wapp's dependency supply chain before production.

It does not change the Prisma schema and does not execute a production
migration.

## Prisma alignment

The following packages are pinned together to `7.10.0`:

- `prisma`;
- `@prisma/client`;
- `@prisma/adapter-mariadb`.

Prisma major/version skew is not allowed.

RH2 intentionally stays on Prisma 7 stable and does not move Wapp onto a Prisma
8 release candidate.

## MariaDB connector

The Prisma MariaDB adapter previously resolved `mariadb 3.4.5`.

RH2 applies a scoped pnpm override:

```text
@prisma/adapter-mariadb>mariadb = 3.5.3
```

This is intentionally the smallest patched move in the same 3.4 line.

The RH2 lockfile gate rejects any resolved MariaDB connector below `3.5.3`.

## deepmerge-ts

At the time of RH2, `@prisma/config` still pins `deepmerge-ts 7.1.5`.

That line is affected by CVE-2026-40345 / GHSA-ggr8-5vv4-36mx.

Until Prisma ships the patched dependency itself, Wapp applies the scoped
override:

```text
@prisma/config>deepmerge-ts = 8.0.2
```

This is a major transitive override, so it is accepted only if the complete
Prisma/client generation, unit, integration, typecheck and build gates pass.

The override should be removed once a future stable Prisma release depends on a
patched deepmerge-ts version directly.

## Automated gate

`pnpm security:dependencies` performs three checks:

1. validates the pinned Prisma versions and lockfile floors;
2. runs the complete pnpm vulnerability audit at `moderate` threshold;
3. runs the production-only audit at the same threshold.

The GitHub Quality Gate runs this immediately after dependency installation.

A newly published moderate/high/critical advisory can therefore intentionally
turn the quality gate red. That is a release-safety signal, not something to
bypass with a blind audit fix.

## RH2 validation order

The installer performs:

1. controlled package/override update;
2. lockfile install;
3. explicit lockfile security gate;
4. full dependency audit;
5. production dependency audit;
6. repository secret/security scan;
7. Prisma client generation;
8. unit tests;
9. typecheck;
10. disposable Docker integration tests;
11. application production build;
12. RH1 production-template and Compose structural checks.

No production containers or production volumes are modified.

## pnpm 11 configuration source

`pnpm-workspace.yaml` is the authoritative configuration source for RH2
overrides.

pnpm 11 no longer reads `pnpm.overrides` from the root `package.json`, so the
security overrides must remain in the workspace YAML. The RH2 dependency gate
fails if the obsolete root `pnpm` block returns.


## MariaDB published security line

The initial RH2 plan targeted `mariadb 3.4.6`. The npm registry used by this
workspace does not publish that release and reports `3.5.3` as the current
published patched GA line.

Wapp therefore pins the transitive Prisma MariaDB connector to `3.5.3`.
The dependency gate rejects older MariaDB resolutions.

## mysql2 transitively used by Prisma

After the Prisma 7.10.0 alignment, the dependency audit exposed two active
advisories through Prisma's transitive `mysql2` dependency:

- authentication-plugin downgrade / plaintext credential exposure;
- unbounded zlib inflate / decompression-bomb denial of service.

The common patched floor is `mysql2 >= 3.23.1`.

Wapp applies the scoped pnpm 11 workspace override:

```text
prisma>mysql2 = 3.23.1
```

This is intentionally scoped to Prisma instead of forcing every future
workspace consumer of mysql2 to the same resolution.

The RH2 gate rejects any mysql2 resolution below 3.23.1. As with the
deepmerge-ts override, this override should be re-evaluated when Prisma ships a
stable release whose own dependency tree already satisfies the security floor.
