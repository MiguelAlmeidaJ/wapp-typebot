#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.7] Building shared quick replies..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/security/permissions.ts" \
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
  apps/api/src/modules/quick-replies \
  docs

# ---------------------------------------------------------------------------
# Prisma
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

if (!schema.includes("quickReplies")) {
  schema = schema.replace(
    `  messages            Message[]
  ticketNotes`,
    `  messages            Message[]
  quickReplies         QuickReply[]
  ticketNotes`
  );
}

if (!schema.includes("createdQuickReplies")) {
  schema = schema.replace(
    `  assignedTickets  Ticket[]
  ticketNotes`,
    `  assignedTickets     Ticket[]
  createdQuickReplies QuickReply[]
  ticketNotes`
  );
}

if (!schema.includes("model QuickReply {")) {
  const anchor = "model TicketNote {";

  if (!schema.includes(anchor)) {
    throw new Error(
      "TicketNote model not found. P1.7 expects P1.6 to be applied."
    );
  }

  const model = `model QuickReply {
  id                    String             @id @default(uuid()) @db.Char(36)
  companyId             String             @db.Char(36)
  createdByMembershipId String?            @db.Char(36)
  shortcut              String             @db.VarChar(50)
  title                 String             @db.VarChar(160)
  body                  String             @db.Text
  isActive              Boolean            @default(true)
  company               Company            @relation(fields: [companyId], references: [id], onDelete: Cascade)
  createdByMembership   CompanyMembership? @relation(fields: [createdByMembershipId], references: [id], onDelete: SetNull)
  createdAt             DateTime           @default(now())
  updatedAt             DateTime           @updatedAt

  @@unique([companyId, shortcut])
  @@index([companyId, isActive, title])
  @@index([createdByMembershipId])
}

`;

  schema = schema.replace(
    anchor,
    `${model}${anchor}`
  );
}

fs.writeFileSync(path, schema);
console.log("QuickReply schema installed.");
NODE

# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/security/permissions.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes('"quickReplies.read"')) {
  content = content.replace(
    `  | "contacts.manage"`,
    `  | "contacts.manage"
  | "quickReplies.read"
  | "quickReplies.manage"`
  );
}

/*
 * OWNER and ADMIN: read + manage.
 */
for (const role of ["OWNER", "ADMIN"]) {
  const roleAnchor = `${role}: [`;
  const start = content.indexOf(roleAnchor);

  if (start < 0) {
    throw new Error(`Role block ${role} not found.`);
  }

  const end = content.indexOf("  ],", start);
  const block = content.slice(start, end);

  if (!block.includes('"quickReplies.read"')) {
    const insertAt =
      content.indexOf(
        '"contacts.manage",',
        start
      );

    if (
      insertAt < 0 ||
      insertAt > end
    ) {
      throw new Error(
        `contacts.manage not found in ${role}.`
      );
    }

    const after =
      insertAt +
      '"contacts.manage",'.length;

    content =
      content.slice(0, after) +
      `
    "quickReplies.read",
    "quickReplies.manage",` +
      content.slice(after);
  }
}

/*
 * SUPERVISOR: read + manage.
 */
{
  const start =
    content.indexOf("SUPERVISOR: [");
  const end =
    content.indexOf("  ],", start);
  const block =
    content.slice(start, end);

  if (!block.includes('"quickReplies.read"')) {
    const insertAt =
      content.indexOf(
        '"contacts.manage",',
        start
      );

    if (
      insertAt < 0 ||
      insertAt > end
    ) {
      throw new Error(
        "contacts.manage not found in SUPERVISOR."
      );
    }

    const after =
      insertAt +
      '"contacts.manage",'.length;

    content =
      content.slice(0, after) +
      `
    "quickReplies.read",
    "quickReplies.manage",` +
      content.slice(after);
  }
}

/*
 * AGENT: read only.
 */
{
  const start =
    content.indexOf("AGENT: [");
  const end =
    content.indexOf("  ]", start);
  const block =
    content.slice(start, end);

  if (!block.includes('"quickReplies.read"')) {
    const insertAt =
      content.indexOf(
        '"contacts.manage",',
        start
      );

    if (
      insertAt < 0 ||
      insertAt > end
    ) {
      throw new Error(
        "contacts.manage not found in AGENT."
      );
    }

    const after =
      insertAt +
      '"contacts.manage",'.length;

    content =
      content.slice(0, after) +
      `
    "quickReplies.read",` +
      content.slice(after);
  }
}

fs.writeFileSync(path, content);
console.log("Quick reply permissions installed.");
NODE

# ---------------------------------------------------------------------------
# Backend service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/quick-replies/quick-reply.service.ts <<'EOF'
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

function normalizeShortcut(
  value: string
) {
  return value
    .trim()
    .toLowerCase()
    .replace(/^\/+/, "");
}

