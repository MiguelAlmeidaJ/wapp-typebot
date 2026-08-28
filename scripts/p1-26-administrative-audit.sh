#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.26] Installing immutable administrative audit..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/security/permissions.ts" \
  "apps/api/src/security/permissions.test.ts" \
  "apps/api/src/lib/prisma-json.ts"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if [[ ! -f "apps/api/src/integration/critical.integration.test.ts" ]]; then
  echo "ERROR: P1.25 is required before P1.26."
  exit 1
fi

mkdir -p \
  apps/api/src/modules/audit \
  apps/api/prisma/migrations/20260828160000_admin_audit \
  docs

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/prisma/schema.prisma";

let content =
  fs.readFileSync(
    path,
    "utf8"
  )
    .replace(
      /\r\n/g,
      "\n"
    );

if (
  !content.includes(
    "auditLogs"
  )
) {
  content =
    content.replace(
      "  tags                    Tag[]",
      `  tags                    Tag[]
  auditLogs               AuditLog[]`
    );

  content =
    content.replace(
      "  ticketNotes         TicketNote[]",
      `  ticketNotes         TicketNote[]
  auditLogs           AuditLog[]`
    );
}

if (
  !content.includes(
    "model AuditLog {"
  )
) {
  content += `

model AuditLog {
  id                String             @id @default(uuid()) @db.Char(36)
  companyId         String             @db.Char(36)
  actorMembershipId String?            @db.Char(36)
  action            String             @db.VarChar(80)
  entityType        String             @db.VarChar(60)
  entityId          String?            @db.VarChar(190)
  beforeData        Json?
  afterData         Json?
  metadata          Json?
  requestId         String?            @db.VarChar(100)
  ipAddress         String?            @db.VarChar(64)
  userAgent         String?            @db.VarChar(500)
  company           Company            @relation(fields: [companyId], references: [id], onDelete: Cascade)
  actorMembership   CompanyMembership? @relation(fields: [actorMembershipId], references: [id], onDelete: SetNull)
  createdAt         DateTime           @default(now())

  @@index([companyId, createdAt])
  @@index([companyId, action, createdAt])
  @@index([companyId, entityType, entityId])
  @@index([actorMembershipId, createdAt])
}
`;
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > apps/api/prisma/migrations/20260828160000_admin_audit/migration.sql <<'EOF'
CREATE TABLE `AuditLog` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `actorMembershipId` CHAR(36) NULL,
  `action` VARCHAR(80) NOT NULL,
  `entityType` VARCHAR(60) NOT NULL,
  `entityId` VARCHAR(190) NULL,
  `beforeData` JSON NULL,
  `afterData` JSON NULL,
  `metadata` JSON NULL,
  `requestId` VARCHAR(100) NULL,
  `ipAddress` VARCHAR(64) NULL,
  `userAgent` VARCHAR(500) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  INDEX `AuditLog_companyId_createdAt_idx` (`companyId`, `createdAt`),
  INDEX `AuditLog_companyId_action_createdAt_idx` (`companyId`, `action`, `createdAt`),
  INDEX `AuditLog_companyId_entityType_entityId_idx` (`companyId`, `entityType`, `entityId`),
  INDEX `AuditLog_actorMembershipId_createdAt_idx` (`actorMembershipId`, `createdAt`),

  CONSTRAINT `AuditLog_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `AuditLog_actorMembershipId_fkey`
    FOREIGN KEY (`actorMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

cat > apps/api/src/modules/audit/audit.service.ts <<'EOF'
import type {
  Prisma
} from "../../generated/prisma/client.js";

import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";

export type AuditEntityType =
  | "TEAM_MEMBERSHIP"
  | "QUEUE"
  | "SLA_SETTINGS"
  | "TAG"
  | "QUICK_REPLY"
  | "WHATSAPP_CONNECTION";

function jsonValue(
  value: unknown
):
  | Prisma.InputJsonValue
  | undefined {
  if (
    value === null ||
    value === undefined
  ) {
    return undefined;
  }

  return toPrismaJson(
    value
  );
}

export async function recordAudit(input: {
  companyId: string;
  actorMembershipId: string;
  action: string;
  entityType: AuditEntityType;
  entityId?: string | null;
  before?: unknown;
  after?: unknown;
  metadata?: unknown;
  requestId?: string;
  ipAddress?: string;
  userAgent?: string;
}) {
  return prisma.auditLog.create({
    data: {
      companyId:
        input.companyId,
      actorMembershipId:
        input.actorMembershipId,
      action:
        input.action,
      entityType:
        input.entityType,
      entityId:
        input.entityId ??
        null,
      beforeData:
        jsonValue(
          input.before
        ),
      afterData:
        jsonValue(
          input.after
        ),
      metadata:
        jsonValue(
          input.metadata
        ),
      requestId:
        input.requestId,
      ipAddress:
        input.ipAddress,
      userAgent:
        input.userAgent
    }
  });
}

export async function snapshotAuditEntity(input: {
  companyId: string;
  entityType: AuditEntityType;
  entityId: string;
}) {
  switch (
    input.entityType
  ) {
    case "TEAM_MEMBERSHIP":
      return prisma.companyMembership.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          role: true,
          isActive:
            true,
          user: {
            select: {
              id: true,
              name: true,
              email: true,
              isActive:
                true
            }
          }
        }
      });

    case "QUEUE":
      return prisma.queue.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          name: true,
          isActive:
            true,
          members: {
            select: {
              membershipId:
                true
            },
            orderBy: {
              createdAt:
                "asc"
            }
          }
        }
      });

    case "SLA_SETTINGS":
      return prisma.company.findFirst({
        where: {
          id:
            input.companyId
        },
        select: {
          id: true,
          firstResponseSlaMinutes:
            true,
          replySlaMinutes:
            true
        }
      });

    case "TAG":
      return prisma.tag.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          name: true,
          colorKey:
            true,
          isActive:
            true
        }
      });

    case "QUICK_REPLY":
      return prisma.quickReply.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          shortcut:
            true,
          title: true,
          isActive:
            true
        }
      });

    case "WHATSAPP_CONNECTION":
      return prisma.whatsAppConnection.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          name: true,
          provider:
            true,
          status: true,
          acceptGroups:
            true,
          defaultQueueId:
            true
        }
      });
  }
}

