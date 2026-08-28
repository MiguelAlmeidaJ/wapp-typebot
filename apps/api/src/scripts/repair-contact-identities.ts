import { prisma } from "../lib/database.js";

function record(
  value: unknown
):
  | Record<string, unknown>
  | undefined {
  return value &&
    typeof value ===
      "object" &&
    !Array.isArray(
      value
    )
    ? value as
        Record<
          string,
          unknown
        >
    : undefined;
}

function text(
  value: unknown
) {
  return typeof value ===
      "string" &&
    value.trim()
    ? value.trim()
    : undefined;
}

function rawMessageIdentity(
  payload: unknown
) {
  const root =
    record(
      payload
    );

  const data =
    record(
      root?.data
    );

  const key =
    record(
      data?.key
    );

  return {
    pushName:
      text(
        data?.pushName
      ),
    remoteJid:
      text(
        key?.remoteJid
      ),
    remoteJidAlt:
      text(
        key?.remoteJidAlt
      )
  };
}

function isPhoneJid(
  value:
    | string
    | undefined
) {
  return Boolean(
    value?.endsWith(
      "@s.whatsapp.net"
    )
  );
}

function isLidJid(
  value:
    | string
    | undefined
) {
  return Boolean(
    value?.endsWith(
      "@lid"
    )
  );
}

const apply =
  process.argv.includes(
    "--apply"
  );

let nameCandidates = 0;
let namesUpdated = 0;
let jidCandidates = 0;
let jidsUpdated = 0;
let jidConflicts = 0;

try {
  const contacts =
    await prisma.contact.findMany({
      where: {
        isGroup:
          false
      },
      orderBy: {
        createdAt:
          "asc"
      }
    });

  for (
    const contact
    of contacts
  ) {
    /*
     * Do not query Message through ticket.contactId + global timestamp sort.
     * On MySQL that can require a large filesort and trigger error 1038
     * (Out of sort memory) even though we only need a tiny sample.
     *
     * Resolve ticket ids first, then read each ticket through the existing
     * Message(ticketId, timestamp) access path and merge the small samples
     * in application memory.
     */
    const tickets =
      await prisma.ticket.findMany({
        where: {
          contactId:
            contact.id
        },
        select: {
          id: true
        },
        orderBy: {
          createdAt:
            "asc"
        }
      });

    const messageSamples =
      (
        await Promise.all(
          tickets.map(
            ticket =>
              prisma.message.findMany({
                where: {
                  ticketId:
                    ticket.id
                },
                select: {
                  id: true,
                  direction:
                    true,
                  rawPayload:
                    true,
                  timestamp:
                    true
                },
                orderBy: [
                  {
                    timestamp:
                      "asc"
                  },
                  {
                    id:
                      "asc"
                  }
                ],
                take: 20
              })
          )
        )
      )
        .flat()
        .sort(
          (
            left,
            right
          ) =>
            left.timestamp
              .getTime() -
              right.timestamp
                .getTime() ||
            left.id.localeCompare(
              right.id
            )
        )
        .slice(
          0,
          100
        );

    const identities =
      messageSamples.map(
        message => ({
          ...rawMessageIdentity(
            message.rawPayload
          ),
          direction:
            message.direction,
          timestamp:
            message.timestamp
        })
      );

    /*
     * Strong contamination signal:
     * - first stored WhatsApp message for the contact was OUTBOUND;
     * - Evolution pushName on that message equals Contact.name;
     * - later inbound processing already discovered a different whatsappName.
     *
     * This is the exact shape produced when a sender profile name was
     * incorrectly used as the recipient's display name.
     */
    const first =
      identities[0];

    const firstInboundPushName =
      identities.find(
        identity =>
          identity.direction ===
            "INBOUND" &&
          identity.pushName &&
          identity.pushName !==
            first?.pushName
      )?.pushName;

    if (
      first
        ?.direction ===
        "OUTBOUND" &&
      first.pushName &&
      contact.name ===
        first.pushName &&
      (
        (
          contact.whatsappName &&
          contact.name !==
            contact.whatsappName
        ) ||
        (
          firstInboundPushName &&
          contact.name !==
            firstInboundPushName
        )
      )
    ) {
      nameCandidates +=
        1;

      const repairedName =
        contact.whatsappName &&
        contact.whatsappName !==
          contact.name
          ? contact.whatsappName
          : firstInboundPushName;

      if (!repairedName) {
        continue;
      }

      console.log(
        `[identity] name candidate ${contact.id}: "${contact.name}" -> "${repairedName}"`
      );

      if (apply) {
        await prisma.contact.update({
          where: {
            id:
              contact.id
          },
          data: {
            name:
              repairedName
          }
        });

        namesUpdated +=
          1;
      }
    }

    /*
     * Safe LID repair:
     * if the stored contact key is a LID and Evolution provides a phone-number
     * alternate JID in the historical payload, move the same contact id to the
     * canonical PN key only when no other contact already owns that PN key.
     *
     * Tickets keep their contactId, so no ticket/message history is moved.
     */
    if (
      isLidJid(
        contact.remoteJid
      )
    ) {
      const alternate =
        identities
          .map(
            identity =>
              identity
                .remoteJidAlt
          )
          .find(
            isPhoneJid
          );

      if (alternate) {
        jidCandidates +=
          1;

        const conflict =
          await prisma.contact.findUnique({
            where: {
              companyId_remoteJid: {
                companyId:
                  contact.companyId,
                remoteJid:
                  alternate
              }
            },
            select: {
              id: true
            }
          });

        if (
          conflict &&
          conflict.id !==
            contact.id
        ) {
          jidConflicts +=
            1;

          console.warn(
            `[identity] LID conflict ${contact.id}: ${contact.remoteJid} -> ${alternate}; existing contact ${conflict.id}. No automatic merge.`
          );
        } else {
          console.log(
            `[identity] LID candidate ${contact.id}: ${contact.remoteJid} -> ${alternate}`
          );

          if (apply) {
            const digits =
              alternate
                .split(
                  "@"
                )[0]
                ?.replace(
                  /\D/g,
                  ""
                ) ||
              undefined;

            await prisma.contact.update({
              where: {
                id:
                  contact.id
              },
              data: {
                remoteJid:
                  alternate,
                phoneNumber:
                  digits
              }
            });

            jidsUpdated +=
              1;
          }
        }
      }
    }
  }

  console.log("");
  console.log(
    `[identity] mode: ${apply ? "APPLY" : "DRY RUN"}`
  );

  console.log(
    `[identity] contaminated name candidates: ${nameCandidates}`
  );

  console.log(
    `[identity] names updated: ${namesUpdated}`
  );

  console.log(
    `[identity] LID candidates: ${jidCandidates}`
  );

  console.log(
    `[identity] LID keys updated: ${jidsUpdated}`
  );

  console.log(
    `[identity] LID conflicts requiring manual review: ${jidConflicts}`
  );

  if (
    !apply &&
    (
      nameCandidates >
        0 ||
      jidCandidates >
        0
    )
  ) {
    console.log("");
    console.log(
      "[identity] Review the candidates above. Apply safe repairs with:"
    );
    console.log(
      "  pnpm contacts:repair-identities:apply"
    );
  }
} finally {
  await prisma.$disconnect();
}
