#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.1c] Fixing contact identity repair query plan..."

TARGET="apps/api/src/scripts/repair-contact-identities.ts"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: missing $TARGET"
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/scripts/repair-contact-identities.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldBlock = `    const messages =
      await prisma.message.findMany({
        where: {
          ticket: {
            contactId:
              contact.id
          }
        },
        select: {
          direction:
            true,
          rawPayload:
            true,
          timestamp:
            true
        },
        orderBy: {
          timestamp:
            "asc"
        },
        take: 20
      });

    const identities =
      messages.map(
        message => ({
          ...rawMessageIdentity(
            message.rawPayload
          ),
          direction:
            message.direction
        })
      );`;

const newBlock = `    /*
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
      );`;

if (
  content.includes(
    oldBlock
  )
) {
  content =
    content.replace(
      oldBlock,
      newBlock
    );
} else if (
  !content.includes(
    "Do not query Message through ticket.contactId"
  )
) {
  throw new Error(
    "P2.1b repair query block not found. Inspect current file before retrying."
  );
}

const oldFirst = `    const first =
      identities[0];`;

const newFirst = `    const first =
      identities[0];

    const firstInboundPushName =
      identities.find(
        identity =>
          identity.direction ===
            "INBOUND" &&
          identity.pushName &&
          identity.pushName !==
            first?.pushName
      )?.pushName;`;

if (
  content.includes(
    oldFirst
  )
) {
  content =
    content.replace(
      oldFirst,
      newFirst
    );
} else if (
  !content.includes(
    "firstInboundPushName"
  )
) {
  throw new Error(
    "P2.1b first identity anchor not found."
  );
}

const oldCandidate = `      first.pushName &&
      contact.whatsappName &&
      contact.name ===
        first.pushName &&
      contact.name !==
        contact.whatsappName
    ) {`;

const newCandidate = `      first.pushName &&
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
    ) {`;

if (
  content.includes(
    oldCandidate
  )
) {
  content =
    content.replace(
      oldCandidate,
      newCandidate
    );
} else if (
  !content.includes(
    "firstInboundPushName &&"
  )
) {
  throw new Error(
    "P2.1b contaminated-name condition not found."
  );
}

const oldLog = [
'      console.log(',
'        `[identity] name candidate ${contact.id}: "${contact.name}" -> "${contact.whatsappName}"`',
'      );',
'',
'      if (apply) {',
'        await prisma.contact.update({',
'          where: {',
'            id:',
'              contact.id',
'          },',
'          data: {',
'            name:',
'              contact',
'                .whatsappName',
'          }',
'        });'
].join("\n");

const newLog = [
'      const repairedName =',
'        contact.whatsappName &&',
'        contact.whatsappName !==',
'          contact.name',
'          ? contact.whatsappName',
'          : firstInboundPushName;',
'',
'      if (!repairedName) {',
'        continue;',
'      }',
'',
'      console.log(',
'        `[identity] name candidate ${contact.id}: "${contact.name}" -> "${repairedName}"`',
'      );',
'',
'      if (apply) {',
'        await prisma.contact.update({',
'          where: {',
'            id:',
'              contact.id',
'          },',
'          data: {',
'            name:',
'              repairedName',
'          }',
'        });'
].join("\n");

if (
  content.includes(
    oldLog
  )
) {
  content =
    content.replace(
      oldLog,
      newLog
    );
} else if (
  !content.includes(
    "const repairedName ="
  )
) {
  throw new Error(
    "P2.1b repair-name block not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Contact identity repair now uses indexed per-ticket reads."
);
NODE

echo "[P2.1c] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo
echo "[P2.1c] Repair utility fixed."
echo
echo "Run DRY RUN again:"
echo "  pnpm contacts:repair-identities"
echo
echo "Do not run :apply until you review the candidates."
