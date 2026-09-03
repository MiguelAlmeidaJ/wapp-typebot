import {
  stdin
} from "node:process";

import {
  prisma
} from "../lib/database.js";
import {
  hashPassword
} from "./first-owner-password-adapter.js";
import {
  firstOwnerModel
} from "./first-owner-model.js";
import {
  normalizeBootstrapEmail,
  validateInitialOwnerPassword
} from "./first-owner-bootstrap.policy.js";

const LOCK_NAME =
  "wapp:first-owner-bootstrap";

function requireProductionGuard() {
  if (
    process.env.NODE_ENV !==
      "production" &&
    process.env.RH5_ALLOW_NON_PRODUCTION !==
      "true"
  ) {
    throw new Error(
      "First OWNER password finalization is production-only."
    );
  }
}

function requiredEnv(
  name:
    string
) {
  const value =
    process.env[
      name
    ]?.trim();

  if (
    !value
  ) {
    throw new Error(
      `${name} is required.`
    );
  }

  return value;
}

async function readPasswordFromStdin() {
  let value =
    "";

  for await (
    const chunk
    of stdin
  ) {
    value +=
      chunk.toString();
  }

  value =
    value.replace(
      /\r?\n$/,
      ""
    );

  if (
    !value
  ) {
    throw new Error(
      "Final OWNER password must be supplied through STDIN."
    );
  }

  return value;
}

function acquiredLock(
  value:
    unknown
) {
  return (
    String(
      value ??
      ""
    ) ===
      "1"
  );
}

requireProductionGuard();

const model =
  firstOwnerModel;

const email =
  normalizeBootstrapEmail(
    requiredEnv(
      "BOOTSTRAP_OWNER_EMAIL"
    )
  );

const password =
  validateInitialOwnerPassword(
    await readPasswordFromStdin(),
    email
  );

await prisma.$transaction(
  async transaction => {
    const tx =
      transaction as any;

    const lockRows =
      await transaction
        .$queryRawUnsafe<
          Array<{
            acquired:
              number
              | bigint
              | string
              | null;
          }>
        >(
          "SELECT GET_LOCK(?, 15) AS acquired",
          LOCK_NAME
        );

    if (
      !acquiredLock(
        lockRows[
          0
        ]?.acquired
      )
    ) {
      throw new Error(
        "Could not acquire first OWNER bootstrap lock."
      );
    }

    try {
      const user =
        await tx[
          model.USER_DELEGATE
        ].findFirst({
          where: {
            [
              model
                .USER_EMAIL_FIELD
            ]:
              email
          }
        });

      if (
        !user
      ) {
        throw new Error(
          "Bootstrap OWNER user was not found."
        );
      }

      if (
        user.mustChangePassword !==
          true
      ) {
        throw new Error(
          "OWNER password has already been finalized; this one-time command is disabled."
        );
      }

      const ownerMemberships =
        await tx[
          model
            .MEMBERSHIP_DELEGATE
        ].count({
          where: {
            [
              model
                .MEMBERSHIP_USER_ID_FIELD
            ]:
              user[
                model
                  .USER_ID_FIELD
              ],
            [
              model
                .MEMBERSHIP_ROLE_FIELD
            ]:
              "OWNER"
          }
        });

      if (
        ownerMemberships !==
          1
      ) {
        throw new Error(
          `Expected exactly one OWNER membership for the bootstrap user; found ${ownerMemberships}.`
        );
      }

      const passwordHash =
        await hashPassword(
          password
        );

      await tx[
        model.USER_DELEGATE
      ].update({
        where: {
          [
            model
              .USER_ID_FIELD
          ]:
            user[
              model
                .USER_ID_FIELD
            ]
        },
        data: {
          [
            model
              .USER_PASSWORD_FIELD
          ]:
            passwordHash,
          mustChangePassword:
            false
        }
      });
    } finally {
      await transaction
        .$queryRawUnsafe(
          "SELECT RELEASE_LOCK(?) AS released",
          LOCK_NAME
        );
    }
  },
  {
    maxWait:
      20_000,
    timeout:
      60_000
  }
);

console.log(
  `[prod:first-owner:finalize] PASS — OWNER ${email} password finalized; sealed bootstrap state cleared.`
);

await prisma.$disconnect();
