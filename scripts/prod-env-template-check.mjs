import {
  readFile
} from "node:fs/promises";

const path =
  "infra/production/.env.production.example";

const requiredKeys =
  [
    "WAPP_DOMAIN",
    "WAPP_IMAGE_TAG",
    "MYSQL_DATABASE",
    "MYSQL_USER",
    "MYSQL_PASSWORD",
    "MYSQL_ROOT_PASSWORD",
    "DATABASE_URL",
    "SHADOW_DATABASE_URL",
    "DATABASE_TLS_CA_PATH",
    "REDIS_PASSWORD",
    "REDIS_URL",
    "API_BODY_MAX_BYTES",
    "JWT_SECRET",
    "METRICS_TOKEN",
    "ACCESS_TOKEN_TTL_SECONDS",
    "REFRESH_TOKEN_TTL_DAYS",
    "EVOLUTION_BASE_URL",
    "EVOLUTION_API_KEY",
    "EVOLUTION_WEBHOOK_SECRET",
    "EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS",
    "MEDIA_MAX_BYTES",
    "S3_BUCKET",
    "S3_REGION",
    "S3_ENDPOINT",
    "S3_FORCE_PATH_STYLE",
    "S3_ACCESS_KEY_ID",
    "S3_SECRET_ACCESS_KEY",
    "JOBS_MEDIA_CAPTURE_CONCURRENCY",
    "JOBS_MEDIA_CAPTURE_ATTEMPTS",
    "MAINTENANCE_ENABLED",
    "MAINTENANCE_INTERVAL_HOURS",
    "SESSION_RETENTION_DAYS",
    "MAINTENANCE_STALE_MEDIA_MINUTES",
    "WAPP_BACKUP_DIR",
    "WAPP_BACKUP_PASSPHRASE_FILE",
    "WAPP_BACKUP_RETENTION_DAYS",
    "WAPP_BACKUP_MIN_KEEP",
    "WAPP_BACKUP_AUTO_PRUNE",
    "TYPEBOT_URL"
  ];

const placeholderKeys =
  [
    "WAPP_DOMAIN",
    "WAPP_IMAGE_TAG",
    "MYSQL_PASSWORD",
    "MYSQL_ROOT_PASSWORD",
    "DATABASE_URL",
    "SHADOW_DATABASE_URL",
    "REDIS_PASSWORD",
    "REDIS_URL",
    "JWT_SECRET",
    "METRICS_TOKEN",
    "EVOLUTION_BASE_URL",
    "EVOLUTION_API_KEY",
    "EVOLUTION_WEBHOOK_SECRET",
    "S3_BUCKET",
    "S3_ENDPOINT",
    "S3_ACCESS_KEY_ID",
    "S3_SECRET_ACCESS_KEY"
  ];

const source =
  await readFile(
    path,
    "utf8"
  );

const values =
  new Map();

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
    throw new Error(
      `Malformed template line: ${line}`
    );
  }

  const key =
    line.slice(
      0,
      separator
    ).trim();

  const value =
    line.slice(
      separator +
        1
    ).trim();

  if (
    values.has(
      key
    )
  ) {
    duplicates.add(
      key
    );
  }

  values.set(
    key,
    value
  );
}

if (
  duplicates.size >
  0
) {
  throw new Error(
    `Duplicate template keys: ${[
      ...duplicates
    ].join(", ")}`
  );
}

const missing =
  requiredKeys.filter(
    key =>
      !values.has(
        key
      )
  );

if (
  missing.length >
  0
) {
  throw new Error(
    `Missing template keys: ${missing.join(", ")}`
  );
}

for (
  const key
  of placeholderKeys
) {
  if (
    !/CHANGE_ME/i.test(
      values.get(
        key
      ) ??
      ""
    )
  ) {
    throw new Error(
      `${key} must remain an obvious CHANGE_ME placeholder in the tracked template.`
    );
  }
}

if (
  values.get(
    "TYPEBOT_URL"
  ) !==
  ""
) {
  throw new Error(
    "TYPEBOT_URL must remain empty in the production template until Typebot is formally enabled."
  );
}

console.log(
  `[prod:template] PASS — ${requiredKeys.length} keys present; tracked secrets remain placeholders.`
);
