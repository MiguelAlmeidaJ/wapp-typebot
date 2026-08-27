#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.8] Building ticket tags and filters..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/security/permissions.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
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
  apps/api/src/modules/tags \
  docs

# ---------------------------------------------------------------------------
# Prisma
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

if (!schema.includes("tags                Tag[]")) {
  schema = schema.replace(
    `  quickReplies         QuickReply[]
  ticketNotes`,
    `  quickReplies         QuickReply[]
  tags                 Tag[]
  ticketNotes`
  );
}

if (!schema.includes("createdTicketTags")) {
  schema = schema.replace(
    `  createdQuickReplies QuickReply[]
  ticketNotes`,
    `  createdQuickReplies QuickReply[]
  createdTicketTags   TicketTag[]
  ticketNotes`
  );
}

if (!schema.includes("  tags                 TicketTag[]")) {
  schema = schema.replace(
    `  messages             Message[]
  notes`,
    `  messages             Message[]
  tags                 TicketTag[]
  notes`
  );
}

if (!schema.includes("model Tag {")) {
  const anchor = "model QuickReply {";

  if (!schema.includes(anchor)) {
    throw new Error(
      "QuickReply model not found. P1.8 expects P1.7."
    );
  }

  const models = `model Tag {
  id        String      @id @default(uuid()) @db.Char(36)
  companyId String      @db.Char(36)
  name      String      @db.VarChar(80)
  colorKey  String      @default("GREEN") @db.VarChar(20)
  isActive  Boolean     @default(true)
  company   Company     @relation(fields: [companyId], references: [id], onDelete: Cascade)
  tickets   TicketTag[]
  createdAt DateTime    @default(now())
  updatedAt DateTime    @updatedAt

  @@unique([companyId, name])
  @@index([companyId, isActive, name])
}

model TicketTag {
  ticketId              String             @db.Char(36)
  tagId                 String             @db.Char(36)
  createdByMembershipId String?            @db.Char(36)
  ticket                Ticket             @relation(fields: [ticketId], references: [id], onDelete: Cascade)
  tag                   Tag                @relation(fields: [tagId], references: [id], onDelete: Cascade)
  createdByMembership   CompanyMembership? @relation(fields: [createdByMembershipId], references: [id], onDelete: SetNull)
  createdAt             DateTime           @default(now())

  @@id([ticketId, tagId])
  @@index([tagId, createdAt])
  @@index([createdByMembershipId])
}

`;

  schema = schema.replace(
    anchor,
    `${models}${anchor}`
  );
}

fs.writeFileSync(path, schema);
console.log("Tag/TicketTag schema installed.");
NODE

# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/security/permissions.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes('"tags.read"')) {
  content = content.replace(
    `  | "quickReplies.manage"`,
    `  | "quickReplies.manage"
  | "tags.read"
  | "tags.manage"`
  );
}

function addPermissions(role, permissions) {
  const start =
    content.indexOf(`${role}: [`);

  if (start < 0) {
    throw new Error(`Role block ${role} not found.`);
  }

  const end =
    content.indexOf("  ],", start);

  let block =
    content.slice(start, end);

  for (const permission of permissions) {
    if (block.includes(`"${permission}"`)) {
      continue;
    }

    const marker =
      role === "AGENT"
        ? '"quickReplies.read",'
        : '"quickReplies.manage",';

    const markerIndex =
      content.indexOf(
        marker,
        start
      );

    if (
      markerIndex < 0 ||
      markerIndex > end
    ) {
      throw new Error(
        `Permission insertion marker not found in ${role}.`
      );
    }

    const after =
      markerIndex +
      marker.length;

    content =
      content.slice(0, after) +
      `
    "${permission}",` +
      content.slice(after);

    block =
      content.slice(
        start,
        content.indexOf("  ],", start)
      );
  }
}

addPermissions("OWNER", [
  "tags.read",
  "tags.manage"
]);
addPermissions("ADMIN", [
  "tags.read",
  "tags.manage"
]);
addPermissions("SUPERVISOR", [
  "tags.read",
  "tags.manage"
]);
addPermissions("AGENT", [
  "tags.read"
]);

fs.writeFileSync(path, content);
console.log("Tag permissions installed.");
NODE

# ---------------------------------------------------------------------------
# Tag catalog backend
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tags/tag.service.ts <<'EOF'
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export const tagColorKeys = [
  "GREEN",
  "BLUE",
  "ORANGE",
  "RED",
  "PURPLE",
  "GRAY"
] as const;

export async function listTags(input: {
  companyId: string;
  includeInactive?: boolean;
}) {
  return prisma.tag.findMany({
    where: {
      companyId: input.companyId,
      ...(input.includeInactive
        ? {}
        : {
            isActive: true
          })
    },
    orderBy: [
      {
        isActive: "desc"
      },
      {
        name: "asc"
      }
    ],
    take: 200
  });
}

