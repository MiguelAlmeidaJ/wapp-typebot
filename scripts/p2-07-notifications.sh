#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.7] Installing persistent notifications..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/realtime/realtime.bus.ts" \
  "apps/api/src/modules/realtime/realtime.routes.ts" \
  "apps/api/src/modules/messages/message-ingestion.service.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/web/components/auth-provider.tsx" \
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
  apps/api/src/modules/notifications \
  apps/api/prisma/migrations/20260828233000_notifications \
  apps/web/components/notifications \
  docs

# ---------------------------------------------------------------------------
# Prisma
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/prisma/schema.prisma";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

function addRelation(
  modelName,
  fieldLine
) {
  const start =
    content.indexOf(
      `model ${modelName} {`
    );

  if (
    start <
    0
  ) {
    throw new Error(
      `${modelName} model not found.`
    );
  }

  const end =
    content.indexOf(
      "\n}",
      start
    );

  if (
    end <
    0
  ) {
    throw new Error(
      `${modelName} model end not found.`
    );
  }

  const block =
    content.slice(
      start,
      end
    );

  const fieldName =
    fieldLine
      .trim()
      .split(
        /\s+/
      )[0];

  if (
    block.includes(
      `\n  ${fieldName} `
    )
  ) {
    return;
  }

  content =
    content.slice(
      0,
      end
    ) +
    `\n${fieldLine}` +
    content.slice(
      end
    );
}

addRelation(
  "Company",
  "  notifications           Notification[]"
);

addRelation(
  "CompanyMembership",
  "  notifications           Notification[]"
);

addRelation(
  "Ticket",
  "  notifications           Notification[]"
);

if (
  !content.includes(
    "model Notification {"
  )
) {
  content += `

model Notification {
  id              String            @id @default(uuid()) @db.Char(36)
  companyId       String            @db.Char(36)
  membershipId    String            @db.Char(36)
  ticketId        String?           @db.Char(36)
  messageId       String?           @db.Char(36)
  type            String            @db.VarChar(40)
  title           String            @db.VarChar(180)
  body            String            @db.VarChar(500)
  dedupeKey       String            @db.VarChar(190)
  occurrenceCount Int               @default(1)
  readAt          DateTime?
  company         Company           @relation(fields: [companyId], references: [id], onDelete: Cascade)
  membership      CompanyMembership @relation(fields: [membershipId], references: [id], onDelete: Cascade)
  ticket          Ticket?           @relation(fields: [ticketId], references: [id], onDelete: Cascade)
  createdAt       DateTime          @default(now())
  updatedAt       DateTime          @updatedAt

  @@unique([companyId, membershipId, dedupeKey])
  @@index([membershipId, readAt, updatedAt])
  @@index([companyId, updatedAt])
  @@index([ticketId, updatedAt])
}
`;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.7] Notification Prisma model prepared."
);
NODE

cat > apps/api/prisma/migrations/20260828233000_notifications/migration.sql <<'EOF'
CREATE TABLE `Notification` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `membershipId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NULL,
  `messageId` CHAR(36) NULL,
  `type` VARCHAR(40) NOT NULL,
  `title` VARCHAR(180) NOT NULL,
  `body` VARCHAR(500) NOT NULL,
  `dedupeKey` VARCHAR(190) NOT NULL,
  `occurrenceCount` INTEGER NOT NULL DEFAULT 1,
  `readAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),

  UNIQUE INDEX `Notification_companyId_membershipId_dedupeKey_key`
    (`companyId`, `membershipId`, `dedupeKey`),

  INDEX `Notification_membershipId_readAt_updatedAt_idx`
    (`membershipId`, `readAt`, `updatedAt`),

  INDEX `Notification_companyId_updatedAt_idx`
    (`companyId`, `updatedAt`),

  INDEX `Notification_ticketId_updatedAt_idx`
    (`ticketId`, `updatedAt`),

  CONSTRAINT `Notification_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `Notification_membershipId_fkey`
    FOREIGN KEY (`membershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `Notification_ticketId_fkey`
    FOREIGN KEY (`ticketId`)
    REFERENCES `Ticket`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

# ---------------------------------------------------------------------------
# Notification policy
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/notifications/notification.policy.ts <<'EOF'
export function notificationPreview(
  value:
    string
    | null
    | undefined,
  fallback =
    "Nova mensagem"
) {
  const normalized =
    value
      ?.replace(
        /\s+/g,
        " "
      )
      .trim();

  if (
    !normalized
  ) {
    return fallback;
  }

  return normalized.length >
    180
    ? `${normalized.slice(
        0,
        177
      )}...`
    : normalized;
}

export function inboundNotificationKey(
  ticketId: string,
  isNewTicket:
    boolean
) {
  return isNewTicket
    ? `new-ticket:${ticketId}`
    : `inbound:${ticketId}`;
}

export function uniqueMembershipIds(
  values:
    Array<
      string
      | null
      | undefined
    >
) {
  return [
    ...new Set(
      values.filter(
        (
          value
        ): value is string =>
          Boolean(
            value
          )
      )
    )
  ];
}
EOF

