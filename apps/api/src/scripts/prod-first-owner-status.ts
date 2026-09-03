import {
  prisma
} from "../lib/database.js";
import {
  firstOwnerModel
} from "./first-owner-model.js";

const model =
  firstOwnerModel;

const db =
  prisma as any;

const [
  users,
  companies,
  memberships,
  owners,
  pendingOwners
] =
  await Promise.all([
    db[
      model.USER_DELEGATE
    ].count(),
    db[
      model.COMPANY_DELEGATE
    ].count(),
    db[
      model
        .MEMBERSHIP_DELEGATE
    ].count(),
    db[
      model
        .MEMBERSHIP_DELEGATE
    ].count({
      where: {
        [
          model
            .MEMBERSHIP_ROLE_FIELD
        ]:
          "OWNER"
      }
    }),
    db[
      model.USER_DELEGATE
    ].count({
      where: {
        mustChangePassword:
          true,
        memberships: {
          some: {
            [
              model
                .MEMBERSHIP_ROLE_FIELD
            ]:
              "OWNER"
          }
        }
      }
    }).catch(
      async () => {
        const pendingUsers =
          await db[
            model.USER_DELEGATE
          ].findMany({
            where: {
              mustChangePassword:
                true
            },
            select: {
              [
                model
                  .USER_ID_FIELD
              ]:
                true
            }
          });

        let count =
          0;

        for (
          const user
          of pendingUsers
        ) {
          count +=
            await db[
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
        }

        return count;
      }
    )
  ]);

let state:
  "EMPTY"
  | "PENDING_PASSWORD_FINALIZATION"
  | "READY"
  | "INCONSISTENT";

if (
  owners ===
    0 &&
  users ===
    0 &&
  companies ===
    0 &&
  memberships ===
    0
) {
  state =
    "EMPTY";
} else if (
  owners ===
    1 &&
  pendingOwners ===
    1
) {
  state =
    "PENDING_PASSWORD_FINALIZATION";
} else if (
  owners >=
    1 &&
  pendingOwners ===
    0
) {
  state =
    "READY";
} else {
  state =
    "INCONSISTENT";
}

console.log(
  JSON.stringify({
    state,
    users,
    companies,
    memberships,
    owners,
    pendingOwners
  })
);

await prisma.$disconnect();