export async function createTag(input: {
  companyId: string;
  name: string;
  colorKey: typeof tagColorKeys[number];
}) {
  const name = input.name.trim();

  const existing =
    await prisma.tag.findFirst({
      where: {
        companyId: input.companyId,
        name
      },
      select: {
        id: true
      }
    });

  if (existing) {
    throw new AppError(
      "Já existe uma etiqueta com este nome.",
      409,
      "TAG_NAME_IN_USE"
    );
  }

  const tag =
    await prisma.tag.create({
      data: {
        companyId:
          input.companyId,
        name,
        colorKey:
          input.colorKey
      }
    });

  publishRealtime(
    input.companyId,
    {
      type: "tag.updated",
      tagId: tag.id
    }
  );

  return tag;
}

export async function updateTag(input: {
  companyId: string;
  tagId: string;
  name?: string;
  colorKey?: typeof tagColorKeys[number];
  isActive?: boolean;
}) {
  const existing =
    await prisma.tag.findFirst({
      where: {
        id: input.tagId,
        companyId:
          input.companyId
      }
    });

  if (!existing) {
    throw new AppError(
      "Etiqueta não encontrada.",
      404,
      "TAG_NOT_FOUND"
    );
  }

  const name =
    input.name?.trim();

  if (
    name &&
    name !== existing.name
  ) {
    const duplicate =
      await prisma.tag.findFirst({
        where: {
          companyId:
            input.companyId,
          name,
          id: {
            not: existing.id
          }
        },
        select: {
          id: true
        }
      });

    if (duplicate) {
      throw new AppError(
        "Já existe uma etiqueta com este nome.",
        409,
        "TAG_NAME_IN_USE"
      );
    }
  }

  const tag =
    await prisma.tag.update({
      where: {
        id: existing.id
      },
      data: {
        ...(name !== undefined
          ? { name }
          : {}),
        ...(input.colorKey !== undefined
          ? {
              colorKey:
                input.colorKey
            }
          : {}),
        ...(input.isActive !== undefined
          ? {
              isActive:
                input.isActive
            }
          : {})
      }
    });

  publishRealtime(
    input.companyId,
    {
      type: "tag.updated",
      tagId: tag.id
    }
  );

  return tag;
}
EOF

cat > apps/api/src/modules/tags/tag.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  createTag,
  listTags,
  tagColorKeys,
  updateTag
} from "./tag.service.js";

const colorSchema =
  z.enum(tagColorKeys);

const idSchema = z.object({
  id: z.string().uuid()
});

const createSchema = z.object({
  name: z
    .string()
    .trim()
    .min(1)
    .max(80),
  colorKey:
    colorSchema.default("GREEN")
});

const updateSchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(1)
      .max(80)
      .optional(),
    colorKey:
      colorSchema.optional(),
    isActive:
      z.boolean().optional()
  })
  .refine(
    value =>
      value.name !== undefined ||
      value.colorKey !== undefined ||
      value.isActive !== undefined,
    {
      message:
        "Informe ao menos uma alteração."
    }
  );

export async function tagRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/tags",
    async request => {
      const auth =
        await requirePermission(
          request,
          "tags.read"
        );

      return {
        tags:
          await listTags({
            companyId:
              auth.companyId
          })
      };
    }
  );

  app.get(
    "/api/v1/tags/manage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "tags.manage"
        );

      return {
        tags:
          await listTags({
            companyId:
              auth.companyId,
            includeInactive:
              true
          })
      };
    }
  );

  app.post(
    "/api/v1/tags",
    async (request, reply) => {
      const auth =
        await requirePermission(
          request,
          "tags.manage"
        );

      const input =
        createSchema.parse(
          request.body
        );

      return reply
        .status(201)
        .send({
          tag:
            await createTag({
              companyId:
                auth.companyId,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/tags/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "tags.manage"
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
        tag:
          await updateTag({
            companyId:
              auth.companyId,
            tagId:
              params.id,
            ...input
          })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register tag routes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { tagRoutes } from "./modules/tags/tag.routes.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { teamRoutes } from "./modules/team/team.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find teamRoutes import."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (!content.includes("await app.register(tagRoutes);")) {
  const anchor =
    "  await app.register(teamRoutes);";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find teamRoutes registration."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  await app.register(tagRoutes);`
  );
}

fs.writeFileSync(path, content);
console.log("Tag routes registered.");
NODE

# ---------------------------------------------------------------------------
# Ticket tags service + include
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("  tags: {")) {
  const anchor = `  assignedMembership: {
    include: {
      user: {
        select: {
          id: true,
          name: true,
          email: true
        }
      }
    }
  },`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticketInclude assignedMembership block."
    );
  }

  const tagsInclude = `${anchor}
  tags: {
    include: {
      tag: true
    },
    orderBy: {
      createdAt: "asc"
    }
  },`;

  content = content.replace(
    anchor,
    tagsInclude
  );
}

if (!content.includes("export async function replaceTicketTags(")) {
  content += `

export async function replaceTicketTags(input: {
  companyId: string;
  ticketId: string;
  actorMembershipId: string;
  role: WappRole;
  tagIds: string[];
}) {
  const ticket = await getTicket(
    input.companyId,
    input.ticketId
  );

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.actorMembershipId,
    input.role
  );

  const uniqueTagIds =
    [...new Set(input.tagIds)];

  if (uniqueTagIds.length > 20) {
    throw new AppError(
      "Um atendimento pode ter no máximo 20 etiquetas.",
      422,
      "TOO_MANY_TICKET_TAGS"
    );
  }

  if (uniqueTagIds.length > 0) {
    const validCount =
      await prisma.tag.count({
        where: {
          companyId:
            input.companyId,
          id: {
            in: uniqueTagIds
          },
          isActive: true
        }
      });

    if (
      validCount !==
      uniqueTagIds.length
    ) {
      throw new AppError(
        "Uma ou mais etiquetas são inválidas ou estão inativas.",
        422,
        "INVALID_TICKET_TAG"
      );
    }
  }

  await prisma.$transaction(async tx => {
    await tx.ticketTag.deleteMany({
      where: {
        ticketId:
          ticket.id
      }
    });

    if (uniqueTagIds.length > 0) {
      await tx.ticketTag.createMany({
        data:
          uniqueTagIds.map(tagId => ({
            ticketId:
              ticket.id,
            tagId,
            createdByMembershipId:
              input.actorMembershipId
          })),
        skipDuplicates: true
      });
    }
  });

  const updated =
    await prisma.ticket.findFirst({
      where: {
        id: ticket.id,
        companyId:
          input.companyId
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

  return updated;
}
`;
}

fs.writeFileSync(path, content);
console.log("Ticket tag assignment service installed.");
NODE

# ---------------------------------------------------------------------------
# Ticket route
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.routes.ts";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("replaceTicketTags,")) {
  content = content.replace(
    `  markTicketRead,
  sendTicketText,`,
    `  markTicketRead,
  replaceTicketTags,
  sendTicketText,`
  );
}

