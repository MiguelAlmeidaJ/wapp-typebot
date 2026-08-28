import {
  readFile
} from "node:fs/promises";
import {
  resolve
} from "node:path";

const envPath =
  resolve(
    process.cwd(),
    process.env
      .WAPP_PROD_ENV ??
      "infra/production/.env.production"
  );

function parseEnv(
  source
) {
  const values = {};

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
        separator + 1
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

    values[key] =
      value;
  }

  return values;
}

function fail(
  message
) {
  throw new Error(
    message
  );
}

function required(
  env,
  key
) {
  const value =
    env[key];

  if (
    !value ||
    /CHANGE_ME/i.test(
      value
    )
  ) {
    fail(
      `${key} is missing or still contains a placeholder.`
    );
  }

  return value;
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
    /localhost|127\.0\.0\.1/i.test(
      domain
    )
  ) {
    fail(
      "WAPP_DOMAIN must be a real hostname without protocol or path."
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
    required(
      env,
      "MYSQL_PASSWORD"
    );

  required(
    env,
    "MYSQL_ROOT_PASSWORD"
  );

  const databaseUrl =
    new URL(
      required(
        env,
        "DATABASE_URL"
      )
    );

  if (
    databaseUrl.protocol !==
      "mysql:" ||
    databaseUrl.hostname !==
      "mysql" ||
    decodeURIComponent(
      databaseUrl.username
    ) !==
      mysqlUser ||
    decodeURIComponent(
      databaseUrl.password
    ) !==
      mysqlPassword ||
    databaseUrl.pathname
      .replace(
        /^\/+/,
        ""
      ) !==
      mysqlDatabase
  ) {
    fail(
      "DATABASE_URL must match the bundled mysql service credentials."
    );
  }

  const redisPassword =
    required(
      env,
      "REDIS_PASSWORD"
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

  const jwtSecret =
    required(
      env,
      "JWT_SECRET"
    );

  if (
    jwtSecret.length <
    32
  ) {
    fail(
      "JWT_SECRET must contain at least 32 characters."
    );
  }

  const evolutionKey =
    required(
      env,
      "EVOLUTION_API_KEY"
    );

  if (
    evolutionKey.length <
    32
  ) {
    fail(
      "EVOLUTION_API_KEY must contain at least 32 characters."
    );
  }

  const webhookSecret =
    required(
      env,
      "EVOLUTION_WEBHOOK_SECRET"
    );

  if (
    webhookSecret.length <
    32
  ) {
    fail(
      "EVOLUTION_WEBHOOK_SECRET must contain at least 32 characters."
    );
  }

  new URL(
    required(
      env,
      "EVOLUTION_BASE_URL"
    )
  );

  required(
    env,
    "S3_BUCKET"
  );

  const s3Access =
    required(
      env,
      "S3_ACCESS_KEY_ID"
    );

  const s3Secret =
    required(
      env,
      "S3_SECRET_ACCESS_KEY"
    );

  if (
    !s3Access ||
    !s3Secret
  ) {
    fail(
      "S3 credentials must be configured for this baseline."
    );
  }

  if (
    env.S3_ENDPOINT
  ) {
    new URL(
      env.S3_ENDPOINT
    );
  }

  console.log(
    `[prod:preflight] PASS — https://${domain}`
  );

  console.log(
    "[prod:preflight] MySQL, Redis, auth, Evolution and S3 configuration look consistent."
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

  process.exitCode = 1;
}
