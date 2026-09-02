#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_PACKAGE="package.json"
API_PACKAGE="apps/api/package.json"
LOCKFILE="pnpm-lock.yaml"
QUALITY=".github/workflows/quality-gate.yml"

PRISMA_VERSION="7.10.0"
MARIADB_VERSION="3.4.6"
DEEPMERGE_VERSION="8.0.2"

echo "[RH2] Installing dependency security hardening..."

for check in \
  "$ROOT_PACKAGE|\"packageManager\": \"pnpm@11.16.0\"" \
  "$API_PACKAGE|\"@prisma/adapter-mariadb\"" \
  "$API_PACKAGE|\"@prisma/client\"" \
  "$API_PACKAGE|\"prisma\"" \
  "$LOCKFILE|lockfileVersion: '9.0'" \
  "$QUALITY|name: Quality Gate"
do
  file="${check%%|*}"
  marker="${check#*|}"

  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: RH2 prerequisite missing:"
    echo "  $file -> $marker"
    echo "RH2 made no changes."
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");

const apiPath =
  "apps/api/package.json";

const rootPath =
  "package.json";

const api =
  JSON.parse(
    fs.readFileSync(
      apiPath,
      "utf8"
    )
  );

const root =
  JSON.parse(
    fs.readFileSync(
      rootPath,
      "utf8"
    )
  );

const prismaVersion =
  "7.10.0";

for (
  const dependency
  of [
    "@prisma/adapter-mariadb",
    "@prisma/client"
  ]
) {
  if (
    !api.dependencies?.[
      dependency
    ]
  ) {
    throw new Error(
      `${dependency} is missing from apps/api/package.json.`
    );
  }

  api.dependencies[
    dependency
  ] =
    prismaVersion;
}

if (
  !api.devDependencies
    ?.prisma
) {
  throw new Error(
    "prisma CLI is missing from apps/api devDependencies."
  );
}

api.devDependencies.prisma =
  prismaVersion;

root.pnpm ??=
  {};

root.pnpm.overrides ??=
  {};

root.pnpm.overrides[
  "@prisma/adapter-mariadb>mariadb"
] =
  "3.4.6";

root.pnpm.overrides[
  "@prisma/config>deepmerge-ts"
] =
  "8.0.2";

root.scripts ??=
  {};

root.scripts[
  "security:dependencies"
] =
  "node scripts/rh2-dependency-security-gate.mjs && pnpm audit --audit-level moderate && pnpm audit --prod --audit-level moderate";

fs.writeFileSync(
  apiPath,
  `${JSON.stringify(
    api,
    null,
    2
  )}\n`
);

fs.writeFileSync(
  rootPath,
  `${JSON.stringify(
    root,
    null,
    2
  )}\n`
);

console.log(
  "[RH2] Prisma versions and scoped pnpm overrides prepared."
);
NODE

cat > scripts/rh2-dependency-security-gate.mjs <<'EOF'
import {
  readFile
} from "node:fs/promises";

const PRISMA_VERSION =
  "7.10.0";

const MARIADB_MINIMUM =
  "3.4.6";

const MARIADB_OVERRIDE =
  "3.4.6";

const DEEPMERGE_MINIMUM =
  "8.0.0";

const DEEPMERGE_OVERRIDE =
  "8.0.2";

function fail(
  message
) {
  throw new Error(
    message
  );
}

function compareVersions(
  left,
  right
) {
  const leftParts =
    left
      .split(
        "."
      )
      .map(
        Number
      );

  const rightParts =
    right
      .split(
        "."
      )
      .map(
        Number
      );

  for (
    let index =
      0;
    index <
      Math.max(
        leftParts.length,
        rightParts.length
      );
    index +=
      1
  ) {
    const a =
      leftParts[
        index
      ] ??
      0;

    const b =
      rightParts[
        index
      ] ??
      0;

    if (
      a <
      b
    ) {
      return -1;
    }

    if (
      a >
      b
    ) {
      return 1;
    }
  }

  return 0;
}

