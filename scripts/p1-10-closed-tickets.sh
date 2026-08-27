#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.10] Building closed ticket history and safe reopen..."

for required in \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
  "apps/web/components/auth-provider.tsx" \
  "apps/web/components/messages/message-media.tsx" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/web/components/conversations \
  docs

# ---------------------------------------------------------------------------
# Backend: safe reopen
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("export async function reopenTicket(")) {
  const anchor =
    "export async function sendTicketText(";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find sendTicketText anchor."
    );
  }

  const fn = `export async function reopenTicket(input: {
  companyId: string;
  ticketId: string;
  membershipId: string;
  role: WappRole;
}) {
  const current = await getTicket(
    input.companyId,
    input.ticketId
  );

  if (current.status !== "CLOSED") {
    return {
      ticket: current,
      reusedExisting: true
    };
  }

  assertCanOperateTicket(
    current.assignedMembershipId,
    input.membershipId,
    input.role
  );

  await validateMembership(
    input.companyId,
    input.membershipId
  );

  const activeKey =
    \`\${current.whatsappConnectionId}:\${current.contactId}\`;

  const existingActive =
    await prisma.ticket.findFirst({
      where: {
        companyId:
          input.companyId,
        whatsappConnectionId:
          current.whatsappConnectionId,
        contactId:
          current.contactId,
        status: {
          in: [
            "OPEN",
            "PENDING"
          ]
        }
      },
      include: ticketInclude,
      orderBy: {
        lastMessageAt: "desc"
      }
    });

  if (existingActive) {
    return {
      ticket:
        existingActive,
      reusedExisting: true
    };
  }

  try {
    const ticket =
      await prisma.ticket.update({
        where: {
          id: current.id
        },
        data: {
          activeKey,
          status: "OPEN",
          assignedMembershipId:
            input.membershipId,
          unreadCount: 0,
          closedAt: null
        },
        include: ticketInclude
      });

    publishRealtime(
      input.companyId,
      {
        type: "ticket.updated",
        ticketId:
          ticket.id
      }
    );

    return {
      ticket,
      reusedExisting: false
    };
  } catch (error) {
    /*
     * A new inbound message can race with reopen and create
     * another active ticket after the pre-check. The unique
     * activeKey remains the final safety boundary.
     */
    const racedTicket =
      await prisma.ticket.findFirst({
        where: {
          companyId:
            input.companyId,
          whatsappConnectionId:
            current.whatsappConnectionId,
          contactId:
            current.contactId,
          status: {
            in: [
              "OPEN",
              "PENDING"
            ]
          }
        },
        include: ticketInclude,
        orderBy: {
          lastMessageAt: "desc"
        }
      });

    if (racedTicket) {
      return {
        ticket:
          racedTicket,
        reusedExisting: true
      };
    }

    throw error;
  }
}

`;

  content = content.replace(
    anchor,
    `${fn}${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Safe ticket reopen service installed.");
NODE

# ---------------------------------------------------------------------------
# Backend route
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.routes.ts";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("reopenTicket,")) {
  /*
   * Tolerant insertion into the ticket.service import list.
   */
  const importStart =
    content.indexOf(
      'from "./ticket.service.js";'
    );

  if (importStart < 0) {
    throw new Error(
      "ticket.service import not found."
    );
  }

  const braceStart =
    content.lastIndexOf(
      "{",
      importStart
    );

  if (braceStart < 0) {
    throw new Error(
      "ticket.service import opening brace not found."
    );
  }

  content =
    content.slice(0, braceStart + 1) +
    `
  reopenTicket,` +
    content.slice(braceStart + 1);
}

if (
  !content.includes(
    '"/api/v1/tickets/:id/reopen"'
  )
) {
  const closeRoute =
    `  app.post(
    "/api/v1/tickets/:id/close",`;

  if (!content.includes(closeRoute)) {
    throw new Error(
      "Close ticket route anchor not found."
    );
  }

  const route = `  app.post(
    "/api/v1/tickets/:id/reopen",
    async request => {
      const auth =
        await requireAuth(request);

      const params =
        ticketIdSchema.parse(
          request.params
        );

      return reopenTicket({
        companyId:
          auth.companyId,
        ticketId:
          params.id,
        membershipId:
          auth.membershipId,
        role:
          auth.role
      });
    }
  );

`;

  content = content.replace(
    closeRoute,
    `${route}${closeRoute}`
  );
}

fs.writeFileSync(path, content);
console.log("Ticket reopen route installed.");
NODE

# ---------------------------------------------------------------------------
# Closed ticket history component
# ---------------------------------------------------------------------------

cat > apps/web/components/conversations/closed-tickets-drawer.tsx <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";
import { MessageMedia } from "@/components/messages/message-media";
import { ApiError } from "@/lib/api";

type TicketStatus =
  | "OPEN"
  | "PENDING"
  | "CLOSED";

type MessageType =
  | "TEXT"
  | "IMAGE"
  | "AUDIO"
  | "VIDEO"
  | "DOCUMENT"
  | "STICKER"
  | "LOCATION"
  | "CONTACT"
  | "UNKNOWN";

interface ClosedTicket {
  id: string;
  status: TicketStatus;
  lastMessage: string | null;
  lastMessageAt: string;
  closedAt: string | null;
  contact: {
    id: string;
    name: string;
    phoneNumber: string | null;
    isGroup: boolean;
  };
  queue: {
    id: string;
    name: string;
  } | null;
  assignedMembership: {
    id: string;
    user: {
      id: string;
      name: string;
      email: string;
    };
  } | null;
  tags?: Array<{
    tagId: string;
    tag: {
      id: string;
      name: string;
      colorKey: string;
      isActive: boolean;
    };
  }>;
}

interface ClosedTicketsResponse {
  tickets: ClosedTicket[];
}

interface ArchivedMessage {
  id: string;
  direction:
    | "INBOUND"
    | "OUTBOUND";
  type: MessageType;
  body: string | null;
  mediaMimeType: string | null;
  mediaFileName: string | null;
  mediaStatus:
    | "NONE"
    | "PENDING"
    | "READY"
    | "FAILED";
  mediaSize: number | null;
  timestamp: string;
}

interface MessagesResponse {
  messages: ArchivedMessage[];
}

interface ReopenResponse {
  ticket: ClosedTicket & {
    status:
      | "OPEN"
      | "PENDING";
  };
  reusedExisting: boolean;
}

function dateTimeLabel(
  value: string | null
) {
  if (!value) {
    return "—";
  }

  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit"
    }
  ).format(
    new Date(value)
  );
}

function messageFallback(
  type: MessageType
) {
  switch (type) {
    case "IMAGE":
      return "[Imagem]";
    case "AUDIO":
      return "[Áudio]";
    case "VIDEO":
      return "[Vídeo]";
    case "DOCUMENT":
      return "[Documento]";
    case "STICKER":
      return "[Sticker]";
    case "LOCATION":
      return "[Localização]";
    case "CONTACT":
      return "[Contato]";
    default:
      return "";
  }
}

export function ClosedTicketsDrawer({
  onClose,
  onReopened
}: {
  onClose: () => void;
  onReopened: (
    ticketId: string,
    reusedExisting: boolean
  ) => void;
}) {
  const { request } =
    useAuth();

  const [tickets, setTickets] =
    useState<ClosedTicket[]>([]);
  const [selectedId, setSelectedId] =
    useState<string | null>(null);
  const [messages, setMessages] =
    useState<ArchivedMessage[]>([]);
  const [loadingTickets, setLoadingTickets] =
    useState(true);
  const [loadingMessages, setLoadingMessages] =
    useState(false);
  const [reopening, setReopening] =
    useState(false);
  const [search, setSearch] =
    useState("");
  const [error, setError] =
    useState("");

  const selectedTicket =
    useMemo(
      () =>
        tickets.find(
          ticket =>
            ticket.id ===
            selectedId
        ) ?? null,
      [
        selectedId,
        tickets
      ]
    );

  const visibleTickets =
    useMemo(() => {
      const query =
        search
          .trim()
          .toLowerCase();

      if (!query) {
        return tickets;
      }

      return tickets.filter(
        ticket =>
          ticket.contact.name
            .toLowerCase()
            .includes(query) ||
          (
            ticket.contact
              .phoneNumber ??
            ""
          )
            .toLowerCase()
            .includes(query) ||
          (
            ticket.lastMessage ??
            ""
          )
            .toLowerCase()
            .includes(query)
      );
    }, [
      search,
      tickets
    ]);

  const loadTickets =
    useCallback(async () => {
      setLoadingTickets(true);
      setError("");

      try {
        const payload =
          await request<ClosedTicketsResponse>(
            "/api/v1/tickets?status=CLOSED"
          );

        setTickets(
          payload.tickets
        );

        setSelectedId(
          current =>
            current &&
            payload.tickets.some(
              ticket =>
                ticket.id ===
                current
            )
              ? current
              : payload.tickets[0]
                  ?.id ??
                null
        );
      } catch {
        setError(
          "Não foi possível carregar os atendimentos encerrados."
        );
      } finally {
        setLoadingTickets(false);
      }
    }, [request]);

  useEffect(() => {
    void loadTickets();
  }, [loadTickets]);

  useEffect(() => {
    if (!selectedId) {
      setMessages([]);
      return;
    }

    let cancelled = false;

    void (async () => {
      setLoadingMessages(true);
      setError("");

      try {
        const payload =
          await request<MessagesResponse>(
            `/api/v1/tickets/${selectedId}/messages`
          );

        if (!cancelled) {
          setMessages(
            payload.messages
          );
        }
      } catch {
        if (!cancelled) {
          setError(
            "Não foi possível carregar o histórico deste atendimento."
          );
        }
      } finally {
        if (!cancelled) {
          setLoadingMessages(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [
    request,
    selectedId
  ]);

  async function reopen() {
    if (
      !selectedId ||
      reopening
    ) {
      return;
    }

    setReopening(true);
    setError("");

    try {
      const payload =
        await request<ReopenResponse>(
          `/api/v1/tickets/${selectedId}/reopen`,
          {
            method: "POST"
          }
        );

      onReopened(
        payload.ticket.id,
        payload.reusedExisting
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível reabrir o atendimento."
      );
    } finally {
      setReopening(false);
    }
  }

  return (
    <aside className="closed-tickets-drawer">
      <header className="closed-tickets-drawer__header">
        <div>
          <span className="eyebrow">
            Histórico
          </span>
          <strong>
            Atendimentos encerrados
          </strong>
          <small>
            Consulte o histórico e reabra somente quando necessário.
          </small>
        </div>

        <button
          aria-label="Fechar atendimentos encerrados"
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      {error && (
        <div className="closed-tickets-drawer__error">
          {error}
        </div>
      )}

      <div className="closed-tickets-layout">
        <section className="closed-tickets-list">
          <div className="closed-tickets-list__search">
            <input
              onChange={event =>
                setSearch(
                  event.target.value
                )
              }
              placeholder="Buscar encerrado…"
              value={search}
            />
            <span>
              {visibleTickets.length}
            </span>
          </div>

          <div className="closed-tickets-list__items">
            {loadingTickets ? (
              <div className="closed-tickets-empty">
                Carregando…
              </div>
            ) : visibleTickets.length === 0 ? (
              <div className="closed-tickets-empty">
                Nenhum atendimento encerrado.
              </div>
            ) : (
              visibleTickets.map(
                ticket => (
                  <button
                    className={
                      ticket.id ===
                      selectedId
                        ? "closed-ticket-row closed-ticket-row--active"
                        : "closed-ticket-row"
                    }
                    key={ticket.id}
                    onClick={() =>
                      setSelectedId(
                        ticket.id
                      )
                    }
                    type="button"
                  >
                    <div className="closed-ticket-row__top">
                      <strong>
                        {
                          ticket
                            .contact
                            .name
                        }
                      </strong>
                      <time>
                        {dateTimeLabel(
                          ticket.closedAt
                        )}
                      </time>
                    </div>

                    <p>
                      {ticket.lastMessage ??
                        "Sem mensagem"}
                    </p>

                    <div className="closed-ticket-row__meta">
                      <span>
                        {
                          ticket.queue
                            ?.name ??
                          "Sem fila"
                        }
                      </span>

                      <span>
                        {
                          ticket
                            .assignedMembership
                            ?.user
                            .name ??
                          "Sem atendente"
                        }
                      </span>
                    </div>
                  </button>
                )
              )
            )}
          </div>
        </section>

        <section className="closed-ticket-history">
          {!selectedTicket ? (
            <div className="closed-tickets-empty">
              Selecione um atendimento.
            </div>
          ) : (
            <>
              <header className="closed-ticket-history__header">
                <div>
                  <strong>
                    {
                      selectedTicket
                        .contact
                        .name
                    }
                  </strong>
                  <span>
                    {
                      selectedTicket
                        .contact
                        .phoneNumber ??
                      (
                        selectedTicket
                          .contact
                          .isGroup
                          ? "Grupo"
                          : "Sem telefone"
                      )
                    }
                  </span>
                  <small>
                    Encerrado em{" "}
                    {dateTimeLabel(
                      selectedTicket.closedAt
                    )}
                  </small>
                </div>

                <button
                  disabled={reopening}
                  onClick={() =>
                    void reopen()
                  }
                  type="button"
                >
                  {reopening
                    ? "Reabrindo…"
                    : "Reabrir atendimento"}
                </button>
              </header>

              <div className="closed-ticket-history__messages">
                {loadingMessages ? (
                  <div className="closed-tickets-empty">
                    Carregando histórico…
                  </div>
                ) : messages.length === 0 ? (
                  <div className="closed-tickets-empty">
                    Nenhuma mensagem neste atendimento.
                  </div>
                ) : (
                  messages.map(
                    message => (
                      <article
                        className={
                          message.direction ===
                          "OUTBOUND"
                            ? "archived-message archived-message--outbound"
                            : "archived-message"
                        }
                        key={message.id}
                      >
                        <MessageMedia
                          fileName={
                            message.mediaFileName
                          }
                          messageId={
                            message.id
                          }
                          mimeType={
                            message.mediaMimeType
                          }
                          status={
                            message.mediaStatus
                          }
                          type={
                            message.type
                          }
                        />

                        {(message.body ??
                          messageFallback(
                            message.type
                          )) && (
                          <p>
                            {message.body ??
                              messageFallback(
                                message.type
                              )}
                          </p>
                        )}

                        <time>
                          {dateTimeLabel(
                            message.timestamp
                          )}
                        </time>
                      </article>
                    )
                  )
                )}
              </div>

              <footer className="closed-ticket-history__footer">
                Histórico em modo leitura.
              </footer>
            </>
          )}
        </section>
      </div>
    </aside>
  );
}
EOF

# ---------------------------------------------------------------------------
# Conversations integration
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { ClosedTicketsDrawer } from "@/components/conversations/closed-tickets-drawer";';

if (!content.includes(importLine)) {
  const candidates = [
    'import { ConversationSearch } from "@/components/conversations/conversation-search";',
    'import { MessageMedia } from "@/components/messages/message-media";',
    'import { useAuth } from "@/components/auth-provider";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find Conversations import anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (
  !content.includes(
    "const [closedTicketsOpen"
  )
) {
  const candidates = [
    `  const [conversationSearchOpen, setConversationSearchOpen] =
    useState(false);`,
    `  const [tagPickerOpen, setTagPickerOpen] =
    useState(false);`,
    `  const [notesOpen, setNotesOpen] = useState(false);`
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find Conversations overlay-state anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [closedTicketsOpen, setClosedTicketsOpen] =
    useState(false);
  const [operationNotice, setOperationNotice] =
    useState("");`
  );
}