cat > apps/api/src/modules/notifications/notification.policy.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  inboundNotificationKey,
  notificationPreview,
  uniqueMembershipIds
} from "./notification.policy.js";

test(
  "notification preview is compact and whitespace-normalized",
  () => {
    assert.equal(
      notificationPreview(
        "  Olá\n\npreciso   de ajuda  "
      ),
      "Olá preciso de ajuda"
    );

    assert.equal(
      notificationPreview(
        null,
        "[imagem]"
      ),
      "[imagem]"
    );
  }
);

test(
  "inbound activity coalesces by ticket",
  () => {
    assert.equal(
      inboundNotificationKey(
        "ticket-1",
        false
      ),
      "inbound:ticket-1"
    );

    assert.equal(
      inboundNotificationKey(
        "ticket-1",
        true
      ),
      "new-ticket:ticket-1"
    );
  }
);

test(
  "recipient ids are unique",
  () => {
    assert.deepEqual(
      uniqueMembershipIds([
        "a",
        "b",
        "a",
        null,
        undefined
      ]),
      [
        "a",
        "b"
      ]
    );
  }
);
EOF

# ---------------------------------------------------------------------------
# Notification service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/notifications/notification.service.ts <<'EOF'
import {
  randomUUID
} from "node:crypto";

import {
  AppError
} from "../../errors/app-error.js";
import {
  prisma
} from "../../lib/database.js";
import {
  publishRealtime
} from "../realtime/realtime.bus.js";
import {
  inboundNotificationKey,
  notificationPreview,
  uniqueMembershipIds
} from "./notification.policy.js";

export type NotificationType =
  | "NEW_TICKET"
  | "INBOUND_MESSAGE"
  | "ASSIGNED_TO_YOU";

async function createOrRefreshNotification(input: {
  companyId: string;
  membershipId: string;
  ticketId?:
    string;
  messageId?:
    string;
  type:
    NotificationType;
  title: string;
  body: string;
  dedupeKey: string;
}) {
  const notification =
    await prisma.notification.upsert({
      where: {
        companyId_membershipId_dedupeKey: {
          companyId:
            input.companyId,
          membershipId:
            input.membershipId,
          dedupeKey:
            input.dedupeKey
        }
      },
      create: {
        companyId:
          input.companyId,
        membershipId:
          input.membershipId,
        ticketId:
          input.ticketId,
        messageId:
          input.messageId,
        type:
          input.type,
        title:
          input.title,
        body:
          input.body,
        dedupeKey:
          input.dedupeKey
      },
      update: {
        ticketId:
          input.ticketId,
        messageId:
          input.messageId,
        type:
          input.type,
        title:
          input.title,
        body:
          input.body,
        occurrenceCount: {
          increment:
            1
        },
        readAt:
          null
      }
    });

  publishRealtime(
    input.companyId,
    {
      type:
        "notification.created",
      notificationId:
        notification.id,
      membershipId:
        input.membershipId,
      ticketId:
        input.ticketId,
      messageId:
        input.messageId
    }
  );

  return notification;
}

async function activeRecipient(
  companyId: string,
  membershipId: string
) {
  return prisma.companyMembership.findFirst({
    where: {
      id:
        membershipId,
      companyId,
      isActive:
        true,
      user: {
        isActive:
          true
      }
    },
    select: {
      id:
        true
    }
  });
}

async function recipientIdsForTicket(input: {
  companyId: string;
  ticketId: string;
}) {
  const ticket =
    await prisma.ticket.findFirst({
      where: {
        id:
          input.ticketId,
        companyId:
          input.companyId
      },
      select: {
        assignedMembershipId:
          true,
        queueId:
          true
      }
    });

  if (
    !ticket
  ) {
    return [];
  }

  if (
    ticket
      .assignedMembershipId
  ) {
    const recipient =
      await activeRecipient(
        input.companyId,
        ticket
          .assignedMembershipId
      );

    return recipient
      ? [
          recipient.id
        ]
      : [];
  }

  if (
    ticket.queueId
  ) {
    const queueMembers =
      await prisma.queueMember.findMany({
        where: {
          queueId:
            ticket.queueId,
          membership: {
            companyId:
              input.companyId,
            isActive:
              true,
            user: {
              isActive:
                true
            }
          }
        },
        select: {
          membershipId:
            true
        }
      });

    const queueRecipients =
      uniqueMembershipIds(
        queueMembers.map(
          item =>
            item.membershipId
        )
      );

    if (
      queueRecipients.length >
      0
    ) {
      return queueRecipients;
    }
  }

  const activeMemberships =
    await prisma.companyMembership.findMany({
      where: {
        companyId:
          input.companyId,
        isActive:
          true,
        user: {
          isActive:
            true
        }
      },
      select: {
        id:
          true
      }
    });

  return activeMemberships.map(
    item =>
      item.id
  );
}