function lockVersions(
  lock,
  packageName
) {
  const escaped =
    packageName.replace(
      /[.*+?^${}()|[\]\\]/g,
      "\\$&"
    );

  const expression =
    new RegExp(
      `^\\s{2,4}'?${escaped}@([0-9]+\\.[0-9]+\\.[0-9]+)'?(?:\\([^\\n]*\\))?:`,
      "gm"
    );

  return [
    ...new Set(
      Array.from(
        lock.matchAll(
          expression
        ),
        match =>
          match[
            1
          ]
      )
    )
  ];
}

const [
  rootSource,
  apiSource,
  lock
] =
  await Promise.all([
    readFile(
      "package.json",
      "utf8"
    ),
    readFile(
      "apps/api/package.json",
      "utf8"
    ),
    readFile(
      "pnpm-lock.yaml",
      "utf8"
    )
  ]);

const root =
  JSON.parse(
    rootSource
  );

const api =
  JSON.parse(
    apiSource
  );

for (
  const [
    location,
    version
  ]
  of [
    [
      "@prisma/client",
      api.dependencies
        ?.["@prisma/client"]
    ],
    [
      "@prisma/adapter-mariadb",
      api.dependencies
        ?.["@prisma/adapter-mariadb"]
    ],
    [
      "prisma",
      api.devDependencies
        ?.prisma
    ]
  ]
) {
  if (
    version !==
    PRISMA_VERSION
  ) {
    fail(
      `${location} must be pinned exactly to ${PRISMA_VERSION}; found ${version ?? "missing"}.`
    );
  }
}

const overrides =
  root.pnpm
    ?.overrides ??
  {};

if (
  overrides[
    "@prisma/adapter-mariadb>mariadb"
  ] !==
  MARIADB_OVERRIDE
) {
  fail(
    `MariaDB scoped override must be ${MARIADB_OVERRIDE}.`
  );
}

if (
  overrides[
    "@prisma/config>deepmerge-ts"
  ] !==
  DEEPMERGE_OVERRIDE
) {
  fail(
    `deepmerge-ts scoped override must be ${DEEPMERGE_OVERRIDE}.`
  );
}

for (
  const marker
  of [
    `specifier: ${PRISMA_VERSION}`,
    `version: ${PRISMA_VERSION}`,
    `'@prisma/adapter-mariadb@${PRISMA_VERSION}'`,
    `'@prisma/client@${PRISMA_VERSION}'`,
    `'prisma@${PRISMA_VERSION}'`
  ]
) {
  if (
    !lock.includes(
      marker
    )
  ) {
    fail(
      `Lockfile marker missing after upgrade: ${marker}`
    );
  }
}

const mariadbVersions =
  lockVersions(
    lock,
    "mariadb"
  );

if (
  mariadbVersions.length ===
  0
) {
  fail(
    "No resolved mariadb package found in pnpm-lock.yaml."
  );
}

for (
  const version
  of mariadbVersions
) {
  if (
    compareVersions(
      version,
      MARIADB_MINIMUM
    ) <
    0
  ) {
    fail(
      `Vulnerable mariadb resolution remains: ${version}; minimum is ${MARIADB_MINIMUM}.`
    );
  }
}

if (
  !mariadbVersions.includes(
    MARIADB_OVERRIDE
  )
) {
  fail(
    `Expected mariadb ${MARIADB_OVERRIDE} in lockfile; found ${mariadbVersions.join(", ")}.`
  );
}

const deepmergeVersions =
  lockVersions(
    lock,
    "deepmerge-ts"
  );

if (
  deepmergeVersions.length ===
  0
) {
  fail(
    "No resolved deepmerge-ts package found in pnpm-lock.yaml."
  );
}

for (
  const version
  of deepmergeVersions
) {
  if (
    compareVersions(
      version,
      DEEPMERGE_MINIMUM
    ) <
    0
  ) {
    fail(
      `Vulnerable deepmerge-ts resolution remains: ${version}; minimum is ${DEEPMERGE_MINIMUM}.`
    );
  }
}

if (
  !deepmergeVersions.includes(
    DEEPMERGE_OVERRIDE
  )
) {
  fail(
    `Expected deepmerge-ts ${DEEPMERGE_OVERRIDE} in lockfile; found ${deepmergeVersions.join(", ")}.`
  );
}

