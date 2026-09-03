import {
  readFile
} from "node:fs/promises";

const [
  compose,
  envExample,
  envTs,
  databaseTs,
  databaseTlsTs,
  preflight,
  packageSource,
  gitignore
] =
  await Promise.all([
    readFile(
      "infra/production/docker-compose.yml",
      "utf8"
    ),
    readFile(
      "infra/production/.env.production.example",
      "utf8"
    ),
    readFile(
      "apps/api/src/config/env.ts",
      "utf8"
    ),
    readFile(
      "apps/api/src/lib/database.ts",
      "utf8"
    ),
    readFile(
      "apps/api/src/lib/database-tls.ts",
      "utf8"
    ),
    readFile(
      "scripts/prod-preflight.mjs",
      "utf8"
    ),
    readFile(
      "package.json",
      "utf8"
    ),
    readFile(
      ".gitignore",
      "utf8"
    )
  ]);

const pkg =
  JSON.parse(
    packageSource
  );

for (
  const marker
  of [
    "--require-secure-transport=ON",
    "--tls-version=TLSv1.2,TLSv1.3",
    "--ssl-ca=/etc/mysql/tls/ca.pem",
    "--ssl-cert=/etc/mysql/tls/server-cert.pem",
    "--ssl-key=/etc/mysql/tls/server-key.pem",
    "DATABASE_TLS_CA_PATH: /etc/wapp/mysql-tls/ca.pem"
  ]
) {
  if (
    !compose.includes(
      marker
    )
  ) {
    throw new Error(
      `RH3 compose marker missing: ${marker}`
    );
  }
}

const applicationCaMounts =
  (
    compose.match(
      /\.\/mysql-tls\/ca\.pem:\/etc\/wapp\/mysql-tls\/ca\.pem:ro/g
    ) ??
    []
  ).length;

if (
  applicationCaMounts !==
    3
) {
  throw new Error(
    `RH3 expected 3 application CA mounts; found ${applicationCaMounts}.`
  );
}

for (
  const marker
  of [
    "DATABASE_TLS_CA_PATH=/etc/wapp/mysql-tls/ca.pem",
    "sslcert=/etc/wapp/mysql-tls/ca.pem&sslaccept=strict"
  ]
) {
  if (
    !envExample.includes(
      marker
    )
  ) {
    throw new Error(
      `RH3 env template marker missing: ${marker}`
    );
  }
}

if (
  !envTs.includes(
    "DATABASE_TLS_CA_PATH:"
  )
) {
  throw new Error(
    "RH3 API env schema is missing DATABASE_TLS_CA_PATH."
  );
}

for (
  const marker
  of [
    'from "./database-tls.js"',
    'allowPublicKeyRetrieval: env.NODE_ENV !== "production"',
    "ssl: databaseTls"
  ]
) {
  if (
    !databaseTs.includes(
      marker
    )
  ) {
    throw new Error(
      `RH3 database runtime marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    'input.nodeEnv !==\n    "production"',
    "rejectUnauthorized:\n      true",
    "DATABASE_TLS_CA_PATH is required when NODE_ENV=production"
  ]
) {
  if (
    !databaseTlsTs.includes(
      marker
    )
  ) {
    throw new Error(
      `RH3 TLS helper marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of [
    "DATABASE_TLS_CA_PATH must be /etc/wapp/mysql-tls/ca.pem",
    "sslaccept",
    "strict"
  ]
) {
  if (
    !preflight.includes(
      marker
    )
  ) {
    throw new Error(
      `RH3 production preflight marker missing: ${marker}`
    );
  }
}

for (
  const [
    scriptName,
    expected
  ]
  of [
    [
      "prod:mysql:tls:init",
      "bash scripts/prod-mysql-tls-init.sh"
    ],
    [
      "prod:mysql:tls:check",
      "bash scripts/prod-mysql-tls-check.sh"
    ],
    [
      "prod:mysql:verify",
      "bash scripts/prod-db-security-check.sh"
    ],
    [
      "rh3:mysql:rehearsal",
      "bash scripts/rh3-mysql-tls-rehearsal.sh"
    ]
  ]
) {
  if (
    pkg.scripts?.[
      scriptName
    ] !==
      expected
  ) {
    throw new Error(
      `RH3 package script mismatch: ${scriptName}`
    );
  }
}

if (
  !gitignore.includes(
    "infra/production/mysql-tls/"
  )
) {
  throw new Error(
    "RH3 TLS material is not ignored by Git."
  );
}

console.log(
  "[RH3] production security smoke PASS"
);