async function assertShortcutAvailable(input: {
  companyId: string;
  shortcut: string;
  excludeId?: string;
}) {
  const existing =
    await prisma.quickReply.findFirst({
      where: {
        companyId: input.companyId,
        shortcut: input.shortcut,
        ...(input.excludeId
          ? {
              id: {
                not: input.excludeId
              }
            }
          : {})
      },
      select: {
        id: true
      }
    });

  if (existing) {
    throw new AppError(
      `O atalho /${input.shortcut} já está em uso.`,
      409,
      "QUICK_REPLY_SHORTCUT_IN_USE"
    );
  }
}

export async function listQuickReplies(input: {
  companyId: string;
  search?: string;
  includeInactive?: boolean;
}) {
  const search = input.search?.trim();

  return prisma.quickReply.findMany({
    where: {
      companyId: input.companyId,
      ...(input.includeInactive
        ? {}
        : {
            isActive: true
          }),
      ...(search
        ? {
            OR: [
              {
                shortcut: {
                  contains:
                    normalizeShortcut(
                      search
                    )
                }
              },
              {
                title: {
                  contains: search
                }
              },
              {
                body: {
                  contains: search
                }
              }
            ]
          }
        : {})
    },
    include: {
      createdByMembership: {
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
    },
    orderBy: [
      {
        isActive: "desc"
      },
      {
        title: "asc"
      }
    ],
    take: 300
  });
}

export async function createQuickReply(input: {
  companyId: string;
  membershipId: string;
  shortcut: string;
  title: string;
  body: string;
}) {
  const shortcut =
    normalizeShortcut(
      input.shortcut
    );

  await assertShortcutAvailable({
    companyId: input.companyId,
    shortcut
  });

  const quickReply =
    await prisma.quickReply.create({
      data: {
        companyId:
          input.companyId,
        createdByMembershipId:
          input.membershipId,
        shortcut,
        title:
          input.title.trim(),
        body:
          input.body.trim()
      },
      include: {
        createdByMembership: {
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
    });

  publishRealtime(
    input.companyId,
    {
      type: "quick-reply.updated",
      quickReplyId:
        quickReply.id
    }
  );

  return quickReply;
}

export async function updateQuickReply(input: {
  companyId: string;
  quickReplyId: string;
  shortcut?: string;
  title?: string;
  body?: string;
  isActive?: boolean;
}) {
  const existing =
    await prisma.quickReply.findFirst({
      where: {
        id: input.quickReplyId,
        companyId: input.companyId
      }
    });

  if (!existing) {
    throw new AppError(
      "Resposta rápida não encontrada.",
      404,
      "QUICK_REPLY_NOT_FOUND"
    );
  }

  const shortcut =
    input.shortcut !== undefined
      ? normalizeShortcut(
          input.shortcut
        )
      : undefined;

  if (
    shortcut !== undefined &&
    shortcut !== existing.shortcut
  ) {
    await assertShortcutAvailable({
      companyId:
        input.companyId,
      shortcut,
      excludeId:
        existing.id
    });
  }

  const quickReply =
    await prisma.quickReply.update({
      where: {
        id: existing.id
      },
      data: {
        ...(shortcut !== undefined
          ? { shortcut }
          : {}),
        ...(input.title !== undefined
          ? {
              title:
                input.title.trim()
            }
          : {}),
        ...(input.body !== undefined
          ? {
              body:
                input.body.trim()
            }
          : {}),
        ...(input.isActive !== undefined
          ? {
              isActive:
                input.isActive
            }
          : {})
      },
      include: {
        createdByMembership: {
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
    });

  publishRealtime(
    input.companyId,
    {
      type: "quick-reply.updated",
      quickReplyId:
        quickReply.id
    }
  );

  return quickReply;
}
EOF

# ---------------------------------------------------------------------------
# Backend routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/quick-replies/quick-reply.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  createQuickReply,
  listQuickReplies,
  updateQuickReply
} from "./quick-reply.service.js";

const shortcutSchema = z
  .string()
  .trim()
  .transform(value =>
    value.replace(/^\/+/, "")
  )
  .pipe(
    z
      .string()
      .min(1)
      .max(50)
      .regex(
        /^[a-zA-Z0-9][a-zA-Z0-9_-]*$/,
        "Use apenas letras, números, hífen ou underline no atalho."
      )
  );

const listSchema = z.object({
  search: z
    .string()
    .trim()
    .max(160)
    .optional()
});

const idSchema = z.object({
  id: z.string().uuid()
});

const createSchema = z.object({
  shortcut: shortcutSchema,
  title: z
    .string()
    .trim()
    .min(2)
    .max(160),
  body: z
    .string()
    .trim()
    .min(1)
    .max(10_000)
});

const updateSchema = z
  .object({
    shortcut:
      shortcutSchema.optional(),
    title: z
      .string()
      .trim()
      .min(2)
      .max(160)
      .optional(),
    body: z
      .string()
      .trim()
      .min(1)
      .max(10_000)
      .optional(),
    isActive:
      z.boolean().optional()
  })
  .refine(
    value =>
      value.shortcut !== undefined ||
      value.title !== undefined ||
      value.body !== undefined ||
      value.isActive !== undefined,
    {
      message:
        "Informe ao menos uma alteração."
    }
  );

export async function quickReplyRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/quick-replies",
    async request => {
      const auth =
        await requirePermission(
          request,
          "quickReplies.read"
        );

      const query =
        listSchema.parse(
          request.query
        );

      return {
        quickReplies:
          await listQuickReplies({
            companyId:
              auth.companyId,
            search:
              query.search,
            includeInactive:
              false
          })
      };
    }
  );

  app.get(
    "/api/v1/quick-replies/manage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "quickReplies.manage"
        );

      const query =
        listSchema.parse(
          request.query
        );

      return {
        quickReplies:
          await listQuickReplies({
            companyId:
              auth.companyId,
            search:
              query.search,
            includeInactive:
              true
          })
      };
    }
  );

  app.post(
    "/api/v1/quick-replies",
    async (request, reply) => {
      const auth =
        await requirePermission(
          request,
          "quickReplies.manage"
        );

      const input =
        createSchema.parse(
          request.body
        );

      return reply
        .status(201)
        .send({
          quickReply:
            await createQuickReply({
              companyId:
                auth.companyId,
              membershipId:
                auth.membershipId,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/quick-replies/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "quickReplies.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        updateSchema.parse(
          request.body
        );

      return {
        quickReply:
          await updateQuickReply({
            companyId:
              auth.companyId,
            quickReplyId:
              params.id,
            ...input
          })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register routes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8");

const importLine =
  'import { quickReplyRoutes } from "./modules/quick-replies/quick-reply.routes.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { queueRoutes } from "./modules/queues/queue.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find queueRoutes import."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (!content.includes("await app.register(quickReplyRoutes);")) {
  const anchor =
    "  await app.register(queueRoutes);";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find queueRoutes registration."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  await app.register(quickReplyRoutes);`
  );
}

fs.writeFileSync(path, content);
console.log("Quick reply routes registered.");
NODE

# ---------------------------------------------------------------------------
# Realtime
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
    content.includes('| "note.created"') &&
    !content.includes(
      '| "quick-reply.updated"'
    )
  ) {
    content = content.replace(
      '| "note.created"',
      '| "note.created"\n  | "quick-reply.updated"'
    );
  }

  if (
    content.includes("noteId?: string;") &&
    !content.includes(
      "quickReplyId?: string;"
    )
  ) {
    content = content.replace(
      "noteId?: string;",
      "noteId?: string;\n  quickReplyId?: string;"
    );
  }

  fs.writeFileSync(
    path,
    content
  );
}

console.log("quick-reply.updated realtime installed.");
NODE

# ---------------------------------------------------------------------------
# Frontend types/state/helpers
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("interface QuickReply {")) {
  const anchor =
    "interface TicketNote {";

  if (!content.includes(anchor)) {
    throw new Error(
      "TicketNote interface not found. P1.7 expects P1.6."
    );
  }

  const types = `interface QuickReply {
  id: string;
  shortcut: string;
  title: string;
  body: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
  createdByMembership: {
    id: string;
    user: {
      id: string;
      name: string;
    };
  } | null;
}

interface QuickRepliesResponse {
  quickReplies: QuickReply[];
}

`;

  content = content.replace(
    anchor,
    `${types}${anchor}`
  );
}

if (!content.includes("function expandQuickReply(")) {
  const anchor =
    "function ticketPreview(ticket: Ticket) {";

  if (!content.includes(anchor)) {
    throw new Error(
      "ticketPreview helper not found."
    );
  }

  const helper = `function expandQuickReply(
  body: string,
  context: {
    contactName: string;
    agentName: string;
    companyName: string;
  }
) {
  const firstName =
    context.contactName
      .trim()
      .split(/\\s+/)[0] ??
    context.contactName;

  const variables: Record<string, string> = {
    "{{nome}}":
      context.contactName,
    "{{primeiro_nome}}":
      firstName,
    "{{atendente}}":
      context.agentName,
    "{{empresa}}":
      context.companyName
  };

  return Object.entries(
    variables
  ).reduce(
    (result, [token, value]) =>
      result.split(token).join(value),
    body
  );
}

`;

  content = content.replace(
    anchor,
    `${helper}${anchor}`
  );
}

if (!content.includes("const [quickReplies, setQuickReplies]")) {
  const anchor =
    '  const [notes, setNotes] = useState<TicketNote[]>([]);';

  if (!content.includes(anchor)) {
    throw new Error(
      "P1.6 notes state not found."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [quickReplies, setQuickReplies] =
    useState<QuickReply[]>([]);
  const [managedQuickReplies, setManagedQuickReplies] =
    useState<QuickReply[]>([]);
  const [quickRepliesOpen, setQuickRepliesOpen] =
    useState(false);
  const [quickReplyManagerOpen, setQuickReplyManagerOpen] =
    useState(false);
  const [quickReplySearch, setQuickReplySearch] =
    useState("");
  const [quickReplyShortcut, setQuickReplyShortcut] =
    useState("");
  const [quickReplyTitle, setQuickReplyTitle] =
    useState("");
  const [quickReplyBody, setQuickReplyBody] =
    useState("");
  const [editingQuickReplyId, setEditingQuickReplyId] =
    useState<string | null>(null);
  const [savingQuickReply, setSavingQuickReply] =
    useState(false);`
  );
}

if (!content.includes("const composerTextRef =")) {
  const anchor =
    `  const attachmentInputRef =
    useRef<HTMLInputElement | null>(null);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "attachmentInputRef not found."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const composerTextRef =
    useRef<HTMLTextAreaElement | null>(null);`
  );
}

/*
 * Management rights in UI mirror API.
 */
if (!content.includes("const canManageQuickReplies =")) {
  const anchor =
    `  const selectedTicket = useMemo(`;

  if (!content.includes(anchor)) {
    throw new Error(
      "selectedTicket memo not found."
    );
  }

  const computed = `  const canManageQuickReplies =
    session
      ? ["OWNER", "ADMIN", "SUPERVISOR"].includes(
          session.role
        )
      : false;

`;

  content = content.replace(
    anchor,
    `${computed}${anchor}`
  );
}

/*
 * Derived visible palette.
 */
if (!content.includes("const filteredQuickReplies = useMemo(")) {
  const anchor =
    `  const hasPendingMedia = messages.some(`;

  if (!content.includes(anchor)) {
    throw new Error(
      "hasPendingMedia anchor not found."
    );
  }

  const memo = `  const filteredQuickReplies = useMemo(() => {
    const slashQuery =
      text.startsWith("/")
        ? text.slice(1).trim()
        : "";

    const query =
      (
        slashQuery ||
        quickReplySearch
      )
        .toLowerCase()
        .trim();

    return quickReplies
      .filter(reply =>
        reply.isActive
      )
      .filter(reply => {
        if (!query) {
          return true;
        }

        return (
          reply.shortcut
            .toLowerCase()
            .includes(query) ||
          reply.title
            .toLowerCase()
            .includes(query) ||
          reply.body
            .toLowerCase()
            .includes(query)
        );
      })
      .slice(0, 12);
  }, [
    quickReplies,
    quickReplySearch,
    text
  ]);

`;

  content = content.replace(
    anchor,
    `${memo}${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Quick reply frontend types/state/helpers installed.");
NODE

# ---------------------------------------------------------------------------
# Frontend loaders + realtime
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("const loadQuickReplies = useCallback(")) {
  const anchor =
    `  const loadNotes = useCallback(`;

  if (!content.includes(anchor)) {
    throw new Error(
      "loadNotes callback not found."
    );
  }

  const callbacks = `  const loadQuickReplies = useCallback(
    async () => {
      const payload =
        await request<QuickRepliesResponse>(
          "/api/v1/quick-replies"
        );

      setQuickReplies(
        payload.quickReplies
      );
    },
    [request]
  );

  const loadManagedQuickReplies = useCallback(
    async () => {
      if (!canManageQuickReplies) {
        setManagedQuickReplies([]);
        return;
      }

      const payload =
        await request<QuickRepliesResponse>(
          "/api/v1/quick-replies/manage"
        );

      setManagedQuickReplies(
        payload.quickReplies
      );
    },
    [
      canManageQuickReplies,
      request
    ]
  );

`;

  content = content.replace(
    anchor,
    `${callbacks}${anchor}`
  );
}

/*
 * Initial load.
 */
const initialOld =
  `void Promise.all([loadTickets(), loadReferenceData()]).catch(() => {`;

if (
  content.includes(initialOld) &&
  !content.includes(
    "loadQuickReplies()"
  )
) {
  content = content.replace(
    initialOld,
    `void Promise.all([
        loadTickets(),
        loadReferenceData(),
        loadQuickReplies()
      ]).catch(() => {`
  );

  content = content.replace(
    `  }, [loadReferenceData, loadTickets, loading, router, session]);`,
    `  }, [
    loadQuickReplies,
    loadReferenceData,
    loadTickets,
    loading,
    router,
    session
  ]);`
  );
}

/*
 * Realtime refresh.
 */
if (
  content.includes(
    'event.type === "note.created"'
  ) &&
  !content.includes(
    'event.type === "quick-reply.updated"'
  )
) {
  const anchor =
    `      if (event.type === "queue.updated") {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "queue.updated block not found."
    );
  }

  const update = `      if (
        event.type === "quick-reply.updated"
      ) {
        void loadQuickReplies();

        if (canManageQuickReplies) {
          void loadManagedQuickReplies();
        }
      }

`;

  content = content.replace(
    anchor,
    `${update}${anchor}`
  );

  content = content.replace(
    `    loadMessages,
    loadNotes,`,
    `    canManageQuickReplies,
    loadManagedQuickReplies,
    loadMessages,
    loadNotes,
    loadQuickReplies,`
  );
}

fs.writeFileSync(path, content);
console.log("Quick reply loaders/realtime installed.");
NODE

# ---------------------------------------------------------------------------
# Frontend actions
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("function selectQuickReply(")) {
  const anchor =
    "  async function handleCreateNote(";

  if (!content.includes(anchor)) {
    throw new Error(
      "handleCreateNote anchor not found."
    );
  }

  const actions = `  function selectQuickReply(
    reply: QuickReply
  ) {
    if (
      !selectedTicket ||
      !session
    ) {
      return;
    }

    const expanded =
      expandQuickReply(
        reply.body,
        {
          contactName:
            selectedTicket.contact.name,
          agentName:
            session.user.name,
          companyName:
            session.company.name
        }
      );

    setText(expanded);
    setQuickRepliesOpen(false);
    setQuickReplySearch("");

    window.setTimeout(() => {
      composerTextRef.current?.focus();
      composerTextRef.current?.setSelectionRange(
        expanded.length,
        expanded.length
      );
    }, 0);
  }

  function resetQuickReplyForm() {
    setEditingQuickReplyId(null);
    setQuickReplyShortcut("");
    setQuickReplyTitle("");
    setQuickReplyBody("");
  }

  function editQuickReply(
    reply: QuickReply
  ) {
    setEditingQuickReplyId(
      reply.id
    );
    setQuickReplyShortcut(
      reply.shortcut
    );
    setQuickReplyTitle(
      reply.title
    );
    setQuickReplyBody(
      reply.body
    );
  }

  async function saveQuickReply(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !canManageQuickReplies ||
      !quickReplyShortcut.trim() ||
      !quickReplyTitle.trim() ||
      !quickReplyBody.trim()
    ) {
      return;
    }

    setSavingQuickReply(true);
    setError("");

    try {
      const payload = {
        shortcut:
          quickReplyShortcut.trim(),
        title:
          quickReplyTitle.trim(),
        body:
          quickReplyBody.trim()
      };

      if (editingQuickReplyId) {
        await request(
          \`/api/v1/quick-replies/\${editingQuickReplyId}\`,
          {
            method: "PATCH",
            body:
              JSON.stringify(
                payload
              )
          }
        );
      } else {
        await request(
          "/api/v1/quick-replies",
          {
            method: "POST",
            body:
              JSON.stringify(
                payload
              )
          }
        );
      }

      resetQuickReplyForm();

      await Promise.all([
        loadQuickReplies(),
        loadManagedQuickReplies()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar a resposta rápida."
      );
    } finally {
      setSavingQuickReply(false);
    }
  }

  async function toggleQuickReply(
    reply: QuickReply
  ) {
    if (!canManageQuickReplies) {
      return;
    }

    setError("");

    try {
      await request(
        \`/api/v1/quick-replies/\${reply.id}\`,
        {
          method: "PATCH",
          body: JSON.stringify({
            isActive:
              !reply.isActive
          })
        }
      );

      await Promise.all([
        loadQuickReplies(),
        loadManagedQuickReplies()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível alterar a resposta rápida."
      );
    }
  }

`;

  content = content.replace(
    anchor,
    `${actions}${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Quick reply actions installed.");
NODE

# ---------------------------------------------------------------------------
# Frontend palette + management drawer + composer button
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

/*
 * Drawer inserted inside conversation-body, beside internal notes drawer.
 */
if (!content.includes('className="quick-reply-manager"')) {
  const anchor =
    `                {notesOpen && (
                  <aside className="ticket-notes-drawer">`;

  if (!content.includes(anchor)) {
    throw new Error(
      "P1.6 notes drawer anchor not found."
    );
  }

  const manager = `                {quickReplyManagerOpen &&
                  canManageQuickReplies && (
                    <aside className="quick-reply-manager">
                      <header className="quick-reply-manager__header">
                        <div>
                          <span className="eyebrow">
                            Atendimento
                          </span>
                          <strong>
                            Respostas rápidas
                          </strong>
                          <small>
                            Biblioteca compartilhada pela empresa.
                          </small>
                        </div>

                        <button
                          aria-label="Fechar respostas rápidas"
                          onClick={() => {
                            setQuickReplyManagerOpen(false);
                            resetQuickReplyForm();
                          }}
                          type="button"
                        >
                          ×
                        </button>
                      </header>

                      <div className="quick-reply-manager__list">
                        {managedQuickReplies.length === 0 ? (
                          <div className="quick-reply-manager__empty">
                            Nenhuma resposta rápida cadastrada.
                          </div>
                        ) : (
                          managedQuickReplies.map(reply => (
                            <article
                              className={
                                reply.isActive
                                  ? "quick-reply-admin-item"
                                  : "quick-reply-admin-item quick-reply-admin-item--inactive"
                              }
                              key={reply.id}
                            >
                              <div className="quick-reply-admin-item__heading">
                                <div>
                                  <code>
                                    /{reply.shortcut}
                                  </code>
                                  <strong>
                                    {reply.title}
                                  </strong>
                                </div>

                                <span>
                                  {reply.isActive
                                    ? "Ativa"
                                    : "Inativa"}
                                </span>
                              </div>

                              <p>{reply.body}</p>

                              <div className="quick-reply-admin-item__actions">
                                <button
                                  onClick={() =>
                                    editQuickReply(reply)
                                  }
                                  type="button"
                                >
                                  Editar
                                </button>

                                <button
                                  onClick={() =>
                                    void toggleQuickReply(
                                      reply
                                    )
                                  }
                                  type="button"
                                >
                                  {reply.isActive
                                    ? "Desativar"
                                    : "Ativar"}
                                </button>
                              </div>
                            </article>
                          ))
                        )}
                      </div>

                      <form
                        className="quick-reply-form"
                        onSubmit={saveQuickReply}
                      >
                        <div className="quick-reply-form__heading">
                          <strong>
                            {editingQuickReplyId
                              ? "Editar resposta"
                              : "Nova resposta"}
                          </strong>

                          {editingQuickReplyId && (
                            <button
                              onClick={resetQuickReplyForm}
                              type="button"
                            >
                              Cancelar edição
                            </button>
                          )}
                        </div>

                        <label>
                          <span>Atalho</span>
                          <div className="quick-reply-shortcut-field">
                            <span>/</span>
                            <input
                              maxLength={50}
                              onChange={event =>
                                setQuickReplyShortcut(
                                  event.target.value
                                )
                              }
                              placeholder="saudacao"
                              required
                              value={quickReplyShortcut}
                            />
                          </div>
                        </label>

                        <label>
                          <span>Título</span>
                          <input
                            maxLength={160}
                            onChange={event =>
                              setQuickReplyTitle(
                                event.target.value
                              )
                            }
                            placeholder="Saudação inicial"
                            required
                            value={quickReplyTitle}
                          />
                        </label>

                        <label>
                          <span>Mensagem</span>
                          <textarea
                            maxLength={10_000}
                            onChange={event =>
                              setQuickReplyBody(
                                event.target.value
                              )
                            }
                            placeholder="Olá, {{primeiro_nome}}! Como posso ajudar?"
                            required
                            rows={5}
                            value={quickReplyBody}
                          />
                        </label>

                        <small>
                          Variáveis: {"{{nome}}"}, {"{{primeiro_nome}}"}, {"{{atendente}}"}, {"{{empresa}}"}
                        </small>

                        <button
                          className="primary-button"
                          disabled={savingQuickReply}
                          type="submit"
                        >
                          <span>
                            {savingQuickReply
                              ? "Salvando…"
                              : editingQuickReplyId
                                ? "Salvar alterações"
                                : "Criar resposta"}
                          </span>
                          <span>→</span>
                        </button>
                      </form>
                    </aside>
                  )}

`;

  content = content.replace(
    anchor,
    `${manager}${anchor}`
  );
}

/*
 * Palette before the composer form.
 */
if (!content.includes('className="quick-reply-palette"')) {
  const anchor =
    `                <form
                  className="conversation-composer`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Conversation composer anchor not found."
    );
  }

  const palette = `                {(quickRepliesOpen ||
                  (text.startsWith("/") &&
                    !attachment &&
                    !recording)) && (
                  <div className="quick-reply-palette">
                    <div className="quick-reply-palette__header">
                      <input
                        autoFocus={quickRepliesOpen}
                        onChange={event =>
                          setQuickReplySearch(
                            event.target.value
                          )
                        }
                        placeholder="Buscar resposta rápida…"
                        value={
                          text.startsWith("/")
                            ? text.slice(1)
                            : quickReplySearch
                        }
                      />

                      {canManageQuickReplies && (
                        <button
                          onClick={() => {
                            setQuickRepliesOpen(false);
                            setQuickReplyManagerOpen(true);
                            setNotesOpen(false);
                            void loadManagedQuickReplies();
                          }}
                          type="button"
                        >
                          Gerenciar
                        </button>
                      )}
                    </div>

                    <div className="quick-reply-palette__items">
                      {filteredQuickReplies.length === 0 ? (
                        <div className="quick-reply-palette__empty">
                          Nenhuma resposta encontrada.
                        </div>
                      ) : (
                        filteredQuickReplies.map(reply => (
                          <button
                            className="quick-reply-option"
                            key={reply.id}
                            onClick={() =>
                              selectQuickReply(reply)
                            }
                            type="button"
                          >
                            <div>
                              <code>
                                /{reply.shortcut}
                              </code>
                              <strong>
                                {reply.title}
                              </strong>
                            </div>

                            <p>{reply.body}</p>
                          </button>
                        ))
                      )}
                    </div>
                  </div>
                )}

`;

  content = content.replace(
    anchor,
    `${palette}${anchor}`
  );
}

/*
 * Composer gets one additional 42px column and quick-reply button.
 */
content = content.replace(
  `className="conversation-composer conversation-composer--attachments conversation-composer--voice"`,
  `className="conversation-composer conversation-composer--attachments conversation-composer--voice conversation-composer--quick-replies"`
);

if (!content.includes('className="composer__quick-reply"')) {
  const attachButtonAnchor = `                  <button
                    aria-label="Anexar arquivo"
                    className="composer__attach"`;

  if (!content.includes(attachButtonAnchor)) {
    throw new Error(
      "Attachment composer button not found."
    );
  }

  const button = `                  <button
                    aria-label="Respostas rápidas"
                    className={
                      quickRepliesOpen
                        ? "composer__quick-reply composer__quick-reply--active"
                        : "composer__quick-reply"
                    }
                    disabled={
                      sending ||
                      recording ||
                      !!attachment
                    }
                    onClick={() => {
                      setQuickRepliesOpen(
                        current => !current
                      );
                      setQuickReplySearch("");
                    }}
                    title="Respostas rápidas (ou digite /)"
                    type="button"
                  >
                    ↯
                  </button>

`;

  content = content.replace(
    attachButtonAnchor,
    `${button}${attachButtonAnchor}`
  );
}

/*
 * Add textarea ref and auto-open behavior through normal onChange.
 */
if (!content.includes("ref={composerTextRef}")) {
  const textareaAnchor = `                <textarea
                  disabled={`;

  if (!content.includes(textareaAnchor)) {
    throw new Error(
      "Composer textarea anchor not found."
    );
  }

  content = content.replace(
    textareaAnchor,
    `                <textarea
                  ref={composerTextRef}
                  disabled={`
  );
}

fs.writeFileSync(path, content);
console.log("Quick reply palette/manager/composer UI installed.");
NODE

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.7 / Quick replies" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.7 / Quick replies ---------------------------------------- */

.conversation-composer--quick-replies {
  grid-template-columns:
    42px
    42px
    42px
    minmax(0, 1fr)
    46px !important;
}

.composer__quick-reply {
  display: grid;
  width: 42px;
  height: 46px;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: var(--surface-subtle);
  color: var(--muted);
  font-size: 18px;
  font-weight: 700;
}

.composer__quick-reply:hover:not(:disabled),
.composer__quick-reply--active {
  border-color: #b9cec0;
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.composer__quick-reply:disabled {
  opacity: 0.4;
}

.quick-reply-palette {
  position: absolute;
  z-index: 24;
  right: 14px;
  bottom: 78px;
  display: grid;
  width: min(460px, calc(100% - 28px));
  max-height: min(470px, 64%);
  grid-template-rows: auto minmax(0, 1fr);
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 15px;
  background: #fff;
  box-shadow:
    0 18px 50px
    rgba(23, 32, 26, 0.15);
}

.quick-reply-palette__header {
  display: grid;
  grid-template-columns:
    minmax(0, 1fr)
    auto;
  align-items: center;
  gap: 8px;
  border-bottom: 1px solid var(--line);
  padding: 9px;
}

.quick-reply-palette__header input {
  width: 100%;
  height: 38px;
  border: 1px solid var(--line);
  border-radius: 10px;
  outline: none;
  background: var(--surface-subtle);
  padding: 0 11px;
  font-size: 10px;
}

.quick-reply-palette__header input:focus {
  border-color: var(--accent);
  background: #fff;
}

.quick-reply-palette__header button {
  height: 38px;
  border: 1px solid var(--line);
  border-radius: 10px;
  background: #fff;
  padding: 0 10px;
  color: var(--ink);
  font-size: 9px;
  font-weight: 750;
}

.quick-reply-palette__items {
  min-height: 0;
  overflow-y: auto;
  padding: 6px;
}

.quick-reply-option {
  display: grid;
  width: 100%;
  gap: 6px;
  border: 0;
  border-radius: 10px;
  background: transparent;
  padding: 10px;
  text-align: left;
}

.quick-reply-option:hover {
  background: #f1f5f2;
}

.quick-reply-option > div {
  display: flex;
  align-items: center;
  gap: 8px;
}

.quick-reply-option code,
.quick-reply-admin-item code {
  border-radius: 6px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 3px 6px;
  font-family: inherit;
  font-size: 8px;
  font-weight: 800;
}

.quick-reply-option strong {
  font-size: 10px;
}

.quick-reply-option p {
  display: -webkit-box;
  overflow: hidden;
  margin: 0;
  color: var(--muted);
  font-size: 9px;
  line-height: 1.45;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.quick-reply-palette__empty {
  display: grid;
  min-height: 120px;
  place-items: center;
  color: var(--muted);
  padding: 20px;
  font-size: 10px;
}

.quick-reply-manager {
  position: absolute;
  z-index: 32;
  top: 0;
  right: 0;
  bottom: 0;
  display: grid;
  width: min(450px, 92%);
  min-height: 0;
  grid-template-rows:
    auto
    minmax(0, 1fr)
    auto;
  border-left: 1px solid var(--line);
  background: #fbfcfa;
  box-shadow:
    -18px 0 38px
    rgba(26, 35, 29, 0.09);
}

.quick-reply-manager__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  border-bottom: 1px solid var(--line);
  padding: 17px;
}

.quick-reply-manager__header > div {
  display: grid;
  gap: 4px;
}

.quick-reply-manager__header strong {
  font-size: 15px;
}

.quick-reply-manager__header small {
  color: var(--muted);
  font-size: 9px;
}

.quick-reply-manager__header > button {
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

.quick-reply-manager__list {
  min-height: 0;
  overflow-y: auto;
  padding: 10px;
}

.quick-reply-manager__empty {
  display: grid;
  min-height: 160px;
  place-items: center;
  color: var(--muted);
  font-size: 10px;
}

.quick-reply-admin-item {
  display: grid;
  gap: 8px;
  margin-bottom: 8px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: #fff;
  padding: 11px;
}

.quick-reply-admin-item--inactive {
  opacity: 0.56;
}

.quick-reply-admin-item__heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 10px;
}

.quick-reply-admin-item__heading > div {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 7px;
}

.quick-reply-admin-item__heading strong {
  overflow: hidden;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.quick-reply-admin-item__heading > span {
  color: var(--muted);
  font-size: 8px;
}

.quick-reply-admin-item p {
  margin: 0;
  color: var(--muted);
  font-size: 9px;
  line-height: 1.5;
  white-space: pre-wrap;
}

.quick-reply-admin-item__actions {
  display: flex;
  gap: 6px;
}

.quick-reply-admin-item__actions button {
  border: 0;
  border-radius: 7px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 6px 8px;
  font-size: 8px;
  font-weight: 750;
}

.quick-reply-form {
  display: grid;
  gap: 9px;
  border-top: 1px solid var(--line);
  background: #fff;
  padding: 12px;
}

.quick-reply-form__heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.quick-reply-form__heading strong {
  font-size: 11px;
}

.quick-reply-form__heading button {
  border: 0;
  background: transparent;
  color: var(--muted);
  font-size: 8px;
  text-decoration: underline;
}

.quick-reply-form label {
  display: grid;
  gap: 5px;
}

.quick-reply-form label > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 700;
}

.quick-reply-form input,
.quick-reply-form textarea {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 10px;
  outline: none;
  background: var(--surface-subtle);
  padding: 9px 10px;
  font: inherit;
  font-size: 9px;
}

.quick-reply-form textarea {
  resize: vertical;
  line-height: 1.5;
}

.quick-reply-form input:focus,
.quick-reply-form textarea:focus {
  border-color: var(--accent);
  background: #fff;
}

.quick-reply-shortcut-field {
  display: grid;
  grid-template-columns:
    24px
    minmax(0, 1fr);
  align-items: center;
  border: 1px solid var(--line);
  border-radius: 10px;
  background: var(--surface-subtle);
}

.quick-reply-shortcut-field > span {
  color: var(--accent-dark);
  text-align: right;
  font-size: 10px;
  font-weight: 800;
}

.quick-reply-shortcut-field input {
  border: 0;
  background: transparent;
}

.quick-reply-form > small {
  color: var(--muted);
  font-size: 8px;
  line-height: 1.45;
}

.quick-reply-form .primary-button {
  width: 100%;
  height: 39px;
  margin: 0;
}

@media (max-width: 680px) {
  .conversation-composer--quick-replies {
    grid-template-columns:
      38px
      38px
      38px
      minmax(0, 1fr)
      44px !important;
  }

  .composer__quick-reply {
    width: 38px;
    height: 44px;
  }

  .quick-reply-manager {
    width: 100%;
    border-left: 0;
  }

  .quick-reply-palette {
    right: 8px;
    bottom: 74px;
    width: calc(100% - 16px);
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/QUICK_REPLIES.md <<'EOF'
# Quick replies

P1.7 adds a shared company library of reusable replies.

## Usage

All operational roles can read/use active quick replies.

The operator can:

- click the quick-reply button in the composer;
- type `/` followed by a shortcut or search term;
- select a reply;
- review or edit the expanded text;
- send it through the normal message flow.

Selecting a reply never sends automatically.

## Management

OWNER, ADMIN and SUPERVISOR can:

- create;
- edit;
- activate;
- deactivate.

AGENT can only read/use the active library.

Replies are soft-disabled rather than deleted.

## Variables

The following variables are expanded when a reply is inserted into the
composer:

- `{{nome}}`
- `{{primeiro_nome}}`
- `{{atendente}}`
- `{{empresa}}`

Expansion happens at insertion time using the selected ticket and current
session.

## Shortcuts

A shortcut is company-unique, case-insensitive after normalization, and stored
without the leading slash.

Examples:

- `/saudacao`
- `/prazo`
- `/pix`
- `/encerramento`

Allowed shortcut characters:

- letters
- numbers
- hyphen
- underscore

## Realtime

Library changes publish:

`quick-reply.updated`

Other open Wapp sessions refresh the active quick-reply library automatically.
EOF

echo "[P1.7] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.7] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.7] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.7] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.7] Quick replies installed."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name quick_replies"
echo "  pnpm dev"
echo
echo "Test:"
echo "  1. create /saudacao as OWNER/ADMIN/SUPERVISOR"
echo "  2. use {{primeiro_nome}} in the body"
echo "  3. type /sau in the composer"
echo "  4. select the reply and confirm it only fills the composer"
echo "  5. login as AGENT and confirm use works but management is hidden"