/*
 * Add Encerrados button before the assignment summary.
 */
if (
  !content.includes(
    'className="closed-tickets-toggle"'
  )
) {
  const searchIndex =
    content.indexOf(
      'className="conversation-search-toggle'
    );

  const tagsIndex =
    content.indexOf(
      'className="ticket-tags-toggle"'
    );

  const fromIndex =
    searchIndex >= 0
      ? searchIndex
      : tagsIndex;

  if (fromIndex < 0) {
    throw new Error(
      "Could not find toolbar insertion anchor."
    );
  }

  const smallIndex =
    content.indexOf(
      "\n\n                <small>",
      fromIndex
    );

  if (smallIndex < 0) {
    throw new Error(
      "Could not find assignment summary after toolbar."
    );
  }

  const button = `

                <button
                  className={
                    closedTicketsOpen
                      ? "closed-tickets-toggle closed-tickets-toggle--active"
                      : "closed-tickets-toggle"
                  }
                  onClick={() => {
                    setClosedTicketsOpen(
                      current => !current
                    );
                    setConversationSearchOpen(false);
                    setTagPickerOpen(false);
                    setTagManagerOpen(false);
                    setNotesOpen(false);
                    setQuickReplyManagerOpen(false);
                    setOperationNotice("");
                  }}
                  type="button"
                >
                  Encerrados
                </button>`;

  content =
    content.slice(0, smallIndex) +
    button +
    content.slice(smallIndex);
}

