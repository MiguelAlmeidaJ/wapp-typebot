#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.12] Building ticket operational history..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
  "apps/api/src/modules/messages/message-ingestion.service.ts" \
  "apps/api/src/modules/realtime/realtime.bus.ts" \
  "apps/web/lib/realtime-types.ts" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/tickets \
  apps/web/components/conversations \
  docs

# ---------------------------------------------------------------------------
# Prisma: immutable operational event log
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

function addRelation(modelName, fieldLine, beforePattern) {
  const regex =
    new RegExp(
      `model ${modelName} \\{[\\s\\S]*?\\n\\}`
    );

  const match =
    schema.match(regex);

  if (!match) {
    throw new Error(
      `${modelName} model not found.`
    );
  }

  let model = match[0];

  const fieldName =
    fieldLine.trim().split(/\s+/)[0];

  if (
    new RegExp(
      `^\\s*${fieldName}\\s+`,
      "m"
    ).test(model)
  ) {
    return;
  }

  const before =
    model.match(beforePattern);

  if (!before) {
    throw new Error(
      `Could not find relation anchor in ${modelName}.`
    );
  }

  model = model.replace(
    before[0],
    `${fieldLine}\n${before[0]}`
  );

  schema = schema.replace(
    match[0],
    model
  );
}

addRelation(
  "Company",
  "  ticketEvents          TicketEvent[]",
  /^\s*(?:ticketNotes|quickReplies|tags|sessions)\s+/m
);

addRelation(
  "CompanyMembership",
  "  ticketEvents         TicketEvent[]",
  /^\s*(?:ticketNotes|createdTicketTags|createdQuickReplies|createdAt)\s+/m
);

addRelation(
  "Ticket",
  "  events               TicketEvent[]",
  /^\s*(?:notes|tags|createdAt)\s+/m
);

if (!schema.includes("model TicketEvent {")) {
  const anchor = "model TicketNote {";

  if (!schema.includes(anchor)) {
    throw new Error(
      "TicketNote model not found. P1.12 expects P1.6+."
    );
  }

  const model = `model TicketEvent {
  id                String             @id @default(uuid()) @db.Char(36)
  companyId         String             @db.Char(36)
  ticketId          String             @db.Char(36)
  actorMembershipId String?            @db.Char(36)
  type              String             @db.VarChar(40)
  metadata          Json?
  company           Company            @relation(fields: [companyId], references: [id], onDelete: Cascade)
  ticket            Ticket             @relation(fields: [ticketId], references: [id], onDelete: Cascade)
  actorMembership   CompanyMembership? @relation(fields: [actorMembershipId], references: [id], onDelete: SetNull)
  createdAt         DateTime           @default(now())

  @@index([ticketId, createdAt])
  @@index([companyId, createdAt])
  @@index([actorMembershipId, createdAt])
}

`;

  schema = schema.replace(
    anchor,
    `${model}${anchor}`
  );
}

fs.writeFileSync(path, schema);
console.log("TicketEvent schema installed.");
NODE

# ---------------------------------------------------------------------------
# Event service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tickets/ticket-event.service.ts <<'EOF'
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export type TicketEventType =
  | "CREATED"
  | "CLAIMED"
  | "TRANSFERRED"
  | "CLOSED"
  | "REOPENED"
  | "TAGS_UPDATED";

export async function recordTicketEvent(input: {
  companyId: string;
  ticketId: string;
  type: TicketEventType;
  actorMembershipId?: string | null;
  metadata?: Record<string, unknown> | null;
}) {
  const event =
    await prisma.ticketEvent.create({
      data: {
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        type:
          input.type,
        actorMembershipId:
          input.actorMembershipId ??
          null,
        metadata:
          input.metadata
            ? toPrismaJson(
                input.metadata
              )
            : undefined
      }
    });

  publishRealtime(
    input.companyId,
    {
      type:
        "ticket.event.created",
      ticketId:
        input.ticketId,
      eventId:
        event.id
    }
  );

  return event;
}

export async function listTicketEvents(input: {
  companyId: string;
  ticketId: string;
}) {
  const ticket =
    await prisma.ticket.findFirst({
      where: {
        id: input.ticketId,
        companyId:
          input.companyId
      },
      select: {
        id: true
      }
    });

  if (!ticket) {
    throw new AppError(
      "Atendimento não encontrado.",
      404,
      "TICKET_NOT_FOUND"
    );
  }

  return prisma.ticketEvent.findMany({
    where: {
      companyId:
        input.companyId,
      ticketId:
        input.ticketId
    },
    include: {
      actorMembership: {
        select: {
          id: true,
          role: true,
          user: {
            select: {
              id: true,
              name: true,
              email: true
            }
          }
        }
      }
    },
    orderBy: {
      createdAt: "desc"
    },
    take: 300
  });
}
EOF

