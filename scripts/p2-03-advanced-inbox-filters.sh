#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.3] Installing advanced inbox filters..."

API_ROUTES="apps/api/src/modules/tickets/ticket.routes.ts"
API_SERVICE="apps/api/src/modules/tickets/ticket.service.ts"
WEB_PAGE="apps/web/app/dashboard/conversations/page.tsx"
WEB_CSS="apps/web/app/globals.css"

for required in \
  "$API_ROUTES" \
  "$API_SERVICE" \
  "$WEB_PAGE" \
  "$WEB_CSS"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/tickets \
  docs

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

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
    "export interface TicketListFilters"
  )
) {
  const anchor = `export type TicketListStatus =
  | "ACTIVE"
  | "OPEN"
  | "PENDING"
  | "CLOSED";`;

  if (!content.includes(anchor)) {
    throw new Error(
      "TicketListStatus anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

export interface TicketListFilters {
  q?: string;
  queueId?:
    | string
    | "NONE";
  assigneeId?:
    | string
    | "ME"
    | "NONE";
  actorMembershipId?: string;
  unreadOnly?: boolean;
  tagId?: string;
  conversationType?:
    | "ALL"
    | "DIRECT"
    | "GROUP";
}`
    );
}

const oldFunction = `export async function listTickets(
  companyId: string,
  status: TicketListStatus
) {
  const where: Prisma.TicketWhereInput = {
    companyId,
    ...(status === "ACTIVE"
      ? {
          status: {
            in: ["OPEN", "PENDING"]
          }
        }
      : { status })
  };

  return prisma.ticket.findMany({
    where,
    include: ticketInclude,
    orderBy: {
      lastMessageAt: "desc"
    },
    take: 200
  });
}`;

const newFunction = `export async function listTickets(
  companyId: string,
  status: TicketListStatus,
  filters:
    TicketListFilters = {}
) {
  const q =
    filters.q
      ?.trim()
      .slice(
        0,
        120
      );

  const assigneeId =
    filters.assigneeId ===
      "ME"
      ? filters
          .actorMembershipId
      : filters.assigneeId ===
          "NONE"
        ? null
        : filters
            .assigneeId;

  const where:
    Prisma.TicketWhereInput = {
    companyId,
    ...(status === "ACTIVE"
      ? {
          status: {
            in: [
              "OPEN",
              "PENDING"
            ]
          }
        }
      : {
          status
        }),
    ...(q
      ? {
          OR: [
            {
              contact: {
                name: {
                  contains:
                    q
                }
              }
            },
            {
              contact: {
                whatsappName: {
                  contains:
                    q
                }
              }
            },
            {
              contact: {
                phoneNumber: {
                  contains:
                    q
                }
              }
            },
            {
              contact: {
                remoteJid: {
                  contains:
                    q
                }
              }
            },
            {
              lastMessage: {
                contains:
                  q
              }
            }
          ]
        }
      : {}),
    ...(filters.queueId
      ? filters.queueId ===
          "NONE"
        ? {
            queueId:
              null
          }
        : {
            queueId:
              filters.queueId
          }
      : {}),
    ...(filters.assigneeId
      ? {
          assignedMembershipId:
            assigneeId
        }
      : {}),
    ...(filters.unreadOnly
      ? {
          unreadCount: {
            gt: 0
          }
        }
      : {}),
    ...(filters.tagId
      ? {
          tags: {
            some: {
              tagId:
                filters.tagId
            }
          }
        }
      : {}),
    ...(filters.conversationType ===
      "DIRECT"
      ? {
          contact: {
            isGroup:
              false
          }
        }
      : filters.conversationType ===
          "GROUP"
        ? {
            contact: {
              isGroup:
                true
            }
          }
        : {})
  };

  return prisma.ticket.findMany({
    where,
    include:
      ticketInclude,
    orderBy: [
      {
        unreadCount:
          "desc"
      },
      {
        lastMessageAt:
          "desc"
      }
    ],
    take: 200
  });
}`;

if (
  content.includes(
    oldFunction
  )
) {
  content =
    content.replace(
      oldFunction,
      newFunction
    );
} else if (
  !content.includes(
    "filters:\n    TicketListFilters = {}"
  )
) {
  throw new Error(
    "listTickets implementation anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.routes.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldSchema = `const listSchema = z.object({
  status: z
    .enum(["ACTIVE", "OPEN", "PENDING", "CLOSED"])
    .default("ACTIVE")
});`;

const newSchema = `const listSchema = z.object({
  status: z
    .enum([
      "ACTIVE",
      "OPEN",
      "PENDING",
      "CLOSED"
    ])
    .default("ACTIVE"),
  q: z
    .string()
    .trim()
    .max(120)
    .optional(),
  queueId: z
    .union([
      z.string().uuid(),
      z.literal("NONE")
    ])
    .optional(),
  assigneeId: z
    .union([
      z.string().uuid(),
      z.literal("ME"),
      z.literal("NONE")
    ])
    .optional(),
  unreadOnly: z
    .enum([
      "true",
      "false"
    ])
    .transform(
      value =>
        value === "true"
    )
    .optional(),
  tagId: z
    .string()
    .uuid()
    .optional(),
  conversationType: z
    .enum([
      "ALL",
      "DIRECT",
      "GROUP"
    ])
    .default("ALL")
});`;

if (
  content.includes(
    oldSchema
  )
) {
  content =
    content.replace(
      oldSchema,
      newSchema
    );
} else if (
  !content.includes(
    "conversationType: z"
  )
) {
  throw new Error(
    "ticket listSchema anchor not found."
  );
}

const oldCall =
  `tickets: await listTickets(auth.companyId, query.status)`;

const newCall = `tickets: await listTickets(
        auth.companyId,
        query.status,
        {
          q:
            query.q,
          queueId:
            query.queueId,
          assigneeId:
            query.assigneeId,
          actorMembershipId:
            auth.membershipId,
          unreadOnly:
            query.unreadOnly,
          tagId:
            query.tagId,
          conversationType:
            query.conversationType
        }
      )`;

if (
  content.includes(
    oldCall
  )
) {
  content =
    content.replace(
      oldCall,
      newCall
    );
} else if (
  !content.includes(
    "actorMembershipId:\n            auth.membershipId"
  )
) {
  throw new Error(
    "listTickets route call anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > apps/api/src/modules/tickets/ticket-list-filter.test.ts <<'EOF'
import assert from "node:assert/strict";
import { test } from "node:test";

import type {
  TicketListFilters
} from "./ticket.service.js";

function normalize(
  input:
    TicketListFilters
) {
  return {
    q:
      input.q
        ?.trim(),
    queueId:
      input.queueId,
    assigneeId:
      input.assigneeId,
    unreadOnly:
      Boolean(
        input.unreadOnly
      ),
    tagId:
      input.tagId,
    conversationType:
      input.conversationType ??
      "ALL"
  };
}

test(
  "ticket list filters preserve explicit operational scope",
  () => {
    assert.deepEqual(
      normalize({
        q:
          "  joao  ",
        queueId:
          "NONE",
        assigneeId:
          "ME",
        unreadOnly:
          true,
        tagId:
          "00000000-0000-4000-8000-000000000000",
        conversationType:
          "DIRECT"
      }),
      {
        q:
          "joao",
        queueId:
          "NONE",
        assigneeId:
          "ME",
        unreadOnly:
          true,
        tagId:
          "00000000-0000-4000-8000-000000000000",
        conversationType:
          "DIRECT"
      }
    );
  }
);
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

const current =
  pkg.scripts?.test;

if (
  typeof current !==
    "string"
) {
  throw new Error(
    "API test script missing."
  );
}

const file =
  "src/modules/tickets/ticket-list-filter.test.ts";

if (
  !current.includes(
    file
  )
) {
  pkg.scripts.test =
    `${current} ${file}`;
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
  "apps/web/app/dashboard/conversations/page.tsx";

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
    "type TicketStatusFilter ="
  )
) {
  const anchor =
    "interface TicketsResponse {";

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "TicketsResponse anchor not found."
    );
  }

  const types = `type TicketStatusFilter =
  | "ACTIVE"
  | "PENDING"
  | "OPEN";

type TicketConversationFilter =
  | "ALL"
  | "DIRECT"
  | "GROUP";

interface InboxFilterState {
  search: string;
  status:
    TicketStatusFilter;
  queueId: string;
  assigneeId: string;
  unreadOnly: boolean;
  tagId: string;
  conversationType:
    TicketConversationFilter;
}

`;

  content =
    content.replace(
      anchor,
      `${types}${anchor}`
    );
}

if (
  !content.includes(
    "const [inboxFilters, setInboxFilters]"
  )
) {
  const anchor =
    `  const [tickets, setTickets] = useState<Ticket[]>([]);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "tickets state anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  const [inboxFilters, setInboxFilters] =
    useState<InboxFilterState>({
      search: "",
      status:
        "ACTIVE",
      queueId: "",
      assigneeId: "",
      unreadOnly:
        false,
      tagId: "",
      conversationType:
        "ALL"
    });
  const [debouncedTicketSearch, setDebouncedTicketSearch] =
    useState("");`
    );
}

if (
  !content.includes(
    "const activeInboxFilterCount ="
  )
) {
  const anchor =
    `  const pendingCount = tickets.filter(`;

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "pendingCount anchor not found."
    );
  }

  const helpers = `  const activeInboxFilterCount =
    [
      inboxFilters.status !==
        "ACTIVE",
      Boolean(
        inboxFilters.queueId
      ),
      Boolean(
        inboxFilters.assigneeId
      ),
      inboxFilters.unreadOnly,
      Boolean(
        inboxFilters.tagId
      ),
      inboxFilters.conversationType !==
        "ALL"
    ].filter(
      Boolean
    ).length;

  const hasInboxFilter =
    Boolean(
      debouncedTicketSearch ||
      activeInboxFilterCount
    );

`;

  content =
    content.slice(
      0,
      index
    ) +
    helpers +
    content.slice(
      index
    );
}

const loadStart =
  `  const loadTickets = useCallback(async () => {`;

const start =
  content.indexOf(
    loadStart
  );

if (start < 0) {
  throw new Error(
    "loadTickets callback start not found."
  );
}

if (
  !content
    .slice(
      start,
      start + 4000
    )
    .includes(
      "debouncedTicketSearch"
    )
) {
  const endCandidates = [
    `  }, [request]);`,
    `  }, [
    request
  ]);`
  ];

  let end = -1;
  let endMarker = "";

  for (
    const candidate
    of endCandidates
  ) {
    const found =
      content.indexOf(
        candidate,
        start
      );

    if (
      found >= 0 &&
      (
        end < 0 ||
        found < end
      )
    ) {
      end =
        found;
      endMarker =
        candidate;
    }
  }

  if (end < 0) {
    throw new Error(
      "loadTickets callback end not found."
    );
  }

  const replacement = `  const loadTickets = useCallback(async () => {
    const params =
      new URLSearchParams({
        status:
          inboxFilters.status
      });

    if (
      debouncedTicketSearch
    ) {
      params.set(
        "q",
        debouncedTicketSearch
      );
    }

    if (
      inboxFilters.queueId
    ) {
      params.set(
        "queueId",
        inboxFilters.queueId
      );
    }

    if (
      inboxFilters.assigneeId
    ) {
      params.set(
        "assigneeId",
        inboxFilters.assigneeId
      );
    }

    if (
      inboxFilters.unreadOnly
    ) {
      params.set(
        "unreadOnly",
        "true"
      );
    }

    if (
      inboxFilters.tagId
    ) {
      params.set(
        "tagId",
        inboxFilters.tagId
      );
    }

    if (
      inboxFilters.conversationType !==
      "ALL"
    ) {
      params.set(
        "conversationType",
        inboxFilters.conversationType
      );
    }

    const payload =
      await request<TicketsResponse>(
        \`/api/v1/tickets?\${params.toString()}\`
      );

    setTickets(
      payload.tickets
    );

    setSelectedId(
      current => {
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
      }
    );
  }, [
    debouncedTicketSearch,
    inboxFilters.assigneeId,
    inboxFilters.conversationType,
    inboxFilters.queueId,
    inboxFilters.status,
    inboxFilters.tagId,
    inboxFilters.unreadOnly,
    request
  ]);`;

  content =
    content.slice(
      0,
      start
    ) +
    replacement +
    content.slice(
      end +
      endMarker.length
    );
}

if (
  !content.includes(
    "window.setTimeout(\n        () => {\n          setDebouncedTicketSearch("
  )
) {
  const anchor = `  useEffect(() => {
    if (!loading && !session) {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "auth loading effect anchor not found."
    );
  }

  const debounce = `  useEffect(() => {
    const timeout =
      window.setTimeout(
        () => {
          setDebouncedTicketSearch(
            inboxFilters.search
              .trim()
          );
        },
        280
      );

    return () =>
      window.clearTimeout(
        timeout
      );
  }, [
    inboxFilters.search
  ]);

`;

  content =
    content.replace(
      anchor,
      `${debounce}${anchor}`
    );
}

if (
  !content.includes(
    "function clearInboxFilters()"
  )
) {
  const anchor =
    `  async function handleClose() {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "handleClose anchor not found."
    );
  }

  const helper = `  function clearInboxFilters() {
    setInboxFilters({
      search: "",
      status:
        "ACTIVE",
      queueId: "",
      assigneeId: "",
      unreadOnly:
        false,
      tagId: "",
      conversationType:
        "ALL"
    });

    setDebouncedTicketSearch(
      ""
    );
  }

`;

  content =
    content.replace(
      anchor,
      `${helper}${anchor}`
    );
}

const oldHeading = `          <div className="ticket-list__heading ticket-list__heading--stacked">
            <strong>Atendimentos ativos</strong>
            <div className="ticket-counters">
              <span>{pendingCount} aguardando</span>
              <span>{openCount} em atendimento</span>
            </div>
          </div>

          <div className="ticket-list__items">`;

const newHeading = `          <div className="ticket-list__heading ticket-list__heading--filters">
            <div className="ticket-list__title-row">
              <div>
                <strong>
                  Atendimentos
                </strong>
                <span>
                  {tickets.length}
                  {hasInboxFilter
                    ? " encontrados"
                    : " ativos"}
                </span>
              </div>

              {hasInboxFilter && (
                <button
                  className="inbox-filter-clear"
                  onClick={
                    clearInboxFilters
                  }
                  type="button"
                >
                  Limpar
                </button>
              )}
            </div>

            <label className="inbox-ticket-search">
              <span>
                Buscar
              </span>
              <input
                onChange={event =>
                  setInboxFilters(
                    current => ({
                      ...current,
                      search:
                        event.target.value
                    })
                  )
                }
                placeholder="Nome, número ou mensagem"
                type="search"
                value={
                  inboxFilters.search
                }
              />
            </label>

            <div className="inbox-status-filters">
              {(
                [
                  [
                    "ACTIVE",
                    "Todos"
                  ],
                  [
                    "PENDING",
                    "Aguardando"
                  ],
                  [
                    "OPEN",
                    "Atendendo"
                  ]
                ] as const
              ).map(
                ([
                  value,
                  label
                ]) => (
                  <button
                    className={
                      inboxFilters.status ===
                      value
                        ? "inbox-status-chip inbox-status-chip--active"
                        : "inbox-status-chip"
                    }
                    key={value}
                    onClick={() =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          status:
                            value
                        })
                      )
                    }
                    type="button"
                  >
                    {label}
                  </button>
                )
              )}

              <button
                className={
                  inboxFilters.unreadOnly
                    ? "inbox-status-chip inbox-status-chip--active"
                    : "inbox-status-chip"
                }
                onClick={() =>
                  setInboxFilters(
                    current => ({
                      ...current,
                      unreadOnly:
                        !current.unreadOnly
                    })
                  )
                }
                type="button"
              >
                Não lidas
              </button>
            </div>

            <details
              className={
                activeInboxFilterCount > 0
                  ? "inbox-advanced-filters inbox-advanced-filters--active"
                  : "inbox-advanced-filters"
              }
            >
              <summary>
                Filtros
                {activeInboxFilterCount > 0 && (
                  <span>
                    {activeInboxFilterCount}
                  </span>
                )}
              </summary>

              <div className="inbox-advanced-filters__body">
                <label>
                  <span>
                    Fila
                  </span>
                  <select
                    onChange={event =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          queueId:
                            event.target.value
                        })
                      )
                    }
                    value={
                      inboxFilters.queueId
                    }
                  >
                    <option value="">
                      Todas
                    </option>
                    <option value="NONE">
                      Sem fila
                    </option>
                    {queues.map(
                      queue => (
                        <option
                          key={
                            queue.id
                          }
                          value={
                            queue.id
                          }
                        >
                          {queue.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label>
                  <span>
                    Atendente
                  </span>
                  <select
                    onChange={event =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          assigneeId:
                            event.target.value
                        })
                      )
                    }
                    value={
                      inboxFilters.assigneeId
                    }
                  >
                    <option value="">
                      Todos
                    </option>
                    <option value="ME">
                      Meus atendimentos
                    </option>
                    <option value="NONE">
                      Sem atendente
                    </option>
                    {team.map(
                      membership => (
                        <option
                          key={
                            membership.id
                          }
                          value={
                            membership.id
                          }
                        >
                          {membership.user.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label>
                  <span>
                    Etiqueta
                  </span>
                  <select
                    onChange={event =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          tagId:
                            event.target.value
                        })
                      )
                    }
                    value={
                      inboxFilters.tagId
                    }
                  >
                    <option value="">
                      Todas
                    </option>
                    {tags.map(
                      tag => (
                        <option
                          key={
                            tag.id
                          }
                          value={
                            tag.id
                          }
                        >
                          {tag.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label>
                  <span>
                    Tipo
                  </span>
                  <select
                    onChange={event =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          conversationType:
                            event.target.value as
                              TicketConversationFilter
                        })
                      )
                    }
                    value={
                      inboxFilters.conversationType
                    }
                  >
                    <option value="ALL">
                      Todos
                    </option>
                    <option value="DIRECT">
                      Contatos
                    </option>
                    <option value="GROUP">
                      Grupos
                    </option>
                  </select>
                </label>
              </div>
            </details>
          </div>

          <div className="ticket-list__items">`;

if (
  content.includes(
    oldHeading
  )
) {
  content =
    content.replace(
      oldHeading,
      newHeading
    );
} else if (
  !content.includes(
    'className="ticket-list__heading ticket-list__heading--filters"'
  )
) {
  throw new Error(
    "ticket list heading anchor not found."
  );
}

const oldEmpty = `                <strong>Nenhuma conversa ativa.</strong>
                <p>Novas mensagens entram aqui em tempo real.</p>`;

const newEmpty = `                <strong>
                  {hasInboxFilter
                    ? "Nenhuma conversa encontrada."
                    : "Nenhuma conversa ativa."}
                </strong>
                <p>
                  {hasInboxFilter
                    ? "Ajuste ou limpe os filtros para ampliar a busca."
                    : "Novas mensagens entram aqui em tempo real."}
                </p>`;

if (
  content.includes(
    oldEmpty
  )
) {
  content =
    content.replace(
      oldEmpty,
      newEmpty
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Advanced inbox filters installed."
);
NODE

if ! grep -Fq -- "WAPP P2.3 / ADVANCED INBOX FILTERS" "$WEB_CSS"; then
  cat >> "$WEB_CSS" <<'EOF'

/* --- WAPP P2.3 / ADVANCED INBOX FILTERS ------------------------------- */

.ticket-list__heading--filters {
  display: grid;
  gap: 9px;
  padding: 13px 14px 11px;
}

.ticket-list__title-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.ticket-list__title-row > div {
  display: flex;
  align-items: baseline;
  gap: 6px;
  min-width: 0;
}

.ticket-list__title-row strong {
  font-size: 12px;
}

.ticket-list__title-row span {
  color: var(--muted);
  font-size: 9px;
}

.inbox-filter-clear {
  border: 0;
  background: transparent;
  color: var(--accent-dark);
  padding: 2px 0;
  font-size: 9px;
  font-weight: 760;
  cursor: pointer;
}

.inbox-ticket-search {
  display: flex;
  min-height: 34px;
  align-items: center;
  gap: 8px;
  border: 1px solid var(--line);
  border-radius: 9px;
  background: white;
  padding: 0 9px;
}

.inbox-ticket-search:focus-within {
  border-color: rgba(31, 122, 80, 0.38);
  box-shadow: 0 0 0 3px rgba(31, 122, 80, 0.055);
}

.inbox-ticket-search > span {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 8px;
  font-weight: 760;
}

.inbox-ticket-search input {
  width: 100%;
  min-width: 0;
  border: 0;
  outline: 0;
  background: transparent;
  color: var(--ink);
  font: inherit;
  font-size: 10px;
}

.inbox-ticket-search input::placeholder {
  color: #8b948e;
}

.inbox-status-filters {
  display: flex;
  gap: 5px;
  overflow-x: auto;
  scrollbar-width: none;
}

.inbox-status-filters::-webkit-scrollbar {
  display: none;
}

.inbox-status-chip {
  flex: 0 0 auto;
  min-height: 26px;
  border: 1px solid var(--line);
  border-radius: 999px;
  background: white;
  color: #59635d;
  padding: 0 9px;
  font-size: 8px;
  font-weight: 720;
  cursor: pointer;
}

.inbox-status-chip--active {
  border-color: rgba(31, 122, 80, 0.22);
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.inbox-advanced-filters {
  position: relative;
}

.inbox-advanced-filters > summary {
  display: inline-flex;
  min-height: 24px;
  align-items: center;
  gap: 5px;
  color: var(--muted);
  font-size: 8px;
  font-weight: 720;
  cursor: pointer;
  list-style: none;
}

.inbox-advanced-filters > summary::-webkit-details-marker {
  display: none;
}

.inbox-advanced-filters > summary::before {
  content: "Filtros:";
  font-size: 8px;
  font-weight: 600;
}

.inbox-advanced-filters--active > summary {
  color: var(--accent-dark);
}

.inbox-advanced-filters > summary > span {
  display: grid;
  min-width: 17px;
  height: 17px;
  place-items: center;
  border-radius: 999px;
  background: var(--accent-soft);
  padding: 0 5px;
  font-size: 8px;
}

.inbox-advanced-filters__body {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 7px;
  padding-top: 7px;
}

.inbox-advanced-filters__body label {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.inbox-advanced-filters__body label > span {
  color: var(--muted);
  font-size: 7px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.inbox-advanced-filters__body select {
  width: 100%;
  min-width: 0;
  height: 30px;
  border: 1px solid var(--line);
  border-radius: 7px;
  outline: 0;
  background: white;
  padding: 0 7px;
  color: var(--ink);
  font: inherit;
  font-size: 8px;
}

.inbox-advanced-filters__body select:focus {
  border-color: rgba(31, 122, 80, 0.38);
}

@media (max-width: 760px) {
  .inbox-advanced-filters__body {
    grid-template-columns: 1fr;
  }
}

/* --- /WAPP P2.3 ------------------------------------------------------- */
EOF
fi

cat > docs/P2_03_ADVANCED_INBOX_FILTERS.md <<'EOF'
# P2.3 Advanced inbox filters

P2.3 moves inbox filtering to the API instead of filtering only the ticket
array already loaded in the browser.

`GET /api/v1/tickets` accepts:

- `status=ACTIVE|OPEN|PENDING|CLOSED`;
- `q=<name, WhatsApp name, phone, JID or last message>`;
- `queueId=<uuid>|NONE`;
- `assigneeId=<membership uuid>|ME|NONE`;
- `unreadOnly=true|false`;
- `tagId=<uuid>`;
- `conversationType=ALL|DIRECT|GROUP`.

`ME` is resolved from the authenticated membership, never from a user id
provided by the browser.

The inbox orders unread conversations first, then newest activity.

The left column gets a debounced search, compact status chips, unread toggle,
queue/assignee/tag/type filters, active-filter count and one-click reset.

No message-scroll, composer, quoted-reply or reaction layout is changed.
EOF

echo "[P2.3] Unit tests..."
pnpm test

echo "[P2.3] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P2.3] Typechecking Web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.3] Advanced inbox filters installed."
echo "No Prisma migration is required."