/*
 * Render drawer first inside conversation-body.
 */
if (
  !content.includes(
    "<ClosedTicketsDrawer"
  )
) {
  const anchor =
    `              <div className="conversation-body">`;

  if (!content.includes(anchor)) {
    throw new Error(
      "conversation-body anchor not found."
    );
  }

  const drawer = `${anchor}
                {closedTicketsOpen && (
                  <ClosedTicketsDrawer
                    onClose={() =>
                      setClosedTicketsOpen(false)
                    }
                    onReopened={(
                      ticketId,
                      reusedExisting
                    ) => {
                      setClosedTicketsOpen(false);
                      setOperationNotice(
                        reusedExisting
                          ? "Já havia um atendimento ativo para este contato. Abrimos o atendimento existente."
                          : "Atendimento reaberto e atribuído a você."
                      );

                      void loadTickets()
                        .then(() => {
                          setSelectedId(ticketId);
                        });
                    }}
                  />
                )}`;

  content = content.replace(
    anchor,
    drawer
  );
}

/*
 * Lightweight operation notice below the page-level error area.
 */
if (
  !content.includes(
    'className="inbox-notice"'
  )
) {
  const errorCandidates = [
    `{error && <div className="inbox-error">{error}</div>}`,
    `{error && (
        <div className="inbox-error">{error}</div>
      )}`
  ];

  const anchor =
    errorCandidates.find(candidate =>
      content.includes(candidate)
    );

  if (anchor) {
    content = content.replace(
      anchor,
      `${anchor}

      {operationNotice && (
        <div className="inbox-notice">
          <span>{operationNotice}</span>
          <button
            aria-label="Fechar aviso"
            onClick={() =>
              setOperationNotice("")
            }
            type="button"
          >
            ×
          </button>
        </div>
      )}`
    );
  }
}

