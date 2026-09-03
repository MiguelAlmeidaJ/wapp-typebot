import {
  readFile
} from "node:fs/promises";

const [
  schema,
  migration,
  bootstrap,
  finalize,
  bootstrapWrapper,
  finalizeWrapper,
  packageSource
] =
  await Promise.all([
    readFile(
      "apps/api/prisma/schema.prisma",
      "utf8"
    ),
    readFile(
      "apps/api/prisma/migrations/20260902170000_first_owner_bootstrap/migration.sql",
      "utf8"
    ),
    readFile(
      "apps/api/src/scripts/prod-first-owner-bootstrap.ts",
      "utf8"
    ),
    readFile(
      "apps/api/src/scripts/prod-first-owner-finalize.ts",
      "utf8"
    ),
    readFile(
      "scripts/prod-first-owner-bootstrap.sh",
      "utf8"
    ),
    readFile(
      "scripts/prod-first-owner-finalize.sh",
      "utf8"
    ),
    readFile(
      "package.json",
      "utf8"
    )
  ]);

const pkg =
  JSON.parse(
    packageSource
  );

if (
  !/\bmustChangePassword\s+Boolean\s+@default\(false\)/.test(
    schema
  )
) {
  throw new Error(
    "RH5 User.mustChangePassword schema field missing."
  );
}

if (
  !migration.includes(
    "ADD COLUMN `mustChangePassword` BOOLEAN NOT NULL DEFAULT false"
  )
) {
  throw new Error(
    "RH5 migration does not add mustChangePassword safely."
  );
}

for (
  const marker
  of [
    "randomBytes",
    "GET_LOCK",
    "RELEASE_LOCK",
    "Identity database is not empty",
    "mustChangePassword:",
    "true",
    "never displayed"
  ]
) {
  if (
    !bootstrap.includes(
      marker
    )
  ) {
    throw new Error(
      `RH5 bootstrap marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "readPasswordFromStdin",
    "mustChangePassword !==",
    "already been finalized",
    "mustChangePassword:",
    "false"
  ]
) {
  if (
    !finalize.includes(
      marker
    )
  ) {
    throw new Error(
      `RH5 finalize marker missing: ${marker}`
    );
  }
}

for (
  const forbidden
  of [
    "BOOTSTRAP_OWNER_PASSWORD",
    "process.argv",
    "--password"
  ]
) {
  if (
    bootstrap.includes(
      forbidden
    ) ||
    finalize.includes(
      forbidden
    )
  ) {
    throw new Error(
      `RH5 secret input must not use CLI args/env password: ${forbidden}`
    );
  }
}

if (
  !bootstrapWrapper.includes(
    "CREATE FIRST OWNER"
  )
) {
  throw new Error(
    "RH5 bootstrap wrapper confirmation phrase missing."
  );
}

for (
  const marker
  of [
    "read -r -s OWNER_PASSWORD",
    "read -r -s OWNER_PASSWORD_CONFIRM",
    "printf '%s' \"$OWNER_PASSWORD\""
  ]
) {
  if (
    !finalizeWrapper.includes(
      marker
    )
  ) {
    throw new Error(
      `RH5 final password wrapper safety marker missing: ${marker}`
    );
  }
}

for (
  const [
    name,
    expected
  ]
  of [
    [
      "prod:first-owner:status",
      "bash scripts/prod-first-owner-status.sh"
    ],
    [
      "prod:first-owner:bootstrap",
      "bash scripts/prod-first-owner-bootstrap.sh"
    ],
    [
      "prod:first-owner:finalize",
      "bash scripts/prod-first-owner-finalize.sh"
    ],
    [
      "rh5:first-owner:drill",
      "bash scripts/rh5-first-owner-drill.sh"
    ]
  ]
) {
  if (
    pkg.scripts?.[
      name
    ] !==
      expected
  ) {
    throw new Error(
      `RH5 package script mismatch: ${name}`
    );
  }
}

console.log(
  "[RH5] first OWNER bootstrap smoke PASS"
);
