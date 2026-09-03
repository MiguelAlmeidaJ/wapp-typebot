import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
  scryptSync
} from "node:crypto";
import {
  chmod,
  open,
  readFile,
  stat
} from "node:fs/promises";
import {
  createReadStream,
  createWriteStream
} from "node:fs";
import {
  pipeline
} from "node:stream/promises";

const MAGIC =
  Buffer.from(
    "WAPPBK1\0",
    "ascii"
  );

const SALT_BYTES =
  16;

const IV_BYTES =
  12;

const TAG_BYTES =
  16;

const HEADER_BYTES =
  MAGIC.length +
  SALT_BYTES +
  IV_BYTES;

const SCRYPT_OPTIONS = {
  N:
    1 << 17,
  r:
    8,
  p:
    1,
  maxmem:
    256 * 1024 * 1024
};

async function passphrase(
  path
) {
  const source =
    await readFile(
      path,
      "utf8"
    );

  const value =
    source.replace(
      /\r?\n$/,
      ""
    );

  if (
    value.length <
    32
  ) {
    throw new Error(
      "Backup passphrase must contain at least 32 characters."
    );
  }

  return value;
}

function deriveKey(
  secret,
  salt
) {
  return scryptSync(
    secret,
    salt,
    32,
    SCRYPT_OPTIONS
  );
}

async function encrypt(
  input,
  output,
  passphrasePath
) {
  const secret =
    await passphrase(
      passphrasePath
    );

  const salt =
    randomBytes(
      SALT_BYTES
    );

  const iv =
    randomBytes(
      IV_BYTES
    );

  const key =
    deriveKey(
      secret,
      salt
    );

  const cipher =
    createCipheriv(
      "aes-256-gcm",
      key,
      iv
    );

  const handle =
    await open(
      output,
      "wx",
      0o600
    );

  try {
    await handle.write(
      Buffer.concat([
        MAGIC,
        salt,
        iv
      ])
    );
  } finally {
    await handle.close();
  }

  await pipeline(
    createReadStream(
      input
    ),
    cipher,
    createWriteStream(
      output,
      {
        flags:
          "a",
        mode:
          0o600
      }
    )
  );

  const tag =
    cipher.getAuthTag();

  const append =
    await open(
      output,
      "a"
    );

  try {
    await append.write(
      tag
    );
  } finally {
    await append.close();
  }

  await chmod(
    output,
    0o600
  );
}

async function decrypt(
  input,
  output,
  passphrasePath
) {
  const info =
    await stat(
      input
    );

  if (
    info.size <=
    HEADER_BYTES +
      TAG_BYTES
  ) {
    throw new Error(
      "Encrypted backup is too small to be a valid Wapp backup."
    );
  }

  const handle =
    await open(
      input,
      "r"
    );

  const header =
    Buffer.alloc(
      HEADER_BYTES
    );

  const tag =
    Buffer.alloc(
      TAG_BYTES
    );

  try {
    await handle.read(
      header,
      0,
      HEADER_BYTES,
      0
    );

    await handle.read(
      tag,
      0,
      TAG_BYTES,
      info.size -
        TAG_BYTES
    );
  } finally {
    await handle.close();
  }

  if (
    !header.subarray(
      0,
      MAGIC.length
    ).equals(
      MAGIC
    )
  ) {
    throw new Error(
      "Backup magic/version header is invalid."
    );
  }

  const salt =
    header.subarray(
      MAGIC.length,
      MAGIC.length +
        SALT_BYTES
    );

  const iv =
    header.subarray(
      MAGIC.length +
        SALT_BYTES,
      HEADER_BYTES
    );

  const secret =
    await passphrase(
      passphrasePath
    );

  const key =
    deriveKey(
      secret,
      salt
    );

  const decipher =
    createDecipheriv(
      "aes-256-gcm",
      key,
      iv
    );

  decipher.setAuthTag(
    tag
  );

  await pipeline(
    createReadStream(
      input,
      {
        start:
          HEADER_BYTES,
        end:
          info.size -
          TAG_BYTES -
          1
      }
    ),
    decipher,
    createWriteStream(
      output,
      {
        flags:
          "wx",
        mode:
          0o600
      }
    )
  );

  await chmod(
    output,
    0o600
  );
}

const [
  ,
  ,
  action,
  input,
  output,
  passphrasePath
] =
  process.argv;

if (
  ![
    "encrypt",
    "decrypt"
  ].includes(
    action
  ) ||
  !input ||
  !output ||
  !passphrasePath
) {
  console.error(
    "Usage: node scripts/prod-backup-crypto.mjs <encrypt|decrypt> <input> <output> <passphrase-file>"
  );
  process.exit(
    2
  );
}

if (
  action ===
  "encrypt"
) {
  await encrypt(
    input,
    output,
    passphrasePath
  );
} else {
  await decrypt(
    input,
    output,
    passphrasePath
  );
}