if (!content.includes("const replaceTagsSchema")) {
  const anchor = `const transferSchema = z.object({
  queueId: z.string().uuid().nullable().optional(),
  membershipId: z.string().uuid().nullable().optional()
});`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find transferSchema anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

const replaceTagsSchema = z.object({
  tagIds: z
    .array(z.string().uuid())
    .max(20)
});`
  );
}

if (
  !content.includes(
    '"/api/v1/tickets/:id/tags"'
  )
) {
  const anchor = `  app.post(
    "/api/v1/tickets/:id/transfer",`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find transfer route anchor."
    );
  }

  const route = `  app.put(
    "/api/v1/tickets/:id/tags",
    async request => {
      const auth =
        await requireAuth(request);

      const params =
        ticketIdSchema.parse(
          request.params
        );

      const input =
        replaceTagsSchema.parse(
          request.body
        );

      return {
        ticket:
          await replaceTicketTags({
            companyId:
              auth.companyId,
            ticketId:
              params.id,
            actorMembershipId:
              auth.membershipId,
            role:
              auth.role,
            tagIds:
              input.tagIds
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
console.log("Ticket tag route installed.");
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
    content.includes('| "quick-reply.updated"') &&
    !content.includes('| "tag.updated"')
  ) {
    content = content.replace(
      '| "quick-reply.updated"',
      '| "quick-reply.updated"\n  | "tag.updated"'
    );
  }

  if (
    content.includes("quickReplyId?: string;") &&
    !content.includes("tagId?: string;")
  ) {
    content = content.replace(
      "quickReplyId?: string;",
      "quickReplyId?: string;\n  tagId?: string;"
    );
  }

  fs.writeFileSync(path, content);
}

console.log("tag.updated realtime installed.");
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

if (!content.includes("interface TagInfo {")) {
  const anchor =
    "interface QueueInfo {";

  if (!content.includes(anchor)) {
    throw new Error(
      "QueueInfo interface anchor not found."
    );
  }

  const types = `interface TagInfo {
  id: string;
  name: string;
  colorKey:
    | "GREEN"
    | "BLUE"
    | "ORANGE"
    | "RED"
    | "PURPLE"
    | "GRAY";
  isActive: boolean;
}

interface TicketTagInfo {
  tagId: string;
  tag: TagInfo;
}

`;

  content = content.replace(
    anchor,
    `${types}${anchor}`
  );
}

if (!content.includes("  tags: TicketTagInfo[];")) {
  const anchor =
    `  assignedMembership: AssignedMembership | null;
  messages: TicketMessagePreview[];`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Ticket interface anchor not found."
    );
  }

  content = content.replace(
    anchor,
    `  assignedMembership: AssignedMembership | null;
  tags: TicketTagInfo[];
  messages: TicketMessagePreview[];`
  );
}

if (!content.includes("interface TagsResponse {")) {
  const anchor =
    "interface QuickRepliesResponse {";

  if (!content.includes(anchor)) {
    throw new Error(
      "QuickRepliesResponse anchor not found."
    );
  }

  const response = `interface TagsResponse {
  tags: TagInfo[];
}

`;

  content = content.replace(
    anchor,
    `${response}${anchor}`
  );
}

if (!content.includes("const [tags, setTags]")) {
  const anchor =
    `  const [quickReplies, setQuickReplies] =
    useState<QuickReply[]>([]);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Quick replies state anchor not found."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [tags, setTags] =
    useState<TagInfo[]>([]);
  const [managedTags, setManagedTags] =
    useState<TagInfo[]>([]);
  const [tagPickerOpen, setTagPickerOpen] =
    useState(false);
  const [tagManagerOpen, setTagManagerOpen] =
    useState(false);
  const [ticketTagFilter, setTicketTagFilter] =
    useState("");
  const [tagName, setTagName] =
    useState("");
  const [tagColorKey, setTagColorKey] =
    useState<TagInfo["colorKey"]>("GREEN");
  const [editingTagId, setEditingTagId] =
    useState<string | null>(null);
  const [savingTag, setSavingTag] =
    useState(false);
  const [updatingTicketTags, setUpdatingTicketTags] =
    useState(false);`
  );
}

if (!content.includes("const canManageTags =")) {
  const anchor =
    `  const canManageQuickReplies =`;

  if (!content.includes(anchor)) {
    throw new Error(
      "canManageQuickReplies anchor not found."
    );
  }

  const end =
    content.indexOf(
      "\n\n",
      content.indexOf(anchor)
    );

  if (end < 0) {
    throw new Error(
      "Could not find canManageQuickReplies block end."
    );
  }

  const addition = `

  const canManageTags =
    session
      ? ["OWNER", "ADMIN", "SUPERVISOR"].includes(
          session.role
        )
      : false;`;

  content =
    content.slice(0, end) +
    addition +
    content.slice(end);
}

if (!content.includes("const visibleTickets = useMemo(")) {
  const anchor =
    `  const pendingCount = tickets.filter(`;

  if (!content.includes(anchor)) {
    throw new Error(
      "pendingCount anchor not found."
    );
  }

  const memo = `  const visibleTickets = useMemo(
    () =>
      ticketTagFilter
        ? tickets.filter(ticket =>
            ticket.tags.some(
              link =>
                link.tag.id ===
                ticketTagFilter
            )
          )
        : tickets,
    [
      ticketTagFilter,
      tickets
    ]
  );

`;

  content = content.replace(
    anchor,
    `${memo}${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Tag frontend types/state installed.");
NODE

# ---------------------------------------------------------------------------
# Frontend loaders/realtime/actions
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("const loadTags = useCallback(")) {
  const anchor =
    `  const loadQuickReplies = useCallback(`;

  if (!content.includes(anchor)) {
    throw new Error(
      "loadQuickReplies anchor not found."
    );
  }

  const callbacks = `  const loadTags = useCallback(
    async () => {
      const payload =
        await request<TagsResponse>(
          "/api/v1/tags"
        );

      setTags(payload.tags);
    },
    [request]
  );

  const loadManagedTags = useCallback(
    async () => {
      if (!canManageTags) {
        setManagedTags([]);
        return;
      }

      const payload =
        await request<TagsResponse>(
          "/api/v1/tags/manage"
        );

      setManagedTags(
        payload.tags
      );
    },
    [
      canManageTags,
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
 * Initial load: add tags.
 */
if (
  content.includes("loadQuickReplies(),") &&
  !content.includes("loadTags(),")
) {
  content = content.replace(
    `        loadReferenceData(),
        loadQuickReplies()`,
    `        loadReferenceData(),
        loadQuickReplies(),
        loadTags()`
  );

  content = content.replace(
    `    loadQuickReplies,
    loadReferenceData,`,
    `    loadQuickReplies,
    loadReferenceData,
    loadTags,`
  );
}

/*
 * Realtime.
 */
if (
  content.includes(
    'event.type === "quick-reply.updated"'
  ) &&
  !content.includes(
    'event.type === "tag.updated"'
  )
) {
  const anchor =
    `      if (event.type === "queue.updated") {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "queue.updated realtime anchor not found."
    );
  }

  const block = `      if (
        event.type === "tag.updated"
      ) {
        void loadTags();

        if (canManageTags) {
          void loadManagedTags();
        }

        void loadTickets();
      }

`;

  content = content.replace(
    anchor,
    `${block}${anchor}`
  );

  content = content.replace(
    `    canManageQuickReplies,
    loadManagedQuickReplies,`,
    `    canManageQuickReplies,
    canManageTags,
    loadManagedQuickReplies,
    loadManagedTags,`
  );

  content = content.replace(
    `    loadQuickReplies,
    loadReferenceData,`,
    `    loadQuickReplies,
    loadReferenceData,
    loadTags,`
  );
}

/*
 * Actions.
 */
if (!content.includes("async function toggleTicketTag(")) {
  const anchor =
    "  function selectQuickReply(";

  if (!content.includes(anchor)) {
    throw new Error(
      "selectQuickReply action anchor not found."
    );
  }

  const actions = `  async function toggleTicketTag(
    tagId: string
  ) {
    if (
      !selectedId ||
      !selectedTicket ||
      updatingTicketTags
    ) {
      return;
    }

    const currentIds =
      selectedTicket.tags.map(
        link => link.tag.id
      );

    const nextIds =
      currentIds.includes(tagId)
        ? currentIds.filter(
            id => id !== tagId
          )
        : [...currentIds, tagId];

    setUpdatingTicketTags(true);
    setError("");

    try {
      await request(
        \`/api/v1/tickets/\${selectedId}/tags\`,
        {
          method: "PUT",
          body: JSON.stringify({
            tagIds: nextIds
          })
        }
      );

      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar as etiquetas."
      );
    } finally {
      setUpdatingTicketTags(false);
    }
  }

  function resetTagForm() {
    setEditingTagId(null);
    setTagName("");
    setTagColorKey("GREEN");
  }

  function editTag(
    tag: TagInfo
  ) {
    setEditingTagId(tag.id);
    setTagName(tag.name);
    setTagColorKey(tag.colorKey);
  }

  async function saveTag(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !canManageTags ||
      !tagName.trim()
    ) {
      return;
    }

    setSavingTag(true);
    setError("");

    try {
      const payload = {
        name: tagName.trim(),
        colorKey: tagColorKey
      };

      if (editingTagId) {
        await request(
          \`/api/v1/tags/\${editingTagId}\`,
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
          "/api/v1/tags",
          {
            method: "POST",
            body:
              JSON.stringify(
                payload
              )
          }
        );
      }

      resetTagForm();

      await Promise.all([
        loadTags(),
        loadManagedTags()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar a etiqueta."
      );
    } finally {
      setSavingTag(false);
    }
  }

  async function toggleTagActive(
    tag: TagInfo
  ) {
    if (!canManageTags) {
      return;
    }

    setError("");

    try {
      await request(
        \`/api/v1/tags/\${tag.id}\`,
        {
          method: "PATCH",
          body: JSON.stringify({
            isActive:
              !tag.isActive
          })
        }
      );

      await Promise.all([
        loadTags(),
        loadManagedTags(),
        loadTickets()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível alterar a etiqueta."
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
console.log("Tag loaders/realtime/actions installed.");
NODE

# ---------------------------------------------------------------------------
# Frontend: use visibleTickets in list
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

/*
 * Replace only JSX list map occurrence.
 */
if (
  content.includes("{tickets.map(ticket => (") &&
  !content.includes("{visibleTickets.map(ticket => (")
) {
  content = content.replace(
    "{tickets.map(ticket => (",
    "{visibleTickets.map(ticket => ("
  );
}

fs.writeFileSync(path, content);
console.log("Ticket list now respects tag filter.");
NODE

# ---------------------------------------------------------------------------
# Frontend UI
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

/*
 * Filter in ticket list heading. Use count badges anchor.
 */
if (!content.includes('className="ticket-tag-filter"')) {
  const anchor = `                <span>{openCount} em atendimento</span>
              </div>`;

  if (content.includes(anchor)) {
    content = content.replace(
      anchor,
      `                <span>{openCount} em atendimento</span>
              </div>

              <select
                className="ticket-tag-filter"
                onChange={event =>
                  setTicketTagFilter(
                    event.target.value
                  )
                }
                value={ticketTagFilter}
              >
                <option value="">
                  Todas as etiquetas
                </option>
                {tags.map(tag => (
                  <option
                    key={tag.id}
                    value={tag.id}
                  >
                    {tag.name}
                  </option>
                ))}
              </select>`
    );
  }
}

/*
 * Ticket row chips under queue label when possible.
 */
if (!content.includes('className="ticket-row__tags"')) {
  const queueAnchor = `<span className="ticket-row__queue">
                        {ticket.queue?.name ?? "Sem fila"}
                      </span>`;

  if (content.includes(queueAnchor)) {
    content = content.replace(
      queueAnchor,
      `${queueAnchor}

                      {ticket.tags.length > 0 && (
                        <div className="ticket-row__tags">
                          {ticket.tags
                            .slice(0, 3)
                            .map(link => (
                              <span
                                className={\`tag-chip tag-chip--\${link.tag.colorKey.toLowerCase()}\`}
                                key={link.tag.id}
                              >
                                {link.tag.name}
                              </span>
                            ))}

                          {ticket.tags.length > 3 && (
                            <span className="ticket-row__tag-more">
                              +{ticket.tags.length - 3}
                            </span>
                          )}
                        </div>
                      )}`
    );
  }
}

/*
 * Add tag button after notes button.
 */
if (!content.includes('className="ticket-tags-toggle"')) {
  const notesButtonEnd = `                </button>

                <small>
                  Atual:`;

  if (!content.includes(notesButtonEnd)) {
    throw new Error(
      "Could not find notes button/current assignment boundary."
    );
  }

  const tagButton = `                </button>

                <button
                  className="ticket-tags-toggle"
                  onClick={() =>
                    setTagPickerOpen(
                      current => !current
                    )
                  }
                  type="button"
                >
                  Etiquetas
                  {selectedTicket.tags.length > 0 && (
                    <span>
                      {selectedTicket.tags.length}
                    </span>
                  )}
                </button>

                <small>
                  Atual:`;

  content = content.replace(
    notesButtonEnd,
    tagButton
  );
}

/*
 * Selected tag chips near assignment small line.
 */
if (!content.includes('className="selected-ticket-tags"')) {
  const anchor = `                <small>
                  Atual: {selectedTicket.queue?.name ?? "sem fila"} · {" "}
                  {selectedTicket.assignedMembership?.user.name ?? "sem atendente"}
                </small>`;

  if (content.includes(anchor)) {
    content = content.replace(
      anchor,
      `${anchor}

                {selectedTicket.tags.length > 0 && (
                  <div className="selected-ticket-tags">
                    {selectedTicket.tags.map(link => (
                      <span
                        className={\`tag-chip tag-chip--\${link.tag.colorKey.toLowerCase()}\`}
                        key={link.tag.id}
                      >
                        {link.tag.name}
                      </span>
                    ))}
                  </div>
                )}`
    );
  }
}

/*
 * Picker and manager in conversation-body.
 */
if (!content.includes('className="ticket-tag-picker"')) {
  const anchor =
    `              <div className="conversation-body">`;

  if (!content.includes(anchor)) {
    throw new Error(
      "conversation-body anchor not found."
    );
  }

  const ui = `              <div className="conversation-body">
                {tagPickerOpen && (
                  <div className="ticket-tag-picker">
                    <header>
                      <strong>
                        Etiquetas do atendimento
                      </strong>

                      <div>
                        {canManageTags && (
                          <button
                            onClick={() => {
                              setTagPickerOpen(false);
                              setTagManagerOpen(true);
                              setNotesOpen(false);
                              setQuickReplyManagerOpen(false);
                              void loadManagedTags();
                            }}
                            type="button"
                          >
                            Gerenciar
                          </button>
                        )}

                        <button
                          aria-label="Fechar etiquetas"
                          onClick={() =>
                            setTagPickerOpen(false)
                          }
                          type="button"
                        >
                          ×
                        </button>
                      </div>
                    </header>

                    <div className="ticket-tag-picker__list">
                      {tags.length === 0 ? (
                        <div className="ticket-tag-picker__empty">
                          Nenhuma etiqueta cadastrada.
                        </div>
                      ) : (
                        tags.map(tag => {
                          const checked =
                            selectedTicket.tags.some(
                              link =>
                                link.tag.id ===
                                tag.id
                            );

                          return (
                            <button
                              className={
                                checked
                                  ? "ticket-tag-option ticket-tag-option--active"
                                  : "ticket-tag-option"
                              }
                              disabled={updatingTicketTags}
                              key={tag.id}
                              onClick={() =>
                                void toggleTicketTag(
                                  tag.id
                                )
                              }
                              type="button"
                            >
                              <span
                                className={\`tag-dot tag-dot--\${tag.colorKey.toLowerCase()}\`}
                              />
                              <strong>
                                {tag.name}
                              </strong>
                              <span>
                                {checked
                                  ? "✓"
                                  : ""}
                              </span>
                            </button>
                          );
                        })
                      )}
                    </div>
                  </div>
                )}

                {tagManagerOpen &&
                  canManageTags && (
                    <aside className="tag-manager">
                      <header className="tag-manager__header">
                        <div>
                          <span className="eyebrow">
                            Organização
                          </span>
                          <strong>
                            Etiquetas
                          </strong>
                          <small>
                            Compartilhadas pela empresa.
                          </small>
                        </div>

                        <button
                          aria-label="Fechar gerenciamento de etiquetas"
                          onClick={() => {
                            setTagManagerOpen(false);
                            resetTagForm();
                          }}
                          type="button"
                        >
                          ×
                        </button>
                      </header>

                      <div className="tag-manager__list">
                        {managedTags.length === 0 ? (
                          <div className="tag-manager__empty">
                            Nenhuma etiqueta cadastrada.
                          </div>
                        ) : (
                          managedTags.map(tag => (
                            <article
                              className={
                                tag.isActive
                                  ? "tag-admin-item"
                                  : "tag-admin-item tag-admin-item--inactive"
                              }
                              key={tag.id}
                            >
                              <div>
                                <span
                                  className={\`tag-dot tag-dot--\${tag.colorKey.toLowerCase()}\`}
                                />
                                <strong>
                                  {tag.name}
                                </strong>
                              </div>

                              <span>
                                {tag.isActive
                                  ? "Ativa"
                                  : "Inativa"}
                              </span>

                              <div className="tag-admin-item__actions">
                                <button
                                  onClick={() =>
                                    editTag(tag)
                                  }
                                  type="button"
                                >
                                  Editar
                                </button>

                                <button
                                  onClick={() =>
                                    void toggleTagActive(
                                      tag
                                    )
                                  }
                                  type="button"
                                >
                                  {tag.isActive
                                    ? "Desativar"
                                    : "Ativar"}
                                </button>
                              </div>
                            </article>
                          ))
                        )}
                      </div>

                      <form
                        className="tag-form"
                        onSubmit={saveTag}
                      >
                        <div className="tag-form__heading">
                          <strong>
                            {editingTagId
                              ? "Editar etiqueta"
                              : "Nova etiqueta"}
                          </strong>

                          {editingTagId && (
                            <button
                              onClick={resetTagForm}
                              type="button"
                            >
                              Cancelar edição
                            </button>
                          )}
                        </div>

                        <label>
                          <span>Nome</span>
                          <input
                            maxLength={80}
                            onChange={event =>
                              setTagName(
                                event.target.value
                              )
                            }
                            placeholder="Ex.: Urgente"
                            required
                            value={tagName}
                          />
                        </label>

                        <label>
                          <span>Cor</span>
                          <select
                            onChange={event =>
                              setTagColorKey(
                                event.target.value as TagInfo["colorKey"]
                              )
                            }
                            value={tagColorKey}
                          >
                            <option value="GREEN">
                              Verde
                            </option>
                            <option value="BLUE">
                              Azul
                            </option>
                            <option value="ORANGE">
                              Laranja
                            </option>
                            <option value="RED">
                              Vermelho
                            </option>
                            <option value="PURPLE">
                              Roxo
                            </option>
                            <option value="GRAY">
                              Cinza
                            </option>
                          </select>
                        </label>

                        <button
                          className="primary-button"
                          disabled={
                            savingTag ||
                            !tagName.trim()
                          }
                          type="submit"
                        >
                          <span>
                            {savingTag
                              ? "Salvando…"
                              : editingTagId
                                ? "Salvar alterações"
                                : "Criar etiqueta"}
                          </span>
                          <span>→</span>
                        </button>
                      </form>
                    </aside>
                  )}`;

  content = content.replace(
    anchor,
    ui
  );
}

fs.writeFileSync(path, content);
console.log("Tag filter/picker/manager UI installed.");
NODE

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.8 / Ticket tags" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.8 / Ticket tags ------------------------------------------ */

.ticket-tag-filter {
  width: 100%;
  height: 34px;
  margin-top: 9px;
  border: 1px solid var(--line);
  border-radius: 9px;
  outline: none;
  background: #fff;
  color: var(--muted);
  padding: 0 9px;
  font-size: 9px;
}

.ticket-tag-filter:focus {
  border-color: var(--accent);
}

.ticket-row__tags,
.selected-ticket-tags {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
}

.ticket-row__tags {
  margin-top: 5px;
}

.selected-ticket-tags {
  grid-column: 1 / -1;
  margin-top: 4px;
}

.tag-chip {
  display: inline-flex;
  max-width: 120px;
  min-height: 17px;
  align-items: center;
  overflow: hidden;
  border-radius: 999px;
  padding: 2px 6px;
  font-size: 7px;
  font-weight: 750;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tag-chip--green {
  background: #e2f1e7;
  color: #24603f;
}

.tag-chip--blue {
  background: #e2ecf6;
  color: #345f82;
}

.tag-chip--orange {
  background: #f5ead8;
  color: #8b5d20;
}

.tag-chip--red {
  background: #f7e3e1;
  color: #93423c;
}

.tag-chip--purple {
  background: #eee5f5;
  color: #67487d;
}

.tag-chip--gray {
  background: #e9ecea;
  color: #5c6660;
}

.ticket-row__tag-more {
  color: var(--muted);
  font-size: 7px;
}

.ticket-tags-toggle {
  display: inline-flex;
  min-height: 40px;
  align-items: center;
  justify-content: center;
  gap: 7px;
  border: 1px solid var(--line);
  border-radius: 11px;
  background: #fff;
  color: var(--ink);
  padding: 0 12px;
  font-size: 10px;
  font-weight: 750;
}

.ticket-tags-toggle:hover {
  border-color: var(--line-strong);
  background: var(--surface-subtle);
}

.ticket-tags-toggle > span {
  display: grid;
  min-width: 18px;
  height: 18px;
  place-items: center;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 0 5px;
  font-size: 8px;
}

.ticket-tag-picker {
  position: absolute;
  z-index: 26;
  top: 10px;
  right: 12px;
  width: min(330px, calc(100% - 24px));
  max-height: min(440px, 78%);
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: #fff;
  box-shadow:
    0 18px 46px
    rgba(24, 33, 27, 0.14);
}

.ticket-tag-picker > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  border-bottom: 1px solid var(--line);
  padding: 11px 12px;
}

.ticket-tag-picker > header strong {
  font-size: 10px;
}

.ticket-tag-picker > header > div {
  display: flex;
  align-items: center;
  gap: 5px;
}

.ticket-tag-picker > header button {
  border: 0;
  border-radius: 7px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 6px 8px;
  font-size: 8px;
}

.ticket-tag-picker__list {
  max-height: 360px;
  overflow-y: auto;
  padding: 6px;
}

.ticket-tag-picker__empty {
  display: grid;
  min-height: 120px;
  place-items: center;
  color: var(--muted);
  padding: 20px;
  font-size: 9px;
}

.ticket-tag-option {
  display: grid;
  width: 100%;
  grid-template-columns:
    12px
    minmax(0, 1fr)
    20px;
  align-items: center;
  gap: 8px;
  border: 0;
  border-radius: 9px;
  background: transparent;
  padding: 9px;
  text-align: left;
}

.ticket-tag-option:hover,
.ticket-tag-option--active {
  background: #f0f4f1;
}

.ticket-tag-option strong {
  overflow: hidden;
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ticket-tag-option > span:last-child {
  color: var(--accent-dark);
  text-align: center;
  font-size: 10px;
  font-weight: 800;
}

.tag-dot {
  display: inline-block;
  width: 9px;
  height: 9px;
  border-radius: 999px;
}

.tag-dot--green {
  background: #4d9b6d;
}

.tag-dot--blue {
  background: #5e8fb6;
}

.tag-dot--orange {
  background: #c68a3d;
}

.tag-dot--red {
  background: #c1665d;
}

.tag-dot--purple {
  background: #8d6aa7;
}

.tag-dot--gray {
  background: #818b85;
}

.tag-manager {
  position: absolute;
  z-index: 34;
  top: 0;
  right: 0;
  bottom: 0;
  display: block;
  width: min(410px, 92%);
  min-height: 0;
  overflow-x: hidden;
  overflow-y: auto;
  border-left: 1px solid var(--line);
  background: #fbfcfa;
  box-shadow:
    -18px 0 38px
    rgba(26, 35, 29, 0.09);
  scrollbar-gutter: stable;
}

.tag-manager__header {
  position: sticky;
  z-index: 4;
  top: 0;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  border-bottom: 1px solid var(--line);
  background: #fbfcfa;
  padding: 17px;
}

.tag-manager__header > div {
  display: grid;
  gap: 4px;
}

.tag-manager__header strong {
  font-size: 15px;
}

.tag-manager__header small {
  color: var(--muted);
  font-size: 9px;
}

.tag-manager__header > button {
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

.tag-manager__list {
  padding: 10px;
}

.tag-manager__empty {
  display: grid;
  min-height: 150px;
  place-items: center;
  color: var(--muted);
  font-size: 9px;
}

.tag-admin-item {
  display: grid;
  grid-template-columns:
    minmax(0, 1fr)
    auto;
  gap: 8px;
  margin-bottom: 8px;
  border: 1px solid var(--line);
  border-radius: 11px;
  background: #fff;
  padding: 10px;
}

.tag-admin-item--inactive {
  opacity: 0.55;
}

.tag-admin-item > div:first-child {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 7px;
}

.tag-admin-item > div:first-child strong {
  overflow: hidden;
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tag-admin-item > span {
  color: var(--muted);
  font-size: 8px;
}

.tag-admin-item__actions {
  display: flex;
  grid-column: 1 / -1;
  gap: 6px;
}

.tag-admin-item__actions button {
  border: 0;
  border-radius: 7px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 6px 8px;
  font-size: 8px;
  font-weight: 750;
}

.tag-form {
  display: grid;
  gap: 9px;
  border-top: 1px solid var(--line);
  background: #fff;
  padding: 12px 12px 18px;
}

.tag-form__heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.tag-form__heading strong {
  font-size: 11px;
}

.tag-form__heading button {
  border: 0;
  background: transparent;
  color: var(--muted);
  font-size: 8px;
  text-decoration: underline;
}

.tag-form label {
  display: grid;
  gap: 5px;
}

.tag-form label > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 700;
}

.tag-form input,
.tag-form select {
  width: 100%;
  height: 38px;
  border: 1px solid var(--line);
  border-radius: 10px;
  outline: none;
  background: var(--surface-subtle);
  padding: 0 9px;
  font: inherit;
  font-size: 9px;
}

.tag-form input:focus,
.tag-form select:focus {
  border-color: var(--accent);
  background: #fff;
}

.tag-form .primary-button {
  width: 100%;
  height: 39px;
  margin: 0;
}

@media (max-width: 680px) {
  .tag-manager {
    width: 100%;
    border-left: 0;
  }

  .ticket-tag-picker {
    right: 8px;
    width: calc(100% - 16px);
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/TICKET_TAGS.md <<'EOF'
# Ticket tags

P1.8 adds reusable company tags to operational tickets.

## Catalog

A tag contains:

- name
- colorKey
- active/inactive state

Colors are semantic UI keys, not arbitrary CSS supplied by users:

- GREEN
- BLUE
- ORANGE
- RED
- PURPLE
- GRAY

## Permissions

OWNER, ADMIN and SUPERVISOR can manage the catalog.

AGENT can read active tags.

Applying/removing tags from a ticket is a ticket operation and follows the
existing assignment rule. An AGENT cannot change tags on a ticket assigned to
another agent.

## Ticket relation

Tags are attached through `TicketTag`.

A ticket can have at most 20 tags.

Replacing ticket tags:

`PUT /api/v1/tickets/:id/tags`

```json
{
  "tagIds": ["uuid-1", "uuid-2"]
}
```

Only active tags from the same company are accepted.

## UI

The Conversations screen provides:

- tag chips on tickets;
- tag chips on the selected ticket;
- a tag picker;
- catalog management for privileged roles;
- a ticket-list filter by tag.

## Realtime

Catalog changes emit:

`tag.updated`

Ticket assignment changes continue using:

`ticket.updated`

This keeps other operator sessions synchronized without turning tags into
messages or WhatsApp content.
EOF

echo "[P1.8] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.8] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.8] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.8] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.8] Ticket tags installed."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name ticket_tags"
echo "  pnpm dev"
echo
echo "Test:"
echo "  1. create tags Urgente and Retorno"
echo "  2. apply both to a ticket"
echo "  3. filter the ticket list by Retorno"
echo "  4. remove Retorno from the ticket"
echo "  5. login as AGENT and validate assignment protection"
