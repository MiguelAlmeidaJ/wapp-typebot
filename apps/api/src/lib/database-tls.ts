import {
  readFileSync
} from "node:fs";

type DatabaseTlsInput = {
  nodeEnv:
    string;
  caPath?:
    string;
};

export function buildDatabaseTlsOptions(
  input:
    DatabaseTlsInput
):
  | false
  | {
      ca:
        string;
      rejectUnauthorized:
        true;
    } {
  if (
    input.nodeEnv !==
    "production"
  ) {
    return false;
  }

  const caPath =
    input.caPath
      ?.trim();

  if (
    !caPath
  ) {
    throw new Error(
      "DATABASE_TLS_CA_PATH is required when NODE_ENV=production."
    );
  }

  const ca =
    readFileSync(
      caPath,
      "utf8"
    );

  if (
    !ca.includes(
      "-----BEGIN CERTIFICATE-----"
    )
  ) {
    throw new Error(
      "DATABASE_TLS_CA_PATH does not contain a PEM certificate."
    );
  }

  return {
    ca,
    rejectUnauthorized:
      true
  };
}
