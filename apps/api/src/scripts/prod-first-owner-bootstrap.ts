import {
  randomBytes
} from "node:crypto";

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
  buildBootstrapCompanySlug,
  normalizeBootstrapEmail,
  normalizeRequiredLabel
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
      "First OWNER bootstrap is production-only."
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

const email =
  normalizeBootstrapEmail(
    requiredEnv(
      "BOOTSTRAP_OWNER_EMAIL"
    )
  );

const ownerName =
  normalizeRequiredLabel(
    requiredEnv(
      "BOOTSTRAP_OWNER_NAME"
    ),
    "OWNER name"
  );

const companyName =
  normalizeRequiredLabel(
    requiredEnv(
      "BOOTSTRAP_COMPANY_NAME"
    ),
    "Company name"
  );

const model =
  firstOwnerModel;

const result =
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
        const membershipDelegate =
          tx[
            model
              .MEMBERSHIP_DELEGATE
          ];

        const existingOwners =
          await membershipDelegate
            .count({
              where: {
                [
                  model
                    .MEMBERSHIP_ROLE_FIELD
                ]:
                  "OWNER"
              }
            });

        if (
          existingOwners >
            0
        ) {
          throw new Error(
            "First OWNER bootstrap is permanently disabled because an OWNER already exists."
          );
        }

        const [
          users,
          companies,
          memberships
        ] =
          await Promise.all([
            tx[
              model.USER_DELEGATE
            ].count(),
            tx[
              model.COMPANY_DELEGATE
            ].count(),
            membershipDelegate.count()
          ]);

        if (
          users !==
            0 ||
          companies !==
            0 ||
          memberships !==
            0
        ) {
          throw new Error(
            `Identity database is not empty (users=${users}, companies=${companies}, memberships=${memberships}). RH5 will not guess how to merge legacy or partial identity data.`
          );
        }

        const existingEmail =
          await tx[
            model.USER_DELEGATE
          ].findFirst({
            where: {
              [
                model
                  .USER_EMAIL_FIELD
              ]:
                email
            },
            select: {
              [
                model
                  .USER_ID_FIELD
              ]:
                true
            }
          });

        if (
          existingEmail
        ) {
          throw new Error(
            "Bootstrap OWNER email already exists."
          );
        }

        const sealedSecret =
          randomBytes(
            48
          ).toString(
            "base64url"
          );

        const sealedHash =
          await hashPassword(
            sealedSecret
          );

        const companyData:
          Record<
            string,
            unknown
          > = {
            [
              model
                .COMPANY_NAME_FIELD
            ]:
              companyName
          };

        if (
          model
            .COMPANY_SLUG_FIELD
        ) {
          const companySlug =
            buildBootstrapCompanySlug(
              companyName
            );

          const existingSlug =
            await tx[
              model.COMPANY_DELEGATE
            ].findFirst({
              where: {
                [
                  model
                    .COMPANY_SLUG_FIELD
                ]:
                  companySlug
              },
              select: {
                [
                  model
                    .COMPANY_ID_FIELD
                ]:
                  true
              }
            });

          if (
            existingSlug
          ) {
            throw new Error(
              `Bootstrap company slug already exists: ${companySlug}.`
            );
          }

          companyData[
            model
              .COMPANY_SLUG_FIELD
          ] =
            companySlug;
        }

        const company =
          await tx[
            model.COMPANY_DELEGATE
          ].create({
            data:
              companyData
          });

        const user =
          await tx[
            model.USER_DELEGATE
          ].create({
            data: {
              [
                model
                  .USER_EMAIL_FIELD
              ]:
                email,
              [
                model
                  .USER_NAME_FIELD
              ]:
                ownerName,
              [
                model
                  .USER_PASSWORD_FIELD
              ]:
                sealedHash,
              mustChangePassword:
                true
            }
          });

        const membership =
          await membershipDelegate
            .create({
              data: {
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
                    .MEMBERSHIP_COMPANY_ID_FIELD
                ]:
                  company[
                    model
                      .COMPANY_ID_FIELD
                  ],
                [
                  model
                    .MEMBERSHIP_ROLE_FIELD
                ]:
                  "OWNER"
              }
            });

        return {
          userId:
            String(
              user[
                model
                  .USER_ID_FIELD
              ]
            ),
          companyId:
            String(
              company[
                model
                  .COMPANY_ID_FIELD
              ]
            ),
          membershipId:
            String(
              membership.id ??
              "created"
            )
        };
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
  "[prod:first-owner:bootstrap] PASS — first OWNER identity created in sealed state."
);

console.log(
  `[prod:first-owner:bootstrap] email=${email} userId=${result.userId} companyId=${result.companyId} membershipId=${result.membershipId}`
);

console.log(
  "[prod:first-owner:bootstrap] The bootstrap password was generated in memory, never displayed, and is not recoverable."
);

console.log(
  "[prod:first-owner:bootstrap] Run prod:first-owner:finalize to set the real password before first login."
);

await prisma.$disconnect();