fs.writeFileSync(path, content);
console.log("Closed ticket drawer integrated into Conversations.");
NODE

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.10 / Closed tickets" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.10 / Closed tickets -------------------------------------- */

.closed-tickets-toggle {
  display: inline-flex;
  min-height: 40px;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--line);
  border-radius: 11px;
  background: #fff;
  color: var(--ink);
  padding: 0 12px;
  font-size: 10px;
  font-weight: 750;
}

.closed-tickets-toggle:hover,
.closed-tickets-toggle--active {
  border-color: #c6cec9;
  background: #f0f3f1;
}

.inbox-notice {
  display: flex;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  border: 1px solid #cfe3d6;
  border-radius: 10px;
  background: #eef8f1;
  color: #2d6844;
  padding: 9px 12px;
  font-size: 9px;
}

.inbox-notice > button {
  border: 0;
  background: transparent;
  color: inherit;
  font-size: 17px;
}

.closed-tickets-drawer {
  position: absolute;
  z-index: 40;
  inset: 0;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-rows:
    auto
    auto
    minmax(0, 1fr);
  overflow: hidden;
  background: #fbfcfa;
}

.closed-tickets-drawer__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  border-bottom: 1px solid var(--line);
  background: #fbfcfa;
  padding: 15px 17px;
}

