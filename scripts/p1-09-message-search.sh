#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.9] Building conversation history search..."

for required in \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/auth/auth.guard.ts" \
  "apps/web/components/auth-provider.tsx" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -Fq 'className="conversation-body"' \
  apps/web/app/dashboard/conversations/page.tsx; then
  echo "ERROR: canonical conversation-body not found."
  exit 1
fi

if ! grep -Fq 'className="ticket-tags-toggle"' \
  apps/web/app/dashboard/conversations/page.tsx; then
  echo "ERROR: P1.8 tag controls not found."
  exit 1
fi

mkdir -p \
  apps/api/src/modules/messages \
  apps/web/components/conversations \
  docs

# ---------------------------------------------------------------------------
# API search service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/messages/message-search.service.ts <<'EOF'
import type { Prisma } from "../../generated/prisma/client.js";

import { prisma } from "../../lib/database.js";

export async function searchMessageHistory(input: {
  companyId: string;
  query: string;
  ticketId?: string;
  page: number;
  limit: number;
}) {
  const query = input.query.trim();

  const where: Prisma.MessageWhereInput = {
    companyId: input.companyId,
    ...(input.ticketId
      ? {
          ticketId: input.ticketId
        }
      : {}),
    OR: [
      {
        body: {
          contains: query
        }
      },
      {
        mediaFileName: {
          contains: query
        }
      },
      {
        ticket: {
          contact: {
            name: {
              contains: query
            }
          }
        }
      },
      {
        ticket: {
          contact: {
            phoneNumber: {
              contains: query
            }
          }
        }
      }
    ]
  };

  const [total, messages] =
    await prisma.$transaction([
      prisma.message.count({
        where
      }),
      prisma.message.findMany({
        where,
        select: {
          id: true,
          ticketId: true,
          direction: true,
          type: true,
          body: true,
          mediaFileName: true,
          mediaMimeType: true,
          timestamp: true,
          ticket: {
            select: {
              id: true,
              status: true,
              lastMessageAt: true,
              contact: {
                select: {
                  id: true,
                  name: true,
                  phoneNumber: true,
                  isGroup: true
                }
              },
              queue: {
                select: {
                  id: true,
                  name: true
                }
              },
              assignedMembership: {
                select: {
                  id: true,
                  user: {
                    select: {
                      id: true,
                      name: true
                    }
                  }
                }
              }
            }
          }
        },
        orderBy: [
          {
            timestamp: "desc"
          },
          {
            createdAt: "desc"
          }
        ],
        skip:
          (input.page - 1) *
          input.limit,
        take:
          input.limit
      })
    ]);

  return {
    messages,
    pagination: {
      page:
        input.page,
      limit:
        input.limit,
      total,
      pages:
        Math.max(
          1,
          Math.ceil(
            total / input.limit
          )
        )
    }
  };
}
EOF

# ---------------------------------------------------------------------------
# API search route
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/messages/message-search.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../auth/auth.guard.js";
import { searchMessageHistory } from "./message-search.service.js";

const searchSchema = z.object({
  q: z
    .string()
    .trim()
    .min(2)
    .max(160),
  ticketId: z
    .string()
    .uuid()
    .optional(),
  page: z.coerce
    .number()
    .int()
    .positive()
    .default(1),
  limit: z.coerce
    .number()
    .int()
    .min(10)
    .max(50)
    .default(30)
});