export async function listAuditLogs(input: {
  companyId: string;
  limit: number;
  cursor?: string;
  action?: string;
  entityType?: string;
  actorMembershipId?: string;
}) {
  let cursorWhere:
    Prisma.AuditLogWhereInput =
    {};

  if (
    input.cursor
  ) {
    const cursor =
      await prisma.auditLog.findFirst({
        where: {
          id:
            input.cursor,
          companyId:
            input.companyId
        },
        select: {
          id: true,
          createdAt:
            true
        }
      });

    if (cursor) {
      cursorWhere = {
        OR: [
          {
            createdAt: {
              lt:
                cursor.createdAt
            }
          },
          {
            createdAt:
              cursor.createdAt,
            id: {
              lt:
                cursor.id
            }
          }
        ]
      };
    }
  }

  const rows =
    await prisma.auditLog.findMany({
      where: {
        companyId:
          input.companyId,
        ...cursorWhere,
        ...(input.action
          ? {
              action:
                input.action
            }
          : {}),
        ...(input.entityType
          ? {
              entityType:
                input.entityType
            }
          : {}),
        ...(input.actorMembershipId
          ? {
              actorMembershipId:
                input.actorMembershipId
            }
          : {})
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
      orderBy: [
        {
          createdAt:
            "desc"
        },
        {
          id:
            "desc"
        }
      ],
      take:
        input.limit +
        1
    });

  const hasMore =
    rows.length >
    input.limit;

  const items =
    rows.slice(
      0,
      input.limit
    );

  return {
    items,
    pagination: {
      hasMore,
      cursor:
        hasMore
          ? items[
              items.length -
                1
            ]?.id ??
            null
          : null
    }
  };
}
EOF

cat > apps/api/src/modules/audit/audit.hooks.ts <<'EOF'
import type {
  FastifyInstance,
  FastifyRequest
} from "fastify";

import { requireAuth } from "../auth/auth.guard.js";
import {
  type AuditEntityType,
  recordAudit,
  snapshotAuditEntity
} from "./audit.service.js";

interface AuditContext {
  companyId: string;
  membershipId: string;
  role: string;
  action: string;
  entityType: AuditEntityType;
  entityId:
    | string
    | null;
  before:
    unknown;
  responseBody:
    unknown;
  requestId: string;
  ipAddress: string;
  userAgent:
    | string
    | undefined;
}

const contexts =
  new WeakMap<
    FastifyRequest,
    AuditContext
  >();

function objectValue(
  value: unknown
) {
  return value &&
    typeof value ===
      "object"
    ? value as
        Record<
          string,
          unknown
        >
    : {};
}

function idParam(
  request:
    FastifyRequest
) {
  const params =
    objectValue(
      request.params
    );

  return typeof params.id ===
    "string"
    ? params.id
    : null;
}

function routeDescriptor(
  request:
    FastifyRequest
):
  | {
      action: string;
      entityType:
        AuditEntityType;
      entityId:
        | string
        | null;
    }
  | null {
  const method =
    request.method
      .toUpperCase();

  const route =
    request.routeOptions
      .url;

  const key =
    `${method} ${route}`;

  const param =
    idParam(
      request
    );

  switch (key) {
    case "POST /api/v1/team/memberships":
      return {
        action:
          "TEAM_MEMBERSHIP_CREATED",
        entityType:
          "TEAM_MEMBERSHIP",
        entityId:
          null
      };

    case "PATCH /api/v1/team/memberships/:id":
      return {
        action:
          "TEAM_MEMBERSHIP_UPDATED",
        entityType:
          "TEAM_MEMBERSHIP",
        entityId:
          param
      };

    case "POST /api/v1/queues":
      return {
        action:
          "QUEUE_CREATED",
        entityType:
          "QUEUE",
        entityId:
          null
      };

    case "PUT /api/v1/queues/:id/members":
      return {
        action:
          "QUEUE_MEMBERS_UPDATED",
        entityType:
          "QUEUE",
        entityId:
          param
      };

    case "PUT /api/v1/sla/settings":
      return {
        action:
          "SLA_SETTINGS_UPDATED",
        entityType:
          "SLA_SETTINGS",
        entityId:
          null
      };

    case "POST /api/v1/tags":
      return {
        action:
          "TAG_CREATED",
        entityType:
          "TAG",
        entityId:
          null
      };

    case "PATCH /api/v1/tags/:id":
      return {
        action:
          "TAG_UPDATED",
        entityType:
          "TAG",
        entityId:
          param
      };

    case "POST /api/v1/quick-replies":
      return {
        action:
          "QUICK_REPLY_CREATED",
        entityType:
          "QUICK_REPLY",
        entityId:
          null
      };

    case "PATCH /api/v1/quick-replies/:id":
      return {
        action:
          "QUICK_REPLY_UPDATED",
        entityType:
          "QUICK_REPLY",
        entityId:
          param
      };

    case "POST /api/v1/whatsapp/connections":
      return {
        action:
          "WHATSAPP_CONNECTION_CREATED",
        entityType:
          "WHATSAPP_CONNECTION",
        entityId:
          null
      };

    case "PATCH /api/v1/whatsapp/connections/:id/settings":
      return {
        action:
          "WHATSAPP_CONNECTION_SETTINGS_UPDATED",
        entityType:
          "WHATSAPP_CONNECTION",
        entityId:
          param
      };

    case "POST /api/v1/whatsapp/connections/:id/connect":
      return {
        action:
          "WHATSAPP_CONNECTION_CONNECT_REQUESTED",
        entityType:
          "WHATSAPP_CONNECTION",
        entityId:
          param
      };

    default:
      return null;
  }
}

function responseEntityId(
  entityType:
    AuditEntityType,
  body: unknown
) {
  const root =
    objectValue(
      body
    );

  const key =
    entityType ===
      "TEAM_MEMBERSHIP"
      ? "membership"
      : entityType ===
          "QUEUE"
        ? "queue"
        : entityType ===
            "TAG"
          ? "tag"
          : entityType ===
              "QUICK_REPLY"
            ? "quickReply"
            : entityType ===
                "WHATSAPP_CONNECTION"
              ? "connection"
              : null;

  if (!key) {
    return null;
  }

  const entity =
    objectValue(
      root[key]
    );

  return typeof entity.id ===
    "string"
    ? entity.id
    : null;
}

function parsePayload(
  payload: unknown
) {
  try {
    if (
      typeof payload ===
        "string"
    ) {
      return JSON.parse(
        payload
      );
    }

    if (
      Buffer.isBuffer(
        payload
      )
    ) {
      return JSON.parse(
        payload.toString(
          "utf8"
        )
      );
    }
  } catch {
    return null;
  }

  return null;
}

export function installAdminAuditHooks(
  app: FastifyInstance
) {
  app.addHook(
    "preHandler",
    async request => {
      const descriptor =
        routeDescriptor(
          request
        );

      if (!descriptor) {
        return;
      }

      const auth =
        await requireAuth(
          request
        );

      const before =
        descriptor.entityId
          ? await snapshotAuditEntity({
              companyId:
                auth.companyId,
              entityType:
                descriptor.entityType,
              entityId:
                descriptor.entityId
            })
          : descriptor.entityType ===
              "SLA_SETTINGS"
            ? await snapshotAuditEntity({
                companyId:
                  auth.companyId,
                entityType:
                  descriptor.entityType,
                entityId:
                  auth.companyId
              })
            : null;

      contexts.set(
        request,
        {
          companyId:
            auth.companyId,
          membershipId:
            auth.membershipId,
          role:
            auth.role,
          action:
            descriptor.action,
          entityType:
            descriptor.entityType,
          entityId:
            descriptor.entityId,
          before,
          responseBody:
            null,
          requestId:
            request.id,
          ipAddress:
            request.ip,
          userAgent:
            request.headers[
              "user-agent"
            ]
        }
      );
    }
  );

  app.addHook(
    "onSend",
    async (
      request,
      _reply,
      payload
    ) => {
      const context =
        contexts.get(
          request
        );

      if (context) {
        context.responseBody =
          parsePayload(
            payload
          );
      }

      return payload;
    }
  );

  app.addHook(
    "onResponse",
    async (
      request,
      reply
    ) => {
      const context =
        contexts.get(
          request
        );

      if (
        !context ||
        reply.statusCode >=
          400
      ) {
        return;
      }

      try {
        const entityId =
          context.entityId ??
          (
            context.entityType ===
              "SLA_SETTINGS"
              ? context.companyId
              : responseEntityId(
                  context.entityType,
                  context.responseBody
                )
          );

        const after =
          entityId
            ? await snapshotAuditEntity({
                companyId:
                  context.companyId,
                entityType:
                  context.entityType,
                entityId
              })
            : null;

        await recordAudit({
          companyId:
            context.companyId,
          actorMembershipId:
            context.membershipId,
          action:
            context.action,
          entityType:
            context.entityType,
          entityId,
          before:
            context.before,
          after,
          metadata: {
            role:
              context.role,
            method:
              request.method,
            route:
              request
                .routeOptions
                .url
          },
          requestId:
            context.requestId,
          ipAddress:
            context.ipAddress,
          userAgent:
            context.userAgent
        });
      } catch (error) {
        request.log.error(
          {
            err:
              error
          },
          "Administrative audit write failed."
        );
      } finally {
        contexts.delete(
          request
        );
      }
    }
  );
}
EOF

cat > apps/api/src/modules/audit/audit.routes.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import { listAuditLogs } from "./audit.service.js";

const querySchema =
  z.object({
    limit: z.coerce
      .number()
      .int()
      .min(20)
      .max(200)
      .default(100),
    cursor:
      z.string()
        .uuid()
        .optional(),
    action:
      z.string()
        .trim()
        .min(1)
        .max(80)
        .optional(),
    entityType:
      z.string()
        .trim()
        .min(1)
        .max(60)
        .optional(),
    actorMembershipId:
      z.string()
        .uuid()
        .optional()
  });

export async function auditRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/audit",
    async request => {
      const auth =
        await requirePermission(
          request,
          "audit.read"
        );

      const query =
        querySchema.parse(
          request.query
        );

      return listAuditLogs({
        companyId:
          auth.companyId,
        ...query
      });
    }
  );
}
EOF

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/security/permissions.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  )
    .replace(
      /\r\n/g,
      "\n"
    );