.closed-tickets-drawer__header > div {
  display: grid;
  gap: 4px;
}

.closed-tickets-drawer__header strong {
  font-size: 15px;
}

.closed-tickets-drawer__header small {
  color: var(--muted);
  font-size: 9px;
}

.closed-tickets-drawer__header > button {
  display: grid;
  width: 30px;
  height: 30px;
  place-items: center;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--muted);
  font-size: 21px;
}

.closed-tickets-drawer__error {
  border-bottom: 1px solid #efd2cf;
  background: var(--danger-soft);
  color: var(--danger);
  padding: 8px 12px;
  font-size: 9px;
}

.closed-tickets-layout {
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-columns:
    minmax(250px, 32%)
    minmax(0, 1fr);
  overflow: hidden;
}

.closed-tickets-list {
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-rows:
    auto
    minmax(0, 1fr);
  border-right: 1px solid var(--line);
  background: #fff;
}

.closed-tickets-list__search {
  display: grid;
  grid-template-columns:
    minmax(0, 1fr)
    auto;
  align-items: center;
  gap: 7px;
  border-bottom: 1px solid var(--line);
  padding: 9px;
}

.closed-tickets-list__search input {
  width: 100%;
  height: 36px;
  border: 1px solid var(--line);
  border-radius: 9px;
  outline: none;
  background: var(--surface-subtle);
  padding: 0 9px;
  font-size: 9px;
}

