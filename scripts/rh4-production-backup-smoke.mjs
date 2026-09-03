import {
  readFile
} from "node:fs/promises";

const [
  packageSource,
  envExample,
  preflight,
  createScript,
  restoreScript,
  commonScript,
  cryptoScript,
  pruneScript
] =
  await Promise.all([
    readFile(
      "package.json",
      "utf8"
    ),
    readFile(
      "infra/production/.env.production.example",
      "utf8"
    ),
    readFile(
      "scripts/prod-preflight.mjs",
      "utf8"
    ),
    readFile(
      "scripts/prod-backup-create.sh",
      "utf8"
    ),
    readFile(
      "scripts/prod-backup-restore.sh",
      "utf8"
    ),
    readFile(
      "scripts/prod-backup-common.sh",
      "utf8"
    ),
    readFile(
      "scripts/prod-backup-crypto.mjs",
      "utf8"
    ),
    readFile(
      "scripts/prod-backup-prune.mjs",
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
      "prod:backup:create",
      "bash scripts/prod-backup-create.sh"
    ],
    [
      "prod:backup:verify",
      "bash scripts/prod-backup-verify.sh"
    ],
    [
      "prod:backup:restore",
      "bash scripts/prod-backup-restore.sh"
    ],
    [
      "prod:backup:prune",
      "bash scripts/prod-backup-prune.sh"
    ],
    [
      "rh4:backup:drill",
      "bash scripts/rh4-backup-restore-drill.sh"
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
      `RH4 package script mismatch: ${name}`
    );
  }
}

for (
  const marker
  of [
    "WAPP_BACKUP_DIR=/mnt/wapp-backups",
    "WAPP_BACKUP_PASSPHRASE_FILE=/etc/wapp/secrets/backup-passphrase",
    "WAPP_BACKUP_RETENTION_DAYS=30",
    "WAPP_BACKUP_MIN_KEEP=7",
    "WAPP_BACKUP_AUTO_PRUNE=true"
  ]
) {
  if (
    !envExample.includes(
      marker
    )
  ) {
    throw new Error(
      `RH4 env template marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    '"WAPP_BACKUP_RETENTION_DAYS"',
    '"WAPP_BACKUP_MIN_KEEP"',
    '"WAPP_BACKUP_AUTO_PRUNE"'
  ]
) {
  if (
    !preflight.includes(
      marker
    )
  ) {
    throw new Error(
      `RH4 preflight marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "--single-transaction",
    "--ssl-mode=VERIFY_IDENTITY",
    "prod-backup-crypto.mjs",
    "prod-backup-manifest.mjs"
  ]
) {
  if (
    !createScript.includes(
      marker
    )
  ) {
    throw new Error(
      `RH4 create marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "RESTORE PRODUCTION DATABASE",
    "pre-restore",
    "WAPP_PROD_RESTORE_ALLOW_COMMIT_MISMATCH",
    "DROP DATABASE IF EXISTS",
    "FLUSHDB",
    "prod:mysql:verify"
  ]
) {
  if (
    !restoreScript.includes(
      marker
    )
  ) {
    throw new Error(
      `RH4 restore safety marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "must be outside the application repository",
    "permissions must be 400 or 600",
    "another production backup/restore operation is already running"
  ]
) {
  if (
    !commonScript.includes(
      marker
    )
  ) {
    throw new Error(
      `RH4 backup config safety marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "aes-256-gcm",
    "scryptSync",
    "getAuthTag",
    "setAuthTag"
  ]
) {
  if (
    !cryptoScript.includes(
      marker
    )
  ) {
    throw new Error(
      `RH4 crypto marker missing: ${marker}`
    );
  }
}

if (
  !pruneScript.includes(
    ".slice(\n      minKeep"
  )
) {
  throw new Error(
    "RH4 retention script does not protect minimum backups."
  );
}

const combinedProductionScripts =
  [
    createScript,
    restoreScript
  ].join(
    "\n"
  );

for (
  const forbidden
  of [
    "docker compose down -v",
    "docker volume rm",
    "mysql_data",
    "rm -rf /var/lib/mysql"
  ]
) {
  if (
    combinedProductionScripts.includes(
      forbidden
    )
  ) {
    throw new Error(
      `RH4 forbidden destructive volume operation found: ${forbidden}`
    );
  }
}

console.log(
  "[RH4] production backup / restore smoke PASS"
);
