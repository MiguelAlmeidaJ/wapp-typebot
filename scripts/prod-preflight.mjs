import {
  stat
} from "node:fs/promises";
import {
  readFile
} from "node:fs/promises";
import {
  resolve
} from "node:path";

const envPath =
  resolve(
    process.cwd(),
    process.env.WAPP_PROD_ENV ??
      "infra/production/.env.production"
  );

const placeholderPattern =
  /CHANGE_ME|REPLACE_ME|YOUR_[A-Z0-9_]+|example\.com/i;

function fail(
  message
) {
  throw new Error(
    message
  );
}

function parseEnv(
  source
) {
  const values =
    {};

  const duplicates =
    new Set();

  for (
    const rawLine
    of source.split(
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

    if (
      separator <
      1
    ) {
      continue;
    }

    const key =
      line.slice(
        0,
        separator
      ).trim();

    let value =
      line.slice(
        separator +
          1
      ).trim();

    if (
      (
        value.startsWith(
          '"'
        ) &&
        value.endsWith(
          '"'
        )
      ) ||
      (
        value.startsWith(
          "'"
        ) &&
        value.endsWith(
          "'"
        )
      )
    ) {
      value =
        value.slice(
          1,
          -1
        );
    }

    if (
      Object.hasOwn(
        values,
        key
      )
    ) {
      duplicates.add(
        key
      );
    }

    values[
      key
    ] =
      value;
  }

  if (
    duplicates.size >
    0
  ) {
    fail(
      `Duplicate environment keys: ${[
        ...duplicates
      ].join(", ")}`
    );
  }

  return values;
}

function required(
  env,
  key
) {
  const value =
    env[
      key
    ];

  if (
    !value ||
    placeholderPattern.test(
      value
    )
  ) {
    fail(
      `${key} is missing or still contains a placeholder.`
    );
  }

  return value;
}

function strongSecret(
  env,
  key,
  minimum
) {
  const value =
    required(
      env,
      key
    );

  if (
    value.length <
    minimum
  ) {
    fail(
      `${key} must contain at least ${minimum} characters.`
    );
  }

  return value;
}

function integerInRange(
  env,
  key,
  minimum,
  maximum
) {
  const raw =
    required(
      env,
      key
    );

  if (
    !/^\d+$/.test(
      raw
    )
  ) {
    fail(
      `${key} must be an integer.`
    );
  }

  const value =
    Number(
      raw
    );

  if (
    !Number.isSafeInteger(
      value
    ) ||
    value <
      minimum ||
    value >
      maximum
  ) {
    fail(
      `${key} must be between ${minimum} and ${maximum}.`
    );
  }

  return value;
}

function booleanValue(
  env,
  key
) {
  const value =
    required(
      env,
      key
    );

  if (
    ![
      "true",
      "false"
    ].includes(
      value
    )
  ) {
    fail(
      `${key} must be true or false.`
    );
  }

  return value ===
    "true";
}

function webUrl(
  env,
  key,
  {
    allowHttp =
      true,
    allowEmpty =
      false
  } = {}
) {
  const raw =
    env[
      key
    ] ??
    "";

  if (
    allowEmpty &&
    !raw
  ) {
    return null;
  }

  const value =
    required(
      env,
      key
    );

  let url;

  try {
    url =
      new URL(
        value
      );
  } catch {
    fail(
      `${key} must be a valid URL.`
    );
  }

  const protocols =
    allowHttp
      ? [
          "http:",
          "https:"
        ]
      : [
          "https:"
        ];

  if (
    !protocols.includes(
      url.protocol
    )
  ) {
    fail(
      `${key} must use ${allowHttp ? "http or https" : "https"}.`
    );
  }

  if (
    /localhost|127\.0\.0\.1|0\.0\.0\.0/i.test(
      url.hostname
    )
  ) {
    fail(
      `${key} must not point to localhost in production.`
    );
  }

  return url;
}

function sameBundledMysqlCredentials(
  url,
  {
    user,
    password
  }
) {
  return (
    url.protocol ===
      "mysql:" &&
    url.hostname ===
      "mysql" &&
    decodeURIComponent(
      url.username
    ) ===
      user &&
    decodeURIComponent(
      url.password
    ) ===
      password
  );
}

try {
  const source =
    await readFile(
      envPath,
      "utf8"
    );

  const env =
    parseEnv(
      source
    );

  if (
    process.platform !==
    "win32"
  ) {
    const info =
      await stat(
        envPath
      );

    if (
      (
        info.mode &
        0o077
      ) !==
      0
    ) {
      console.warn(
        "[prod:preflight] WARN: production env is readable by group/other users. Prefer chmod 600."
      );
    }
  }

  const domain =
    required(
      env,
      "WAPP_DOMAIN"
    );

  if (
    domain.includes(
      "://"
    ) ||
    domain.includes(
      "/"
    ) ||
    /\s/.test(
      domain
    ) ||
    /localhost|127\.0\.0\.1/i.test(
      domain
    ) ||
    !/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(
      domain
    )
  ) {
    fail(
      "WAPP_DOMAIN must be a real hostname without protocol or path."
    );
  }

  const imageTag =
    required(
      env,
      "WAPP_IMAGE_TAG"
    );

  if (
    !/^[A-Za-z0-9._-]+$/.test(
      imageTag
    ) ||
    /^(latest|local)$/i.test(
      imageTag
    )
  ) {
    fail(
      "WAPP_IMAGE_TAG must be an immutable release tag, not local/latest."
    );
  }

  const mysqlDatabase =
    required(
      env,
      "MYSQL_DATABASE"
    );

  const mysqlUser =
    required(
      env,
      "MYSQL_USER"
    );

  const mysqlPassword =
    strongSecret(
      env,
      "MYSQL_PASSWORD",
      16
    );

  strongSecret(
    env,
    "MYSQL_ROOT_PASSWORD",
    16
  );

  const databaseUrl =
    new URL(
      required(
        env,
        "DATABASE_URL"
      )
    );

  if (
    !sameBundledMysqlCredentials(
      databaseUrl,
      {
        user:
          mysqlUser,
        password:
          mysqlPassword
      }
    ) ||
    databaseUrl.pathname
      .replace(
        /^\/+/,
        ""
      ) !==
      mysqlDatabase
  ) {
    fail(
      "DATABASE_URL must match the bundled mysql service credentials/database."
    );
  }

  const shadowUrl =
    new URL(
      required(
        env,
        "SHADOW_DATABASE_URL"
      )
    );

  if (
    !sameBundledMysqlCredentials(
      shadowUrl,
      {
        user:
          mysqlUser,
        password:
          mysqlPassword
      }
    )
  ) {
    fail(
      "SHADOW_DATABASE_URL must use the bundled mysql service credentials."
    );
  }

  const databaseTlsCaPath =
    required(
      env,
      "DATABASE_TLS_CA_PATH"
    );

  if (
    databaseTlsCaPath !==
      "/etc/wapp/mysql-tls/ca.pem"
  ) {
    fail(
      "DATABASE_TLS_CA_PATH must be /etc/wapp/mysql-tls/ca.pem in the production containers."
    );
  }

  for (
    const [
      key,
      url
    ]
    of [
      [
        "DATABASE_URL",
        databaseUrl
      ],
      [
        "SHADOW_DATABASE_URL",
        shadowUrl
      ]
    ]
  ) {
    if (
      url.searchParams.get(
        "sslcert"
      ) !==
        databaseTlsCaPath ||
      url.searchParams.get(
        "sslaccept"
      ) !==
        "strict"
    ) {
      fail(
        `${key} must use sslcert=${databaseTlsCaPath} and sslaccept=strict.`
      );
    }
  }

  const shadowDatabase =
    shadowUrl.pathname
      .replace(
        /^\/+/,
        ""
      );

  if (
    !shadowDatabase ||
    shadowDatabase ===
      mysqlDatabase
  ) {
    fail(
      "SHADOW_DATABASE_URL must name a database different from MYSQL_DATABASE."
    );
  }

  const redisPassword =
    strongSecret(
      env,
      "REDIS_PASSWORD",
      16
    );

  const redisUrl =
    new URL(
      required(
        env,
        "REDIS_URL"
      )
    );

  if (
    ![
      "redis:",
      "rediss:"
    ].includes(
      redisUrl.protocol
    ) ||
    redisUrl.hostname !==
      "redis" ||
    decodeURIComponent(
      redisUrl.password
    ) !==
      redisPassword
  ) {
    fail(
      "REDIS_URL must match the bundled redis service password."
    );
  }

  strongSecret(
    env,
    "JWT_SECRET",
    32
  );

  strongSecret(
    env,
    "METRICS_TOKEN",
    32
  );

  integerInRange(
    env,
    "API_BODY_MAX_BYTES",
    65_536,
    52_428_800
  );

  integerInRange(
    env,
    "ACCESS_TOKEN_TTL_SECONDS",
    60,
    86_400
  );

  integerInRange(
    env,
    "REFRESH_TOKEN_TTL_DAYS",
    1,
    365
  );

  webUrl(
    env,
    "EVOLUTION_BASE_URL"
  );

  strongSecret(
    env,
    "EVOLUTION_API_KEY",
    32
  );

  strongSecret(
    env,
    "EVOLUTION_WEBHOOK_SECRET",
    32
  );

  integerInRange(
    env,
    "EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS",
    15,
    3_600
  );

  integerInRange(
    env,
    "MEDIA_MAX_BYTES",
    1_024,
    104_857_600
  );

  required(
    env,
    "S3_BUCKET"
  );

  required(
    env,
    "S3_REGION"
  );

  required(
    env,
    "S3_ACCESS_KEY_ID"
  );

  strongSecret(
    env,
    "S3_SECRET_ACCESS_KEY",
    16
  );

  webUrl(
    env,
    "S3_ENDPOINT",
    {
      allowHttp:
        true,
      allowEmpty:
        true
    }
  );

  booleanValue(
    env,
    "S3_FORCE_PATH_STYLE"
  );

  integerInRange(
    env,
    "JOBS_MEDIA_CAPTURE_CONCURRENCY",
    1,
    32
  );

  integerInRange(
    env,
    "JOBS_MEDIA_CAPTURE_ATTEMPTS",
    1,
    20
  );

  booleanValue(
    env,
    "MAINTENANCE_ENABLED"
  );

  integerInRange(
    env,
    "MAINTENANCE_INTERVAL_HOURS",
    1,
    168
  );

  integerInRange(
    env,
    "SESSION_RETENTION_DAYS",
    7,
    365
  );

  integerInRange(
    env,
    "MAINTENANCE_STALE_MEDIA_MINUTES",
    5,
    1_440
  );

  const backupDirectory =
    required(
      env,
      "WAPP_BACKUP_DIR"
    );

  const backupPassphraseFile =
    required(
      env,
      "WAPP_BACKUP_PASSPHRASE_FILE"
    );

  if (
    !backupDirectory.startsWith(
      "/"
    ) ||
    !backupPassphraseFile.startsWith(
      "/"
    )
  ) {
    fail(
      "Production backup directory and passphrase file must use absolute host paths."
    );
  }

  const repositoryRoot =
    resolve(
      process.cwd()
    );

  const isInsideRepository =
    value =>
      value ===
        repositoryRoot ||
      value.startsWith(
        repositoryRoot +
          "/"
      ) ||
      value.startsWith(
        repositoryRoot +
          "\\"
      );

  if (
    isInsideRepository(
      backupDirectory
    ) ||
    isInsideRepository(
      backupPassphraseFile
    )
  ) {
    fail(
      "Production backup storage and passphrase file must live outside the application repository."
    );
  }

  integerInRange(
    env,
    "WAPP_BACKUP_RETENTION_DAYS",
    7,
    3650
  );

  integerInRange(
    env,
    "WAPP_BACKUP_MIN_KEEP",
    1,
    365
  );

  booleanValue(
    env,
    "WAPP_BACKUP_AUTO_PRUNE"
  );

  webUrl(
    env,
    "TYPEBOT_URL",
    {
      allowHttp:
        true,
      allowEmpty:
        true
    }
  );

  console.log(
    `[prod:preflight] PASS — https://${domain}`
  );

  console.log(
    "[prod:preflight] Compose credentials, Prisma URLs, auth, metrics, Evolution, S3, jobs and maintenance configuration look consistent."
  );
} catch (error) {
  console.error(
    "[prod:preflight] FAIL:",
    error instanceof Error
      ? error.message
      : error
  );

  console.error(
    "[prod:preflight] No containers were changed."
  );

  process.exitCode =
    1;
}
