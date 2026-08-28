#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.1e] Fixing automatic WhatsApp display-name promotion..."

IDENTITY="apps/api/src/modules/messages/contact-identity.ts"
INGESTION="apps/api/src/modules/messages/message-ingestion.service.ts"
TEST="apps/api/src/modules/messages/contact-identity.test.ts"

for required in "$IDENTITY" "$INGESTION" "$TEST"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -Fq -- "canUsePushName" "$INGESTION"; then
  echo "ERROR: P2.1b identity protection is not present."
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/contact-identity.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !content.includes(
    "export function shouldPromoteWhatsappName("
  )
) {
  content += `

function normalizedIdentity(
  value:
    | string
    | null
    | undefined
) {
  return value
    ?.trim()
    .toLocaleLowerCase(
      "pt-BR"
    ) ??
    "";
}

export function shouldPromoteWhatsappName(input: {
  currentName: string;
  currentWhatsappName?:
    | string
    | null;
  remoteJid: string;
  phoneNumber?:
    | string
    | null;
  incomingPushName: string;
}) {
  const currentName =
    normalizedIdentity(
      input.currentName
    );

  const incoming =
    normalizedIdentity(
      input.incomingPushName
    );

  if (
    !incoming ||
    !currentName ||
    currentName ===
      incoming
  ) {
    return false;
  }

  const remoteLocalPart =
    normalizedIdentity(
      input.remoteJid
        .split(
          "@"
        )[0]
    );

  const automaticNames =
    new Set(
      [
        normalizedIdentity(
          input.phoneNumber
        ),
        normalizedIdentity(
          input.remoteJid
        ),
        remoteLocalPart,
        normalizedIdentity(
          input.currentWhatsappName
        ),
        "contato"
      ].filter(
        Boolean
      )
    );

  /*
   * We only replace Contact.name when the current value is demonstrably an
   * automatic identity. A custom/manual Wapp display name is preserved.
   *
   * This fixes the common flow:
   *   outbound first -> Contact.name = phone number
   *   first inbound  -> pushName = real WhatsApp contact name
   */
  return automaticNames.has(
    currentName
  );
}
`;
}

fs.writeFileSync(
  path,
  content
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/message-ingestion.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldImport = `import {
  canUsePushName,
  contactCreationName
} from "./contact-identity.js";`;

const newImport = `import {
  canUsePushName,
  contactCreationName,
  shouldPromoteWhatsappName
} from "./contact-identity.js";`;

if (
  content.includes(
    oldImport
  )
) {
  content =
    content.replace(
      oldImport,
      newImport
    );
} else if (
  !content.includes(
    "shouldPromoteWhatsappName"
  )
) {
  throw new Error(
    "P2.1b contact identity import anchor not found."
  );
}

/*
 * Resolve the existing contact before upsert. We need its current name and
 * previous whatsappName to distinguish an automatic name from a manual one.
 */
const upsertAnchor = `  const contact = await prisma.contact.upsert({`;

if (
  !content.includes(
    "const existingContact ="
  )
) {
  if (
    !content.includes(
      upsertAnchor
    )
  ) {
    throw new Error(
      "contact upsert anchor not found."
    );
  }

  const lookup = `  const existingContact =
    await prisma.contact.findUnique({
      where: {
        companyId_remoteJid: {
          companyId:
            connection.companyId,
          remoteJid:
            parsed.remoteJid
        }
      },
      select: {
        name: true,
        whatsappName:
          true,
        phoneNumber:
          true,
        remoteJid:
          true
      }
    });

  const validPushName =
    canUsePushName({
      fromMe:
        parsed.fromMe,
      isGroup:
        parsed.isGroup,
      pushName:
        parsed.pushName
    });

  const promoteWhatsappName =
    Boolean(
      validPushName &&
      parsed.pushName &&
      existingContact &&
      shouldPromoteWhatsappName({
        currentName:
          existingContact.name,
        currentWhatsappName:
          existingContact
            .whatsappName,
        remoteJid:
          existingContact
            .remoteJid,
        phoneNumber:
          existingContact
            .phoneNumber,
        incomingPushName:
          parsed.pushName
      })
    );

`;

  content =
    content.replace(
      upsertAnchor,
      `${lookup}${upsertAnchor}`
    );
}

/*
 * Replace the update-side canUsePushName block with the precomputed flag,
 * and promote Contact.name only when the previous name was automatic.
 */
const oldUpdate = `      ...(canUsePushName({
        fromMe:
          parsed.fromMe,
        isGroup:
          parsed.isGroup,
        pushName:
          parsed.pushName
      })
        ? {
            whatsappName:
              parsed.pushName
          }
        : {}),`;

const newUpdate = `      ...(validPushName
        ? {
            whatsappName:
              parsed.pushName,
            ...(promoteWhatsappName
              ? {
                  name:
                    parsed.pushName
                }
              : {})
          }
        : {}),`;

if (
  content.includes(
    oldUpdate
  )
) {
  content =
    content.replace(
      oldUpdate,
      newUpdate
    );
} else if (
  !content.includes(
    "promoteWhatsappName"
  )
) {
  throw new Error(
    "P2.1b contact update block not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

cat >> apps/api/src/modules/messages/contact-identity.test.ts <<'EOF'

test(
  "incoming WhatsApp name promotes an automatic phone-number display name",
  async () => {
    const {
      shouldPromoteWhatsappName
    } =
      await import(
        "./contact-identity.js"
      );

    assert.equal(
      shouldPromoteWhatsappName({
        currentName:
          "553299254233",
        currentWhatsappName:
          null,
        remoteJid:
          "553299254233@s.whatsapp.net",
        phoneNumber:
          "553299254233",
        incomingPushName:
          "Jozias Souza"
      }),
      true
    );
  }
);

test(
  "incoming WhatsApp name can replace the previous automatic WhatsApp name",
  async () => {
    const {
      shouldPromoteWhatsappName
    } =
      await import(
        "./contact-identity.js"
      );

    assert.equal(
      shouldPromoteWhatsappName({
        currentName:
          "Jozias",
        currentWhatsappName:
          "Jozias",
        remoteJid:
          "553299254233@s.whatsapp.net",
        phoneNumber:
          "553299254233",
        incomingPushName:
          "Jozias Souza"
      }),
      true
    );
  }
);

test(
  "manual Wapp display name is never overwritten by incoming pushName",
  async () => {
    const {
      shouldPromoteWhatsappName
    } =
      await import(
        "./contact-identity.js"
      );

    assert.equal(
      shouldPromoteWhatsappName({
        currentName:
          "Cliente VIP - Jozias",
        currentWhatsappName:
          "Jozias Souza",
        remoteJid:
          "553299254233@s.whatsapp.net",
        phoneNumber:
          "553299254233",
        incomingPushName:
          "Jozias S."
      }),
      false
    );
  }
);
EOF

echo "[P2.1e] Unit tests..."
pnpm test

echo "[P2.1e] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo
echo "[P2.1e] Automatic display-name promotion installed."
echo "No Prisma migration is required."
echo
echo "Existing contaminated contacts are NOT changed automatically."
echo "Inspect them with:"
echo "  pnpm contacts:repair-identities"
