import {
  prisma
} from "../lib/database.js";

type StatusRow = {
  Variable_name:
    string;
  Value:
    string;
};

type SecureTransportRow = {
  requiredSecureTransport:
    number
    | bigint
    | string;
  currentUser:
    string;
};

try {
  const sslRows =
    await prisma
      .$queryRawUnsafe<
        StatusRow[]
      >(
        "SHOW SESSION STATUS LIKE 'Ssl_cipher'"
      );

  const secureRows =
    await prisma
      .$queryRawUnsafe<
        SecureTransportRow[]
      >(
        "SELECT @@require_secure_transport AS requiredSecureTransport, CURRENT_USER() AS currentUser"
      );

  const cipher =
    sslRows[
      0
    ]?.Value
      ?.trim();

  if (
    !cipher
  ) {
    throw new Error(
      "Database session is not using TLS: Ssl_cipher is empty."
    );
  }

  const secureTransport =
    String(
      secureRows[
        0
      ]?.requiredSecureTransport ??
      ""
    ).toUpperCase();

  if (
    ![
      "1",
      "ON"
    ].includes(
      secureTransport
    )
  ) {
    throw new Error(
      `MySQL require_secure_transport is not enabled: ${secureTransport || "unknown"}.`
    );
  }

  console.log(
    `[db:transport] PASS — TLS cipher ${cipher}; require_secure_transport=${secureTransport}; user=${secureRows[0]?.currentUser ?? "unknown"}`
  );
} finally {
  await prisma
    .$disconnect();
}