for (
  const vulnerableMarker
  of [
    "mariadb@3.4.5",
    "deepmerge-ts@7.1.5"
  ]
) {
  if (
    lock.includes(
      vulnerableMarker
    )
  ) {
    fail(
      `Known vulnerable lockfile marker remains: ${vulnerableMarker}`
    );
  }
}

console.log(
  `[RH2] dependency gate PASS — Prisma ${PRISMA_VERSION}; mariadb ${mariadbVersions.join(", ")}; deepmerge-ts ${deepmergeVersions.join(", ")}.`
);
EOF

node <<'NODE'
const fs = require("node:fs");

const path =
  ".github/workflows/quality-gate.yml";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

/*
 * P3.5.1 introduced Prisma placeholder URLs, but two of those keys were
 * accidentally aligned as job-level keys instead of entries under `env`.
 * Normalize the whole small env block while RH2 is already touching the
 * quality gate.
 */
const malformedEnv = `    env:
      NEXT_PUBLIC_API_URL: http://localhost:4000
    DATABASE_URL: mysql://wapp_ci:wapp_ci@127.0.0.1:3306/wapp_ci
    SHADOW_DATABASE_URL: mysql://wapp_ci:wapp_ci@127.0.0.1:3306/wapp_ci_shadow
`;

const correctEnv = `    env:
      NEXT_PUBLIC_API_URL: http://localhost:4000
      DATABASE_URL: mysql://wapp_ci:wapp_ci@127.0.0.1:3306/wapp_ci
      SHADOW_DATABASE_URL: mysql://wapp_ci:wapp_ci@127.0.0.1:3306/wapp_ci_shadow
`;

if (
  content.includes(
    malformedEnv
  )
) {
  content =
    content.replace(
      malformedEnv,
      correctEnv
    );
} else if (
  !content.includes(
    correctEnv
  )
) {
  throw new Error(
    "Quality Gate env block differs from the expected RH1/P3.5 baseline."
  );
}

if (
  !content.includes(
    "      - name: Dependency audit"
  )
) {
  const anchor = `      - name: Security scan
        run: pnpm security:scan
`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Security scan workflow anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `      - name: Dependency audit
        run: pnpm security:dependencies

${anchor}`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[RH2] Quality Gate now enforces dependency audit."
);
NODE

cat > docs/RH2_DEPENDENCY_SECURITY.md <<'EOF'
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
@prisma/adapter-mariadb>mariadb = 3.4.6
```

This is intentionally the smallest patched move in the same 3.4 line.

The RH2 lockfile gate rejects any resolved MariaDB connector below `3.4.6`.

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
EOF

echo "[RH2] Updating lockfile and installed dependency graph..."
pnpm install --no-frozen-lockfile

echo "[RH2] Explicit dependency resolution gate..."
node scripts/rh2-dependency-security-gate.mjs

echo "[RH2] Full dependency audit — moderate and above..."
pnpm audit --audit-level moderate

echo "[RH2] Production dependency audit — moderate and above..."
pnpm audit --prod --audit-level moderate

echo "[RH2] Repository security scan..."
pnpm security:scan

echo "[RH2] Prisma generate..."
pnpm db:generate

echo "[RH2] Unit tests..."
pnpm test

echo "[RH2] Typecheck..."
pnpm typecheck

echo "[RH2] Integration tests..."
pnpm test:integration

echo "[RH2] Production application build..."
pnpm build

echo "[RH2] Rechecking RH1 production template..."
pnpm prod:template

echo "[RH2] Rechecking production Compose structure..."
docker compose \
  --env-file infra/production/.env.production.example \
  -f infra/production/docker-compose.yml \
  config \
  --quiet

echo
echo "[RH2] DEPENDENCY SECURITY PASS."
echo
echo "Resolved security floors:"
echo "  Prisma CLI / Client / adapter: $PRISMA_VERSION"
echo "  mariadb: >= $MARIADB_VERSION"
echo "  deepmerge-ts: >= 8.0.0 (override $DEEPMERGE_VERSION)"
echo
echo "No Prisma migration was created or executed against production."
echo "Disposable integration-test containers may have been created and removed."
echo "Production containers and production volumes were not modified."
echo
echo "Next release-hardening milestone: RH3 MySQL production security."
