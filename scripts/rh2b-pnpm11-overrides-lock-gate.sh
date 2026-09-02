#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_PACKAGE="package.json"
API_PACKAGE="apps/api/package.json"
WORKSPACE="pnpm-workspace.yaml"
LOCKFILE="pnpm-lock.yaml"
GATE="scripts/rh2-dependency-security-gate.mjs"

echo "[RH2b] Repairing pnpm 11 overrides + lockfile gate..."

for check in \
  "$ROOT_PACKAGE|\"security:dependencies\"" \
  "$API_PACKAGE|\"@prisma/client\": \"7.10.0\"" \
  "$API_PACKAGE|\"@prisma/adapter-mariadb\": \"7.10.0\"" \
  "$API_PACKAGE|\"prisma\": \"7.10.0\"" \
  "$WORKSPACE|packages:" \
  "$LOCKFILE|lockfileVersion: '9.0'" \
  "$GATE|dependency gate"
do
  file="${check%%|*}"
  marker="${check#*|}"

  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: RH2b expected partial RH2 state is missing:"
    echo "  $file -> $marker"
    echo "Do not rerun RH2 blindly; inspect the current tree."
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");

const path =
  "package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

if (
  pkg.pnpm &&
  Object.keys(
    pkg.pnpm
  ).length >
    0
) {
  /*
   * pnpm 11 no longer reads these settings from package.json.
   * RH2 only added overrides here, so remove the obsolete block rather than
   * keeping a misleading configuration source.
   */
  delete pkg.pnpm;
}

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);

