#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.1b] Fixing conversation identity and shell UX..."

for required in \
  "apps/api/src/modules/messages/evolution-message.parser.ts" \
  "apps/api/src/modules/messages/message-ingestion.service.ts" \
  "apps/api/package.json" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -q "replyingTo" apps/web/app/dashboard/conversations/page.tsx; then
  echo "ERROR: P2.1 quoted replies must be installed before P2.1b."
  exit 1
fi

mkdir -p \
  apps/api/src/modules/messages \
  apps/api/src/scripts \
  docs

# ---------------------------------------------------------------------------
# WhatsApp contact identity rules.
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/messages/contact-identity.ts <<'EOF'
export function isPhoneJid(
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

export function isLidJid(
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

export function canonicalRemoteJid(input: {
  remoteJid: string;
  remoteJidAlt?: string;
}) {
  /*
   * Evolution/Baileys can deliver a user through a LID while also exposing
   * the traditional phone-number JID in remoteJidAlt.
   *
   * Keep group/newsletter/broadcast addresses untouched. For a direct LID
   * conversation, prefer the phone-number JID when Evolution gives it to us.
   */
  if (
    isLidJid(
      input.remoteJid
    ) &&
    isPhoneJid(
      input.remoteJidAlt
    )
  ) {
    return input.remoteJidAlt!;
  }

  return input.remoteJid;
}

export function canUsePushName(input: {
  fromMe: boolean;
  isGroup: boolean;
  pushName?: string;
}) {
  /*
   * For fromMe messages, pushName identifies the sender (our own WhatsApp
   * profile) in common Evolution/Baileys payloads. It must never rename the
   * recipient contact.
   */
  return Boolean(
    !input.fromMe &&
    !input.isGroup &&
    input.pushName
  );
}

export function contactCreationName(input: {
  fromMe: boolean;
  isGroup: boolean;
  pushName?: string;
  phoneNumber?: string;
  remoteJid: string;
}) {
  if (
    input.isGroup
  ) {
    return `Grupo ${
      input.remoteJid
        .split(
          "@"
        )[0]
    }`;
  }

  if (
    canUsePushName(
      input
    )
  ) {
    return input.pushName!;
  }

  return (
    input.phoneNumber ??
    input.remoteJid
      .split(
        "@"
      )[0] ??
    "Contato"
  );
}
EOF

cat > apps/api/src/modules/messages/contact-identity.test.ts <<'EOF'
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  canUsePushName,
  canonicalRemoteJid,
  contactCreationName
} from "./contact-identity.js";

test(
  "direct LID prefers Evolution phone-number alternate JID",
  () => {
    assert.equal(
      canonicalRemoteJid({
        remoteJid:
          "123456789012345@lid",
        remoteJidAlt:
          "5511999999999@s.whatsapp.net"
      }),
      "5511999999999@s.whatsapp.net"
    );
  }
);

test(
  "group JID is never replaced by participant/alternate identity",
  () => {
    assert.equal(
      canonicalRemoteJid({
        remoteJid:
          "120363000000000000@g.us",
        remoteJidAlt:
          "5511999999999@s.whatsapp.net"
      }),
      "120363000000000000@g.us"
    );
  }
);

test(
  "fromMe pushName must not identify the recipient",
  () => {
    assert.equal(
      canUsePushName({
        fromMe:
          true,
        isGroup:
          false,
        pushName:
          "Miguel Almeida"
      }),
      false
    );

    assert.equal(
      contactCreationName({
        fromMe:
          true,
        isGroup:
          false,
        pushName:
          "Miguel Almeida",
        phoneNumber:
          "5511888888888",
        remoteJid:
          "5511888888888@s.whatsapp.net"
      }),
      "5511888888888"
    );
  }
);

test(
  "inbound pushName remains valid WhatsApp identity",
  () => {
    assert.equal(
      contactCreationName({
        fromMe:
          false,
        isGroup:
          false,
        pushName:
          "Cliente correto",
        phoneNumber:
          "5511888888888",
        remoteJid:
          "5511888888888@s.whatsapp.net"
      }),
      "Cliente correto"
    );
  }
);
EOF

# ---------------------------------------------------------------------------
# Parser: use remoteJidAlt when it safely canonicalizes a direct LID.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/evolution-message.parser.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const identityImport =
  `import { canonicalRemoteJid } from "./contact-identity.js";`;

if (
  !content.includes(
    identityImport
  )
) {
  const anchor =
    `export interface ParsedEvolutionMessage {`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "ParsedEvolutionMessage anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${identityImport}

${anchor}`
    );
}

const oldRemote = `  const key = record(data.key);
  const remoteJid = string(key?.remoteJid);
  const externalId = string(key?.id);

  if (!remoteJid || !externalId) {
    return null;
  }

  if (
    remoteJid === "status@broadcast" ||
    remoteJid.endsWith("@broadcast")
  ) {
    return null;
  }`;

const newRemote = `  const key = record(data.key);
  const sourceRemoteJid =
    string(
      key?.remoteJid
    );
  const remoteJidAlt =
    string(
      key?.remoteJidAlt
    );
  const externalId =
    string(
      key?.id
    );

  if (
    !sourceRemoteJid ||
    !externalId
  ) {
    return null;
  }

  if (
    sourceRemoteJid ===
      "status@broadcast" ||
    sourceRemoteJid.endsWith(
      "@broadcast"
    )
  ) {
    return null;
  }

  const remoteJid =
    canonicalRemoteJid({
      remoteJid:
        sourceRemoteJid,
      remoteJidAlt
    });`;

if (
  content.includes(
    oldRemote
  )
) {
  content =
    content.replace(
      oldRemote,
      newRemote
    );
} else if (
  !content.includes(
    "sourceRemoteJid"
  )
) {
  throw new Error(
    "Evolution parser remoteJid anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Ingestion: never use a fromMe pushName to create/update recipient identity.
# ---------------------------------------------------------------------------

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

const identityImport =
  `import {
  canUsePushName,
  contactCreationName
} from "./contact-identity.js";`;

if (
  !content.includes(
    'from "./contact-identity.js"'
  )
) {
  const anchor =
    `import {
  parseEvolutionMessage,
  type ParsedEvolutionMessage
} from "./evolution-message.parser.js";`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "message parser import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${identityImport}`
    );
}

