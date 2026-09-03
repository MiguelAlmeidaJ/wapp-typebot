import {
  existsSync
} from "node:fs";
import {
  readFile,
  readdir
} from "node:fs/promises";
import {
  execFileSync
} from "node:child_process";
import {
  join
} from "node:path";

const root =
  process.cwd();

const forbiddenTransientInstallers = [
  "scripts/rh1-production-compose-environment.sh",
  "scripts/rh2-dependency-security.sh",
  "scripts/rh2b-pnpm11-overrides-lock-gate.sh",
  "scripts/rh2c-mariadb-published-patched-line.sh",
  "scripts/rh2-resume-mariadb-353.sh",
  "scripts/rh2d-prisma-mysql2-security.sh",
  "scripts/rh3-mysql-production-security.sh",
  "scripts/rh3a-git-bash-openssl-subject.sh",
  "scripts/rh4-production-backup-restore.sh",
  "scripts/rh5-first-owner-bootstrap.sh",
  "scripts/rh5a-company-slug-resume.sh",
  "scripts/rh5b-typescript-localpart-resume.sh",
  "scripts/rh5c-shadow-db-resume.sh"
];

for (
  const file
  of forbiddenTransientInstallers
) {
  if (
    existsSync(
      join(
        root,
        file
      )
    )
  ) {
    throw new Error(
      `RH6 transient installer must not remain in final tree: ${file}`
    );
  }
}

const requiredFiles = [
  "scripts/rh2-dependency-security-gate.mjs",
  "scripts/rh3-production-security-smoke.mjs",
  "scripts/rh4-production-backup-smoke.mjs",
  "scripts/rh5-first-owner-smoke.mjs",
  "scripts/rh3-mysql-tls-rehearsal.sh",
  "scripts/rh4-backup-restore-drill.sh",
  "scripts/rh5-first-owner-drill.sh",
  "scripts/prod-preflight.mjs",
  "scripts/prod-env-template-check.mjs",
  "scripts/prod-config.sh",
  "scripts/prod-deploy.sh",
  "scripts/prod-mysql-tls-init.sh",
  "scripts/prod-mysql-tls-check.sh",
  "scripts/prod-db-security-check.sh",
  "scripts/prod-backup-create.sh",
  "scripts/prod-backup-verify.sh",
  "scripts/prod-backup-restore.sh",
  "scripts/prod-backup-prune.sh",
  "scripts/prod-first-owner-status.sh",
  "scripts/prod-first-owner-bootstrap.sh",
  "scripts/prod-first-owner-finalize.sh",
  "infra/production/docker-compose.yml",
  "infra/production/.env.production.example",
  "apps/api/prisma/schema.prisma",
  "apps/api/prisma/migrations/20260902170000_first_owner_bootstrap/migration.sql"
];

for (
  const file
  of requiredFiles
) {
  if (
    !existsSync(
      join(
        root,
        file
      )
    )
  ) {
    throw new Error(
      `RH6 required file missing: ${file}`
    );
  }
}

const [
  packageSource,
  workspaceSource,
  composeSource,
  schemaSource,
  prodExample,
  prodDeploy,
  backupRestore,
  firstOwnerBootstrap
] =
  await Promise.all([
    readFile(
      "package.json",
      "utf8"
    ),
    readFile(
      "pnpm-workspace.yaml",
      "utf8"
    ),
    readFile(
      "infra/production/docker-compose.yml",
      "utf8"
    ),
    readFile(
      "apps/api/prisma/schema.prisma",
      "utf8"
    ),
    readFile(
      "infra/production/.env.production.example",
      "utf8"
    ),
    readFile(
      "scripts/prod-deploy.sh",
      "utf8"
    ),
    readFile(
      "scripts/prod-backup-restore.sh",
      "utf8"
    ),
    readFile(
      "apps/api/src/scripts/prod-first-owner-bootstrap.ts",
      "utf8"
    )
  ]);

const pkg =
  JSON.parse(
    packageSource
  );

