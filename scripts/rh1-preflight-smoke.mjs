import {
  mkdtemp,
  readFile,
  rm,
  writeFile
} from "node:fs/promises";
import {
  tmpdir
} from "node:os";
import {
  join
} from "node:path";
import {
  spawnSync
} from "node:child_process";

const template =
  await readFile(
    "infra/production/.env.production.example",
    "utf8"
  );

const values =
  new Map();

for (
  const rawLine
  of template.split(
    /\r?\n/
  )
) {
  const line =
    rawLine.trim();

  if (
    !line ||
    line.startsWith(
      "#"
    )
  ) {
    continue;
  }

  const separator =
    line.indexOf(
      "="
    );

  const key =
    line.slice(
      0,
      separator
    );

  const value =
    line.slice(
      separator +
        1
    );

  values.set(
    key,
    value
  );
}

const synthetic = {
  WAPP_DOMAIN:
    "wapp.test.invalid",
  WAPP_IMAGE_TAG:
    "rh1-smoke-0ad52c6",
  MYSQL_PASSWORD:
    "SyntheticMysqlPassword123!",
  MYSQL_ROOT_PASSWORD:
    "SyntheticMysqlRootPassword123!",
  DATABASE_URL:
    "mysql://wapp:SyntheticMysqlPassword123!@mysql:3306/wapp",
  SHADOW_DATABASE_URL:
    "mysql://wapp:SyntheticMysqlPassword123!@mysql:3306/wapp_shadow",
  REDIS_PASSWORD:
    "SyntheticRedisPassword123!",
  REDIS_URL:
    "redis://:SyntheticRedisPassword123!@redis:6379/0",
  JWT_SECRET:
    "SyntheticJwtSecret_123456789012345678901234567890",
  METRICS_TOKEN:
    "SyntheticMetricsToken_123456789012345678901234567",
  EVOLUTION_BASE_URL:
    "https://evolution.test.invalid",
  EVOLUTION_API_KEY:
    "SyntheticEvolutionKey_12345678901234567890123456",
  EVOLUTION_WEBHOOK_SECRET:
    "SyntheticWebhookSecret_12345678901234567890123456",
  S3_BUCKET:
    "synthetic-private-bucket",
  S3_ENDPOINT:
    "https://s3.test.invalid",
  S3_ACCESS_KEY_ID:
    "synthetic-access-key",
  S3_SECRET_ACCESS_KEY:
    "SyntheticS3Secret_1234567890",
  TYPEBOT_URL:
    ""
};

for (
  const [
    key,
    value
  ]
  of Object.entries(
    synthetic
  )
) {
  values.set(
    key,
    value
  );
}

const directory =
  await mkdtemp(
    join(
      tmpdir(),
      "wapp-rh1-"
    )
  );

const envPath =
  join(
    directory,
    ".env.production"
  );

try {
  const source =
    [
      ...values.entries()
    ]
      .map(
        (
          [
            key,
            value
          ]
        ) =>
          `${key}=${value}`
      )
      .join(
        "\n"
      ) +
    "\n";

  await writeFile(
    envPath,
    source,
    {
      encoding:
        "utf8",
      mode:
        0o600
    }
  );

  const result =
    spawnSync(
      process.execPath,
      [
        "scripts/prod-preflight.mjs"
      ],
      {
        cwd:
          process.cwd(),
        env: {
          ...process.env,
          WAPP_PROD_ENV:
            envPath
        },
        encoding:
          "utf8"
      }
    );

  if (
    result.status !==
    0
  ) {
    throw new Error(
      [
        "Synthetic production preflight failed.",
        result.stdout,
        result.stderr
      ]
        .filter(
          Boolean
        )
        .join(
          "\n"
        )
    );
  }

  if (
    !result.stdout.includes(
      "[prod:preflight] PASS"
    )
  ) {
    throw new Error(
      "Synthetic preflight did not report PASS."
    );
  }

  console.log(
    "[RH1] synthetic prod:preflight PASS"
  );
} finally {
  await rm(
    directory,
    {
      recursive:
        true,
      force:
        true
    }
  );
}
