#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[RH6] Installing full release gate..."

for check in \
  "scripts/rh2-dependency-security-gate.mjs|dependency gate PASS" \
  "scripts/rh3-production-security-smoke.mjs|production security smoke PASS" \
  "scripts/rh4-production-backup-smoke.mjs|production backup / restore smoke PASS" \
  "scripts/rh5-first-owner-smoke.mjs|first OWNER bootstrap smoke PASS" \
  "scripts/rh5-first-owner-drill.sh|wapp_shadow" \
  "scripts/prod-preflight.mjs|DATABASE_TLS_CA_PATH" \
  "scripts/prod-config.sh|prod-mysql-tls-check.sh" \
  "scripts/prod-backup-common.sh|WAPP_BACKUP_DIR" \
  "scripts/prod-first-owner-status.sh|prod-first-owner-status.js" \
  "apps/api/prisma/migrations/20260902170000_first_owner_bootstrap/migration.sql|mustChangePassword" \
  "infra/production/docker-compose.yml|--require-secure-transport=ON"
do
  file="${check%%|*}"
  marker="${check#*|}"

  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: RH6 prerequisite missing:"
    echo "  $file -> $marker"
    echo "RH6 made no changes."
    exit 1
  fi
done

echo "[RH6] Confirming RH2-RH5 static baseline..."
node scripts/rh2-dependency-security-gate.mjs
node scripts/rh3-production-security-smoke.mjs
node scripts/rh4-production-backup-smoke.mjs
node scripts/rh5-first-owner-smoke.mjs

cat > scripts/rh6-release-static.mjs <<'EOF'
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
EOF

cat > scripts/rh6-git-clean.mjs <<'EOF'
import {
  execFileSync
} from "node:child_process";

const raw =
  execFileSync(
    "git",
    [
      "status",
      "--porcelain=v1",
      "--untracked-files=all"
    ],
    {
      encoding:
        "utf8"
    }
  );

const relevant =
  raw
    .split(
      /\r?\n/
    )
    .map(
      line =>
        line.trimEnd()
    )
    .filter(
      Boolean
    )
    .filter(
      line =>
        !/^\?\? .*\.patch$/i.test(
          line
        )
    );

if (
  relevant.length >
    0
) {
  console.error(
    "[RH6] release gate requires a clean Git working tree."
  );

  for (
    const line
    of relevant
  ) {
    console.error(
      line
    );
  }

  process.exit(
    1
  );
}

console.log(
  "[RH6] Git working tree PASS — clean (untracked .patch artifacts ignored)."
);
EOF

cat > scripts/rh6-staging-rehearsal.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command_name in docker pnpm node; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: $command_name is required for RH6 staging rehearsal."
    exit 1
  fi
done

echo "[RH6 staging] Docker availability..."
docker info >/dev/null

echo "[RH6 staging] Production Compose structural configuration..."
docker compose \
  --env-file infra/production/.env.production.example \
  -f infra/production/docker-compose.yml \
  config \
  --quiet

echo "[RH6 staging] Integration suite..."
pnpm test:integration

echo "[RH6 staging] MySQL 8.4 production TLS rehearsal..."
pnpm rh3:mysql:rehearsal

echo "[RH6 staging] Encrypted backup / destructive restore drill..."
pnpm rh4:backup:drill

echo "[RH6 staging] First OWNER full lifecycle drill..."
pnpm rh5:first-owner:drill

echo
echo "[RH6 staging] PASS — isolated production-path rehearsal completed."
echo "No production Compose project, production database or named production volume was touched."
EOF

chmod +x scripts/rh6-staging-rehearsal.sh

cat > scripts/prod-release-preflight.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${WAPP_PROD_ENV:-infra/production/.env.production}"
COMPOSE_FILE="infra/production/docker-compose.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing production environment: $ENV_FILE"
  echo "Create it from infra/production/.env.production.example and supply real secrets."
  exit 1
fi

echo "[prod:release:preflight] Git state..."
node scripts/rh6-git-clean.mjs

echo "[prod:release:preflight] Production environment..."
WAPP_PROD_ENV="$ENV_FILE" node scripts/prod-preflight.mjs

echo "[prod:release:preflight] MySQL TLS material..."
bash scripts/prod-mysql-tls-check.sh

echo "[prod:release:preflight] Backup configuration..."
# shellcheck source=/dev/null
source scripts/prod-backup-common.sh
require_backup_config

echo "[prod:release:preflight] Production Compose..."
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  config \
  --quiet

echo
echo "[prod:release:preflight] PASS."
echo "This is a pre-deployment configuration gate only."
echo "It does not start or modify production containers."
EOF

chmod +x scripts/prod-release-preflight.sh

cat > scripts/rh6-release-gate.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:---final}"

case "$MODE" in
  --ci|--final)
    ;;
  *)
    echo "Usage: bash scripts/rh6-release-gate.sh [--ci|--final]"
    exit 2
    ;;
esac

echo "[RH6] Static release topology..."
node scripts/rh6-release-static.mjs

if [[ "$MODE" == "--final" && "${RH6_ALLOW_DIRTY:-false}" != "true" ]]; then
  echo "[RH6] Clean Git gate..."
  node scripts/rh6-git-clean.mjs