export async function messageSearchRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/messages/search",
    async request => {
      const auth =
        await requireAuth(request);

      const query =
        searchSchema.parse(
          request.query
        );

      return searchMessageHistory({
        companyId:
          auth.companyId,
        query:
          query.q,
        ticketId:
          query.ticketId,
        page:
          query.page,
        limit:
          query.limit
      });
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register route
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { messageSearchRoutes } from "./modules/messages/message-search.routes.js";';

if (!content.includes(importLine)) {
  const candidates = [
    'import { mediaRoutes } from "./modules/media/media.routes.js";',
    'import { ticketRoutes } from "./modules/tickets/ticket.routes.js";',
    'import { contactRoutes } from "./modules/contacts/contact.routes.js";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find API route import anchor."
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
    "await app.register(messageSearchRoutes);"
  )
) {
  const candidates = [
    "  await app.register(mediaRoutes);",
    "  await app.register(ticketRoutes);",
    "  await app.register(contactRoutes);"
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find API route registration anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  await app.register(messageSearchRoutes);`
  );
}

fs.writeFileSync(path, content);
console.log("Message history search route registered.");
NODE

# ---------------------------------------------------------------------------
# Search UI component
# ---------------------------------------------------------------------------

cat > apps/web/components/conversations/conversation-search.tsx <<'EOF'
"use client";

import {
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";

type SearchScope =
  | "ALL"
  | "CURRENT";

interface SearchMessage {
  id: string;
  ticketId: string;
  direction:
    | "INBOUND"
    | "OUTBOUND";
  type: string;
  body: string | null;
  mediaFileName: string | null;
  mediaMimeType: string | null;
  timestamp: string;
  ticket: {
    id: string;
    status:
      | "OPEN"
      | "PENDING"
      | "CLOSED";
    lastMessageAt: string;
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
      };
    } | null;
  };
}

interface SearchResponse {
  messages: SearchMessage[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

function dateTimeLabel(
  value: string
) {
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

function messageLabel(
  message: SearchMessage
) {
  if (message.body?.trim()) {
    return message.body.trim();
  }

  if (
    message.mediaFileName?.trim()
  ) {
    return message.mediaFileName;
  }

  switch (
    message.type.toUpperCase()
  ) {
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
    default:
      return `[${message.type}]`;
  }
}

function snippet(
  value: string,
  query: string
) {
  const clean =
    value.replace(
      /\s+/g,
      " "
    );

  const lower =
    clean.toLowerCase();

  const needle =
    query
      .trim()
      .toLowerCase();

  const found =
    lower.indexOf(needle);

  if (
    found < 0 ||
    clean.length <= 150
  ) {
    return clean.slice(
      0,
      150
    );
  }

  const start =
    Math.max(
      0,
      found - 55
    );

  const end =
    Math.min(
      clean.length,
      found +
        needle.length +
        80
    );

  return `${
    start > 0
      ? "…"
      : ""
  }${clean.slice(start, end)}${
    end < clean.length
      ? "…"
      : ""
  }`;
}

export function ConversationSearch({
  selectedTicketId,
  onClose,
  onOpenTicket
}: {
  selectedTicketId: string | null;
  onClose: () => void;
  onOpenTicket: (
    ticketId: string
  ) => void;
}) {
  const { request } =
    useAuth();

  const [query, setQuery] =
    useState("");
  const [scope, setScope] =
    useState<SearchScope>(
      selectedTicketId
        ? "CURRENT"
        : "ALL"
    );
  const [page, setPage] =
    useState(1);
  const [results, setResults] =
    useState<SearchMessage[]>([]);
  const [pagination, setPagination] =
    useState<SearchResponse["pagination"]>({
      page: 1,
      limit: 30,
      total: 0,
      pages: 1
    });
  const [loading, setLoading] =
    useState(false);
  const [error, setError] =
    useState("");

  const canSearchCurrent =
    Boolean(selectedTicketId);

  const trimmedQuery =
    query.trim();

  const ready =
    trimmedQuery.length >= 2;

  useEffect(() => {
    if (
      scope === "CURRENT" &&
      !selectedTicketId
    ) {
      setScope("ALL");
    }
  }, [
    scope,
    selectedTicketId
  ]);

  useEffect(() => {
    setPage(1);
  }, [
    query,
    scope,
    selectedTicketId
  ]);

  useEffect(() => {
    if (!ready) {
      setResults([]);
      setPagination({
        page: 1,
        limit: 30,
        total: 0,
        pages: 1
      });
      setError("");
      return;
    }

    let cancelled = false;

    const timer =
      window.setTimeout(
        () => {
          void (async () => {
            setLoading(true);
            setError("");

            try {
              const params =
                new URLSearchParams({
                  q:
                    trimmedQuery,
                  page:
                    String(page),
                  limit:
                    "30"
                });

              if (
                scope ===
                  "CURRENT" &&
                selectedTicketId
              ) {
                params.set(
                  "ticketId",
                  selectedTicketId
                );
              }

              const payload =
                await request<SearchResponse>(
                  `/api/v1/messages/search?${params.toString()}`
                );

              if (cancelled) {
                return;
              }

              setResults(
                payload.messages
              );

              setPagination(
                payload.pagination
              );
            } catch {
              if (!cancelled) {
                setError(
                  "Não foi possível pesquisar o histórico."
                );
              }
            } finally {
              if (!cancelled) {
                setLoading(false);
              }
            }
          })();
        },
        280
      );

    return () => {
      cancelled = true;
      window.clearTimeout(
        timer
      );
    };
  }, [
    page,
    ready,
    request,
    scope,
    selectedTicketId,
    trimmedQuery
  ]);

  const resultLabel =
    useMemo(() => {
      if (!ready) {
        return "Digite pelo menos 2 caracteres.";
      }

      if (loading) {
        return "Pesquisando…";
      }

      if (
        pagination.total === 0
      ) {
        return "Nenhum resultado.";
      }

      return `${pagination.total} resultado${
        pagination.total === 1
          ? ""
          : "s"
      }`;
    }, [
      loading,
      pagination.total,
      ready
    ]);

  return (
    <aside className="conversation-search">
      <header className="conversation-search__header">
        <div>
          <span className="eyebrow">
            Histórico
          </span>
          <strong>
            Buscar mensagens
          </strong>
          <small>
            Pesquisa no banco, não apenas no que está carregado na tela.
          </small>
        </div>

        <button
          aria-label="Fechar busca"
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      <div className="conversation-search__controls">
        <input
          autoFocus
          maxLength={160}
          onChange={event =>
            setQuery(
              event.target.value
            )
          }
          placeholder="Mensagem, arquivo, contato ou telefone…"
          value={query}
        />

        <div className="conversation-search__scope">
          <button
            className={
              scope === "ALL"
                ? "conversation-search__scope-button conversation-search__scope-button--active"
                : "conversation-search__scope-button"
            }
            onClick={() =>
              setScope("ALL")
            }
            type="button"
          >
            Todas
          </button>

          <button
            className={
              scope === "CURRENT"
                ? "conversation-search__scope-button conversation-search__scope-button--active"
                : "conversation-search__scope-button"
            }
            disabled={
              !canSearchCurrent
            }
            onClick={() =>
              setScope(
                "CURRENT"
              )
            }
            type="button"
          >
            Este atendimento
          </button>
        </div>

        <span className="conversation-search__count">
          {resultLabel}
        </span>
      </div>

      <div className="conversation-search__results">
        {error && (
          <div className="conversation-search__empty conversation-search__empty--error">
            {error}
          </div>
        )}

        {!error &&
          ready &&
          !loading &&
          results.length === 0 && (
            <div className="conversation-search__empty">
              Nenhuma mensagem encontrada com esse termo.
            </div>
          )}

        {!error &&
          results.map(
            message => {
              const active =
                message.ticket.status !==
                "CLOSED";

              return (
                <article
                  className="conversation-search-result"
                  key={
                    message.id
                  }
                >
                  <div className="conversation-search-result__top">
                    <div>
                      <strong>
                        {
                          message
                            .ticket
                            .contact
                            .name
                        }
                      </strong>
                      <span>
                        {
                          message
                            .ticket
                            .contact
                            .phoneNumber ??
                          (
                            message
                              .ticket
                              .contact
                              .isGroup
                              ? "Grupo"
                              : "Sem telefone"
                          )
                        }
                      </span>
                    </div>

                    <time>
                      {dateTimeLabel(
                        message.timestamp
                      )}
                    </time>
                  </div>

                  <p>
                    {snippet(
                      messageLabel(
                        message
                      ),
                      trimmedQuery
                    )}
                  </p>

                  <div className="conversation-search-result__meta">
                    <span>
                      {message.direction ===
                      "INBOUND"
                        ? "Cliente"
                        : "Equipe"}
                    </span>

                    <span>
                      {
                        message
                          .ticket
                          .queue
                          ?.name ??
                        "Sem fila"
                      }
                    </span>

                    <span
                      className={
                        active
                          ? "conversation-search-result__status"
                          : "conversation-search-result__status conversation-search-result__status--closed"
                      }
                    >
                      {
                        message
                          .ticket
                          .status
                      }
                    </span>

                    {active ? (
                      <button
                        onClick={() =>
                          onOpenTicket(
                            message.ticketId
                          )
                        }
                        type="button"
                      >
                        Abrir atendimento
                      </button>
                    ) : (
                      <span>
                        Atendimento encerrado
                      </span>
                    )}
                  </div>
                </article>
              );
            }
          )}
      </div>

      {ready &&
        pagination.pages > 1 && (
          <footer className="conversation-search__pagination">
            <button
              disabled={
                page <= 1 ||
                loading
              }
              onClick={() =>
                setPage(
                  current =>
                    Math.max(
                      1,
                      current - 1
                    )
                )
              }
              type="button"
            >
              Anterior
            </button>

            <span>
              {pagination.page}
              {" / "}
              {pagination.pages}
            </span>

            <button
              disabled={
                page >=
                  pagination.pages ||
                loading
              }
              onClick={() =>
                setPage(
                  current =>
                    Math.min(
                      pagination.pages,
                      current + 1
                    )
                )
              }
              type="button"
            >
              Próxima
            </button>
          </footer>
        )}
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
  'import { ConversationSearch } from "@/components/conversations/conversation-search";';

if (!content.includes(importLine)) {
  const candidates = [
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
    "const [conversationSearchOpen"
  )
) {
  const candidates = [
    `  const [tagPickerOpen, setTagPickerOpen] =
    useState(false);`,
    `  const [notesOpen, setNotesOpen] = useState(false);`,
    `  const [quickRepliesOpen, setQuickRepliesOpen] =
    useState(false);`
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find Conversations drawer-state anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [conversationSearchOpen, setConversationSearchOpen] =
    useState(false);`
  );
}

/*
 * Insert search toggle immediately before the "Atual:" assignment summary,
 * after the P1.8 tag button.
 */
if (
  !content.includes(
    'className="conversation-search-toggle"'
  )
) {
  const tagIndex =
    content.indexOf(
      'className="ticket-tags-toggle"'
    );

  if (tagIndex < 0) {
    throw new Error(
      "ticket-tags-toggle not found."
    );
  }

  const smallIndex =
    content.indexOf(
      "\n\n                <small>",
      tagIndex
    );

  if (smallIndex < 0) {
    throw new Error(
      "Could not find assignment summary after tag button."
    );
  }

  const button = `

                <button
                  className={
                    conversationSearchOpen
                      ? "conversation-search-toggle conversation-search-toggle--active"
                      : "conversation-search-toggle"
                  }
                  onClick={() => {
                    setConversationSearchOpen(
                      current => !current
                    );
                    setTagPickerOpen(false);
                    setTagManagerOpen(false);
                    setNotesOpen(false);
                    setQuickReplyManagerOpen(false);
                  }}
                  type="button"
                >
                  Buscar
                </button>`;

  content =
    content.slice(
      0,
      smallIndex
    ) +
    button +
    content.slice(
      smallIndex
    );
}

/*
 * Render search drawer as the first overlay inside conversation-body.
 * It does not participate in the message/composer grid.
 */
if (
  !content.includes(
    "<ConversationSearch"
  )
) {
  const anchor =
    `              <div className="conversation-body">`;

  if (!content.includes(anchor)) {
    throw new Error(
      "conversation-body anchor not found."
    );
  }

  const search = `${anchor}
                {conversationSearchOpen && (
                  <ConversationSearch
                    onClose={() =>
                      setConversationSearchOpen(false)
                    }
                    onOpenTicket={ticketId => {
                      setSelectedId(ticketId);
                      setConversationSearchOpen(false);
                    }}
                    selectedTicketId={selectedId}
                  />
                )}`;

  content = content.replace(
    anchor,
    search
  );
}

fs.writeFileSync(path, content);
console.log("Conversation search UI integrated.");
NODE

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.9 / Conversation history search" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.9 / Conversation history search -------------------------- */

.conversation-search-toggle {
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

.conversation-search-toggle:hover,
.conversation-search-toggle--active {
  border-color: #b9cec0;
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.conversation-search {
  position: absolute;
  z-index: 36;
  top: 0;
  right: 0;
  bottom: 0;
  display: grid;
  width: min(520px, 96%);
  min-height: 0;
  grid-template-rows:
    auto
    auto
    minmax(0, 1fr)
    auto;
  overflow: hidden;
  border-left: 1px solid var(--line);
  background: #fbfcfa;
  box-shadow:
    -20px 0 44px
    rgba(24, 33, 27, 0.11);
}

.conversation-search__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  border-bottom: 1px solid var(--line);
  background: #fbfcfa;
  padding: 17px;
}

.conversation-search__header > div {
  display: grid;
  gap: 4px;
}

.conversation-search__header strong {
  font-size: 15px;
}

.conversation-search__header small {
  max-width: 350px;
  color: var(--muted);
  font-size: 9px;
  line-height: 1.45;
}

.conversation-search__header > button {
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

.conversation-search__header > button:hover {
  background: #e8ece9;
  color: var(--ink);
}

.conversation-search__controls {
  display: grid;
  gap: 8px;
  border-bottom: 1px solid var(--line);
  background: #fff;
  padding: 11px;
}

.conversation-search__controls > input {
  width: 100%;
  height: 42px;
  border: 1px solid var(--line);
  border-radius: 11px;
  outline: none;
  background: var(--surface-subtle);
  padding: 0 11px;
  font-size: 10px;
}

.conversation-search__controls > input:focus {
  border-color: var(--accent);
  background: #fff;
}

.conversation-search__scope {
  display: flex;
  gap: 5px;
}

.conversation-search__scope-button {
  min-height: 30px;
  border: 0;
  border-radius: 8px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 0 9px;
  font-size: 8px;
  font-weight: 750;
}

.conversation-search__scope-button--active {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.conversation-search__scope-button:disabled {
  opacity: 0.4;
}

.conversation-search__count {
  color: var(--muted);
  font-size: 8px;
}

.conversation-search__results {
  min-height: 0;
  overflow-y: auto;
  padding: 8px;
  scrollbar-gutter: stable;
}

.conversation-search__empty {
  display: grid;
  min-height: 180px;
  place-items: center;
  color: var(--muted);
  padding: 24px;
  text-align: center;
  font-size: 10px;
  line-height: 1.5;
}

.conversation-search__empty--error {
  color: var(--danger);
}

.conversation-search-result {
  display: grid;
  gap: 8px;
  margin-bottom: 7px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: #fff;
  padding: 11px;
}

.conversation-search-result__top {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.conversation-search-result__top > div {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.conversation-search-result__top strong,
.conversation-search-result__top span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.conversation-search-result__top strong {
  font-size: 10px;
}

.conversation-search-result__top span,
.conversation-search-result__top time {
  color: var(--muted);
  font-size: 8px;
}

.conversation-search-result > p {
  margin: 0;
  color: #3f4742;
  font-size: 10px;
  line-height: 1.55;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.conversation-search-result__meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 5px;
}

.conversation-search-result__meta > span {
  border-radius: 999px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 4px 6px;
  font-size: 7px;
}

.conversation-search-result__status {
  color: var(--accent-dark) !important;
}

.conversation-search-result__status--closed {
  color: var(--muted) !important;
}

.conversation-search-result__meta > button {
  margin-left: auto;
  border: 0;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 6px 8px;
  font-size: 8px;
  font-weight: 800;
}

.conversation-search__pagination {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  border-top: 1px solid var(--line);
  background: #fff;
  padding: 9px 11px;
}

.conversation-search__pagination button {
  border: 1px solid var(--line);
  border-radius: 8px;
  background: #fff;
  color: var(--muted);
  padding: 6px 8px;
  font-size: 8px;
}

.conversation-search__pagination button:disabled {
  opacity: 0.4;
}

.conversation-search__pagination span {
  color: var(--muted);
  font-size: 8px;
}

@media (max-width: 680px) {
  .conversation-search {
    width: 100%;
    border-left: 0;
  }

  .conversation-search-toggle {
    min-height: 36px;
    padding: 0 9px;
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/MESSAGE_SEARCH.md <<'EOF'
# Message history search

P1.9 adds server-side historical search for Wapp conversations.

## Scope

Operators can search:

- all company message history;
- only the currently selected ticket.

The search checks:

- message body;
- media file name;
- contact name;
- contact phone number.

The query runs against MySQL, not only against the 200 messages currently
loaded in the Conversations UI.

## Endpoint

`GET /api/v1/messages/search`

Parameters:

- `q`: required, 2-160 characters;
- `ticketId`: optional;
- `page`: default 1;
- `limit`: 10-50, default 30.

Results are company-scoped by authenticated session.

## Closed tickets

Historical results can include closed tickets.

P1.9 displays those results but does not reopen them from search. Active
tickets can be opened directly from the result.

A future archived-ticket workflow can add navigation for closed tickets
without coupling search to ticket reopening.

## Performance

P1.9 intentionally uses Prisma `contains` / SQL LIKE for correctness and
simplicity at the current scale.

Existing indexes on company, ticket and timestamp continue to help scope the
queries, but body matching itself is not full-text indexed.

When message volume becomes large, this service is the boundary where MySQL
FULLTEXT or a dedicated search engine can be introduced without changing the
UI contract.
EOF

echo "[P1.9] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.9] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.9] Conversation history search installed."
echo "No Prisma migration is required."
echo
echo "Restart if needed:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Test:"
echo "  1. search a phrase older than the visible conversation"
echo "  2. switch between All and Current ticket"
echo "  3. search a contact name or phone"
echo "  4. open an active result"