export async function notifyInboundTicketActivity(input: {
  companyId: string;
  ticketId: string;
  messageId: string;
  isNewTicket: boolean;
  preview:
    string
    | null;
  fallbackPreview:
    string;
}) {
  const ticket =
    await prisma.ticket.findFirst({
      where: {
        id:
          input.ticketId,
        companyId:
          input.companyId
      },
      select: {
        contact: {
          select: {
            name:
              true
          }
        }
      }
    });

  if (
    !ticket
  ) {
    return [];
  }

  const recipients =
    await recipientIdsForTicket({
      companyId:
        input.companyId,
      ticketId:
        input.ticketId
    });

  const type:
    NotificationType =
    input.isNewTicket
      ? "NEW_TICKET"
      : "INBOUND_MESSAGE";

  const title =
    input.isNewTicket
      ? "Novo atendimento"
      : `Nova mensagem · ${ticket.contact.name}`;

  const body =
    input.isNewTicket
      ? `${ticket.contact.name}: ${notificationPreview(
          input.preview,
          input.fallbackPreview
        )}`
      : notificationPreview(
          input.preview,
          input.fallbackPreview
        );

  const dedupeKey =
    inboundNotificationKey(
      input.ticketId,
      input.isNewTicket
    );

  return Promise.all(
    recipients.map(
      membershipId =>
        createOrRefreshNotification({
          companyId:
            input.companyId,
          membershipId,
          ticketId:
            input.ticketId,
          messageId:
            input.messageId,
          type,
          title,
          body,
          dedupeKey
        })
    )
  );
}

export async function notifyTicketAssignment(input: {
  companyId: string;
  ticketId: string;
  membershipId: string;
  actorMembershipId?:
    string
    | null;
}) {
  if (
    input.actorMembershipId &&
    input.actorMembershipId ===
      input.membershipId
  ) {
    return null;
  }

  const [
    recipient,
    ticket
  ] =
    await Promise.all([
      activeRecipient(
        input.companyId,
        input.membershipId
      ),
      prisma.ticket.findFirst({
        where: {
          id:
            input.ticketId,
          companyId:
            input.companyId
        },
        select: {
          contact: {
            select: {
              name:
                true
            }
          },
          queue: {
            select: {
              name:
                true
            }
          }
        }
      })
    ]);

  if (
    !recipient ||
    !ticket
  ) {
    return null;
  }

  return createOrRefreshNotification({
    companyId:
      input.companyId,
    membershipId:
      input.membershipId,
    ticketId:
      input.ticketId,
    type:
      "ASSIGNED_TO_YOU",
    title:
      "Atendimento atribuído a você",
    body:
      ticket.queue
        ? `${ticket.contact.name} · ${ticket.queue.name}`
        : ticket
            .contact
            .name,
    dedupeKey:
      `assignment:${input.ticketId}:${randomUUID()}`
  });
}

export async function listNotifications(input: {
  companyId: string;
  membershipId: string;
  limit: number;
  unreadOnly:
    boolean;
}) {
  const where = {
    companyId:
      input.companyId,
    membershipId:
      input.membershipId,
    ...(input.unreadOnly
      ? {
          readAt:
            null
        }
      : {})
  };

  const [
    notifications,
    unreadCount
  ] =
    await Promise.all([
      prisma.notification.findMany({
        where,
        orderBy: {
          updatedAt:
            "desc"
        },
        take:
          Math.min(
            Math.max(
              input.limit,
              1
            ),
            100
          )
      }),
      prisma.notification.count({
        where: {
          companyId:
            input.companyId,
          membershipId:
            input.membershipId,
          readAt:
            null
        }
      })
    ]);

  return {
    notifications,
    unreadCount
  };
}

export async function markNotificationRead(input: {
  companyId: string;
  membershipId: string;
  notificationId: string;
}) {
  const result =
    await prisma.notification.updateMany({
      where: {
        id:
          input.notificationId,
        companyId:
          input.companyId,
        membershipId:
          input.membershipId
      },
      data: {
        readAt:
          new Date()
      }
    });

  if (
    result.count !==
    1
  ) {
    throw new AppError(
      "Notificação não encontrada.",
      404,
      "NOTIFICATION_NOT_FOUND"
    );
  }

  return prisma.notification.findUniqueOrThrow({
    where: {
      id:
        input.notificationId
    }
  });
}

export async function markAllNotificationsRead(input: {
  companyId: string;
  membershipId: string;
}) {
  const result =
    await prisma.notification.updateMany({
      where: {
        companyId:
          input.companyId,
        membershipId:
          input.membershipId,
        readAt:
          null
      },
      data: {
        readAt:
          new Date()
      }
    });

  return {
    updated:
      result.count
  };
}
EOF

# ---------------------------------------------------------------------------
# API routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/notifications/notification.routes.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  requireAuth
} from "../auth/auth.guard.js";
import {
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead
} from "./notification.service.js";

const querySchema =
  z.object({
    limit:
      z.coerce
        .number()
        .int()
        .min(1)
        .max(100)
        .default(40),
    unreadOnly:
      z.enum([
        "true",
        "false"
      ])
        .transform(
          value =>
            value ===
            "true"
        )
        .default(
          "false"
        )
  });

const paramsSchema =
  z.object({
    id:
      z.string()
        .uuid()
  });