fi

echo "[RH6] Production environment template..."
pnpm prod:template

echo "[RH6] Production Compose syntax..."
docker compose \
  --env-file infra/production/.env.production.example \
  -f infra/production/docker-compose.yml \
  config \
  --quiet

echo "[RH6] Prisma schema..."
pnpm --filter @wapp/api exec prisma validate

echo "[RH6] Prisma client generation..."
pnpm db:generate

echo "[RH6] Dependency security..."
node scripts/rh2-dependency-security-gate.mjs
pnpm audit --audit-level moderate
pnpm audit --prod --audit-level moderate

echo "[RH6] Repository security scan..."
pnpm security:scan

echo "[RH6] Unit tests..."
pnpm test

echo "[RH6] Typecheck..."
pnpm typecheck

echo "[RH6] Production build..."
pnpm build

if [[ "$MODE" == "--final" ]]; then
  echo "[RH6] Isolated staging rehearsal..."
  bash scripts/rh6-staging-rehearsal.sh
else
  echo "[RH6] CI mode: Docker staging drills skipped."
fi

echo "[RH6] Final static hardening smokes..."
node scripts/rh3-production-security-smoke.mjs
node scripts/rh4-production-backup-smoke.mjs
node scripts/rh5-first-owner-smoke.mjs

echo "[RH6] Diff whitespace..."
git diff --check

echo
if [[ "$MODE" == "--final" ]]; then
  echo "[RH6] FULL RELEASE GATE PASS."
  echo "Release candidate is approved for an explicit production deployment workflow."
else
  echo "[RH6] CI RELEASE GATE PASS."
fi
EOF

chmod +x scripts/rh6-release-gate.sh

cat > scripts/rh6-clean-transient-installers.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

transient=(
  scripts/rh1-production-compose-environment.sh
  scripts/rh2-dependency-security.sh
  scripts/rh2b-pnpm11-overrides-lock-gate.sh
  scripts/rh2c-mariadb-published-patched-line.sh
  scripts/rh2-resume-mariadb-353.sh
  scripts/rh2d-prisma-mysql2-security.sh
  scripts/rh3-mysql-production-security.sh
  scripts/rh3a-git-bash-openssl-subject.sh
  scripts/rh4-production-backup-restore.sh
  scripts/rh5-first-owner-bootstrap.sh
  scripts/rh5a-company-slug-resume.sh
  scripts/rh5b-typescript-localpart-resume.sh
  scripts/rh5c-shadow-db-resume.sh
)

removed=0

for file in "${transient[@]}"; do
  if [[ -f "$file" ]]; then
    rm -f "$file"
    echo "[RH6 cleanup] removed transient installer: $file"
    removed=$((removed + 1))
  fi
done

echo "[RH6 cleanup] PASS — removed $removed transient installer(s)."
EOF

chmod +x scripts/rh6-clean-transient-installers.sh

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

pkg.scripts ??=
  {};

Object.assign(
  pkg.scripts,
  {
    "release:gate:static":
      "node scripts/rh6-release-static.mjs",
    "release:gate:ci":
      "bash scripts/rh6-release-gate.sh --ci",
    "release:gate:final":
      "bash scripts/rh6-release-gate.sh --final",
    "rh6:staging":
      "bash scripts/rh6-staging-rehearsal.sh",
    "prod:release:preflight":
      "bash scripts/prod-release-preflight.sh"
  }
);

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);

console.log(
  "[RH6] Release gate package commands synchronized."
);
NODE

cat > docs/RH6_FULL_RELEASE_GATE.md <<'EOF'
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
EOF

echo "[RH6] Cleaning transient RH1-RH5 patch installers..."
bash scripts/rh6-clean-transient-installers.sh

echo "[RH6] Syntax checks..."
node --check scripts/rh6-release-static.mjs
node --check scripts/rh6-git-clean.mjs

bash -n scripts/rh6-release-gate.sh
bash -n scripts/rh6-staging-rehearsal.sh
bash -n scripts/prod-release-preflight.sh
bash -n scripts/rh6-clean-transient-installers.sh

echo "[RH6] Permanent static topology..."
node scripts/rh6-release-static.mjs

echo "[RH6] Full release gate with installer-dirty allowance..."
RH6_ALLOW_DIRTY=true \
  pnpm release:gate:final

echo "[RH6] Installer diff whitespace check..."
git diff --check

echo
echo "[RH6] FULL RELEASE HARDENING PASS."
echo
echo "RH1  Production Compose + environment        PASS"
echo "RH2  Dependency security                    PASS"
echo "RH3  MySQL production security              PASS"
echo "RH4  Production backup / restore            PASS"
echo "RH5  First OWNER bootstrap                  PASS"
echo "RH6  Full release gate + staging rehearsal   PASS"
echo
echo "No production deployment was performed."
echo "No production migration was executed."
echo "No production database or named production volume was modified."
echo
echo "Commit the RH6 finalization, push it, then run on the clean commit:"
echo "  pnpm release:gate:final"
echo
echo "On the real production host, before deployment:"
echo "  pnpm prod:release:preflight"