if (
  !content.includes(
    '| "audit.read"'
  )
) {
  content =
    content.replace(
      '  | "admin.test"',
      `  | "admin.test"
  | "audit.read"`
    );

  content =
    content.replace(
      '  OWNER: [\n    "admin.test",',
      `  OWNER: [
    "admin.test",
    "audit.read",`
    );

  content =
    content.replace(
      '  ADMIN: [\n    "admin.test",',
      `  ADMIN: [
    "admin.test",
    "audit.read",`
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
  "apps/api/src/security/permissions.test.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  )
    .replace(
      /\r\n/g,
      "\n"
    );

if (
  !content.includes(
    '"audit.read",'
  )
) {
  content =
    content.replace(
      '    "admin.test",',
      `    "admin.test",
    "audit.read",`
    );

  const supervisorAnchor =
    `          const permission
          of [
            "team.manage",`;

  if (
    content.includes(
      supervisorAnchor
    )
  ) {
    content =
      content.replace(
        supervisorAnchor,
        `          const permission
          of [
            "audit.read",
            "team.manage",`
      );
  }

  const agentAnchor =
    `          const permission
          of [
            "admin.test",`;

  if (
    content.includes(
      agentAnchor
    )
  ) {
    content =
      content.replace(
        agentAnchor,
        `          const permission
          of [
            "admin.test",
            "audit.read",`
      );
  }
}

fs.writeFileSync(
  path,
  content
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/app.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  )
    .replace(
      /\r\n/g,
      "\n"
    );

const routesImport =
  'import { auditRoutes } from "./modules/audit/audit.routes.js";';

const hooksImport =
  'import { installAdminAuditHooks } from "./modules/audit/audit.hooks.js";';

if (
  !content.includes(
    routesImport
  )
) {
  const anchor =
    'import { adminRoutes } from "./modules/admin/admin.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "adminRoutes import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${routesImport}
${hooksImport}`
    );
}

if (
  !content.includes(
    "installAdminAuditHooks(app);"
  )
) {
  const anchor =
    `  app.setErrorHandler((error, request, reply) => {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "app error-handler anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `  installAdminAuditHooks(app);

${anchor}`
    );
}

if (
  !content.includes(
    "await app.register(auditRoutes);"
  )
) {
  const anchor =
    `  await app.register(adminRoutes);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "admin route registration anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  await app.register(auditRoutes);`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > docs/ADMIN_AUDIT.md <<'EOF'
# P1.26 Administrative audit trail

P1.26 adds append-only audit records for successful administrative mutations.

Audited actions include:

- team membership create/update;
- queue create/member replacement;
- SLA setting changes;
- tag create/update;
- quick-reply create/update;
- WhatsApp connection create/settings/connect request.

Each record stores company, actor membership, action, entity, request id,
IP/user-agent and sanitized before/after snapshots.

The audit deliberately excludes:

- passwords and password hashes;
- temporary passwords;
- refresh/access tokens;
- Evolution API keys/webhook secrets;
- QR payloads;
- full quick-reply bodies.

Read access:

`GET /api/v1/audit`

Permission:

`audit.read`

Only OWNER and ADMIN receive this capability in P1.26.

Audit writes occur after a successful business mutation. If the independent
audit write fails, the already completed business mutation is not rolled back;
the API logs the audit failure for operational investigation.
EOF

echo "[P1.26] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.26] Unit tests..."
pnpm test

echo "[P1.26] Typechecking..."
pnpm typecheck

echo
echo "[P1.26] Administrative audit installed."
echo
echo "Migration required before normal runtime:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "After migration, re-run integration tests:"
echo "  pnpm test:integration"
