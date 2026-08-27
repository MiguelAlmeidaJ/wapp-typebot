#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.1] Building contacts domain..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/messages/message-ingestion.service.ts" \
  "apps/api/src/security/permissions.ts" \
  "apps/web/lib/permissions.ts" \
  "apps/web/components/access-gate.tsx" \
  "apps/web/app/dashboard/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    echo "P1.1 expects P0.9 to be applied first."
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/contacts \
  apps/web/app/dashboard/contacts \
  docs

# ---------------------------------------------------------------------------
# Prisma: contact profile fields
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

const contactMatch = schema.match(
  /model Contact \{[\s\S]*?\n\}/
);

if (!contactMatch) {
  throw new Error("Contact model not found.");
}

let model = contactMatch[0];

if (!/^\s*whatsappName\s+String\?/m.test(model)) {
  model = model.replace(
    /^(\s*name\s+String\s+@db\.VarChar\(190\)\s*)$/m,
    `$1
  whatsappName String?   @db.VarChar(190)
  email        String?   @db.VarChar(190)
  notes        String?   @db.Text`
  );
}

if (!model.includes("@@index([companyId, email])")) {
  model = model.replace(
    "  @@index([companyId, name])",
    `  @@index([companyId, name])
  @@index([companyId, email])`
  );
}

schema = schema.replace(contactMatch[0], model);
fs.writeFileSync(path, schema);
NODE

# ---------------------------------------------------------------------------
# Preserve manual contact name during WhatsApp ingestion
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/message-ingestion.service.ts";

let content = fs.readFileSync(path, "utf8");

const oldUpdate = `      ...(parsed.pushName && !parsed.isGroup
        ? { name: parsed.pushName }
        : {}),`;

const newUpdate = `      ...(parsed.pushName && !parsed.isGroup
        ? { whatsappName: parsed.pushName }
        : {}),`;

if (content.includes(oldUpdate)) {
  content = content.replace(oldUpdate, newUpdate);
} else if (!content.includes("whatsappName: parsed.pushName")) {
  throw new Error(
    "Could not find Contact pushName update block."
  );
}

const createAnchor = `      name: displayName(parsed),
      isGroup: parsed.isGroup,`;

const createReplacement = `      name: displayName(parsed),
      whatsappName:
        parsed.pushName && !parsed.isGroup
          ? parsed.pushName
          : undefined,
      isGroup: parsed.isGroup,`;