export async function notificationRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/notifications",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const query =
        querySchema.parse(
          request.query
        );

      return listNotifications({
        companyId:
          auth.companyId,
        membershipId:
          auth.membershipId,
        limit:
          query.limit,
        unreadOnly:
          query.unreadOnly
      });
    }
  );

  app.post(
    "/api/v1/notifications/:id/read",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        paramsSchema.parse(
          request.params
        );

      return {
        notification:
          await markNotificationRead({
            companyId:
              auth.companyId,
            membershipId:
              auth.membershipId,
            notificationId:
              params.id
          })
      };
    }
  );

  app.post(
    "/api/v1/notifications/read-all",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      return markAllNotificationsRead({
        companyId:
          auth.companyId,
        membershipId:
          auth.membershipId
      });
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# App registration
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/app.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const importLine =
  'import { notificationRoutes } from "./modules/notifications/notification.routes.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { realtimeRoutes } from "./modules/realtime/realtime.routes.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "realtimeRoutes import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    "await app.register(notificationRoutes);"
  )
) {
  const anchor =
    `  await app.register(realtimeRoutes);`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "realtimeRoutes registration anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  await app.register(notificationRoutes);`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Realtime targeted delivery
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const busPath =
  "apps/api/src/modules/realtime/realtime.bus.ts";

let bus =
  fs.readFileSync(
    busPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !bus.includes(
    '| "notification.created"'
  )
) {
  const anchor =
    '  | "note.created"';

  if (
    !bus.includes(
      anchor
    )
  ) {
    throw new Error(
      "RealtimeEventType note anchor not found."
    );
  }

  bus =
    bus.replace(
      anchor,
      `${anchor}
  | "notification.created"`
    );
}

if (
  !bus.includes(
    "notificationId?: string;"
  )
) {
  const anchor =
    "  noteId?: string;";

  if (
    !bus.includes(
      anchor
    )
  ) {
    throw new Error(
      "RealtimeEvent noteId anchor not found."
    );
  }

  bus =
    bus.replace(
      anchor,
      `${anchor}
  notificationId?: string;`
    );
}

fs.writeFileSync(
  busPath,
  bus
);

const routesPath =
  "apps/api/src/modules/realtime/realtime.routes.ts";

let routes =
  fs.readFileSync(
    routesPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldSend =
  `    const send = (event: RealtimeEvent) => {
      reply.raw.write(\`data: \${JSON.stringify(event)}\\n\\n\`);
    };`;

const newSend =
  `    const send = (event: RealtimeEvent) => {
      if (
        event.type ===
          "notification.created" &&
        event.membershipId !==
          auth.membershipId
      ) {
        return;
      }

      reply.raw.write(\`data: \${JSON.stringify(event)}\\n\\n\`);
    };`;

if (
  routes.includes(
    oldSend
  )
) {
  routes =
    routes.replace(
      oldSend,
      newSend
    );
} else if (
  !routes.includes(
    'event.type ===\n          "notification.created"'
  )
) {
  throw new Error(
    "Realtime SSE send anchor not found."
  );
}

fs.writeFileSync(
  routesPath,
  routes
);

console.log(
  "[P2.7] Realtime notification events are membership-filtered."
);
NODE

# ---------------------------------------------------------------------------
# Inbound message notifications
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

const importLine =
  `import {
  notifyInboundTicketActivity
} from "../notifications/notification.service.js";`;

if (
  !content.includes(
    'from "../notifications/notification.service.js"'
  )
) {
  const anchor =
    'import { publishRealtime } from "../realtime/realtime.bus.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "message ingestion realtime import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    "notifyInboundTicketActivity({"
  )
) {
  const anchor =
    `  if (hasMedia) {
    scheduleMessageMediaCapture(
      message.id
    );
  }

  if (!parsed.fromMe) {`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "message ingestion media/automation anchor not found."
    );
  }

  const replacement =
    `  if (hasMedia) {
    scheduleMessageMediaCapture(
      message.id
    );
  }

  if (!parsed.fromMe) {
    await notifyInboundTicketActivity({
      companyId:
        connection.companyId,
      ticketId:
        ticket.id,
      messageId:
        message.id,
      isNewTicket:
        !before,
      preview:
        parsed.body,
      fallbackPreview:
        preview(parsed)
    });

`;

  const suffix =
    `    if (!before) {`;

  content =
    content.replace(
      anchor,
      `${replacement}${suffix}`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.7] Inbound notifications installed."
);
NODE

# ---------------------------------------------------------------------------
# Manual transfer notifications
# ---------------------------------------------------------------------------

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

const importLine =
  `import {
  notifyTicketAssignment
} from "../notifications/notification.service.js";`;