const oldDisplay = `function displayName(message: ParsedEvolutionMessage) {
  if (message.isGroup) {
    return \`Grupo \${message.remoteJid.split("@")[0]}\`;
  }

  return (
    message.pushName ??
    message.phoneNumber ??
    message.remoteJid.split("@")[0] ??
    "Contato"
  );
}`;

const newDisplay = `function displayName(
  message:
    ParsedEvolutionMessage
) {
  return contactCreationName({
    fromMe:
      message.fromMe,
    isGroup:
      message.isGroup,
    pushName:
      message.pushName,
    phoneNumber:
      message.phoneNumber,
    remoteJid:
      message.remoteJid
  });
}`;

if (
  content.includes(
    oldDisplay
  )
) {
  content =
    content.replace(
      oldDisplay,
      newDisplay
    );
} else if (
  !content.includes(
    "return contactCreationName("
  )
) {
  throw new Error(
    "displayName anchor not found."
  );
}

const oldUpdate = `      ...(parsed.pushName && !parsed.isGroup
        ? { whatsappName: parsed.pushName }
        : {}),`;

const newUpdate = `      ...(canUsePushName({
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
    "canUsePushName({"
  )
) {
  throw new Error(
    "contact update pushName anchor not found."
  );
}

const oldCreate = `      whatsappName:
        parsed.pushName && !parsed.isGroup
          ? parsed.pushName
          : undefined,`;

const newCreate = `      whatsappName:
        canUsePushName({
          fromMe:
            parsed.fromMe,
          isGroup:
            parsed.isGroup,
          pushName:
            parsed.pushName
        })
          ? parsed.pushName
          : undefined,`;

if (
  content.includes(
    oldCreate
  )
) {
  content =
    content.replace(
      oldCreate,
      newCreate
    );
} else if (
  !content.includes(
    "whatsappName:\n        canUsePushName({"
  )
) {
  throw new Error(
    "contact create pushName anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Conservative one-time repair for contacts already contaminated by fromMe.
# Dry run by default. Also repairs safe LID -> PN contact keys.
# ---------------------------------------------------------------------------

cat > apps/api/src/scripts/repair-contact-identities.ts <<'EOF'
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
    const messages =
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

    if (
      first
        ?.direction ===
        "OUTBOUND" &&
      first.pushName &&
      contact.whatsappName &&
      contact.name ===
        first.pushName &&
      contact.name !==
        contact.whatsappName
    ) {
      nameCandidates +=
        1;

      console.log(
        `[identity] name candidate ${contact.id}: "${contact.name}" -> "${contact.whatsappName}"`
      );

      if (apply) {
        await prisma.contact.update({
          where: {
            id:
              contact.id
          },
          data: {
            name:
              contact
                .whatsappName
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
EOF

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

pkg.scripts ??= {};

pkg.scripts[
  "contacts:repair-identities"
] =
  "tsx src/scripts/repair-contact-identities.ts";

pkg.scripts[
  "contacts:repair-identities:apply"
] =
  "tsx src/scripts/repair-contact-identities.ts --apply";

const current =
  pkg.scripts.test;

if (
  typeof current !==
    "string"
) {
  throw new Error(
    "API test script is missing."
  );
}

const testFile =
  "src/modules/messages/contact-identity.test.ts";

if (
  !current.includes(
    testFile
  )
) {
  pkg.scripts.test =
    `${current} ${testFile}`;
}

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

pkg.scripts ??= {};

pkg.scripts[
  "contacts:repair-identities"
] =
  "pnpm --filter @wapp/api contacts:repair-identities";

pkg.scripts[
  "contacts:repair-identities:apply"
] =
  "pnpm --filter @wapp/api contacts:repair-identities:apply";

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);
NODE

# ---------------------------------------------------------------------------
# Conversation shell:
# - do not auto-open first ticket
# - real home panel
# - explicit return to panel
# - surface WhatsApp name as secondary identity
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

function replaceOnce(
  before,
  after,
  label
) {
  if (
    content.includes(
      after
    )
  ) {
    return;
  }

  if (
    !content.includes(
      before
    )
  ) {
    throw new Error(
      `${label} anchor not found.`
    );
  }

  content =
    content.replace(
      before,
      after
    );
}

replaceOnce(
  `  phoneNumber: string | null;
  isGroup: boolean;`,
  `  phoneNumber: string | null;
  whatsappName:
    | string
    | null;
  isGroup: boolean;`,
  "Contact whatsappName"
);

const oldAutoSelect = `    setTickets(payload.tickets);
    setSelectedId(current => {
      if (current && payload.tickets.some(ticket => ticket.id === current)) {
        return current;
      }
      return payload.tickets[0]?.id ?? null;
    });`;

const newAutoSelect = `    setTickets(payload.tickets);
    setSelectedId(current => {
      if (!current) {
        return null;
      }

      return payload.tickets.some(
        ticket =>
          ticket.id ===
          current
      )
        ? current
        : null;
    });`;

replaceOnce(
  oldAutoSelect,
  newAutoSelect,
  "automatic ticket selection"
);

const oldEmpty = `          {!selectedTicket ? (
            <div className="chat-empty">
              <div className="chat-empty__mark">W</div>
              <strong>Suas conversas vão aparecer aqui.</strong>
              <p>O realtime substitui o polling de três segundos do P0.6.</p>
            </div>
          ) : (`;

const newHome = `          {!selectedTicket ? (
            <div className="conversation-home">
              <header className="conversation-home__header">
                <div>
                  <span className="eyebrow">
                    Central de atendimento
                  </span>
                  <h2>
                    Visão das conversas
                  </h2>
                  <p>
                    Acompanhe a operação e escolha uma conversa quando quiser entrar no atendimento.
                  </p>
                </div>
              </header>

              <div className="conversation-home__metrics">
                <article>
                  <span>
                    Aguardando
                  </span>
                  <strong>
                    {pendingCount}
                  </strong>
                  <small>
                    precisam ser assumidas
                  </small>
                </article>

                <article>
                  <span>
                    Em atendimento
                  </span>
                  <strong>
                    {openCount}
                  </strong>
                  <small>
                    conversas abertas
                  </small>
                </article>

                <article>
                  <span>
                    Ativos
                  </span>
                  <strong>
                    {tickets.length}
                  </strong>
                  <small>
                    total na caixa
                  </small>
                </article>

                <article>
                  <span>
                    Equipe online
                  </span>
                  <strong>
                    {onlineMembershipIds.length}
                  </strong>
                  <small>
                    atendentes disponíveis
                  </small>
                </article>
              </div>

              <div className="conversation-home__columns">
                <section className="conversation-home__panel">
                  <header>
                    <div>
                      <strong>
                        Aguardando atendimento
                      </strong>
                      <span>
                        Prioridade para assumir
                      </span>
                    </div>
                    <span className="conversation-home__count">
                      {pendingCount}
                    </span>
                  </header>

                  <div className="conversation-home__list">
                    {tickets
                      .filter(
                        ticket =>
                          ticket.status ===
                          "PENDING"
                      )
                      .slice(
                        0,
                        6
                      )
                      .map(
                        ticket => (
                          <button
                            key={
                              ticket.id
                            }
                            onClick={() =>
                              setSelectedId(
                                ticket.id
                              )
                            }
                            type="button"
                          >
                            <div className="conversation-home__avatar">
                              {ticket.contact.name
                                .slice(
                                  0,
                                  1
                                )
                                .toUpperCase()}
                            </div>
                            <div>
                              <strong>
                                {ticket.contact.name}
                              </strong>
                              <span>
                                {ticketPreview(
                                  ticket
                                )}
                              </span>
                            </div>
                            <time>
                              {timeLabel(
                                ticket.lastMessageAt
                              )}
                            </time>
                          </button>
                        )
                      )}

                    {pendingCount === 0 && (
                      <div className="conversation-home__empty">
                        Nenhuma conversa aguardando agora.
                      </div>
                    )}
                  </div>
                </section>

                <section className="conversation-home__panel">
                  <header>
                    <div>
                      <strong>
                        Em atendimento
                      </strong>
                      <span>
                        Conversas em andamento
                      </span>
                    </div>
                    <span className="conversation-home__count">
                      {openCount}
                    </span>
                  </header>

                  <div className="conversation-home__list">
                    {tickets
                      .filter(
                        ticket =>
                          ticket.status ===
                          "OPEN"
                      )
                      .slice(
                        0,
                        6
                      )
                      .map(
                        ticket => (
                          <button
                            key={
                              ticket.id
                            }
                            onClick={() =>
                              setSelectedId(
                                ticket.id
                              )
                            }
                            type="button"
                          >
                            <div className="conversation-home__avatar">
                              {ticket.contact.name
                                .slice(
                                  0,
                                  1
                                )
                                .toUpperCase()}
                            </div>
                            <div>
                              <strong>
                                {ticket.contact.name}
                              </strong>
                              <span>
                                {ticketPreview(
                                  ticket
                                )}
                              </span>
                            </div>
                            <time>
                              {timeLabel(
                                ticket.lastMessageAt
                              )}
                            </time>
                          </button>
                        )
                      )}

                    {openCount === 0 && (
                      <div className="conversation-home__empty">
                        Nenhum atendimento aberto agora.
                      </div>
                    )}
                  </div>
                </section>
              </div>
            </div>
          ) : (`;

replaceOnce(
  oldEmpty,
  newHome,
  "conversation home panel"
);

const contactAnchor = `                <div className="chat-header__contact">
                  <div className="ticket-avatar">`;

const contactReplacement = `                <div className="chat-header__contact">
                  <button
                    aria-label="Voltar ao painel de conversas"
                    className="conversation-home-back"
                    onClick={() =>
                      setSelectedId(
                        null
                      )
                    }
                    title="Painel de conversas"
                    type="button"
                  >
                    ←
                  </button>
                  <div className="ticket-avatar">`;

replaceOnce(
  contactAnchor,
  contactReplacement,
  "conversation home back button"
);

const headerIdentityOld = `                    <strong>{selectedTicket.contact.name}</strong>
                    <span>
                      {selectedTicket.contact.phoneNumber ??
                        selectedTicket.contact.remoteJid}
                    </span>`;

const headerIdentityNew = `                    <strong>{selectedTicket.contact.name}</strong>
                    <span>
                      {selectedTicket.contact.whatsappName &&
                      selectedTicket.contact.whatsappName !==
                        selectedTicket.contact.name
                        ? \`\${selectedTicket.contact.whatsappName} · \`
                        : ""}
                      {selectedTicket.contact.phoneNumber ??
                        selectedTicket.contact.remoteJid}
                    </span>`;

replaceOnce(
  headerIdentityOld,
  headerIdentityNew,
  "header secondary WhatsApp identity"
);

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Compact action/routing bar + conversation home UI.
# Append-only overrides preserve canonical conversation scroll/composer.
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P2.1b / CONVERSATION SHELL" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P2.1b / CONVERSATION SHELL ---------------------------------- */

.inbox-screen--contained .assignment-bar {
  display: flex !important;
  flex: 0 0 auto;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: 6px 8px;
  padding: 7px 12px !important;
}

.inbox-screen--contained
  .assignment-bar
  > div:not(.selected-ticket-tags) {
  display: grid;
  flex: 1 1 190px;
  max-width: 330px;
  gap: 3px;
}

.inbox-screen--contained .assignment-bar select {
  height: 32px !important;
  border-radius: 8px;
  padding: 0 10px;
  font-size: 10px;
}

.inbox-screen--contained
  .assignment-bar
  > .secondary-button {
  width: auto !important;
  height: 32px;
  flex: 0 0 auto;
  margin: 0;
  padding: 0 11px;
  border-radius: 8px;
  white-space: nowrap;
}

.inbox-screen--contained
  .assignment-bar
  > .ticket-notes-toggle,
.inbox-screen--contained
  .assignment-bar
  > .ticket-tags-toggle,
.inbox-screen--contained
  .assignment-bar
  > .conversation-search-toggle,
.inbox-screen--contained
  .assignment-bar
  > .closed-tickets-toggle,
.inbox-screen--contained
  .assignment-bar
  > .sla-monitor-toggle,
.inbox-screen--contained
  .assignment-bar
  > .ticket-history-toggle {
  width: auto !important;
  min-width: 0 !important;
  height: 30px !important;
  flex: 0 0 auto;
  margin: 0 !important;
  padding: 0 9px !important;
  border-radius: 8px !important;
  font-size: 10px !important;
  white-space: nowrap;
}

.inbox-screen--contained .assignment-bar > small {
  width: 100%;
  flex: 1 0 100%;
  margin: 0;
  padding: 0 1px;
  line-height: 1.2;
}

.inbox-screen--contained
  .assignment-bar
  > .selected-ticket-tags {
  width: 100%;
  flex: 1 0 100%;
}

.conversation-home-back {
  display: grid;
  width: 30px;
  height: 30px;
  flex: 0 0 30px;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: white;
  color: var(--muted);
  font-size: 14px;
}

.conversation-home-back:hover {
  border-color: var(--line-strong);
  color: var(--ink);
}

.conversation-home {
  min-width: 0;
  min-height: 0;
  height: 100%;
  overflow-y: auto;
  padding: clamp(24px, 4vw, 44px);
  background:
    radial-gradient(
      circle at 88% 8%,
      rgba(31, 122, 80, 0.06),
      transparent 28%
    ),
    var(--surface-subtle);
}

.conversation-home__header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 22px;
}

.conversation-home__header h2 {
  margin: 8px 0 7px;
  font-size: clamp(25px, 3vw, 34px);
  font-weight: 660;
  letter-spacing: -0.045em;
}

.conversation-home__header p {
  max-width: 620px;
  margin: 0;
  color: var(--muted);
  font-size: 12px;
  line-height: 1.55;
}

.conversation-home__metrics {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 10px;
}

.conversation-home__metrics article {
  min-width: 0;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
  padding: 15px 16px;
  box-shadow: 0 8px 24px rgba(24, 33, 27, 0.025);
}

.conversation-home__metrics span,
.conversation-home__metrics small {
  display: block;
  color: var(--muted);
  font-size: 10px;
}

.conversation-home__metrics strong {
  display: block;
  margin: 8px 0 5px;
  font-size: 26px;
  font-weight: 670;
  letter-spacing: -0.04em;
}

.conversation-home__columns {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
  margin-top: 12px;
}

.conversation-home__panel {
  min-width: 0;
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: white;
}

.conversation-home__panel > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  border-bottom: 1px solid var(--line);
  padding: 14px 16px;
}

.conversation-home__panel > header div {
  display: grid;
  gap: 3px;
}

.conversation-home__panel > header strong {
  font-size: 12px;
}

.conversation-home__panel > header span:not(.conversation-home__count) {
  color: var(--muted);
  font-size: 9px;
}

.conversation-home__count {
  display: grid;
  min-width: 28px;
  height: 24px;
  place-items: center;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 0 8px;
  font-size: 10px;
  font-weight: 800;
}

.conversation-home__list {
  display: grid;
}

.conversation-home__list > button {
  display: grid;
  min-width: 0;
  grid-template-columns: 32px minmax(0, 1fr) auto;
  align-items: center;
  gap: 10px;
  border: 0;
  border-bottom: 1px solid #eef0ed;
  background: white;
  padding: 10px 13px;
  text-align: left;
}

.conversation-home__list > button:last-child {
  border-bottom: 0;
}

.conversation-home__list > button:hover {
  background: #f8faf8;
}

.conversation-home__avatar {
  display: grid;
  width: 32px;
  height: 32px;
  place-items: center;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 11px;
  font-weight: 800;
}

.conversation-home__list > button > div:nth-child(2) {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.conversation-home__list > button strong,
.conversation-home__list > button span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.conversation-home__list > button strong {
  font-size: 11px;
}

.conversation-home__list > button span,
.conversation-home__list > button time {
  color: var(--muted);
  font-size: 9px;
}

.conversation-home__empty {
  color: var(--muted);
  padding: 28px 16px;
  font-size: 11px;
  text-align: center;
}

@media (max-width: 1100px) {
  .conversation-home__metrics {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .conversation-home__columns {
    grid-template-columns: 1fr;
  }

  .inbox-screen--contained
    .assignment-bar
    > div:not(.selected-ticket-tags) {
    max-width: none;
  }
}

@media (max-width: 760px) {
  .conversation-home {
    padding: 18px 14px;
  }

  .conversation-home__metrics {
    grid-template-columns: 1fr 1fr;
  }

  .inbox-screen--contained .assignment-bar {
    align-items: stretch;
  }

  .inbox-screen--contained
    .assignment-bar
    > div:not(.selected-ticket-tags) {
    flex-basis: 100%;
  }
}

/* --- /WAPP P2.1b ------------------------------------------------------ */
EOF
fi

cat > docs/P2_01B_CONVERSATION_IDENTITY_UX.md <<'EOF'
# P2.1b Conversation identity + shell UX

P2.1b addresses three issues observed immediately after quoted replies.

## 1. Wrong contact names on fromMe messages

Evolution/Baileys `pushName` on a `fromMe` message can represent the sender
profile (the connected WhatsApp account), not the remote recipient.

Wapp previously used `pushName` for contact creation/update regardless of
direction. That could create several unrelated recipient conversations with
the connected account owner's name.

P2.1b rules:

- inbound direct message: `pushName` may update `whatsappName`;
- outbound/fromMe message: `pushName` never creates or renames the recipient;
- outbound contact fallback is phone number / remote JID;
- group behavior remains unchanged.

## 2. LID / phone-number identity

Evolution 2.3.7 exposes `remoteJidAlt`.

For a direct `@lid` message, when the alternate is an
`@s.whatsapp.net` JID, Wapp uses the phone-number JID as the canonical contact
key.

Groups are never replaced by an alternate participant identity.

## 3. Existing contaminated contacts

Dry run:

```bash
pnpm contacts:repair-identities
```

Apply only conservative repairs:

```bash
pnpm contacts:repair-identities:apply
```

A name is considered contaminated only when:

- the earliest stored message is OUTBOUND;
- that Evolution payload's pushName equals the current Contact.name;
- the contact later obtained a different `whatsappName`.

This is the signature of the previous fromMe naming bug.

The repair also upgrades a stored LID contact to its phone-number JID when
historical payloads provide `remoteJidAlt` and no other contact already owns
that canonical JID.

If a canonical contact already exists, the script reports a conflict and does
not merge contacts/tickets automatically.

## 4. Conversation home

The conversation page no longer auto-opens the first ticket.

With no selected ticket, the right pane shows:

- waiting count;
- open count;
- total active conversations;
- online team count;
- waiting conversations;
- conversations currently in service.

Opening a ticket is explicit.

The conversation header has a back-to-panel button.

## 5. Compact operation bar

Fila, atendente, transfer and the operational tools now use a compact wrapping
toolbar.

P2.1b does not change the canonical message layout:

- `.conversation-scroll` remains the message scroll;
- `.conversation-composer` remains outside that scroll and pinned.
EOF

echo "[P2.1b] Unit tests..."
pnpm test

echo "[P2.1b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P2.1b] Typechecking Web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.1b] Identity and conversation shell installed."
echo "No Prisma migration is required."
echo
echo "Inspect existing contacts without changing data:"
echo "  pnpm contacts:repair-identities"
echo
echo "If the reported candidates are correct:"
echo "  pnpm contacts:repair-identities:apply"