# ---------------------------------------------------------------------------
# Ticket service hooks
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { recordTicketEvent } from "./ticket-event.service.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { publishRealtime } from "../realtime/realtime.bus.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "publishRealtime import not found in ticket.service.ts."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

function functionBlock(name) {
  const start =
    content.indexOf(
      `export async function ${name}(`
    );

  if (start < 0) {
    throw new Error(
      `${name} not found.`
    );
  }

  const next =
    content.indexOf(
      "\nexport async function ",
      start + 20
    );

  return {
    start,
    end:
      next >= 0
        ? next
        : content.length,
    block:
      content.slice(
        start,
        next >= 0
          ? next
          : content.length
      )
  };
}

function insertBeforePublish(
  name,
  marker,
  insertion
) {
  const info =
    functionBlock(name);

  if (
    info.block.includes(marker)
  ) {
    return;
  }

  const publishIndex =
    info.block.indexOf(
      "  publishRealtime("
    );

  if (publishIndex < 0) {
    throw new Error(
      `publishRealtime not found in ${name}.`
    );
  }

  const block =
    info.block.slice(
      0,
      publishIndex
    ) +
    insertion +
    info.block.slice(
      publishIndex
    );

  content =
    content.slice(
      0,
      info.start
    ) +
    block +
    content.slice(
      info.end
    );
}

insertBeforePublish(
  "claimTicket",
  'type: "CLAIMED"',
  `  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      updated.id,
    actorMembershipId:
      input.membershipId,
    type: "CLAIMED",
    metadata: {
      assignedMembershipId:
        updated.assignedMembershipId,
      assigneeName:
        updated.assignedMembership?.user.name ??
        null
    }
  });

`
);

insertBeforePublish(
  "transferTicket",
  'type: "TRANSFERRED"',
  `  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      updated.id,
    actorMembershipId:
      input.actorMembershipId,
    type: "TRANSFERRED",
    metadata: {
      fromQueueId:
        ticket.queueId,
      fromQueueName:
        ticket.queue?.name ??
        null,
      toQueueId:
        updated.queueId,
      toQueueName:
        updated.queue?.name ??
        null,
      fromMembershipId:
        ticket.assignedMembershipId,
      fromAssigneeName:
        ticket.assignedMembership?.user.name ??
        null,
      toMembershipId:
        updated.assignedMembershipId,
      toAssigneeName:
        updated.assignedMembership?.user.name ??
        null
    }
  });

`
);

insertBeforePublish(
  "closeTicket",
  'type: "CLOSED"',
  `  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      ticket.id,
    actorMembershipId:
      input.membershipId,
    type: "CLOSED",
    metadata: {
      previousStatus:
        current.status
    }
  });

`
);

insertBeforePublish(
  "reopenTicket",
  'type: "REOPENED"',
  `    await recordTicketEvent({
      companyId:
        input.companyId,
      ticketId:
        ticket.id,
      actorMembershipId:
        input.membershipId,
      type: "REOPENED",
      metadata: {
        assignedMembershipId:
          ticket.assignedMembershipId,
        assigneeName:
          ticket.assignedMembership?.user.name ??
          null
      }
    });

`
);

insertBeforePublish(
  "replaceTicketTags",
  'type: "TAGS_UPDATED"',
  `  if (updated) {
    await recordTicketEvent({
      companyId:
        input.companyId,
      ticketId:
        ticket.id,
      actorMembershipId:
        input.actorMembershipId,
      type: "TAGS_UPDATED",
      metadata: {
        tagIds:
          updated.tags.map(
            link =>
              link.tag.id
          ),
        tagNames:
          updated.tags.map(
            link =>
              link.tag.name
          )
      }
    });
  }

`
);

fs.writeFileSync(path, content);
console.log("Ticket operational event hooks installed.");
NODE