.closed-tickets-list__search input:focus {
  border-color: var(--accent);
  background: #fff;
}

.closed-tickets-list__search > span {
  display: grid;
  min-width: 26px;
  height: 26px;
  place-items: center;
  border-radius: 999px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 0 6px;
  font-size: 8px;
}

.closed-tickets-list__items {
  min-height: 0;
  overflow-y: auto;
  scrollbar-gutter: stable;
}

.closed-ticket-row {
  display: grid;
  width: 100%;
  gap: 6px;
  border: 0;
  border-bottom: 1px solid var(--line);
  background: #fff;
  padding: 11px 12px;
  text-align: left;
}

.closed-ticket-row:hover,
.closed-ticket-row--active {
  background: #f0f4f1;
}

.closed-ticket-row__top {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.closed-ticket-row__top strong {
  overflow: hidden;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.closed-ticket-row__top time {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 7px;
}

.closed-ticket-row > p {
  overflow: hidden;
  margin: 0;
  color: var(--muted);
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.closed-ticket-row__meta {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.closed-ticket-row__meta > span {
  border-radius: 999px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 3px 5px;
  font-size: 7px;
}

.closed-ticket-history {
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-rows:
    auto
    minmax(0, 1fr)
    auto;
  overflow: hidden;
  background:
    linear-gradient(
      rgba(247, 248, 245, 0.91),
      rgba(247, 248, 245, 0.91)
    ),
    radial-gradient(
      circle at 30% 40%,
      #dce3dd 1px,
      transparent 1px
    );
  background-size:
    auto,
    20px 20px;
}

.closed-ticket-history__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  border-bottom: 1px solid var(--line);
  background: #fff;
  padding: 11px 14px;
}

.closed-ticket-history__header > div {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.closed-ticket-history__header strong {
  font-size: 11px;
}

.closed-ticket-history__header span,
.closed-ticket-history__header small {
  color: var(--muted);
  font-size: 8px;
}

.closed-ticket-history__header > button {
  min-height: 38px;
  border: 1px solid var(--line);
  border-radius: 10px;
  background: var(--sidebar);
  color: #fff;
  padding: 0 11px;
  font-size: 9px;
  font-weight: 750;
}

.closed-ticket-history__header > button:disabled {
  opacity: 0.45;
}

.closed-ticket-history__messages {
  display: flex;
  min-height: 0;
  flex-direction: column;
  gap: 8px;
  overflow-y: auto;
  padding:
    18px
    clamp(14px, 4vw, 52px);
  scrollbar-gutter: stable;
}

.archived-message {
  display: grid;
  width: fit-content;
  max-width: min(560px, 78%);
  gap: 6px;
  align-self: flex-start;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: #fff;
  padding: 9px 10px;
}

.archived-message--outbound {
  align-self: flex-end;
  border-color: #d1e4d8;
  background: #e8f4ec;
}

.archived-message > p {
  margin: 0;
  font-size: 10px;
  line-height: 1.5;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.archived-message > time {
  justify-self: end;
  color: var(--muted);
  font-size: 7px;
}

.closed-ticket-history__footer {
  border-top: 1px solid var(--line);
  background: #fff;
  color: var(--muted);
  padding: 9px 12px;
  text-align: center;
  font-size: 8px;
}

.closed-tickets-empty {
  display: grid;
  min-height: 150px;
  place-items: center;
  color: var(--muted);
  padding: 22px;
  text-align: center;
  font-size: 9px;
}

@media (max-width: 760px) {
  .closed-tickets-layout {
    grid-template-columns:
      minmax(180px, 40%)
      minmax(0, 1fr);
  }

  .closed-ticket-history__header {
    align-items: flex-start;
    flex-direction: column;
  }

  .archived-message {
    max-width: 90%;
  }
}

@media (max-width: 560px) {
  .closed-tickets-layout {
    grid-template-columns: 1fr;
  }

  .closed-tickets-list {
    display: none;
  }

  .closed-tickets-toggle {
    min-height: 36px;
    padding: 0 9px;
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/CLOSED_TICKETS.md <<'EOF'
# Closed tickets and safe reopen

P1.10 adds a read-only archive workflow for closed tickets.

## Operator workflow

The Conversations screen exposes an `Encerrados` control.

The archive drawer contains:

- closed ticket list;
- contact/queue/assignee context;
- read-only message history;
- media rendering through the existing protected media endpoint;
- safe reopen.

The normal conversation composer is never shown inside the archive.

## Safe reopen

`POST /api/v1/tickets/:id/reopen`

Reopening follows the existing ticket assignment rule.

When a closed ticket is reopened successfully:

- `activeKey` is restored;
- status becomes `OPEN`;
- it is assigned to the operator who reopened it;
- `closedAt` becomes null;
- unread count resets to zero.

## Duplicate protection

Before reopening, Wapp checks whether the same company + WhatsApp connection +
contact already has an OPEN/PENDING ticket.

If one exists, Wapp returns that existing active ticket instead of reopening
the old one.

The unique `activeKey` remains the final concurrency guard. If an inbound
message races with the reopen operation and creates an active ticket between
the pre-check and update, Wapp resolves the newly active ticket and opens it.

This preserves the invariant of one active ticket per connection/contact.

## Data preservation

Reopening does not erase:

- messages;
- internal notes;
- tags;
- queue history stored on the ticket;
- media;
- message delivery status.

No Prisma migration is required for P1.10.
EOF

echo "[P1.10] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.10] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.10] Closed ticket history and safe reopen installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Test:"
echo "  1. close a test ticket"
echo "  2. open Encerrados"
echo "  3. read its history/media"
echo "  4. click Reabrir atendimento"
echo "  5. confirm it returns to active conversations"
echo "  6. close it again, send a fresh inbound message, then try reopening the old ticket"
echo "     Wapp must open the already-active ticket instead of creating a duplicate"