console.log(
  "[RH2b] Removed ignored package.json pnpm settings."
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "pnpm-workspace.yaml";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const managedStart =
  "# --- WAPP RH2 / SECURITY OVERRIDES ---";

const managedEnd =
  "# --- /WAPP RH2 ---";

const managedBlock = `${managedStart}
overrides:
  '@prisma/adapter-mariadb>mariadb': 3.4.6
  '@prisma/config>deepmerge-ts': 8.0.2
${managedEnd}
`;

if (
  content.includes(
    managedStart
  )
) {
  const start =
    content.indexOf(
      managedStart
    );

  const end =
    content.indexOf(
      managedEnd,
      start
    );

  if (
    end <
    0
  ) {
    throw new Error(
      "RH2 workspace override block is incomplete."
    );
  }

  const afterEnd =
    end +
    managedEnd.length;

  content =
    content.slice(
      0,
      start
    ) +
    managedBlock +
    content.slice(
      afterEnd
    ).replace(
      /^\n*/,
      "\n"
    );
} else {
  content =
    content.trimEnd() +
    "\n\n" +
    managedBlock;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[RH2b] pnpm 11 workspace overrides installed."
);
NODE

cat > "$GATE" <<'EOF'
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
  const clean =
    value =>
      value
        .split(
          "-"
        )[0]
        .split(
          "+"
        )[0];

  const leftParts =
    clean(
      left
    )
      .split(
        "."
      )
      .map(
        value =>
          Number(
            value
          )
      );

  const rightParts =
    clean(
      right
    )
      .split(
        "."
      )
      .map(
        value =>
          Number(
            value
          )
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

function resolvedVersions(
  lock,
  packageName
) {
  const escaped =
    packageName.replace(
      /[.*+?^${}()|[\]\\]/g,
      "\\$&"
    );

  /*
   * pnpm lockfile v9 may serialize package/snapshot keys with or without
   * quotes and dependency suffixes:
   *
   *   mariadb@3.4.6:
   *   'mariadb@3.4.6':
   *   prisma@7.10.0(...):
   *
   * Read every matching key instead of depending on one exact textual form.
   */
  const expression =
    new RegExp(
      `^\\s{2,4}['"]?${escaped}@([0-9]+\\.[0-9]+\\.[0-9]+)(?:\\([^\\n]*\\))?['"]?:`,
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

function assertExactResolved(
  lock,
  packageName,
  expected
) {
  const versions =
    resolvedVersions(
      lock,
      packageName
    );

  if (
    versions.length ===
    0
  ) {
    fail(
      `No ${packageName} resolution found in pnpm-lock.yaml.`
    );
  }

  if (
    versions.some(
      version =>
        version !==
        expected
    )
  ) {
    fail(
      `${packageName} must resolve only to ${expected}; found ${versions.join(", ")}.`
    );
  }

  return versions;
}

function assertFloor(
  lock,
  packageName,
  minimum
) {
  const versions =
    resolvedVersions(
      lock,
      packageName
    );

  if (
    versions.length ===
    0
  ) {
    fail(
      `No ${packageName} resolution found in pnpm-lock.yaml.`
    );
  }

  for (
    const version
    of versions
  ) {
    if (
      compareVersions(
        version,
        minimum
      ) <
      0
    ) {
      fail(
        `${packageName} ${version} is below the RH2 security floor ${minimum}.`
      );
    }
  }

  return versions;
}

const [
  rootSource,
  apiSource,
  workspace,
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
      "pnpm-workspace.yaml",
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

if (
  root.pnpm
) {
  fail(
    "package.json still contains a pnpm settings block; pnpm 11 ignores it."
  );
}

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

for (
  const marker
  of [
    "'@prisma/adapter-mariadb>mariadb': 3.4.6",
    "'@prisma/config>deepmerge-ts': 8.0.2"
  ]
) {
  if (
    !workspace.includes(
      marker
    )
  ) {
    fail(
      `pnpm-workspace.yaml override missing: ${marker}`
    );
  }
}

assertExactResolved(
  lock,
  "@prisma/adapter-mariadb",
  PRISMA_VERSION
);

assertExactResolved(
  lock,
  "@prisma/client",
  PRISMA_VERSION
);

assertExactResolved(
  lock,
  "prisma",
  PRISMA_VERSION
);

const mariadbVersions =
  assertFloor(
    lock,
    "mariadb",
    MARIADB_MINIMUM
  );

if (
  !mariadbVersions.includes(
    MARIADB_OVERRIDE
  )
) {
  fail(
    `Expected scoped mariadb override ${MARIADB_OVERRIDE}; resolved ${mariadbVersions.join(", ")}.`
  );
}

const deepmergeVersions =
  assertFloor(
    lock,
    "deepmerge-ts",
    DEEPMERGE_MINIMUM
  );

if (
  !deepmergeVersions.includes(
    DEEPMERGE_OVERRIDE
  )
) {
  fail(
    `Expected scoped deepmerge-ts override ${DEEPMERGE_OVERRIDE}; resolved ${deepmergeVersions.join(", ")}.`
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


if [[ -f docs/RH2_DEPENDENCY_SECURITY.md ]] && \
   ! grep -Fq -- "pnpm-workspace.yaml is the authoritative" docs/RH2_DEPENDENCY_SECURITY.md; then
cat >> docs/RH2_DEPENDENCY_SECURITY.md <<'EOF'

## pnpm 11 configuration source

`pnpm-workspace.yaml` is the authoritative configuration source for RH2
overrides.

pnpm 11 no longer reads `pnpm.overrides` from the root `package.json`, so the
security overrides must remain in the workspace YAML. The RH2 dependency gate
fails if the obsolete root `pnpm` block returns.
EOF
fi

echo "[RH2b] Re-resolving dependencies with pnpm-workspace.yaml overrides..."
pnpm install --no-frozen-lockfile

echo "[RH2b] Confirming frozen install + pnpm 11 override source..."
install_output="$(
  pnpm install --frozen-lockfile 2>&1
)" || {
  status=$?
  printf '%s\n' "$install_output"
  echo "ERROR: frozen install failed after RH2b lockfile resolution."
  exit "$status"
}

printf '%s\n' "$install_output"

if grep -Fq 'pnpm.overrides' <<<"$install_output"; then
  echo "ERROR: pnpm is still reporting ignored package.json overrides."
  exit 1
fi

echo "[RH2b] Explicit dependency resolution gate..."
node scripts/rh2-dependency-security-gate.mjs

echo "[RH2b] Full dependency audit — moderate and above..."
pnpm audit --audit-level moderate

echo "[RH2b] Production dependency audit — moderate and above..."
pnpm audit --prod --audit-level moderate

echo "[RH2b] Repository security scan..."
pnpm security:scan

echo "[RH2b] Prisma generate..."
pnpm db:generate

echo "[RH2b] Unit tests..."
pnpm test

echo "[RH2b] Typecheck..."
pnpm typecheck

echo "[RH2b] Integration tests..."
pnpm test:integration

echo "[RH2b] Production application build..."
pnpm build

echo "[RH2b] Rechecking RH1 production template..."
pnpm prod:template

echo "[RH2b] Rechecking production Compose structure..."
docker compose \
  --env-file infra/production/.env.production.example \
  -f infra/production/docker-compose.yml \
  config \
  --quiet

echo
echo "[RH2b] DEPENDENCY SECURITY PASS."
echo
echo "pnpm 11 overrides are now sourced from pnpm-workspace.yaml."
echo "No Prisma migration was created or executed against production."
echo "Production containers and production volumes were not modified."
echo
echo "Next release-hardening milestone: RH3 MySQL production security."
