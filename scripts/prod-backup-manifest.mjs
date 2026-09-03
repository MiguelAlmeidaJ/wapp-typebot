import {
  createHash
} from "node:crypto";
import {
  createReadStream
} from "node:fs";
import {
  readFile,
  stat,
  writeFile
} from "node:fs/promises";
import {
  execFileSync
} from "node:child_process";

async function sha256(
  path
) {
  const hash =
    createHash(
      "sha256"
    );

  await new Promise(
    (
      resolve,
      reject
    ) => {
      const stream =
        createReadStream(
          path
        );

      stream.on(
        "data",
        chunk =>
          hash.update(
            chunk
          )
      );

      stream.on(
        "error",
        reject
      );

      stream.on(
        "end",
        resolve
      );
    }
  );

  return hash.digest(
    "hex"
  );
}

function gitCommit() {
  try {
    return execFileSync(
      "git",
      [
        "rev-parse",
        "HEAD"
      ],
      {
        encoding:
          "utf8",
        stdio: [
          "ignore",
          "pipe",
          "ignore"
        ]
      }
    ).trim();
  } catch {
    return "unknown";
  }
}

async function createManifest(
  backup,
  manifest,
  database,
  reason
) {
  const info =
    await stat(
      backup
    );

  const payload = {
    formatVersion:
      1,
    product:
      "wapp",
    kind:
      "mysql-logical-backup",
    createdAt:
      new Date()
        .toISOString(),
    database,
    reason:
      reason ||
      "scheduled",
    gitCommit:
      gitCommit(),
    encryptedFile:
      backup
        .replace(
          /^.*[\\/]/,
          ""
        ),
    encryptedBytes:
      info.size,
    sha256:
      await sha256(
        backup
      ),
    encryption: {
      cipher:
        "AES-256-GCM",
      kdf:
        "scrypt",
      scryptN:
        131072,
      format:
        "WAPPBK1"
    }
  };

  await writeFile(
    manifest,
    `${JSON.stringify(
      payload,
      null,
      2
    )}\n`,
    {
      encoding:
        "utf8",
      mode:
        0o600,
      flag:
        "wx"
    }
  );
}

async function verifyManifest(
  backup,
  manifest,
  expectedDatabase
) {
  const payload =
    JSON.parse(
      await readFile(
        manifest,
        "utf8"
      )
    );

  if (
    payload.formatVersion !==
      1 ||
    payload.product !==
      "wapp" ||
    payload.kind !==
      "mysql-logical-backup"
  ) {
    throw new Error(
      "Backup manifest type/version is invalid."
    );
  }

  if (
    expectedDatabase &&
    payload.database !==
      expectedDatabase
  ) {
    throw new Error(
      `Backup database mismatch: expected ${expectedDatabase}, got ${payload.database}.`
    );
  }

  const actualHash =
    await sha256(
      backup
    );

  if (
    actualHash !==
    payload.sha256
  ) {
    throw new Error(
      "Encrypted backup SHA-256 does not match its manifest."
    );
  }

  const info =
    await stat(
      backup
    );

  if (
    info.size !==
    payload.encryptedBytes
  ) {
    throw new Error(
      "Encrypted backup size does not match its manifest."
    );
  }

  return payload;
}

const [
  ,
  ,
  action,
  backup,
  manifest,
  databaseOrField,
  reason
] =
  process.argv;

if (
  action ===
  "create"
) {
  if (
    !backup ||
    !manifest ||
    !databaseOrField
  ) {
    process.exit(
      2
    );
  }

  await createManifest(
    backup,
    manifest,
    databaseOrField,
    reason
  );

  process.exit(
    0
  );
}

if (
  action ===
  "verify"
) {
  if (
    !backup ||
    !manifest
  ) {
    process.exit(
      2
    );
  }

  const payload =
    await verifyManifest(
      backup,
      manifest,
      databaseOrField
    );

  process.stdout.write(
    JSON.stringify(
      payload
    )
  );

  process.exit(
    0
  );
}

if (
  action ===
  "get"
) {
  if (
    !manifest ||
    !databaseOrField
  ) {
    process.exit(
      2
    );
  }

  const payload =
    JSON.parse(
      await readFile(
        manifest,
        "utf8"
      )
    );

  const value =
    payload[
      databaseOrField
    ];

  if (
    value ===
    undefined ||
    value ===
    null
  ) {
    process.exit(
      3
    );
  }

  process.stdout.write(
    String(
      value
    )
  );

  process.exit(
    0
  );
}

console.error(
  "Usage: prod-backup-manifest.mjs <create|verify|get> ..."
);

process.exit(
  2
);