if (content.includes(createAnchor)) {
  content = content.replace(
    createAnchor,
    createReplacement
  );
} else if (!content.includes("whatsappName:")) {
  throw new Error(
    "Could not find Contact create block."
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# API permissions
# ---------------------------------------------------------------------------

cat > apps/api/src/security/permissions.ts <<'EOF'
import type { WappRole } from "../lib/tokens.js";

export type WappPermission =
  | "admin.test"
  | "contacts.read"
  | "contacts.manage"
  | "team.read"
  | "team.manage"
  | "queues.read"
  | "queues.manage"
  | "whatsapp.read"
  | "whatsapp.manage"
  | "whatsapp.test";

const permissionsByRole: Record<
  WappRole,
  readonly WappPermission[]
> = {
  OWNER: [
    "admin.test",
    "contacts.read",
    "contacts.manage",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ],
  ADMIN: [
    "admin.test",
    "contacts.read",
    "contacts.manage",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ],
  SUPERVISOR: [
    "contacts.read",
    "contacts.manage",
    "team.read",
    "queues.read",
    "whatsapp.read",
    "whatsapp.test"
  ],
  AGENT: [
    "contacts.read",
    "contacts.manage",
    "team.read",
    "queues.read",
    "whatsapp.read"
  ]
};

export function roleHasPermission(
  role: WappRole,
  permission: WappPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
EOF

# ---------------------------------------------------------------------------
# Contacts API
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/contacts/contact.service.ts <<'EOF'
import type { Prisma } from "../../generated/prisma/client.js";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";

export type ContactTypeFilter =
  | "ALL"
  | "PEOPLE"
  | "GROUPS";

export async function listContacts(input: {
  companyId: string;
  search?: string;
  type: ContactTypeFilter;
  page: number;
  limit: number;
}) {
  const search = input.search?.trim();

  const where: Prisma.ContactWhereInput = {
    companyId: input.companyId,
    ...(input.type === "PEOPLE"
      ? { isGroup: false }
      : input.type === "GROUPS"
        ? { isGroup: true }
        : {}),
    ...(search
      ? {
          OR: [
            {
              name: {
                contains: search
              }
            },
            {
              whatsappName: {
                contains: search
              }
            },
            {
              phoneNumber: {
                contains: search
              }
            },
            {
              remoteJid: {
                contains: search
              }
            },
            {
              email: {
                contains: search
              }
            }
          ]
        }
      : {})
  };

  const [total, contacts] = await prisma.$transaction([
    prisma.contact.count({
      where
    }),
    prisma.contact.findMany({
      where,
      include: {
        _count: {
          select: {
            tickets: true
          }
        },
        tickets: {
          orderBy: {
            lastMessageAt: "desc"
          },
          take: 1,
          select: {
            id: true,
            status: true,
            lastMessage: true,
            lastMessageAt: true,
            whatsappConnection: {
              select: {
                id: true,
                name: true
              }
            }
          }
        }
      },
      orderBy: {
        updatedAt: "desc"
      },
      skip: (input.page - 1) * input.limit,
      take: input.limit
    })
  ]);

  return {
    contacts,
    pagination: {
      page: input.page,
      limit: input.limit,
      total,
      pages: Math.max(
        1,
        Math.ceil(total / input.limit)
      )
    }
  };
}

export async function getContact(
  companyId: string,
  contactId: string
) {
  const contact = await prisma.contact.findFirst({
    where: {
      id: contactId,
      companyId
    },
    include: {
      tickets: {
        orderBy: {
          lastMessageAt: "desc"
        },
        take: 50,
        include: {
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
          },
          whatsappConnection: {
            select: {
              id: true,
              name: true,
              phoneNumber: true
            }
          }
        }
      }
    }
  });

  if (!contact) {
    throw new AppError(
      "Contato não encontrado.",
      404,
      "CONTACT_NOT_FOUND"
    );
  }

  const [ticketCount, openTicketCount, messageCount] =
    await prisma.$transaction([
      prisma.ticket.count({
        where: {
          companyId,
          contactId
        }
      }),
      prisma.ticket.count({
        where: {
          companyId,
          contactId,
          status: {
            in: ["OPEN", "PENDING"]
          }
        }
      }),
      prisma.message.count({
        where: {
          companyId,
          ticket: {
            contactId
          }
        }
      })
    ]);

  return {
    contact,
    stats: {
      ticketCount,
      openTicketCount,
      messageCount
    }
  };
}

export async function updateContact(input: {
  companyId: string;
  contactId: string;
  name?: string;
  email?: string | null;
  notes?: string | null;
}) {
  const existing = await prisma.contact.findFirst({
    where: {
      id: input.contactId,
      companyId: input.companyId
    },
    select: {
      id: true
    }
  });

  if (!existing) {
    throw new AppError(
      "Contato não encontrado.",
      404,
      "CONTACT_NOT_FOUND"
    );
  }

  return prisma.contact.update({
    where: {
      id: input.contactId
    },
    data: {
      ...(input.name !== undefined
        ? { name: input.name.trim() }
        : {}),
      ...(input.email !== undefined
        ? {
            email:
              input.email?.trim() || null
          }
        : {}),
      ...(input.notes !== undefined
        ? {
            notes:
              input.notes?.trim() || null
          }
        : {})
    }
  });
}
EOF

cat > apps/api/src/modules/contacts/contact.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  getContact,
  listContacts,
  updateContact
} from "./contact.service.js";

const contactIdSchema = z.object({
  id: z.string().uuid()
});

const listSchema = z.object({
  search: z
    .string()
    .trim()
    .max(100)
    .optional(),
  type: z
    .enum(["ALL", "PEOPLE", "GROUPS"])
    .default("ALL"),
  page: z.coerce
    .number()
    .int()
    .positive()
    .default(1),
  limit: z.coerce
    .number()
    .int()
    .min(10)
    .max(100)
    .default(30)
});

const updateSchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(2)
      .max(190)
      .optional(),
    email: z
      .string()
      .trim()
      .email()
      .max(190)
      .nullable()
      .optional(),
    notes: z
      .string()
      .trim()
      .max(10_000)
      .nullable()
      .optional()
  })
  .refine(
    value =>
      value.name !== undefined ||
      value.email !== undefined ||
      value.notes !== undefined,
    {
      message: "Informe ao menos uma alteração."
    }
  );