for (
  const [
    name,
    expected
  ]
  of [
    [
      "security:dependencies",
      "node scripts/rh2-dependency-security-gate.mjs && pnpm audit --audit-level moderate && pnpm audit --prod --audit-level moderate"
    ],
    [
      "prod:mysql:verify",
      "bash scripts/prod-db-security-check.sh"
    ],
    [
      "prod:backup:create",
      "bash scripts/prod-backup-create.sh"
    ],
    [
      "prod:backup:restore",
      "bash scripts/prod-backup-restore.sh"
    ],
    [
      "prod:first-owner:status",
      "bash scripts/prod-first-owner-status.sh"
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
      `RH6 permanent script mismatch: ${name}`
    );
  }
}

for (
  const marker
  of [
    "'@prisma/adapter-mariadb>mariadb': 3.5.3",
    "'@prisma/config>deepmerge-ts': 8.0.2",
    "'prisma>mysql2': 3.23.1"
  ]
) {
  if (
    !workspaceSource.includes(
      marker
    )
  ) {
    throw new Error(
      `RH6 dependency override missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "--require-secure-transport=ON",
    "--tls-version=TLSv1.2,TLSv1.3",
    "DATABASE_TLS_CA_PATH: /etc/wapp/mysql-tls/ca.pem"
  ]
) {
  if (
    !composeSource.includes(
      marker
    )
  ) {
    throw new Error(
      `RH6 production Compose security marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "mustChangePassword Boolean",
    "@default(false)"
  ]
) {
  if (
    !schemaSource.includes(
      marker
    )
  ) {
    throw new Error(
      `RH6 first OWNER schema marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "WAPP_BACKUP_DIR=/mnt/wapp-backups",
    "WAPP_BACKUP_PASSPHRASE_FILE=/etc/wapp/secrets/backup-passphrase",
    "DATABASE_TLS_CA_PATH=/etc/wapp/mysql-tls/ca.pem"
  ]
) {
  if (
    !prodExample.includes(
      marker
    )
  ) {
    throw new Error(
      `RH6 production template marker missing: ${marker}`
    );
  }
}

if (
  !prodDeploy.includes(
    "prod-mysql-tls-check.sh"
  )
) {
  throw new Error(
    "RH6 production deploy is not gated by MySQL TLS asset validation."
  );
}

for (
  const marker
  of [
    "pre-restore",
    "RESTORE PRODUCTION DATABASE",
    "prod:mysql:verify"
  ]
) {
  if (
    !backupRestore.includes(
      marker
    )
  ) {
    throw new Error(
      `RH6 restore guard missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "GET_LOCK",
    "randomBytes",
    "Identity database is not empty",
    "mustChangePassword"
  ]
) {
  if (
    !firstOwnerBootstrap.includes(
      marker
    )
  ) {
    throw new Error(
      `RH6 first OWNER guard missing: ${marker}`
    );
  }
}

const migrations =
  (
    await readdir(
      "apps/api/prisma/migrations",
      {
        withFileTypes:
          true
      }
    )
  )
    .filter(
      entry =>
        entry.isDirectory()
    )
    .map(
      entry =>
        entry.name
    )
    .sort();

if (
  migrations.length <
    25
) {
  throw new Error(
    `RH6 expected at least 25 Prisma migrations; found ${migrations.length}.`
  );
}

if (
  migrations[
    migrations.length -
    1
  ] !==
    "20260902170000_first_owner_bootstrap"
) {
  throw new Error(
    `RH6 latest migration mismatch: ${migrations[migrations.length - 1] ?? "none"}.`
  );
}

function command(
  executable,
  args
) {
  return execFileSync(
    executable,
    args,
    {
      encoding:
        "utf8",
      stdio: [
        "ignore",
        "pipe",
        "pipe"
      ]
    }
  ).trim();
}

const nodeMajor =
  Number(
    process.versions.node
      .split(
        "."
      )[
        0
      ]
  );

if (
  nodeMajor !==
    24
) {
  throw new Error(
    `RH6 requires Node 24 LTS; running ${process.versions.node}.`
  );
}

const packageManager =
  pkg.packageManager ??
  "";

if (
  !packageManager.startsWith(
    "pnpm@11."
  )
) {
  throw new Error(
    `RH6 expected pnpm 11 packageManager; got ${packageManager || "missing"}.`
  );
}

const commit =
  command(
    "git",
    [
      "rev-parse",
      "HEAD"
    ]
  );

console.log(
  `[RH6] static release gate PASS — commit=${commit.slice(0, 12)} migrations=${migrations.length} node=${process.versions.node} ${packageManager}`
);