if (
  !content.includes(
    'from "../notifications/notification.service.js"'
  )
) {
  const anchor =
    'import { publishRealtime } from "../realtime/realtime.bus.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "ticket service realtime import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    "await notifyTicketAssignment({"
  )
) {
  const anchor =
    `  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: ticket.id
  });

  return updated;
}

export async function closeTicket`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "transfer completion anchor not found."
    );
  }

  const replacement =
    `  if (
    updated.assignedMembershipId &&
    updated.assignedMembershipId !==
      ticket.assignedMembershipId
  ) {
    await notifyTicketAssignment({
      companyId:
        input.companyId,
      ticketId:
        updated.id,
      membershipId:
        updated.assignedMembershipId,
      actorMembershipId:
        input.actorMembershipId
    });
  }

  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: ticket.id
  });

  return updated;
}

export async function closeTicket`;

  content =
    content.replace(
      anchor,
      replacement
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.7] Manual transfer notifications installed."
);
NODE

# ---------------------------------------------------------------------------
# Automation assignment notifications when P2.4 is present
# ---------------------------------------------------------------------------

if [[ -f "apps/api/src/modules/automations/automation.service.ts" ]]; then
node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/automations/automation.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const importLine =
  `import {
  notifyTicketAssignment
} from "../notifications/notification.service.js";`;

if (
  !content.includes(
    'from "../notifications/notification.service.js"'
  )
) {
  const anchor =
    'import { publishRealtime } from "../realtime/realtime.bus.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "automation realtime import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    "ticket.assignedMembershipId !==\n        membership.id"
  )
) {
  const anchor =
    `      await prisma.ticket.update({
        where: {
          id:
            ticket.id
        },
        data: {
          assignedMembershipId:
            membership.id,
          status:
            "OPEN"
        }
      });

      return {
        type:
          "ASSIGN_MEMBERSHIP" as const,`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "automation ASSIGN_MEMBERSHIP anchor not found."
    );
  }

  const replacement =
    `      await prisma.ticket.update({
        where: {
          id:
            ticket.id
        },
        data: {
          assignedMembershipId:
            membership.id,
          status:
            "OPEN"
        }
      });

      if (
        ticket.assignedMembershipId !==
        membership.id
      ) {
        await notifyTicketAssignment({
          companyId:
            input.companyId,
          ticketId:
            ticket.id,
          membershipId:
            membership.id,
          actorMembershipId:
            null
        });
      }

      return {
        type:
          "ASSIGN_MEMBERSHIP" as const,`;

  content =
    content.replace(
      anchor,
      replacement
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.7] Automation assignment notifications installed."
);
NODE
fi

# ---------------------------------------------------------------------------
# Web realtime contract
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/lib/realtime-types.ts";

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
    '| "notification.created"'
  )
) {
  const anchor =
    '  | "note.created"';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "web realtime note anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  | "notification.created"`
    );
}

if (
  !content.includes(
    "notificationId?: string;"
  )
) {
  const anchor =
    "  noteId?: string;";

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "web realtime noteId anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  notificationId?: string;`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Global notification center
# ---------------------------------------------------------------------------

cat > apps/web/components/notifications/notification-center.tsx <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState
} from "react";
import {
  useRouter
} from "next/navigation";

import {
  useAuth
} from "@/components/auth-provider";
import {
  ApiError
} from "@/lib/api";

interface WappNotification {
  id: string;
  ticketId:
    | string
    | null;
  messageId:
    | string
    | null;
  type:
    | "NEW_TICKET"
    | "INBOUND_MESSAGE"
    | "ASSIGNED_TO_YOU"
    | string;
  title: string;
  body: string;
  occurrenceCount:
    number;
  readAt:
    | string
    | null;
  createdAt:
    string;
  updatedAt:
    string;
}

interface NotificationPayload {
  notifications:
    WappNotification[];
  unreadCount:
    number;
}

function relativeTime(
  value: string
) {
  const seconds =
    Math.max(
      0,
      Math.floor(
        (
          Date.now() -
          new Date(
            value
          ).getTime()
        ) /
          1000
      )
    );

  if (
    seconds <
    60
  ) {
    return "agora";
  }

  const minutes =
    Math.floor(
      seconds /
      60
    );

  if (
    minutes <
    60
  ) {
    return `${minutes} min`;
  }

  const hours =
    Math.floor(
      minutes /
      60
    );

  if (
    hours <
    24
  ) {
    return `${hours}h`;
  }

  const days =
    Math.floor(
      hours /
      24
    );

  return `${days}d`;
}

