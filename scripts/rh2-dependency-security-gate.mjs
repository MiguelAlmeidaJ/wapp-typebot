import {
  readFile
} from "node:fs/promises";

const PRISMA_VERSION =
  "7.10.0";

const MARIADB_MINIMUM =
  "3.5.3";

const MARIADB_OVERRIDE =
  "3.5.3";

const DEEPMERGE_MINIMUM =
  "8.0.0";

const DEEPMERGE_OVERRIDE =
  "8.0.2";

const MYSQL2_MINIMUM =
  "3.23.1";

const MYSQL2_OVERRIDE =
  "3.23.1";

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
    "'@prisma/adapter-mariadb>mariadb': 3.5.3",
    "'@prisma/config>deepmerge-ts': 8.0.2"
,
    "'prisma>mysql2': 3.23.1"  ]
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

const mysql2Versions =
  assertFloor(
    lock,
    "mysql2",
    MYSQL2_MINIMUM
  );

if (
  !mysql2Versions.includes(
    MYSQL2_OVERRIDE
  )
) {
  fail(
    `Expected scoped mysql2 override ${MYSQL2_OVERRIDE}; resolved ${mysql2Versions.join(", ")}.`
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
    "deepmerge-ts@7.1.5",
    "mysql2@3.21.",
    "mysql2@3.22.",
    "mysql2@3.23.0"  ]
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
  `[RH2] dependency gate PASS — Prisma ${PRISMA_VERSION}; mariadb ${mariadbVersions.join(", ")}; deepmerge-ts ${deepmergeVersions.join(", ")}; mysql2 ${mysql2Versions.join(", ")}.`
);