export async function contactRoutes(
  app: FastifyInstance
) {
  app.get("/api/v1/contacts", async request => {
    const auth = await requirePermission(
      request,
      "contacts.read"
    );

    const query = listSchema.parse(request.query);

    return listContacts({
      companyId: auth.companyId,
      search: query.search,
      type: query.type,
      page: query.page,
      limit: query.limit
    });
  });

  app.get(
    "/api/v1/contacts/:id",
    async request => {
      const auth = await requirePermission(
        request,
        "contacts.read"
      );

      const params = contactIdSchema.parse(
        request.params
      );

      return getContact(
        auth.companyId,
        params.id
      );
    }
  );

  app.patch(
    "/api/v1/contacts/:id",
    async request => {
      const auth = await requirePermission(
        request,
        "contacts.manage"
      );

      const params = contactIdSchema.parse(
        request.params
      );

      const input = updateSchema.parse(
        request.body
      );

      return {
        contact: await updateContact({
          companyId: auth.companyId,
          contactId: params.id,
          ...input
        })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register contact routes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8");

const importLine =
  'import { contactRoutes } from "./modules/contacts/contact.routes.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { authRoutes } from "./modules/auth/auth.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find authRoutes import."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}\n${importLine}`
  );
}

if (!content.includes("await app.register(contactRoutes);")) {
  const anchor =
    "  await app.register(authRoutes);";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find authRoutes registration."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}\n  await app.register(contactRoutes);`
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Frontend permissions
# ---------------------------------------------------------------------------

cat > apps/web/lib/permissions.ts <<'EOF'
import type { Role } from "./auth-types";

export type UiPermission =
  | "dashboard.view"
  | "conversations.view"
  | "contacts.view"
  | "queues.manage"
  | "connections.manage"
  | "team.manage"
  | "admin.test";

const permissionsByRole: Record<
  Role,
  readonly UiPermission[]
> = {
  OWNER: [
    "dashboard.view",
    "conversations.view",
    "contacts.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test"
  ],
  ADMIN: [
    "dashboard.view",
    "conversations.view",
    "contacts.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test"
  ],
  SUPERVISOR: [
    "dashboard.view",
    "conversations.view",
    "contacts.view"
  ],
  AGENT: [
    "dashboard.view",
    "conversations.view",
    "contacts.view"
  ]
};

export function roleCan(
  role: Role,
  permission: UiPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
EOF

cat > apps/web/app/dashboard/contacts/layout.tsx <<'EOF'
"use client";

import type { ReactNode } from "react";

import { AccessGate } from "@/components/access-gate";

export default function ContactsLayout({
  children
}: {
  children: ReactNode;
}) {
  return (
    <AccessGate permission="contacts.view">
      {children}
    </AccessGate>
  );
}
EOF

# ---------------------------------------------------------------------------
# Contacts UI
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/contacts/page.tsx <<'EOF'
"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type ContactFilter =
  | "ALL"
  | "PEOPLE"
  | "GROUPS";

interface TicketSummary {
  id: string;
  status: "OPEN" | "PENDING" | "CLOSED";
  lastMessage: string | null;
  lastMessageAt: string;
  whatsappConnection: {
    id: string;
    name: string;
  };
}

interface ContactSummary {
  id: string;
  name: string;
  whatsappName: string | null;
  email: string | null;
  phoneNumber: string | null;
  remoteJid: string;
  isGroup: boolean;
  lastSeenAt: string | null;
  updatedAt: string;
  _count: {
    tickets: number;
  };
  tickets: TicketSummary[];
}

interface ContactDetail {
  id: string;
  name: string;
  whatsappName: string | null;
  email: string | null;
  notes: string | null;
  phoneNumber: string | null;
  remoteJid: string;
  isGroup: boolean;
  lastSeenAt: string | null;
  createdAt: string;
  updatedAt: string;
  tickets: Array<{
    id: string;
    status: "OPEN" | "PENDING" | "CLOSED";
    lastMessage: string | null;
    lastMessageAt: string;
    closedAt: string | null;
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
    whatsappConnection: {
      id: string;
      name: string;
      phoneNumber: string | null;
    };
  }>;
}

interface ContactStats {
  ticketCount: number;
  openTicketCount: number;
  messageCount: number;
}

interface ContactsResponse {
  contacts: ContactSummary[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

function dateLabel(value: string | null) {
  if (!value) {
    return "—";
  }

  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function initials(name: string) {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map(part =>
      part.slice(0, 1).toUpperCase()
    )
    .join("");
}

export default function ContactsPage() {
  const router = useRouter();
  const {
    session,
    loading,
    request
  } = useAuth();

  const [contacts, setContacts] = useState<
    ContactSummary[]
  >([]);
  const [pagination, setPagination] =
    useState<ContactsResponse["pagination"]>({
      page: 1,
      limit: 30,
      total: 0,
      pages: 1
    });

  const [search, setSearch] = useState("");
  const [filter, setFilter] =
    useState<ContactFilter>("PEOPLE");
  const [page, setPage] = useState(1);

  const [selectedId, setSelectedId] =
    useState<string | null>(null);
  const [detail, setDetail] =
    useState<ContactDetail | null>(null);
  const [stats, setStats] =
    useState<ContactStats | null>(null);

  const [editName, setEditName] = useState("");
  const [editEmail, setEditEmail] = useState("");
  const [editNotes, setEditNotes] = useState("");

  const [loadingList, setLoadingList] =
    useState(false);
  const [loadingDetail, setLoadingDetail] =
    useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const loadContacts = useCallback(async () => {
    setLoadingList(true);

    try {
      const params = new URLSearchParams({
        type: filter,
        page: String(page),
        limit: "30"
      });

      if (search.trim()) {
        params.set("search", search.trim());
      }

      const payload =
        await request<ContactsResponse>(
          `/api/v1/contacts?${params.toString()}`
        );

      setContacts(payload.contacts);
      setPagination(payload.pagination);

      setSelectedId(current => {
        if (
          current &&
          payload.contacts.some(
            contact => contact.id === current
          )
        ) {
          return current;
        }

        return payload.contacts[0]?.id ?? null;
      });
    } catch {
      setError(
        "Não foi possível carregar os contatos."
      );
    } finally {
      setLoadingList(false);
    }
  }, [filter, page, request, search]);

  const loadDetail = useCallback(
    async (contactId: string) => {
      setLoadingDetail(true);

      try {
        const payload = await request<{
          contact: ContactDetail;
          stats: ContactStats;
        }>(
          `/api/v1/contacts/${contactId}`
        );

        setDetail(payload.contact);
        setStats(payload.stats);
        setEditName(payload.contact.name);
        setEditEmail(
          payload.contact.email ?? ""
        );
        setEditNotes(
          payload.contact.notes ?? ""
        );
      } catch {
        setError(
          "Não foi possível carregar o contato."
        );
      } finally {
        setLoadingDetail(false);
      }
    },
    [request]
  );

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
    }
  }, [loading, router, session]);

  useEffect(() => {
    if (!session) {
      return;
    }

    const timer = window.setTimeout(() => {
      void loadContacts();
    }, 250);

    return () => window.clearTimeout(timer);
  }, [loadContacts, session]);

  useEffect(() => {
    if (!selectedId) {
      setDetail(null);
      setStats(null);
      return;
    }

    void loadDetail(selectedId);
  }, [loadDetail, selectedId]);

  async function saveContact(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!detail) {
      return;
    }

    setSaving(true);
    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/contacts/${detail.id}`,
        {
          method: "PATCH",
          body: JSON.stringify({
            name: editName,
            email:
              editEmail.trim() || null,
            notes:
              editNotes.trim() || null
          })
        }
      );

      setNotice("Contato atualizado.");

      await Promise.all([
        loadContacts(),
        loadDetail(detail.id)
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar o contato."
      );
    } finally {
      setSaving(false);
    }
  }

  if (loading || !session) {
    return (
      <main className="dashboard-loading">
        Carregando contatos…
      </main>
    );
  }

  return (
    <main className="contacts-screen">
      <header className="contacts-header">
        <div>
          <button
            className="connections-back"
            onClick={() =>
              router.push("/dashboard")
            }
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">
            Relacionamento
          </span>
          <h1>Contatos</h1>
          <p>
            Pessoas e grupos que já interagiram
            com os canais da empresa.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              "/dashboard/conversations"
            )
          }
          type="button"
        >
          Conversas
        </button>
      </header>

      {error && (
        <div className="contacts-feedback contacts-feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="contacts-feedback">
          {notice}
        </div>
      )}

      <section className="contacts-toolbar">
        <input
          onChange={event => {
            setSearch(event.target.value);
            setPage(1);
          }}
          placeholder="Buscar por nome, número ou e-mail…"
          value={search}
        />

        <div className="contacts-filter">
          {(
            [
              ["PEOPLE", "Pessoas"],
              ["GROUPS", "Grupos"],
              ["ALL", "Todos"]
            ] as const
          ).map(([value, label]) => (
            <button
              className={
                filter === value
                  ? "contacts-filter__button contacts-filter__button--active"
                  : "contacts-filter__button"
              }
              key={value}
              onClick={() => {
                setFilter(value);
                setPage(1);
              }}
              type="button"
            >
              {label}
            </button>
          ))}
        </div>

        <span className="contacts-total">
          {pagination.total} registros
        </span>
      </section>

      <section className="contacts-workspace">
        <aside className="contacts-list">
          {loadingList ? (
            <div className="contacts-empty">
              Carregando…
            </div>
          ) : contacts.length === 0 ? (
            <div className="contacts-empty">
              Nenhum contato encontrado.
            </div>
          ) : (
            contacts.map(contact => (
              <button
                className={
                  selectedId === contact.id
                    ? "contact-row contact-row--active"
                    : "contact-row"
                }
                key={contact.id}
                onClick={() =>
                  setSelectedId(contact.id)
                }
                type="button"
              >
                <div className="contact-row__avatar">
                  {initials(contact.name)}
                </div>

                <div className="contact-row__copy">
                  <strong>{contact.name}</strong>
                  <span>
                    {contact.phoneNumber ??
                      contact.remoteJid}
                  </span>
                  <small>
                    {contact._count.tickets}
                    {" "}
                    atendimento(s)
                  </small>
                </div>

                <div className="contact-row__meta">
                  {contact.isGroup && (
                    <span>Grupo</span>
                  )}
                  <time>
                    {dateLabel(
                      contact.lastSeenAt
                    )}
                  </time>
                </div>
              </button>
            ))
          )}

          {pagination.pages > 1 && (
            <div className="contacts-pagination">
              <button
                className="ghost-button"
                disabled={page <= 1}
                onClick={() =>
                  setPage(current =>
                    Math.max(1, current - 1)
                  )
                }
                type="button"
              >
                Anterior
              </button>

              <span>
                {pagination.page} /{" "}
                {pagination.pages}
              </span>

              <button
                className="ghost-button"
                disabled={
                  page >= pagination.pages
                }
                onClick={() =>
                  setPage(current =>
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
            </div>
          )}
        </aside>

        <section className="contact-profile">
          {!selectedId ? (
            <div className="contact-profile__empty">
              Selecione um contato.
            </div>
          ) : loadingDetail || !detail ? (
            <div className="contact-profile__empty">
              Carregando ficha…
            </div>
          ) : (
            <>
              <header className="contact-profile__header">
                <div className="contact-profile__identity">
                  <div className="contact-profile__avatar">
                    {initials(detail.name)}
                  </div>
                  <div>
                    <span className="eyebrow">
                      {detail.isGroup
                        ? "Grupo"
                        : "Contato"}
                    </span>
                    <h2>{detail.name}</h2>
                    <p>
                      {detail.phoneNumber ??
                        detail.remoteJid}
                    </p>
                  </div>
                </div>

                {detail.whatsappName &&
                  detail.whatsappName !==
                    detail.name && (
                    <span className="contact-profile__whatsapp-name">
                      WhatsApp:{" "}
                      {detail.whatsappName}
                    </span>
                  )}
              </header>

              <div className="contact-stats">
                <article>
                  <strong>
                    {stats?.ticketCount ?? 0}
                  </strong>
                  <span>Atendimentos</span>
                </article>
                <article>
                  <strong>
                    {stats?.openTicketCount ?? 0}
                  </strong>
                  <span>Ativos</span>
                </article>
                <article>
                  <strong>
                    {stats?.messageCount ?? 0}
                  </strong>
                  <span>Mensagens</span>
                </article>
              </div>

              <form
                className="contact-form"
                onSubmit={saveContact}
              >
                <div className="contact-form__grid">
                  <label className="field">
                    <span>Nome no Wapp</span>
                    <input
                      maxLength={190}
                      onChange={event =>
                        setEditName(
                          event.target.value
                        )
                      }
                      required
                      value={editName}
                    />
                  </label>

                  <label className="field">
                    <span>E-mail</span>
                    <input
                      maxLength={190}
                      onChange={event =>
                        setEditEmail(
                          event.target.value
                        )
                      }
                      placeholder="Opcional"
                      type="email"
                      value={editEmail}
                    />
                  </label>
                </div>

                <label className="field">
                  <span>Anotações</span>
                  <textarea
                    maxLength={10_000}
                    onChange={event =>
                      setEditNotes(
                        event.target.value
                      )
                    }
                    placeholder="Contexto importante sobre este contato…"
                    rows={4}
                    value={editNotes}
                  />
                </label>

                <div className="contact-form__footer">
                  <div>
                    <span>
                      Última interação
                    </span>
                    <strong>
                      {dateLabel(
                        detail.lastSeenAt
                      )}
                    </strong>
                  </div>

                  <button
                    className="primary-button"
                    disabled={saving}
                    type="submit"
                  >
                    <span>
                      {saving
                        ? "Salvando…"
                        : "Salvar contato"}
                    </span>
                    <span>→</span>
                  </button>
                </div>
              </form>

              <section className="contact-history">
                <div className="contact-history__heading">
                  <span className="eyebrow">
                    Histórico
                  </span>
                  <h3>Atendimentos recentes</h3>
                </div>

                {detail.tickets.length === 0 ? (
                  <p className="contact-history__empty">
                    Nenhum atendimento registrado.
                  </p>
                ) : (
                  <div className="contact-history__list">
                    {detail.tickets.map(ticket => (
                      <article
                        className="contact-ticket"
                        key={ticket.id}
                      >
                        <div>
                          <strong>
                            {ticket.lastMessage ??
                              "Atendimento"}
                          </strong>
                          <span>
                            {ticket.whatsappConnection.name}
                            {" · "}
                            {ticket.queue?.name ??
                              "Sem fila"}
                          </span>
                        </div>

                        <div className="contact-ticket__right">
                          <span
                            className={`contact-ticket__status contact-ticket__status--${ticket.status.toLowerCase()}`}
                          >
                            {ticket.status}
                          </span>
                          <time>
                            {dateLabel(
                              ticket.lastMessageAt
                            )}
                          </time>
                        </div>
                      </article>
                    ))}
                  </div>
                )}
              </section>
            </>
          )}
        </section>
      </section>
    </main>
  );
}
EOF

# ---------------------------------------------------------------------------
# Dashboard navigation
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/web/app/dashboard/page.tsx";
let content = fs.readFileSync(path, "utf8");

if (
  content.includes(
    'permission: "conversations.view"'
  ) &&
  !content.includes(
    'permission: "contacts.view"'
  )
) {
  const conversationEntry = `  {
    label: "Conversas",
    href: "/dashboard/conversations",
    permission: "conversations.view"
  },`;

  const contactsEntry = `${conversationEntry}
  {
    label: "Contatos",
    href: "/dashboard/contacts",
    permission: "contacts.view"
  },`;

  if (!content.includes(conversationEntry)) {
    throw new Error(
      "Could not find P0.9 navigation structure."
    );
  }

  content = content.replace(
    conversationEntry,
    contactsEntry
  );
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# UI styles
# ---------------------------------------------------------------------------

cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.1 / Contacts ---------------------------------------------- */

.contacts-screen {
  min-height: 100vh;
  background: var(--background);
  padding: 42px clamp(18px, 4vw, 60px) 70px;
}

.contacts-header,
.contacts-toolbar,
.contacts-workspace,
.contacts-feedback {
  max-width: 1380px;
  margin-left: auto;
  margin-right: auto;
}

.contacts-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 28px;
  margin-bottom: 22px;
}

.contacts-header h1 {
  margin: 8px 0 10px;
  font-size: clamp(42px, 6vw, 64px);
  font-weight: 640;
  letter-spacing: -0.055em;
  line-height: 1;
}

.contacts-header p {
  max-width: 620px;
  margin: 0;
  color: var(--muted);
  line-height: 1.6;
}

.contacts-feedback {
  margin-bottom: 10px;
  border-radius: 10px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 11px 13px;
  font-size: 11px;
}

.contacts-feedback--error {
  background: var(--danger-soft);
  color: var(--danger);
}

.contacts-toolbar {
  display: grid;
  grid-template-columns: minmax(240px, 1fr) auto auto;
  align-items: center;
  gap: 12px;
  border: 1px solid var(--line);
  border-radius: 16px;
  background: white;
  padding: 12px;
}

.contacts-toolbar > input {
  height: 44px;
  border: 1px solid var(--line);
  border-radius: 10px;
  outline: none;
  background: var(--surface-subtle);
  padding: 0 13px;
  font-size: 11px;
}

.contacts-toolbar > input:focus {
  border-color: var(--accent);
  background: white;
}

.contacts-filter {
  display: flex;
  gap: 5px;
}

.contacts-filter__button {
  height: 36px;
  border: 0;
  border-radius: 9px;
  background: transparent;
  color: var(--muted);
  padding: 0 11px;
  font-size: 10px;
  font-weight: 700;
}

.contacts-filter__button--active {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.contacts-total {
  color: var(--muted);
  font-size: 10px;
  white-space: nowrap;
}

.contacts-workspace {
  display: grid;
  min-height: 650px;
  grid-template-columns: minmax(310px, 390px) 1fr;
  overflow: hidden;
  margin-top: 14px;
  border: 1px solid var(--line);
  border-radius: 18px;
  background: white;
}

.contacts-list {
  min-width: 0;
  border-right: 1px solid var(--line);
  background: #fbfcfa;
}

.contact-row {
  display: grid;
  width: 100%;
  grid-template-columns: 42px minmax(0, 1fr) auto;
  align-items: center;
  gap: 11px;
  border: 0;
  border-bottom: 1px solid #edf0ed;
  background: transparent;
  padding: 13px 14px;
  text-align: left;
}

.contact-row:hover,
.contact-row--active {
  background: #eef4ef;
}

.contact-row__avatar,
.contact-profile__avatar {
  display: grid;
  place-items: center;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-weight: 800;
}

.contact-row__avatar {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  font-size: 10px;
}

.contact-row__copy {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.contact-row__copy strong,
.contact-row__copy span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.contact-row__copy strong {
  font-size: 11px;
}

.contact-row__copy span {
  color: var(--muted);
  font-size: 9px;
}

.contact-row__copy small {
  color: #9aa19c;
  font-size: 8px;
}

.contact-row__meta {
  display: grid;
  justify-items: end;
  gap: 5px;
  color: #9aa19c;
  font-size: 8px;
}

.contact-row__meta > span {
  border-radius: 999px;
  background: #eceeed;
  padding: 4px 6px;
}

.contacts-empty,
.contact-profile__empty {
  display: grid;
  min-height: 220px;
  place-items: center;
  color: var(--muted);
  font-size: 11px;
}

.contacts-pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 14px;
}

.contacts-pagination span {
  color: var(--muted);
  font-size: 9px;
}

.contact-profile {
  min-width: 0;
  padding: 30px;
}

.contact-profile__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 24px;
}

.contact-profile__identity {
  display: flex;
  align-items: center;
  gap: 15px;
}

.contact-profile__avatar {
  width: 58px;
  height: 58px;
  border-radius: 17px;
  font-size: 14px;
}

.contact-profile__identity h2 {
  margin: 5px 0 4px;
  font-size: 26px;
  letter-spacing: -0.04em;
}

.contact-profile__identity p {
  margin: 0;
  color: var(--muted);
  font-size: 10px;
}

.contact-profile__whatsapp-name {
  border-radius: 999px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 7px 10px;
  font-size: 9px;
}

.contact-stats {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
  margin: 24px 0;
}

.contact-stats article {
  display: grid;
  gap: 5px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: var(--surface-subtle);
  padding: 14px;
}

.contact-stats strong {
  font-size: 20px;
}

.contact-stats span {
  color: var(--muted);
  font-size: 9px;
}

.contact-form {
  display: grid;
  gap: 14px;
  border: 1px solid var(--line);
  border-radius: 15px;
  padding: 18px;
}

.contact-form__grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.contact-form textarea {
  width: 100%;
  resize: vertical;
  border: 1px solid var(--line);
  border-radius: 12px;
  outline: none;
  background: var(--surface-subtle);
  padding: 12px 13px;
  font: inherit;
  font-size: 11px;
  line-height: 1.55;
}

.contact-form textarea:focus {
  border-color: var(--accent);
  background: white;
}

.contact-form__footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
}

.contact-form__footer > div {
  display: grid;
  gap: 3px;
}

.contact-form__footer > div span {
  color: var(--muted);
  font-size: 8px;
}

.contact-form__footer > div strong {
  font-size: 10px;
}

.contact-form__footer .primary-button {
  width: 170px;
  height: 44px;
  margin: 0;
}

.contact-history {
  margin-top: 22px;
}

.contact-history__heading h3 {
  margin: 6px 0 14px;
  font-size: 17px;
}

.contact-history__list {
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 14px;
}

.contact-ticket {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  border-bottom: 1px solid var(--line);
  padding: 13px 14px;
}

.contact-ticket:last-child {
  border-bottom: 0;
}

.contact-ticket > div:first-child {
  display: grid;
  min-width: 0;
  gap: 4px;
}

.contact-ticket strong {
  overflow: hidden;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.contact-ticket span,
.contact-ticket time {
  color: var(--muted);
  font-size: 8px;
}

.contact-ticket__right {
  display: grid;
  flex: 0 0 auto;
  justify-items: end;
  gap: 5px;
}

.contact-ticket__status {
  border-radius: 999px;
  padding: 4px 7px;
  font-weight: 800;
}

.contact-ticket__status--open {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.contact-ticket__status--pending {
  background: #f2eee2;
  color: #76632b;
}

.contact-ticket__status--closed {
  background: #eceeed;
  color: #66706a;
}

.contact-history__empty {
  color: var(--muted);
  font-size: 10px;
}

@media (max-width: 900px) {
  .contacts-toolbar {
    grid-template-columns: 1fr;
  }

  .contacts-workspace {
    grid-template-columns: 160px 1fr;
  }

  .contact-row {
    grid-template-columns: 36px 1fr;
  }

  .contact-row__meta {
    display: none;
  }

  .contact-row__avatar {
    width: 34px;
    height: 34px;
  }

  .contact-form__grid,
  .contact-stats {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 650px) {
  .contacts-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .contacts-workspace {
    grid-template-columns: 120px 1fr;
  }

  .contact-profile {
    padding: 18px 14px;
  }

  .contact-profile__header,
  .contact-form__footer {
    align-items: flex-start;
    flex-direction: column;
  }

  .contact-profile__whatsapp-name {
    display: none;
  }
}
EOF

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/CONTACTS.md <<'EOF'
# Contacts

P1.1 turns the automatically-created WhatsApp contact into an application
profile.

## Name ownership

`Contact.name` is the display name chosen inside Wapp.

`Contact.whatsappName` is the latest push name received from WhatsApp.

Incoming messages may refresh `whatsappName`, but must never overwrite a name
that an operator edited in Wapp.

## Profile fields

- name
- whatsappName
- phoneNumber
- email
- notes
- lastSeenAt
- isGroup

## Search

Contacts can be searched by:

- Wapp name
- WhatsApp name
- phone
- remoteJid
- email

and filtered between people, groups or all contacts.

## History

The profile exposes recent tickets and aggregate counts for tickets, active
tickets and messages.

P1.1 intentionally does not create contacts manually or initiate new outbound
conversations. That requires choosing a WhatsApp connection and validating the
destination and belongs in a later contacts milestone.
EOF

echo "[P1.1] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.1] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.1] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.1] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.1] Contacts foundation created."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name contact_profiles"
echo "  pnpm dev"
echo
echo "Open:"
echo "  http://localhost:3000/dashboard/contacts"