# ---------------------------------------------------------------------------
# New ticket CREATED event from WhatsApp ingestion
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/message-ingestion.service.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { recordTicketEvent } from "../tickets/ticket-event.service.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { publishRealtime } from "../realtime/realtime.bus.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "publishRealtime import not found in message ingestion."
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
    'type: "CREATED"'
  )
) {
  const anchor =
    `  if (!before) {
    publishRealtime(connection.companyId, {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "New-ticket realtime block not found in message ingestion."
    );
  }

  content = content.replace(
    anchor,
    `  if (!before) {
    await recordTicketEvent({
      companyId:
        connection.companyId,
      ticketId:
        ticket.id,
      type: "CREATED",
      metadata: {
        source: "WHATSAPP",
        initialDirection:
          parsed.fromMe
            ? "OUTBOUND"
            : "INBOUND"
      }
    });

    publishRealtime(connection.companyId, {`
  );
}

fs.writeFileSync(path, content);
console.log("New WhatsApp tickets now record CREATED event.");
NODE

# ---------------------------------------------------------------------------
# Ticket events API route
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.routes.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { listTicketEvents } from "./ticket-event.service.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { requireAuth } from "../auth/auth.guard.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "requireAuth import not found."
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
    '"/api/v1/tickets/:id/events"'
  )
) {
  const anchor =
    `  app.get(
    "/api/v1/tickets/:id/messages",`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Ticket messages GET route anchor not found."
    );
  }

  const route = `  app.get(
    "/api/v1/tickets/:id/events",
    async request => {
      const auth =
        await requireAuth(request);

      const params =
        ticketIdSchema.parse(
          request.params
        );

      return {
        events:
          await listTicketEvents({
            companyId:
              auth.companyId,
            ticketId:
              params.id
          })
      };
    }
  );

`;

  content = content.replace(
    anchor,
    `${route}${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Ticket event history route installed.");
NODE

# ---------------------------------------------------------------------------
# Realtime type
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

for (const path of [
  "apps/api/src/modules/realtime/realtime.bus.ts",
  "apps/web/lib/realtime-types.ts"
]) {
  let content =
    fs.readFileSync(path, "utf8");

  if (
    !content.includes(
      '| "ticket.event.created"'
    )
  ) {
    const candidates = [
      '| "sla.updated"',
      '| "tag.updated"',
      '| "note.created"',
      '| "ticket.updated"'
    ];

    const anchor =
      candidates.find(candidate =>
        content.includes(candidate)
      );

    if (!anchor) {
      throw new Error(
        `Realtime type anchor not found in ${path}.`
      );
    }

    content = content.replace(
      anchor,
      `${anchor}\n  | "ticket.event.created"`
    );
  }

  if (
    !content.includes(
      "eventId?: string;"
    )
  ) {
    const candidates = [
      "tagId?: string;",
      "quickReplyId?: string;",
      "noteId?: string;",
      "messageId?: string;"
    ];

    const anchor =
      candidates.find(candidate =>
        content.includes(candidate)
      );

    if (!anchor) {
      throw new Error(
        `Realtime event field anchor not found in ${path}.`
      );
    }

    content = content.replace(
      anchor,
      `${anchor}\n  eventId?: string;`
    );
  }

  fs.writeFileSync(path, content);
}

console.log("ticket.event.created realtime installed.");
NODE

# ---------------------------------------------------------------------------
# UI component
# ---------------------------------------------------------------------------

cat > apps/web/components/conversations/ticket-history-drawer.tsx <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";

type EventType =
  | "CREATED"
  | "CLAIMED"
  | "TRANSFERRED"
  | "CLOSED"
  | "REOPENED"
  | "TAGS_UPDATED"
  | string;

interface TicketEvent {
  id: string;
  type: EventType;
  metadata:
    | Record<string, unknown>
    | null;
  createdAt: string;
  actorMembership: {
    id: string;
    role: string;
    user: {
      id: string;
      name: string;
      email: string;
    };
  } | null;
}

interface TicketEventsResponse {
  events: TicketEvent[];
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
      minute: "2-digit",
      second: "2-digit"
    }
  ).format(
    new Date(value)
  );
}

function text(
  metadata: Record<string, unknown> | null,
  key: string
) {
  const value =
    metadata?.[key];

  return typeof value ===
    "string" &&
    value.trim()
      ? value
      : null;
}

function stringList(
  metadata: Record<string, unknown> | null,
  key: string
) {
  const value =
    metadata?.[key];

  return Array.isArray(value)
    ? value.filter(
        item =>
          typeof item ===
          "string"
      ) as string[]
    : [];
}

function eventTitle(
  type: EventType
) {
  switch (type) {
    case "CREATED":
      return "Atendimento criado";
    case "CLAIMED":
      return "Atendimento assumido";
    case "TRANSFERRED":
      return "Atendimento transferido";
    case "CLOSED":
      return "Atendimento encerrado";
    case "REOPENED":
      return "Atendimento reaberto";
    case "TAGS_UPDATED":
      return "Etiquetas atualizadas";
    default:
      return type;
  }
}

function eventDetail(
  event: TicketEvent
) {
  const metadata =
    event.metadata;

  switch (event.type) {
    case "CREATED": {
      const direction =
        text(
          metadata,
          "initialDirection"
        );

      return direction ===
        "INBOUND"
        ? "Criado a partir de uma nova mensagem recebida."
        : direction ===
            "OUTBOUND"
          ? "Criado a partir de uma mensagem enviada."
          : "Atendimento iniciado.";
    }

    case "CLAIMED": {
      const assignee =
        text(
          metadata,
          "assigneeName"
        );

      return assignee
        ? `Assumido por ${assignee}.`
        : "O atendimento foi assumido.";
    }

    case "TRANSFERRED": {
      const fromQueue =
        text(
          metadata,
          "fromQueueName"
        ) ??
        "sem fila";

      const toQueue =
        text(
          metadata,
          "toQueueName"
        ) ??
        "sem fila";

      const fromAssignee =
        text(
          metadata,
          "fromAssigneeName"
        ) ??
        "sem atendente";

      const toAssignee =
        text(
          metadata,
          "toAssigneeName"
        ) ??
        "sem atendente";

      return `Fila: ${fromQueue} → ${toQueue}. Atendente: ${fromAssignee} → ${toAssignee}.`;
    }

    case "CLOSED":
      return "O atendimento foi encerrado.";

    case "REOPENED": {
      const assignee =
        text(
          metadata,
          "assigneeName"
        );

      return assignee
        ? `Reaberto e atribuído a ${assignee}.`
        : "O atendimento foi reaberto.";
    }

    case "TAGS_UPDATED": {
      const names =
        stringList(
          metadata,
          "tagNames"
        );

      return names.length > 0
        ? `Etiquetas atuais: ${names.join(", ")}.`
        : "Todas as etiquetas foram removidas.";
    }

    default:
      return "Evento operacional registrado.";
  }
}

export function TicketHistoryDrawer({
  ticketId,
  contactName,
  onClose
}: {
  ticketId: string;
  contactName: string;
  onClose: () => void;
}) {
  const {
    request,
    subscribe
  } = useAuth();

  const [events, setEvents] =
    useState<TicketEvent[]>([]);
  const [loading, setLoading] =
    useState(true);
  const [error, setError] =
    useState("");

  const load =
    useCallback(async () => {
      try {
        const payload =
          await request<TicketEventsResponse>(
            `/api/v1/tickets/${ticketId}/events`
          );

        setEvents(
          payload.events
        );
        setError("");
      } catch {
        setError(
          "Não foi possível carregar o histórico operacional."
        );
      } finally {
        setLoading(false);
      }
    }, [
      request,
      ticketId
    ]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    return subscribe(
      "/api/v1/realtime/events",
      event => {
        if (
          event.type ===
            "ticket.event.created" &&
          event.ticketId ===
            ticketId
        ) {
          void load();
        }
      }
    );
  }, [
    load,
    subscribe,
    ticketId
  ]);

  const grouped =
    useMemo(
      () => events,
      [events]
    );

  return (
    <aside className="ticket-history-drawer">
      <header className="ticket-history-drawer__header">
        <div>
          <span className="eyebrow">
            Auditoria
          </span>
          <strong>
            Histórico operacional
          </strong>
          <small>
            {contactName}
          </small>
        </div>

        <button
          aria-label="Fechar histórico operacional"
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      <div className="ticket-history-drawer__intro">
        Mensagens e notas continuam em seus próprios históricos. Aqui ficam apenas movimentações do atendimento.
      </div>

      <div className="ticket-history-drawer__events">
        {error && (
          <div className="ticket-history-empty ticket-history-empty--error">
            {error}
          </div>
        )}

        {!error &&
          loading && (
            <div className="ticket-history-empty">
              Carregando histórico…
            </div>
          )}

        {!error &&
          !loading &&
          grouped.length ===
            0 && (
            <div className="ticket-history-empty">
              Nenhuma movimentação registrada ainda. A auditoria passa a registrar novos eventos a partir do P1.12.
            </div>
          )}

        {!error &&
          grouped.map(event => (
            <article
              className={`ticket-history-event ticket-history-event--${event.type.toLowerCase()}`}
              key={event.id}
            >
              <div className="ticket-history-event__rail">
                <span />
              </div>

              <div className="ticket-history-event__content">
                <div className="ticket-history-event__heading">
                  <strong>
                    {eventTitle(
                      event.type
                    )}
                  </strong>

                  <time>
                    {dateTimeLabel(
                      event.createdAt
                    )}
                  </time>
                </div>

                <p>
                  {eventDetail(
                    event
                  )}
                </p>

                <span className="ticket-history-event__actor">
                  {event
                    .actorMembership
                    ?.user.name ??
                    "Sistema"}
                  {event
                    .actorMembership
                    ?.role
                    ? ` · ${event.actorMembership.role}`
                    : ""}
                </span>
              </div>
            </article>
          ))}
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
  'import { TicketHistoryDrawer } from "@/components/conversations/ticket-history-drawer";';

if (!content.includes(importLine)) {
  const candidates = [
    'import { SlaMonitorDrawer } from "@/components/conversations/sla-monitor-drawer";',
    'import { ClosedTicketsDrawer } from "@/components/conversations/closed-tickets-drawer";',
    'import { ConversationSearch } from "@/components/conversations/conversation-search";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find Conversations component import anchor."
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
    "const [ticketHistoryOpen"
  )
) {
  const candidates = [
    `  const [slaMonitorOpen, setSlaMonitorOpen] =
    useState(false);`,
    `  const [closedTicketsOpen, setClosedTicketsOpen] =
    useState(false);`,
    `  const [conversationSearchOpen, setConversationSearchOpen] =
    useState(false);`
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
  const [ticketHistoryOpen, setTicketHistoryOpen] =
    useState(false);`
  );
}

if (
  !content.includes(
    'className="ticket-history-toggle"'
  )
) {
  const toolbarIndexes = [
    content.indexOf(
      'className="sla-monitor-toggle'
    ),
    content.indexOf(
      'className="closed-tickets-toggle'
    ),
    content.indexOf(
      'className="conversation-search-toggle'
    ),
    content.indexOf(
      'className="ticket-tags-toggle"'
    )
  ].filter(value => value >= 0);

  if (
    toolbarIndexes.length === 0
  ) {
    throw new Error(
      "Could not find ticket toolbar anchor."
    );
  }

  const fromIndex =
    Math.max(
      ...toolbarIndexes
    );

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
                    ticketHistoryOpen
                      ? "ticket-history-toggle ticket-history-toggle--active"
                      : "ticket-history-toggle"
                  }
                  onClick={() => {
                    setTicketHistoryOpen(
                      current => !current
                    );
                    setSlaMonitorOpen(false);
                    setClosedTicketsOpen(false);
                    setConversationSearchOpen(false);
                    setTagPickerOpen(false);
                    setTagManagerOpen(false);
                    setNotesOpen(false);
                    setQuickReplyManagerOpen(false);
                  }}
                  type="button"
                >
                  Histórico
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

if (
  !content.includes(
    "<TicketHistoryDrawer"
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
                {ticketHistoryOpen &&
                  selectedTicket && (
                    <TicketHistoryDrawer
                      contactName={
                        selectedTicket.contact.name
                      }
                      onClose={() =>
                        setTicketHistoryOpen(false)
                      }
                      ticketId={
                        selectedTicket.id
                      }
                    />
                  )}`;

  content = content.replace(
    anchor,
    drawer
  );
}

fs.writeFileSync(path, content);
console.log("Ticket history drawer integrated into Conversations.");
NODE

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.12 / Ticket operational history" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.12 / Ticket operational history ------------------------- */

.ticket-history-toggle {
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

.ticket-history-toggle:hover,
.ticket-history-toggle--active {
  border-color: #b9cec0;
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.ticket-history-drawer {
  position: absolute;
  z-index: 44;
  top: 0;
  right: 0;
  bottom: 0;
  display: grid;
  width: min(430px, 94%);
  min-height: 0;
  grid-template-rows:
    auto
    auto
    minmax(0, 1fr);
  overflow: hidden;
  border-left: 1px solid var(--line);
  background: #fbfcfa;
  box-shadow:
    -18px 0 38px
    rgba(26, 35, 29, 0.09);
}

.ticket-history-drawer__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  border-bottom: 1px solid var(--line);
  background: #fbfcfa;
  padding: 17px;
}

.ticket-history-drawer__header > div {
  display: grid;
  gap: 4px;
}

.ticket-history-drawer__header strong {
  font-size: 15px;
}

.ticket-history-drawer__header small {
  color: var(--muted);
  font-size: 9px;
}

.ticket-history-drawer__header > button {
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

.ticket-history-drawer__intro {
  border-bottom: 1px solid var(--line);
  background: #fff;
  color: var(--muted);
  padding: 9px 13px;
  font-size: 8px;
  line-height: 1.5;
}

.ticket-history-drawer__events {
  min-height: 0;
  overflow-y: auto;
  padding: 12px 13px 18px;
  scrollbar-gutter: stable;
}

.ticket-history-event {
  display: grid;
  grid-template-columns:
    18px
    minmax(0, 1fr);
  gap: 8px;
}

.ticket-history-event__rail {
  position: relative;
  display: flex;
  justify-content: center;
}

.ticket-history-event__rail::after {
  position: absolute;
  top: 15px;
  bottom: -5px;
  width: 1px;
  background: var(--line);
  content: "";
}

.ticket-history-event:last-child
.ticket-history-event__rail::after {
  display: none;
}

.ticket-history-event__rail > span {
  position: relative;
  z-index: 1;
  width: 9px;
  height: 9px;
  margin-top: 6px;
  border: 2px solid #fff;
  border-radius: 999px;
  background: #8fa097;
  box-shadow:
    0 0 0 1px
    var(--line);
}

.ticket-history-event--created
.ticket-history-event__rail > span,
.ticket-history-event--reopened
.ticket-history-event__rail > span {
  background: #57916e;
}

.ticket-history-event--closed
.ticket-history-event__rail > span {
  background: #9b716d;
}

.ticket-history-event--transferred
.ticket-history-event__rail > span {
  background: #738da3;
}

.ticket-history-event__content {
  display: grid;
  gap: 6px;
  margin-bottom: 11px;
  border: 1px solid var(--line);
  border-radius: 11px;
  background: #fff;
  padding: 10px 11px;
}

.ticket-history-event__heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 9px;
}

.ticket-history-event__heading strong {
  font-size: 9px;
}

.ticket-history-event__heading time {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 7px;
}

.ticket-history-event__content > p {
  margin: 0;
  color: #505a54;
  font-size: 9px;
  line-height: 1.5;
}

.ticket-history-event__actor {
  color: var(--muted);
  font-size: 7px;
  font-weight: 700;
}

.ticket-history-empty {
  display: grid;
  min-height: 170px;
  place-items: center;
  color: var(--muted);
  padding: 22px;
  text-align: center;
  font-size: 9px;
  line-height: 1.55;
}

.ticket-history-empty--error {
  color: var(--danger);
}

@media (max-width: 680px) {
  .ticket-history-drawer {
    width: 100%;
    border-left: 0;
  }

  .ticket-history-toggle {
    min-height: 36px;
    padding: 0 9px;
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/TICKET_OPERATIONAL_HISTORY.md <<'EOF'
# Ticket operational history

P1.12 adds an immutable operational audit log to each ticket.

## Events

The first event set is:

- `CREATED`
- `CLAIMED`
- `TRANSFERRED`
- `CLOSED`
- `REOPENED`
- `TAGS_UPDATED`

Messages and internal notes are intentionally not duplicated into this log.

## Actor

User actions store `actorMembershipId`.

System-generated actions, such as creation from an inbound WhatsApp message,
have no actor membership and are displayed as `Sistema`.

## Metadata

Events can preserve operational snapshots such as:

- previous/new queue;
- previous/new assignee;
- tag names;
- initial message direction.

Metadata is descriptive history. Current ticket state continues to come from
the normal Ticket/Tag/Queue models.

## API

`GET /api/v1/tickets/:id/events`

The endpoint is company-scoped and returns at most the latest 300 events,
ordered newest first.

## Realtime

New audit entries publish:

`ticket.event.created`

An open history drawer refreshes automatically.

## Historical limitation

P1.12 does not invent past transfer/claim/tag events that were never recorded.

Existing tickets therefore start accumulating reliable audit history from the
moment P1.12 is deployed. This is preferable to creating inaccurate historical
records.

## Migration

P1.12 requires a Prisma migration for the `TicketEvent` model and relations.
EOF

echo "[P1.12] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.12] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.12] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.12] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.12] Ticket operational history installed."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name ticket_operational_history"
echo "  pnpm dev"
echo
echo "Test:"
echo "  1. open an active ticket and click Histórico"
echo "  2. claim/transfer the ticket"
echo "  3. add/remove a tag"
echo "  4. close and reopen the ticket"
echo "  5. confirm each action appears with actor and timestamp"