export function NotificationCenter() {
  const router =
    useRouter();

  const {
    session,
    loading,
    request,
    subscribe
  } =
    useAuth();

  const [
    open,
    setOpen
  ] =
    useState(
      false
    );

  const [
    items,
    setItems
  ] =
    useState<
      WappNotification[]
    >([]);

  const [
    unreadCount,
    setUnreadCount
  ] =
    useState(
      0
    );

  const [
    error,
    setError
  ] =
    useState("");

  const [
    browserPermission,
    setBrowserPermission
  ] =
    useState<
      NotificationPermission
      | "unsupported"
    >(
      "unsupported"
    );

  const mountedRef =
    useRef(
      false
    );

  const load =
    useCallback(
      async () => {
        const payload =
          await request<
            NotificationPayload
          >(
            "/api/v1/notifications?limit=40"
          );

        setItems(
          payload.notifications
        );

        setUnreadCount(
          payload.unreadCount
        );

        return payload;
      },
      [
        request
      ]
    );

  const showBrowserNotification =
    useCallback(
      (
        item:
          WappNotification
      ) => {
        if (
          typeof window ===
            "undefined" ||
          typeof Notification ===
            "undefined" ||
          Notification.permission !==
            "granted" ||
          document.visibilityState ===
            "visible"
        ) {
          return;
        }

        const browserNotification =
          new Notification(
            item.title,
            {
              body:
                item.body,
              tag:
                `wapp-${item.id}`
            }
          );

        browserNotification.onclick =
          () => {
            window.focus();

            if (
              item.ticketId
            ) {
              router.push(
                `/dashboard/conversations?ticket=${item.ticketId}`
              );
            }

            browserNotification.close();
          };
      },
      [
        router
      ]
    );

  useEffect(
    () => {
      mountedRef.current =
        true;

      if (
        typeof Notification !==
        "undefined"
      ) {
        setBrowserPermission(
          Notification.permission
        );
      }

      return () => {
        mountedRef.current =
          false;
      };
    },
    []
  );

  useEffect(
    () => {
      if (
        loading ||
        !session
      ) {
        return;
      }

      void load()
        .catch(() => {});

      return subscribe(
        "/api/v1/realtime/events",
        event => {
          if (
            event.type !==
              "notification.created" ||
            !event.notificationId
          ) {
            return;
          }

          void load()
            .then(
              payload => {
                const item =
                  payload.notifications.find(
                    notification =>
                      notification.id ===
                      event.notificationId
                  );

                if (
                  item
                ) {
                  showBrowserNotification(
                    item
                  );
                }
              }
            )
            .catch(() => {});
        }
      );
    },
    [
      load,
      loading,
      session,
      showBrowserNotification,
      subscribe
    ]
  );

  async function enableBrowserNotifications() {
    if (
      typeof Notification ===
      "undefined"
    ) {
      setBrowserPermission(
        "unsupported"
      );

      return;
    }

    const permission =
      await Notification.requestPermission();

    if (
      mountedRef.current
    ) {
      setBrowserPermission(
        permission
      );
    }
  }

  async function markRead(
    id: string
  ) {
    try {
      await request(
        `/api/v1/notifications/${id}/read`,
        {
          method:
            "POST"
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível atualizar a notificação."
      );
    }
  }

  async function openNotification(
    item:
      WappNotification
  ) {
    if (
      !item.readAt
    ) {
      await markRead(
        item.id
      );
    }

    setOpen(
      false
    );

    if (
      item.ticketId
    ) {
      router.push(
        `/dashboard/conversations?ticket=${item.ticketId}`
      );
    }
  }

  async function markAll() {
    try {
      await request(
        "/api/v1/notifications/read-all",
        {
          method:
            "POST"
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível marcar as notificações como lidas."
      );
    }
  }

  if (
    loading ||
    !session
  ) {
    return null;
  }

  return (
    <aside
      className={
        open
          ? "notification-center notification-center--open"
          : "notification-center"
      }
    >
      <button
        aria-expanded={
          open
        }
        className="notification-center__trigger"
        onClick={() => {
          setOpen(
            current =>
              !current
          );

          setError("");

          if (
            !open
          ) {
            void load()
              .catch(() => {});
          }
        }}
        type="button"
      >
        <span>
          Avisos
        </span>

        {unreadCount >
          0 && (
          <strong>
            {unreadCount >
            99
              ? "99+"
              : unreadCount}
          </strong>
        )}
      </button>

      {open && (
        <div className="notification-center__panel">
          <header>
            <div>
              <span className="eyebrow">
                Central
              </span>

              <strong>
                Notificações
              </strong>
            </div>

            {unreadCount >
              0 && (
              <button
                onClick={() =>
                  void markAll()
                }
                type="button"
              >
                Marcar todas como lidas
              </button>
            )}
          </header>

          {browserPermission !==
            "granted" && (
            <div className="notification-browser-optin">
              <div>
                <strong>
                  Alertas do navegador
                </strong>

                <span>
                  Receba avisos quando o Wapp estiver em segundo plano.
                </span>
              </div>

              <button
                disabled={
                  browserPermission ===
                    "denied" ||
                  browserPermission ===
                    "unsupported"
                }
                onClick={() =>
                  void enableBrowserNotifications()
                }
                type="button"
              >
                {browserPermission ===
                "denied"
                  ? "Bloqueado"
                  : browserPermission ===
                      "unsupported"
                    ? "Indisponível"
                    : "Ativar"}
              </button>
            </div>
          )}

          {error && (
            <div className="notification-center__error">
              {error}
            </div>
          )}

          <div className="notification-center__list">
            {items.length ===
            0 ? (
              <div className="notification-center__empty">
                Nenhum aviso por aqui.
              </div>
            ) : (
              items.map(
                item => (
                  <button
                    className={
                      item.readAt
                        ? "notification-item"
                        : "notification-item notification-item--unread"
                    }
                    key={
                      item.id
                    }
                    onClick={() =>
                      void openNotification(
                        item
                      )
                    }
                    type="button"
                  >
                    <span className="notification-item__indicator" />

                    <div className="notification-item__copy">
                      <div>
                        <strong>
                          {item.title}
                        </strong>

                        <time>
                          {relativeTime(
                            item.updatedAt
                          )}
                        </time>
                      </div>

                      <p>
                        {item.body}
                      </p>

                      {item.occurrenceCount >
                        1 && (
                        <small>
                          {item.occurrenceCount} ocorrências nesta conversa
                        </small>
                      )}
                    </div>
                  </button>
                )
              )
            )}
          </div>
        </div>
      )}
    </aside>
  );
}
EOF

cat > apps/web/app/dashboard/layout.tsx <<'EOF'
import type {
  ReactNode
} from "react";

import {
  NotificationCenter
} from "@/components/notifications/notification-center";

export default function DashboardLayout({
  children
}: Readonly<{
  children:
    ReactNode;
}>) {
  return (
    <>
      {children}
      <NotificationCenter />
    </>
  );
}
EOF

# ---------------------------------------------------------------------------
# Notification deep-link support in Conversations
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

if (
  content.includes(
    'import { useRouter } from "next/navigation";'
  )
) {
  content =
    content.replace(
      'import { useRouter } from "next/navigation";',
      'import { useRouter, useSearchParams } from "next/navigation";'
    );
} else if (
  !content.includes(
    "useSearchParams"
  )
) {
  throw new Error(
    "Conversations next/navigation import anchor not found."
  );
}

if (
  !content.includes(
    "const searchParams = useSearchParams();"
  )
) {
  const anchor =
    `  const router = useRouter();`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Conversations router anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  const searchParams = useSearchParams();`
    );
}

if (
  !content.includes(
    "const notificationTicketId ="
  )
) {
  const anchor =
    `  const selectedTicket = useMemo(`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "selectedTicket memo anchor not found."
    );
  }

  const addition =
    `  const notificationTicketId =
    searchParams.get(
      "ticket"
    );

`;

  content =
    content.replace(
      anchor,
      `${addition}${anchor}`
    );
}

if (
  !content.includes(
    "notificationTicketId &&\n      tickets.some"
  )
) {
  const anchor =
    `  useEffect(() => {
    if (!selectedId) {`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "selectedId effect anchor not found."
    );
  }

  const effect =
    `  useEffect(() => {
    if (
      notificationTicketId &&
      tickets.some(
        ticket =>
          ticket.id ===
          notificationTicketId
      )
    ) {
      setSelectedId(
        notificationTicketId
      );

      router.replace(
        "/dashboard/conversations",
        {
          scroll:
            false
        }
      );
    }
  }, [
    notificationTicketId,
    router,
    tickets
  ]);

`;

  content =
    content.replace(
      anchor,
      `${effect}${anchor}`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.7] Conversation deep links installed."
);
NODE

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

if ! grep -Fq -- "WAPP P2.7 / NOTIFICATION CENTER" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P2.7 / NOTIFICATION CENTER --------------------------------- */

.notification-center {
  position: fixed;
  top: 78px;
  right: 18px;
  z-index: 240;
}

.notification-center__trigger {
  display: inline-flex;
  min-height: 32px;
  align-items: center;
  gap: 7px;
  border: 1px solid var(--line);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.96);
  box-shadow: 0 8px 22px rgba(24, 39, 30, 0.06);
  padding: 0 10px;
  color: var(--ink);
  font: inherit;
  font-size: 8px;
  font-weight: 760;
  cursor: pointer;
  backdrop-filter: blur(10px);
}

.notification-center__trigger:hover,
.notification-center--open
  .notification-center__trigger {
  border-color: rgba(31, 122, 80, 0.24);
  color: var(--accent-dark);
}

.notification-center__trigger strong {
  display: grid;
  min-width: 18px;
  height: 18px;
  place-items: center;
  border-radius: 999px;
  background: var(--accent-dark);
  padding: 0 5px;
  color: white;
  font-size: 7px;
}

.notification-center__panel {
  position: absolute;
  top: 39px;
  right: 0;
  width: min(370px, calc(100vw - 28px));
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.99);
  box-shadow: 0 22px 60px rgba(22, 37, 28, 0.14);
  backdrop-filter: blur(18px);
}

.notification-center__panel > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  border-bottom: 1px solid var(--line);
  padding: 13px 14px;
}

.notification-center__panel > header > div {
  display: grid;
  gap: 2px;
}

.notification-center__panel > header strong {
  font-size: 12px;
}

.notification-center__panel
  > header
  > button {
  border: 0;
  background: transparent;
  color: var(--accent-dark);
  padding: 3px 0;
  font-size: 7px;
  font-weight: 760;
  cursor: pointer;
}

.notification-browser-optin {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  border-bottom: 1px solid var(--line);
  background: #fafbfa;
  padding: 10px 14px;
}

.notification-browser-optin > div {
  display: grid;
  gap: 2px;
}

.notification-browser-optin strong {
  font-size: 8px;
}

.notification-browser-optin span {
  color: var(--muted);
  font-size: 7px;
  line-height: 1.4;
}

.notification-browser-optin button {
  flex: 0 0 auto;
  border: 1px solid var(--line);
  border-radius: 7px;
  background: white;
  padding: 5px 8px;
  color: var(--accent-dark);
  font-size: 7px;
  font-weight: 760;
  cursor: pointer;
}

.notification-browser-optin button:disabled {
  color: var(--muted);
  cursor: not-allowed;
  opacity: 0.65;
}

.notification-center__error {
  border-bottom: 1px solid rgba(163, 59, 50, 0.12);
  background: rgba(163, 59, 50, 0.06);
  padding: 8px 14px;
  color: #973a32;
  font-size: 8px;
}

.notification-center__list {
  max-height: min(480px, calc(100vh - 190px));
  overflow-y: auto;
  scrollbar-width: thin;
}

.notification-item {
  display: grid;
  width: 100%;
  grid-template-columns: 7px minmax(0, 1fr);
  gap: 8px;
  border: 0;
  border-bottom: 1px solid #edf0ed;
  background: white;
  padding: 11px 13px;
  text-align: left;
  cursor: pointer;
}

.notification-item:last-child {
  border-bottom: 0;
}

.notification-item:hover {
  background: #fafbfa;
}

.notification-item--unread {
  background: rgba(31, 122, 80, 0.035);
}

.notification-item__indicator {
  width: 6px;
  height: 6px;
  margin-top: 4px;
  border-radius: 999px;
  background: transparent;
}

.notification-item--unread
  .notification-item__indicator {
  background: var(--accent-dark);
}

.notification-item__copy {
  display: grid;
  min-width: 0;
  gap: 4px;
}

.notification-item__copy > div {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 10px;
}

.notification-item__copy strong {
  overflow: hidden;
  color: var(--ink);
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.notification-item__copy time,
.notification-item__copy small {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 7px;
}

.notification-item__copy p {
  display: -webkit-box;
  overflow: hidden;
  margin: 0;
  color: #59635d;
  font-size: 8px;
  line-height: 1.45;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.notification-center__empty {
  padding: 30px 16px;
  color: var(--muted);
  font-size: 9px;
  text-align: center;
}

@media (max-width: 720px) {
  .notification-center {
    top: 66px;
    right: 12px;
  }

  .notification-center__panel {
    width: min(360px, calc(100vw - 24px));
  }
}

/* --- /WAPP P2.7 ------------------------------------------------------ */
EOF
fi

# ---------------------------------------------------------------------------
# Register tests
# ---------------------------------------------------------------------------

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
  "src/modules/notifications/notification.policy.test.ts";

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

cat > docs/P2_07_NOTIFICATIONS.md <<'EOF'
# P2.7 Notifications

P2.7 adds persistent, recipient-scoped notifications.

## Persistent model

Each notification belongs to:

- one company;
- one company membership;
- optionally one ticket/message.

Fields include:

- type;
- title/body;
- unread/read state;
- occurrence count;
- updated timestamp;
- dedupe key.

Unread state survives refresh, logout and server restart.

## Notification sources

### New inbound ticket

If a ticket is unassigned:

1. notify active members configured in the ticket queue;
2. if the queue has no explicit members, notify all active company members.

### Inbound message on an existing ticket

If assigned, only the active assignee is notified.

If unassigned, the same queue/fallback recipient policy is used.

Repeated inbound messages for the same ticket are coalesced into one
notification per recipient. The notification becomes unread again, updates its
preview and increments `occurrenceCount`.

### Assignment / transfer

When a ticket is transferred to another membership, that membership receives a
targeted notification.

Self-assignment does not notify the actor.

P2.4 `ASSIGN_MEMBERSHIP` automation also creates the targeted assignment
notification when it changes the assignee.

## Realtime privacy

The Redis realtime bus remains company-scoped internally, but
`notification.created` is filtered by the authenticated membership inside the
SSE route.

A browser never receives another membership's notification event.

The event carries ids only; notification content is fetched through the
recipient-scoped API.

## Browser alerts

The Dashboard layout mounts one global Notification Center.

Browser notifications are opt-in and require an explicit user click.

Desktop alerts are only shown when:

- browser permission is granted;
- the Wapp document is not visible.

This is realtime browser notification, not Web Push. The browser/app must still
have an active authenticated Wapp tab. Offline push infrastructure is outside
P2.7.

## Deep links

Clicking a notification navigates to:

`/dashboard/conversations?ticket=<ticket id>`

The conversation page consumes the target once and immediately removes the
query parameter while keeping the selected conversation open.

## API

- `GET /api/v1/notifications`
- `POST /api/v1/notifications/:id/read`
- `POST /api/v1/notifications/read-all`

All endpoints are authenticated and automatically scoped to the current
membership. There is no API to read another member's notification list.

## Migration

P2.7 introduces the `Notification` table.
EOF

echo "[P2.7] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P2.7] Unit tests..."
pnpm test

echo "[P2.7] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.7] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.7] CODE VALIDATION PASS."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
