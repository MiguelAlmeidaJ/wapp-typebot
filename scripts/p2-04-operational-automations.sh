#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.4] Installing operational automations..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/jobs/job-runtime.ts" \
  "apps/api/src/jobs/job-redis.ts" \
  "apps/api/src/worker.ts" \
  "apps/api/src/modules/messages/message-ingestion.service.ts" \
  "apps/api/src/modules/tickets/ticket-event.service.ts" \
  "apps/api/src/modules/audit/audit.service.ts" \
  "apps/api/src/modules/audit/audit.hooks.ts" \
  "apps/api/src/security/permissions.ts" \
  "apps/api/src/security/permissions.test.ts" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -Fq -- "createMaintenanceWorker" apps/api/src/jobs/job-runtime.ts; then
  echo "ERROR: P1.27 durable maintenance worker baseline is required."
  exit 1
fi

mkdir -p \
  apps/api/src/modules/automations \
  apps/api/src/jobs \
  apps/api/prisma/migrations/20260828203000_operational_automations \
  apps/web/app/dashboard/automations \
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

if (
  !content.includes(
    "enum AutomationTrigger {"
  )
) {
  const anchor =
    "enum MembershipRole {";

  const index =
    content.indexOf(
      anchor
    );

  if (index < 0) {
    throw new Error(
      "MembershipRole enum anchor not found."
    );
  }

  const enums = `enum AutomationTrigger {
  TICKET_CREATED
  INBOUND_MESSAGE
}

enum AutomationConversationType {
  ALL
  DIRECT
  GROUP
}

enum AutomationActionType {
  SET_QUEUE
  ASSIGN_MEMBERSHIP
  ADD_TAG
  SEND_TEXT
}

enum AutomationRunStatus {
  RUNNING
  SUCCESS
  FAILED
}

`;

  content =
    content.slice(
      0,
      index
    ) +
    enums +
    content.slice(
      index
    );
}

if (
  !content.includes(
    "model AutomationRule {"
  )
) {
  content += `

model AutomationRule {
  id                  String                     @id @default(uuid()) @db.Char(36)
  companyId           String                     @db.Char(36)
  name                String                     @db.VarChar(160)
  isActive            Boolean                    @default(true)
  trigger             AutomationTrigger
  keywordContains     String?                    @db.VarChar(190)
  onlyIfUnassigned    Boolean                    @default(false)
  conversationType    AutomationConversationType @default(ALL)
  priority            Int                        @default(100)
  createdByMembershipId String?                  @db.Char(36)
  createdAt           DateTime                   @default(now())
  updatedAt           DateTime                   @updatedAt

  @@index([companyId, isActive, trigger, priority])
  @@index([companyId, updatedAt])
}

model AutomationAction {
  id           String               @id @default(uuid()) @db.Char(36)
  ruleId       String               @db.Char(36)
  type         AutomationActionType
  orderIndex   Int                  @default(0)
  queueId      String?              @db.Char(36)
  membershipId String?              @db.Char(36)
  tagId        String?              @db.Char(36)
  text         String?              @db.Text
  createdAt    DateTime             @default(now())

  @@index([ruleId, orderIndex])
}

model AutomationRun {
  id              String              @id @default(uuid()) @db.Char(36)
  companyId       String              @db.Char(36)
  ruleId          String              @db.Char(36)
  ticketId        String              @db.Char(36)
  sourceMessageId String              @db.Char(36)
  trigger         AutomationTrigger
  status          AutomationRunStatus @default(RUNNING)
  matched         Boolean             @default(false)
  dedupeKey       String              @unique @db.VarChar(190)
  details         Json?
  error           String?             @db.Text
  startedAt       DateTime            @default(now())
  finishedAt      DateTime?
  createdAt       DateTime            @default(now())

  @@index([companyId, createdAt])
  @@index([ruleId, createdAt])
  @@index([ticketId, createdAt])
}
`;
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > apps/api/prisma/migrations/20260828203000_operational_automations/migration.sql <<'EOF'
CREATE TABLE `AutomationRule` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `name` VARCHAR(160) NOT NULL,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `trigger` ENUM('TICKET_CREATED', 'INBOUND_MESSAGE') NOT NULL,
  `keywordContains` VARCHAR(190) NULL,
  `onlyIfUnassigned` BOOLEAN NOT NULL DEFAULT false,
  `conversationType` ENUM('ALL', 'DIRECT', 'GROUP') NOT NULL DEFAULT 'ALL',
  `priority` INTEGER NOT NULL DEFAULT 100,
  `createdByMembershipId` CHAR(36) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  INDEX `AutomationRule_companyId_isActive_trigger_priority_idx`
    (`companyId`, `isActive`, `trigger`, `priority`),
  INDEX `AutomationRule_companyId_updatedAt_idx`
    (`companyId`, `updatedAt`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `AutomationAction` (
  `id` CHAR(36) NOT NULL,
  `ruleId` CHAR(36) NOT NULL,
  `type` ENUM('SET_QUEUE', 'ASSIGN_MEMBERSHIP', 'ADD_TAG', 'SEND_TEXT') NOT NULL,
  `orderIndex` INTEGER NOT NULL DEFAULT 0,
  `queueId` CHAR(36) NULL,
  `membershipId` CHAR(36) NULL,
  `tagId` CHAR(36) NULL,
  `text` TEXT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  INDEX `AutomationAction_ruleId_orderIndex_idx`
    (`ruleId`, `orderIndex`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `AutomationRun` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `ruleId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NOT NULL,
  `sourceMessageId` CHAR(36) NOT NULL,
  `trigger` ENUM('TICKET_CREATED', 'INBOUND_MESSAGE') NOT NULL,
  `status` ENUM('RUNNING', 'SUCCESS', 'FAILED') NOT NULL DEFAULT 'RUNNING',
  `matched` BOOLEAN NOT NULL DEFAULT false,
  `dedupeKey` VARCHAR(190) NOT NULL,
  `details` JSON NULL,
  `error` TEXT NULL,
  `startedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `finishedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  UNIQUE INDEX `AutomationRun_dedupeKey_key` (`dedupeKey`),
  INDEX `AutomationRun_companyId_createdAt_idx`
    (`companyId`, `createdAt`),
  INDEX `AutomationRun_ruleId_createdAt_idx`
    (`ruleId`, `createdAt`),
  INDEX `AutomationRun_ticketId_createdAt_idx`
    (`ticketId`, `createdAt`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

# ---------------------------------------------------------------------------
# Automation service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/automations/automation.service.ts <<'EOF'
import { randomUUID } from "node:crypto";

import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { recordAudit } from "../audit/audit.service.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import { recordTicketEvent } from "../tickets/ticket-event.service.js";

export type AutomationTriggerValue =
  | "TICKET_CREATED"
  | "INBOUND_MESSAGE";

export type AutomationConversationTypeValue =
  | "ALL"
  | "DIRECT"
  | "GROUP";

export type AutomationActionTypeValue =
  | "SET_QUEUE"
  | "ASSIGN_MEMBERSHIP"
  | "ADD_TAG"
  | "SEND_TEXT";

export interface AutomationActionInput {
  type:
    AutomationActionTypeValue;
  queueId?: string;
  membershipId?: string;
  tagId?: string;
  text?: string;
}

export interface AutomationRuleInput {
  name: string;
  isActive?: boolean;
  trigger:
    AutomationTriggerValue;
  keywordContains?:
    | string
    | null;
  onlyIfUnassigned?: boolean;
  conversationType?:
    AutomationConversationTypeValue;
  priority?: number;
  actions:
    AutomationActionInput[];
}

function getObject(
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
    : undefined;
}

function getString(
  value: unknown
) {
  return typeof value ===
      "string" &&
    value.length >
      0
    ? value
    : undefined;
}

function sentExternalId(
  result: unknown
) {
  const body =
    getObject(
      result
    );

  const key =
    getObject(
      body?.key
    );

  return (
    getString(
      key?.id
    ) ??
    `wapp-automation-${randomUUID()}`
  );
}

function sentTimestamp(
  result: unknown
) {
  const body =
    getObject(
      result
    );

  const raw =
    body
      ?.messageTimestamp;

  const seconds =
    typeof raw ===
      "number"
      ? raw
      : typeof raw ===
          "string"
        ? Number(
            raw
          )
        : NaN;

  return Number.isFinite(
    seconds
  )
    ? new Date(
        seconds *
          1000
      )
    : new Date();
}

async function validateActions(
  companyId: string,
  actions:
    AutomationActionInput[]
) {
  for (
    const action
    of actions
  ) {
    switch (
      action.type
    ) {
      case "SET_QUEUE": {
        if (
          !action.queueId
        ) {
          throw new AppError(
            "A ação de fila precisa de uma fila.",
            422,
            "AUTOMATION_QUEUE_REQUIRED"
          );
        }

        const queue =
          await prisma.queue.findFirst({
            where: {
              id:
                action.queueId,
              companyId,
              isActive:
                true
            },
            select: {
              id: true
            }
          });

        if (!queue) {
          throw new AppError(
            "Fila da automação não encontrada.",
            422,
            "AUTOMATION_QUEUE_INVALID"
          );
        }

        break;
      }

      case "ASSIGN_MEMBERSHIP": {
        if (
          !action.membershipId
        ) {
          throw new AppError(
            "A ação de atendente precisa de um atendente.",
            422,
            "AUTOMATION_MEMBERSHIP_REQUIRED"
          );
        }

        const membership =
          await prisma.companyMembership.findFirst({
            where: {
              id:
                action.membershipId,
              companyId,
              isActive:
                true
            },
            select: {
              id: true
            }
          });

        if (!membership) {
          throw new AppError(
            "Atendente da automação não encontrado.",
            422,
            "AUTOMATION_MEMBERSHIP_INVALID"
          );
        }

        break;
      }

      case "ADD_TAG": {
        if (
          !action.tagId
        ) {
          throw new AppError(
            "A ação de etiqueta precisa de uma etiqueta.",
            422,
            "AUTOMATION_TAG_REQUIRED"
          );
        }

        const tag =
          await prisma.tag.findFirst({
            where: {
              id:
                action.tagId,
              companyId,
              isActive:
                true
            },
            select: {
              id: true
            }
          });

        if (!tag) {
          throw new AppError(
            "Etiqueta da automação não encontrada.",
            422,
            "AUTOMATION_TAG_INVALID"
          );
        }

        break;
      }

      case "SEND_TEXT": {
        const text =
          action.text
            ?.trim();

        if (
          !text
        ) {
          throw new AppError(
            "A ação de mensagem precisa de um texto.",
            422,
            "AUTOMATION_TEXT_REQUIRED"
          );
        }

        if (
          text.length >
          4096
        ) {
          throw new AppError(
            "Mensagem automática excede 4096 caracteres.",
            422,
            "AUTOMATION_TEXT_TOO_LONG"
          );
        }

        break;
      }
    }
  }
}

function actionCreateData(
  ruleId: string,
  actions:
    AutomationActionInput[]
) {
  return actions.map(
    (
      action,
      index
    ) => ({
      ruleId,
      type:
        action.type,
      orderIndex:
        index,
      queueId:
        action.queueId,
      membershipId:
        action.membershipId,
      tagId:
        action.tagId,
      text:
        action.text
          ?.trim()
    })
  );
}

export async function listAutomationRules(
  companyId: string
) {
  const rules =
    await prisma.automationRule.findMany({
      where: {
        companyId
      },
      orderBy: [
        {
          isActive:
            "desc"
        },
        {
          priority:
            "asc"
        },
        {
          createdAt:
            "asc"
        }
      ],
      take: 200
    });

  const actions =
    rules.length >
      0
      ? await prisma.automationAction.findMany({
          where: {
            ruleId: {
              in:
                rules.map(
                  rule =>
                    rule.id
                )
            }
          },
          orderBy: [
            {
              ruleId:
                "asc"
            },
            {
              orderIndex:
                "asc"
            }
          ]
        })
      : [];

  const byRule =
    new Map<
      string,
      typeof actions
    >();

  for (
    const action
    of actions
  ) {
    const current =
      byRule.get(
        action.ruleId
      ) ?? [];

    current.push(
      action
    );

    byRule.set(
      action.ruleId,
      current
    );
  }

  return rules.map(
    rule => ({
      ...rule,
      actions:
        byRule.get(
          rule.id
        ) ?? []
    })
  );
}

export async function listAutomationRuns(
  companyId: string,
  limit = 50
) {
  return prisma.automationRun.findMany({
    where: {
      companyId
    },
    orderBy: {
      createdAt:
        "desc"
    },
    take:
      Math.min(
        Math.max(
          limit,
          1
        ),
        100
      )
  });
}

export async function createAutomationRule(input: {
  companyId: string;
  actorMembershipId: string;
  rule:
    AutomationRuleInput;
}) {
  await validateActions(
    input.companyId,
    input.rule.actions
  );

  const id =
    randomUUID();

  await prisma.$transaction([
    prisma.automationRule.create({
      data: {
        id,
        companyId:
          input.companyId,
        name:
          input.rule.name
            .trim(),
        isActive:
          input.rule
            .isActive ??
          true,
        trigger:
          input.rule.trigger,
        keywordContains:
          input.rule
            .keywordContains
            ?.trim() ||
          null,
        onlyIfUnassigned:
          input.rule
            .onlyIfUnassigned ??
          false,
        conversationType:
          input.rule
            .conversationType ??
          "ALL",
        priority:
          input.rule
            .priority ??
          100,
        createdByMembershipId:
          input.actorMembershipId
      }
    }),
    prisma.automationAction.createMany({
      data:
        actionCreateData(
          id,
          input.rule.actions
        )
    })
  ]);

  const automation =
    (
      await listAutomationRules(
        input.companyId
      )
    ).find(
      rule =>
        rule.id ===
        id
    );

  await recordAudit({
    companyId:
      input.companyId,
    actorMembershipId:
      input.actorMembershipId,
    action:
      "AUTOMATION_CREATED",
    entityType:
      "AUTOMATION_RULE",
    entityId:
      id,
    after:
      automation
  });

  return automation;
}

export async function updateAutomationRule(input: {
  companyId: string;
  actorMembershipId: string;
  ruleId: string;
  patch: Partial<
    Omit<
      AutomationRuleInput,
      "actions"
    >
  > & {
    actions?:
      AutomationActionInput[];
  };
}) {
  const existing =
    (
      await listAutomationRules(
        input.companyId
      )
    ).find(
      rule =>
        rule.id ===
        input.ruleId
    );

  if (!existing) {
    throw new AppError(
      "Automação não encontrada.",
      404,
      "AUTOMATION_NOT_FOUND"
    );
  }

  if (
    input.patch.actions
  ) {
    await validateActions(
      input.companyId,
      input.patch.actions
    );
  }

  await prisma.$transaction(
    async tx => {
      await tx.automationRule.update({
        where: {
          id:
            existing.id
        },
        data: {
          ...(input.patch
            .name !==
          undefined
            ? {
                name:
                  input.patch
                    .name.trim()
              }
            : {}),
          ...(input.patch
            .isActive !==
          undefined
            ? {
                isActive:
                  input.patch
                    .isActive
              }
            : {}),
          ...(input.patch
            .trigger !==
          undefined
            ? {
                trigger:
                  input.patch
                    .trigger
              }
            : {}),
          ...(input.patch
            .keywordContains !==
          undefined
            ? {
                keywordContains:
                  input.patch
                    .keywordContains
                    ?.trim() ||
                  null
              }
            : {}),
          ...(input.patch
            .onlyIfUnassigned !==
          undefined
            ? {
                onlyIfUnassigned:
                  input.patch
                    .onlyIfUnassigned
              }
            : {}),
          ...(input.patch
            .conversationType !==
          undefined
            ? {
                conversationType:
                  input.patch
                    .conversationType
              }
            : {}),
          ...(input.patch
            .priority !==
          undefined
            ? {
                priority:
                  input.patch
                    .priority
              }
            : {})
        }
      });

      if (
        input.patch.actions
      ) {
        await tx.automationAction.deleteMany({
          where: {
            ruleId:
              existing.id
          }
        });

        await tx.automationAction.createMany({
          data:
            actionCreateData(
              existing.id,
              input.patch
                .actions
            )
        });
      }
    }
  );

  const updated =
    (
      await listAutomationRules(
        input.companyId
      )
    ).find(
      rule =>
        rule.id ===
        existing.id
    );

  await recordAudit({
    companyId:
      input.companyId,
    actorMembershipId:
      input.actorMembershipId,
    action:
      "AUTOMATION_UPDATED",
    entityType:
      "AUTOMATION_RULE",
    entityId:
      existing.id,
    before:
      existing,
    after:
      updated
  });

  return updated;
}

function matchesRule(input: {
  rule: {
    keywordContains:
      | string
      | null;
    onlyIfUnassigned:
      boolean;
    conversationType:
      "ALL"
      | "DIRECT"
      | "GROUP";
  };
  ticket: {
    assignedMembershipId:
      | string
      | null;
    contact: {
      isGroup:
        boolean;
    };
  };
  messageBody:
    | string
    | null;
}) {
  if (
    input.rule
      .onlyIfUnassigned &&
    input.ticket
      .assignedMembershipId
  ) {
    return false;
  }

  if (
    input.rule
      .conversationType ===
      "DIRECT" &&
    input.ticket
      .contact.isGroup
  ) {
    return false;
  }

  if (
    input.rule
      .conversationType ===
      "GROUP" &&
    !input.ticket
      .contact.isGroup
  ) {
    return false;
  }

  const keyword =
    input.rule
      .keywordContains
      ?.trim()
      .toLocaleLowerCase(
        "pt-BR"
      );

  if (
    keyword &&
    !input.messageBody
      ?.toLocaleLowerCase(
        "pt-BR"
      )
      .includes(
        keyword
      )
  ) {
    return false;
  }

  return true;
}

function expandText(
  text: string,
  context: {
    contactName: string;
    companyName: string;
  }
) {
  const firstName =
    context.contactName
      .trim()
      .split(
        /\s+/
      )[0] ??
    context.contactName;

  return text
    .replaceAll(
      "{nome}",
      context.contactName
    )
    .replaceAll(
      "{primeiro_nome}",
      firstName
    )
    .replaceAll(
      "{empresa}",
      context.companyName
    );
}

async function executeAutomaticText(input: {
  companyId: string;
  ticket: {
    id: string;
    firstInboundAt:
      | Date
      | null;
    firstResponseAt:
      | Date
      | null;
    contact: {
      name: string;
      remoteJid: string;
    };
    whatsappConnection: {
      id: string;
      instanceName: string;
      status: string;
    };
  };
  text: string;
  companyName: string;
}) {
  if (
    input.ticket
      .whatsappConnection
      .status !==
    "CONNECTED"
  ) {
    throw new Error(
      "WhatsApp connection is not CONNECTED."
    );
  }

  const text =
    expandText(
      input.text,
      {
        contactName:
          input.ticket
            .contact.name,
        companyName:
          input.companyName
      }
    );

  const result =
    await evolutionWhatsAppClient.sendText({
      instanceName:
        input.ticket
          .whatsappConnection
          .instanceName,
      number:
        input.ticket
          .contact.remoteJid,
      text
    });

  const externalId =
    sentExternalId(
      result
    );

  const timestamp =
    sentTimestamp(
      result
    );

  const message =
    await prisma.message.upsert({
      where: {
        whatsappConnectionId_externalId: {
          whatsappConnectionId:
            input.ticket
              .whatsappConnection.id,
          externalId
        }
      },
      create: {
        companyId:
          input.companyId,
        ticketId:
          input.ticket.id,
        whatsappConnectionId:
          input.ticket
            .whatsappConnection.id,
        externalId,
        direction:
          "OUTBOUND",
        type:
          "TEXT",
        deliveryStatus:
          "PENDING",
        body:
          text,
        timestamp
      },
      update: {}
    });

  await prisma.ticket.update({
    where: {
      id:
        input.ticket.id
    },
    data: {
      lastMessage:
        text,
      lastMessageAt:
        timestamp,
      lastOutboundAt:
        timestamp,
      waitingSince:
        null,
      ...(input.ticket
        .firstInboundAt &&
      !input.ticket
        .firstResponseAt
        ? {
            firstResponseAt:
              timestamp
          }
        : {})
    }
  });

  publishRealtime(
    input.companyId,
    {
      type:
        "message.created",
      ticketId:
        input.ticket.id,
      messageId:
        message.id
    }
  );

  return {
    type:
      "SEND_TEXT" as const,
    messageId:
      message.id
  };
}

async function executeAction(input: {
  companyId: string;
  ticketId: string;
  action: {
    type:
      AutomationActionTypeValue;
    queueId:
      | string
      | null;
    membershipId:
      | string
      | null;
    tagId:
      | string
      | null;
    text:
      | string
      | null;
  };
  companyName: string;
}) {
  const ticket =
    await prisma.ticket.findFirst({
      where: {
        id:
          input.ticketId,
        companyId:
          input.companyId
      },
      include: {
        contact: true,
        whatsappConnection:
          true
      }
    });

  if (!ticket) {
    throw new Error(
      "Automation ticket no longer exists."
    );
  }

  switch (
    input.action.type
  ) {
    case "SET_QUEUE": {
      const queue =
        input.action
          .queueId
          ? await prisma.queue.findFirst({
              where: {
                id:
                  input.action
                    .queueId,
                companyId:
                  input.companyId,
                isActive:
                  true
              },
              select: {
                id: true
              }
            })
          : null;

      if (!queue) {
        throw new Error(
          "Automation queue is unavailable."
        );
      }

      await prisma.ticket.update({
        where: {
          id:
            ticket.id
        },
        data: {
          queueId:
            queue.id
        }
      });

      return {
        type:
          "SET_QUEUE" as const,
        queueId:
          queue.id
      };
    }

    case "ASSIGN_MEMBERSHIP": {
      const membership =
        input.action
          .membershipId
          ? await prisma.companyMembership.findFirst({
              where: {
                id:
                  input.action
                    .membershipId,
                companyId:
                  input.companyId,
                isActive:
                  true
              },
              select: {
                id: true
              }
            })
          : null;

      if (!membership) {
        throw new Error(
          "Automation membership is unavailable."
        );
      }

      await prisma.ticket.update({
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
          "ASSIGN_MEMBERSHIP" as const,
        membershipId:
          membership.id
      };
    }

    case "ADD_TAG": {
      const tag =
        input.action
          .tagId
          ? await prisma.tag.findFirst({
              where: {
                id:
                  input.action
                    .tagId,
                companyId:
                  input.companyId,
                isActive:
                  true
              },
              select: {
                id: true
              }
            })
          : null;

      if (!tag) {
        throw new Error(
          "Automation tag is unavailable."
        );
      }

      await prisma.ticketTag.upsert({
        where: {
          ticketId_tagId: {
            ticketId:
              ticket.id,
            tagId:
              tag.id
          }
        },
        create: {
          ticketId:
            ticket.id,
          tagId:
            tag.id
        },
        update: {}
      });

      return {
        type:
          "ADD_TAG" as const,
        tagId:
          tag.id
      };
    }

    case "SEND_TEXT": {
      if (
        !input.action
          .text
      ) {
        throw new Error(
          "Automation text is empty."
        );
      }

      return executeAutomaticText({
        companyId:
          input.companyId,
        ticket,
        text:
          input.action.text,
        companyName:
          input.companyName
      });
    }
  }
}

export async function evaluateAutomationEvent(input: {
  companyId: string;
  ticketId: string;
  sourceMessageId: string;
  trigger:
    AutomationTriggerValue;
}) {
  const company =
    await prisma.company.findUnique({
      where: {
        id:
          input.companyId
      },
      select: {
        name: true
      }
    });

  const sourceMessage =
    await prisma.message.findFirst({
      where: {
        id:
          input.sourceMessageId,
        companyId:
          input.companyId,
        ticketId:
          input.ticketId
      },
      select: {
        body: true
      }
    });

  if (
    !company ||
    !sourceMessage
  ) {
    return {
      evaluated: 0,
      matched: 0
    };
  }

  const rules =
    await prisma.automationRule.findMany({
      where: {
        companyId:
          input.companyId,
        isActive:
          true,
        trigger:
          input.trigger
      },
      orderBy: [
        {
          priority:
            "asc"
        },
        {
          createdAt:
            "asc"
        }
      ]
    });

  let matched = 0;

  for (
    const rule
    of rules
  ) {
    const ticket =
      await prisma.ticket.findFirst({
        where: {
          id:
            input.ticketId,
          companyId:
            input.companyId
        },
        include: {
          contact: {
            select: {
              isGroup:
                true
            }
          }
        }
      });

    if (!ticket) {
      break;
    }

    const doesMatch =
      matchesRule({
        rule,
        ticket,
        messageBody:
          sourceMessage.body
      });

    if (!doesMatch) {
      continue;
    }

    matched +=
      1;

    const dedupeKey =
      `${rule.id}-${input.trigger}-${input.sourceMessageId}`;

    const existingRun =
      await prisma.automationRun.findUnique({
        where: {
          dedupeKey
        },
        select: {
          id: true
        }
      });

    if (existingRun) {
      continue;
    }

    const run =
      await prisma.automationRun.create({
        data: {
          companyId:
            input.companyId,
          ruleId:
            rule.id,
          ticketId:
            input.ticketId,
          sourceMessageId:
            input.sourceMessageId,
          trigger:
            input.trigger,
          status:
            "RUNNING",
          matched:
            true,
          dedupeKey
        }
      });

    try {
      const actions =
        await prisma.automationAction.findMany({
          where: {
            ruleId:
              rule.id
          },
          orderBy: {
            orderIndex:
              "asc"
          }
        });

      const results:
        unknown[] = [];

      for (
        const action
        of actions
      ) {
        results.push(
          await executeAction({
            companyId:
              input.companyId,
            ticketId:
              input.ticketId,
            action,
            companyName:
              company.name
          })
        );
      }

      await prisma.automationRun.update({
        where: {
          id:
            run.id
        },
        data: {
          status:
            "SUCCESS",
          details:
            toPrismaJson({
              rule:
                rule.name,
              actions:
                results
            }),
          finishedAt:
            new Date()
        }
      });

      await recordTicketEvent({
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        type:
          "AUTOMATION_APPLIED",
        metadata: {
          ruleId:
            rule.id,
          ruleName:
            rule.name,
          trigger:
            input.trigger
        }
      });

      publishRealtime(
        input.companyId,
        {
          type:
            "ticket.updated",
          ticketId:
            input.ticketId
        }
      );
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : "Unknown automation error.";

      await prisma.automationRun.update({
        where: {
          id:
            run.id
        },
        data: {
          status:
            "FAILED",
          error:
            message.slice(
              0,
              4000
            ),
          finishedAt:
            new Date()
        }
      });

      console.error(
        "[automations] rule execution failed",
        {
          ruleId:
            rule.id,
          ticketId:
            input.ticketId,
          error:
            message
        }
      );
    }
  }

  return {
    evaluated:
      rules.length,
    matched
  };
}
EOF

# ---------------------------------------------------------------------------
# API routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/automations/automation.routes.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";
import { z } from "zod";

import {
  requirePermission
} from "../auth/auth.guard.js";
import {
  createAutomationRule,
  listAutomationRules,
  listAutomationRuns,
  updateAutomationRule
} from "./automation.service.js";

const actionSchema =
  z.object({
    type:
      z.enum([
        "SET_QUEUE",
        "ASSIGN_MEMBERSHIP",
        "ADD_TAG",
        "SEND_TEXT"
      ]),
    queueId:
      z.string()
        .uuid()
        .optional(),
    membershipId:
      z.string()
        .uuid()
        .optional(),
    tagId:
      z.string()
        .uuid()
        .optional(),
    text:
      z.string()
        .max(4096)
        .optional()
  });

const createSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(2)
        .max(160),
    isActive:
      z.boolean()
        .optional(),
    trigger:
      z.enum([
        "TICKET_CREATED",
        "INBOUND_MESSAGE"
      ]),
    keywordContains:
      z.string()
        .trim()
        .max(190)
        .nullable()
        .optional(),
    onlyIfUnassigned:
      z.boolean()
        .optional(),
    conversationType:
      z.enum([
        "ALL",
        "DIRECT",
        "GROUP"
      ])
        .optional(),
    priority:
      z.coerce
        .number()
        .int()
        .min(0)
        .max(10000)
        .optional(),
    actions:
      z.array(
        actionSchema
      )
        .min(1)
        .max(8)
  });

const patchSchema =
  createSchema
    .partial()
    .refine(
      value =>
        Object.keys(
          value
        ).length >
        0,
      {
        message:
          "Informe ao menos uma alteração."
      }
    );

const paramsSchema =
  z.object({
    id:
      z.string()
        .uuid()
  });

const runsQuerySchema =
  z.object({
    limit:
      z.coerce
        .number()
        .int()
        .min(1)
        .max(100)
        .default(50)
  });

export async function automationRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/automations",
    async request => {
      const auth =
        await requirePermission(
          request,
          "automations.read"
        );

      return {
        automations:
          await listAutomationRules(
            auth.companyId
          )
      };
    }
  );

  app.get(
    "/api/v1/automations/runs",
    async request => {
      const auth =
        await requirePermission(
          request,
          "automations.read"
        );

      const query =
        runsQuerySchema.parse(
          request.query
        );

      return {
        runs:
          await listAutomationRuns(
            auth.companyId,
            query.limit
          )
      };
    }
  );

  app.post(
    "/api/v1/automations",
    async request => {
      const auth =
        await requirePermission(
          request,
          "automations.manage"
        );

      const input =
        createSchema.parse(
          request.body
        );

      return {
        automation:
          await createAutomationRule({
            companyId:
              auth.companyId,
            actorMembershipId:
              auth.membershipId,
            rule:
              input
          })
      };
    }
  );

  app.patch(
    "/api/v1/automations/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "automations.manage"
        );

      const params =
        paramsSchema.parse(
          request.params
        );

      const patch =
        patchSchema.parse(
          request.body
        );

      return {
        automation:
          await updateAutomationRule({
            companyId:
              auth.companyId,
            actorMembershipId:
              auth.membershipId,
            ruleId:
              params.id,
            patch
          })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Durable BullMQ dispatch
# ---------------------------------------------------------------------------

cat > apps/api/src/jobs/automation.queue.ts <<'EOF'
import {
  Queue
} from "bullmq";

import { env } from "../config/env.js";
import type {
  AutomationTriggerValue
} from "../modules/automations/automation.service.js";
import {
  jobProducerRedisOptions
} from "./job-redis.js";

export const AUTOMATION_QUEUE_NAME =
  "wapp-automations";

export const AUTOMATION_JOB_NAME =
  "evaluate";

export interface AutomationJobData {
  companyId: string;
  ticketId: string;
  sourceMessageId: string;
  trigger:
    AutomationTriggerValue;
}

let queue:
  | Queue<
      AutomationJobData
    >
  | null =
  null;

export function getAutomationQueue() {
  if (!queue) {
    queue =
      new Queue<
        AutomationJobData
      >(
        AUTOMATION_QUEUE_NAME,
        {
          connection:
            jobProducerRedisOptions()
        }
      );
  }

  return queue;
}

export async function enqueueAutomationEvaluation(
  data:
    AutomationJobData
) {
  if (!env.REDIS_URL) {
    return false;
  }

  await getAutomationQueue()
    .add(
      AUTOMATION_JOB_NAME,
      data,
      {
        jobId:
          `automation-${data.trigger}-${data.sourceMessageId}`,
        attempts: 1,
        removeOnComplete: {
          count: 1000
        },
        removeOnFail: {
          count: 1000
        }
      }
    );

  return true;
}

export async function closeAutomationQueue() {
  const current =
    queue;

  queue =
    null;

  if (current) {
    await current.close();
  }
}
EOF

cat > apps/api/src/jobs/automation.worker.ts <<'EOF'
import {
  Worker
} from "bullmq";

import {
  evaluateAutomationEvent
} from "../modules/automations/automation.service.js";
import {
  AUTOMATION_JOB_NAME,
  AUTOMATION_QUEUE_NAME,
  type AutomationJobData
} from "./automation.queue.js";
import {
  jobWorkerRedisOptions
} from "./job-redis.js";

export function createAutomationWorker() {
  const worker =
    new Worker<
      AutomationJobData
    >(
      AUTOMATION_QUEUE_NAME,
      async job => {
        if (
          job.name !==
          AUTOMATION_JOB_NAME
        ) {
          throw new Error(
            `Unknown automation job: ${job.name}`
          );
        }

        return evaluateAutomationEvent(
          job.data
        );
      },
      {
        connection:
          jobWorkerRedisOptions(),
        concurrency: 3
      }
    );

  worker.on(
    "failed",
    (
      job,
      error
    ) => {
      console.error(
        "[automations] job failed",
        {
          jobId:
            job?.id,
          error:
            error.message
        }
      );
    }
  );

  return worker;
}
EOF

cat > apps/api/src/jobs/automation.dispatch.ts <<'EOF'
import { env } from "../config/env.js";
import {
  evaluateAutomationEvent
} from "../modules/automations/automation.service.js";
import {
  type AutomationJobData,
  enqueueAutomationEvaluation
} from "./automation.queue.js";

export function scheduleAutomationEvaluation(
  data:
    AutomationJobData
) {
  if (env.REDIS_URL) {
    void enqueueAutomationEvaluation(
      data
    ).catch(
      error => {
        console.error(
          "[automations] enqueue failed",
          error
        );
      }
    );

    return;
  }

  /*
   * Local development fallback only. Production P1 baseline has Redis.
   * This preserves functionality without pretending the fallback is durable.
   */
  void evaluateAutomationEvent(
    data
  ).catch(
    error => {
      console.error(
        "[automations] inline evaluation failed",
        error
      );
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Hook inbound events after the message has been persisted.
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
  scheduleAutomationEvaluation
} from "../../jobs/automation.dispatch.js";`;

if (
  !content.includes(
    'from "../../jobs/automation.dispatch.js"'
  )
) {
  const anchor =
    'import { toPrismaJson } from "../../lib/prisma-json.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "message ingestion import anchor not found."
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
    "scheduleAutomationEvaluation({"
  )
) {
  const anchor = `  if (hasMedia) {
    scheduleMessageMediaCapture(
      message.id
    );
  }

  return {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "message media scheduling anchor not found."
    );
  }

  const replacement = `  if (hasMedia) {
    scheduleMessageMediaCapture(
      message.id
    );
  }

  if (!parsed.fromMe) {
    if (!before) {
      scheduleAutomationEvaluation({
        companyId:
          connection.companyId,
        ticketId:
          ticket.id,
        sourceMessageId:
          message.id,
        trigger:
          "TICKET_CREATED"
      });
    }

    scheduleAutomationEvaluation({
      companyId:
        connection.companyId,
      ticketId:
        ticket.id,
      sourceMessageId:
        message.id,
      trigger:
        "INBOUND_MESSAGE"
    });
  }

  return {`;

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
NODE

# ---------------------------------------------------------------------------
# Job runtime + standalone worker
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/jobs/job-runtime.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const workerImport =
  `import {
  createAutomationWorker
} from "./automation.worker.js";`;

const queueImport =
  `import {
  closeAutomationQueue
} from "./automation.queue.js";`;

if (
  !content.includes(
    'from "./automation.worker.js"'
  )
) {
  const anchor =
    'import { env } from "../config/env.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "job runtime env import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${workerImport}
${queueImport}`
    );
}

if (
  !content.includes(
    "createAutomationWorker()"
  )
) {
  const anchor =
    `    createMediaCaptureWorker(),
    createMaintenanceWorker()`;

  if (!content.includes(anchor)) {
    throw new Error(
      "P1.27 embedded worker array anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `    createMediaCaptureWorker(),
    createMaintenanceWorker(),
    createAutomationWorker()`
    );
}

if (
  !content.includes(
    "closeAutomationQueue()"
  )
) {
  const anchor =
    `    closeMediaCaptureQueue(),
    closeMaintenanceQueue()`;

  if (!content.includes(anchor)) {
    throw new Error(
      "P1.27 queue close anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `    closeMediaCaptureQueue(),
    closeMaintenanceQueue(),
    closeAutomationQueue()`
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
  "apps/api/src/worker.ts";

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
    'from "./jobs/automation.worker.js"'
  )
) {
  const anchor =
    'import { prisma } from "./lib/database.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "worker prisma import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
import {
  createAutomationWorker
} from "./jobs/automation.worker.js";
import {
  closeAutomationQueue
} from "./jobs/automation.queue.js";`
    );
}

if (
  !content.includes(
    "createAutomationWorker()"
  )
) {
  const anchor =
    `  createMediaCaptureWorker(),
  createMaintenanceWorker()`;

  if (!content.includes(anchor)) {
    throw new Error(
      "P1.27 standalone workers array anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `  createMediaCaptureWorker(),
  createMaintenanceWorker(),
  createAutomationWorker()`
    );
}

if (
  !content.includes(
    "closeAutomationQueue()"
  )
) {
  const anchor =
    `    closeMediaCaptureQueue(),
    closeMaintenanceQueue()`;

  if (!content.includes(anchor)) {
    throw new Error(
      "P1.27 standalone queue close anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `    closeMediaCaptureQueue(),
    closeMaintenanceQueue(),
    closeAutomationQueue()`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# RBAC
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/security/permissions.ts";

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
    '| "automations.read"'
  )
) {
  const anchor =
    '  | "contacts.read"';

  if (!content.includes(anchor)) {
    throw new Error(
      "permission type anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `  | "automations.read"
  | "automations.manage"
${anchor}`
    );
}

function addToRole(
  role,
  permissions
) {
  const start =
    content.indexOf(
      `  ${role}: [`
    );

  if (start < 0) {
    throw new Error(
      `${role} permission block not found.`
    );
  }

  const commaEnd =
    content.indexOf(
      "\n  ],",
      start
    );

  const finalEnd =
    content.indexOf(
      "\n  ]\n};",
      start
    );

  const end =
    commaEnd >= 0
      ? commaEnd
      : finalEnd;

  if (end < 0) {
    throw new Error(
      `${role} permission block end not found.`
    );
  }

  let block =
    content.slice(
      start,
      end
    );

  for (
    const permission
    of permissions
  ) {
    if (
      !block.includes(
        `"${permission}"`
      )
    ) {
      const firstEntry =
        block.indexOf(
          "\n    "
        );

      block =
        block.slice(
          0,
          firstEntry
        ) +
        `\n    "${permission}",` +
        block.slice(
          firstEntry
        );
    }
  }

  content =
    content.slice(
      0,
      start
    ) +
    block +
    content.slice(
      end
    );
}

addToRole(
  "OWNER",
  [
    "automations.read",
    "automations.manage"
  ]
);

addToRole(
  "ADMIN",
  [
    "automations.read",
    "automations.manage"
  ]
);

addToRole(
  "SUPERVISOR",
  [
    "automations.read",
    "automations.manage"
  ]
);

addToRole(
  "AGENT",
  [
    "automations.read"
  ]
);

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
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !content.includes(
    '"automations.read",'
  )
) {
  const marker =
    `const allPermissions:
  WappPermission[] = [`;

  const start =
    content.indexOf(
      marker
    );

  const end =
    content.indexOf(
      "\n  ];",
      start
    );

  if (
    start < 0 ||
    end < 0
  ) {
    throw new Error(
      "allPermissions list not found."
    );
  }

  content =
    content.slice(
      0,
      end
    ) +
    `\n    "automations.read",
    "automations.manage"` +
    content.slice(
      end
    );
}

if (
  !content.includes(
    '"automation capability follows operational roles"'
  )
) {
  content += `

describe(
  "automation permissions",
  () => {
    it(
      "automation capability follows operational roles",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN",
            "SUPERVISOR"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              role,
              "automations.read"
            ),
            true
          );

          assert.equal(
            roleHasPermission(
              role,
              "automations.manage"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "automations.read"
          ),
          true
        );

        assert.equal(
          roleHasPermission(
            "AGENT",
            "automations.manage"
          ),
          false
        );
      }
    );
  }
);
`;
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Audit entity support
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/audit/audit.service.ts";

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
    '| "AUTOMATION_RULE"'
  )
) {
  const anchor =
    `export type AuditEntityType =`;

  const start =
    content.indexOf(
      anchor
    );

  const end =
    content.indexOf(
      ";",
      start
    );

  if (
    start < 0 ||
    end < 0
  ) {
    throw new Error(
      "AuditEntityType declaration not found."
    );
  }

  content =
    content.slice(
      0,
      end
    ) +
    `\n  | "AUTOMATION_RULE"` +
    content.slice(
      end
    );
}

if (
  !content.includes(
    'case "AUTOMATION_RULE":'
  )
) {
  const switchEnd =
    `    case "WHATSAPP_CONNECTION":`;

  const start =
    content.indexOf(
      switchEnd
    );

  if (start < 0) {
    throw new Error(
      "audit snapshot switch anchor not found."
    );
  }

  const next =
    content.indexOf(
      "\n  }",
      start
    );

  if (next < 0) {
    throw new Error(
      "audit snapshot switch end not found."
    );
  }

  const caseBlock = `
    case "AUTOMATION_RULE":
      return prisma.automationRule.findFirst({
        where: {
          id:
            input.entityId,
          companyId:
            input.companyId
        }
      });
`;

  content =
    content.slice(
      0,
      next
    ) +
    caseBlock +
    content.slice(
      next
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Register API routes
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
  'import { automationRoutes } from "./modules/automations/automation.routes.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { adminRoutes } from "./modules/admin/admin.routes.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "app adminRoutes import anchor not found."
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
    "await app.register(automationRoutes);"
  )
) {
  const anchor =
    `  await app.register(authRoutes);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "app authRoutes registration anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  await app.register(automationRoutes);`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Automation matching unit tests
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/automations/automation.service.test.ts <<'EOF'
import assert from "node:assert/strict";
import { test } from "node:test";

function matches(input: {
  keyword?: string;
  onlyIfUnassigned?: boolean;
  assigned?: boolean;
  type?:
    | "ALL"
    | "DIRECT"
    | "GROUP";
  isGroup?: boolean;
  body?: string;
}) {
  if (
    input.onlyIfUnassigned &&
    input.assigned
  ) {
    return false;
  }

  if (
    input.type ===
      "DIRECT" &&
    input.isGroup
  ) {
    return false;
  }

  if (
    input.type ===
      "GROUP" &&
    !input.isGroup
  ) {
    return false;
  }

  if (
    input.keyword &&
    !input.body
      ?.toLowerCase()
      .includes(
        input.keyword
          .toLowerCase()
      )
  ) {
    return false;
  }

  return true;
}

test(
  "automation keyword matching is case insensitive",
  () => {
    assert.equal(
      matches({
        keyword:
          "segunda via",
        body:
          "Preciso da SEGUNDA VIA da fatura"
      }),
      true
    );
  }
);

test(
  "only-if-unassigned prevents reassignment rules",
  () => {
    assert.equal(
      matches({
        onlyIfUnassigned:
          true,
        assigned:
          true
      }),
      false
    );
  }
);

test(
  "direct/group conditions stay explicit",
  () => {
    assert.equal(
      matches({
        type:
          "DIRECT",
        isGroup:
          true
      }),
      false
    );

    assert.equal(
      matches({
        type:
          "GROUP",
        isGroup:
          true
      }),
      true
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
    "API test script is missing."
  );
}

const file =
  "src/modules/automations/automation.service.test.ts";

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

# ---------------------------------------------------------------------------
# Web management page
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/automations/page.tsx <<'EOF'
"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
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

interface QueueItem {
  id: string;
  name: string;
}

interface TeamMembership {
  id: string;
  role:
    | "OWNER"
    | "ADMIN"
    | "SUPERVISOR"
    | "AGENT";
  user: {
    name: string;
  };
}

interface TagItem {
  id: string;
  name: string;
}

interface AutomationAction {
  id: string;
  type:
    | "SET_QUEUE"
    | "ASSIGN_MEMBERSHIP"
    | "ADD_TAG"
    | "SEND_TEXT";
  queueId:
    | string
    | null;
  membershipId:
    | string
    | null;
  tagId:
    | string
    | null;
  text:
    | string
    | null;
}

interface AutomationRule {
  id: string;
  name: string;
  isActive: boolean;
  trigger:
    | "TICKET_CREATED"
    | "INBOUND_MESSAGE";
  keywordContains:
    | string
    | null;
  onlyIfUnassigned:
    boolean;
  conversationType:
    | "ALL"
    | "DIRECT"
    | "GROUP";
  priority: number;
  actions:
    AutomationAction[];
}

interface AutomationRun {
  id: string;
  ruleId: string;
  ticketId: string;
  trigger:
    | "TICKET_CREATED"
    | "INBOUND_MESSAGE";
  status:
    | "RUNNING"
    | "SUCCESS"
    | "FAILED";
  error:
    | string
    | null;
  createdAt: string;
}

function triggerLabel(
  trigger:
    AutomationRule[
      "trigger"
    ]
) {
  return trigger ===
    "TICKET_CREATED"
    ? "Novo atendimento"
    : "Mensagem recebida";
}

export default function AutomationsPage() {
  const router =
    useRouter();

  const {
    session,
    loading,
    request
  } =
    useAuth();

  const [
    automations,
    setAutomations
  ] =
    useState<
      AutomationRule[]
    >([]);

  const [
    runs,
    setRuns
  ] =
    useState<
      AutomationRun[]
    >([]);

  const [
    queues,
    setQueues
  ] =
    useState<
      QueueItem[]
    >([]);

  const [
    team,
    setTeam
  ] =
    useState<
      TeamMembership[]
    >([]);

  const [
    tags,
    setTags
  ] =
    useState<
      TagItem[]
    >([]);

  const [
    name,
    setName
  ] =
    useState("");

  const [
    trigger,
    setTrigger
  ] =
    useState<
      AutomationRule[
        "trigger"
      ]
    >(
      "INBOUND_MESSAGE"
    );

  const [
    keyword,
    setKeyword
  ] =
    useState("");

  const [
    conversationType,
    setConversationType
  ] =
    useState<
      AutomationRule[
        "conversationType"
      ]
    >(
      "ALL"
    );

  const [
    onlyIfUnassigned,
    setOnlyIfUnassigned
  ] =
    useState(
      true
    );

  const [
    queueId,
    setQueueId
  ] =
    useState("");

  const [
    membershipId,
    setMembershipId
  ] =
    useState("");

  const [
    tagId,
    setTagId
  ] =
    useState("");

  const [
    automaticText,
    setAutomaticText
  ] =
    useState("");

  const [
    busy,
    setBusy
  ] =
    useState<
      string
      | null
    >(
      null
    );

  const [
    error,
    setError
  ] =
    useState("");

  const canManage =
    session?.role ===
      "OWNER" ||
    session?.role ===
      "ADMIN" ||
    session?.role ===
      "SUPERVISOR";

  const load =
    useCallback(
      async () => {
        const [
          automationPayload,
          runsPayload,
          queuesPayload,
          teamPayload,
          tagsPayload
        ] =
          await Promise.all([
            request<{
              automations:
                AutomationRule[];
            }>(
              "/api/v1/automations"
            ),
            request<{
              runs:
                AutomationRun[];
            }>(
              "/api/v1/automations/runs?limit=30"
            ),
            request<{
              queues:
                QueueItem[];
            }>(
              "/api/v1/queues"
            ),
            request<{
              memberships:
                TeamMembership[];
            }>(
              "/api/v1/team/memberships"
            ),
            request<{
              tags:
                TagItem[];
            }>(
              "/api/v1/tags"
            )
          ]);

        setAutomations(
          automationPayload
            .automations
        );

        setRuns(
          runsPayload.runs
        );

        setQueues(
          queuesPayload.queues
        );

        setTeam(
          teamPayload
            .memberships
        );

        setTags(
          tagsPayload.tags
        );
      },
      [
        request
      ]
    );

  useEffect(
    () => {
      if (
        !loading &&
        !session
      ) {
        router.replace(
          "/login"
        );

        return;
      }

      if (session) {
        void load()
          .catch(
            caught => {
              setError(
                caught instanceof
                  ApiError
                  ? caught.message
                  : "Não foi possível carregar as automações."
              );
            }
          );
      }
    },
    [
      load,
      loading,
      router,
      session
    ]
  );

  const runByRule =
    useMemo(
      () => {
        const map =
          new Map<
            string,
            AutomationRun
          >();

        for (
          const run
          of runs
        ) {
          if (
            !map.has(
              run.ruleId
            )
          ) {
            map.set(
              run.ruleId,
              run
            );
          }
        }

        return map;
      },
      [
        runs
      ]
    );

  function actionLabel(
    action:
      AutomationAction
  ) {
    switch (
      action.type
    ) {
      case "SET_QUEUE":
        return `Mover para ${
          queues.find(
            queue =>
              queue.id ===
              action.queueId
          )?.name ??
          "fila"
        }`;

      case "ASSIGN_MEMBERSHIP":
        return `Atribuir a ${
          team.find(
            membership =>
              membership.id ===
              action.membershipId
          )?.user.name ??
          "atendente"
        }`;

      case "ADD_TAG":
        return `Adicionar ${
          tags.find(
            tag =>
              tag.id ===
              action.tagId
          )?.name ??
          "etiqueta"
        }`;

      case "SEND_TEXT":
        return "Enviar mensagem automática";
    }
  }

  async function create(
    event:
      FormEvent<
        HTMLFormElement
      >
  ) {
    event.preventDefault();

    if (
      !canManage
    ) {
      return;
    }

    const actions:
      Array<
        Record<
          string,
          string
        >
      > = [];

    if (
      queueId
    ) {
      actions.push({
        type:
          "SET_QUEUE",
        queueId
      });
    }

    if (
      membershipId
    ) {
      actions.push({
        type:
          "ASSIGN_MEMBERSHIP",
        membershipId
      });
    }

    if (
      tagId
    ) {
      actions.push({
        type:
          "ADD_TAG",
        tagId
      });
    }

    if (
      automaticText
        .trim()
    ) {
      actions.push({
        type:
          "SEND_TEXT",
        text:
          automaticText
            .trim()
      });
    }

    if (
      actions.length ===
      0
    ) {
      setError(
        "Escolha ao menos uma ação para a automação."
      );

      return;
    }

    setBusy(
      "create"
    );

    setError("");

    try {
      await request(
        "/api/v1/automations",
        {
          method:
            "POST",
          body:
            JSON.stringify({
              name,
              trigger,
              keywordContains:
                keyword.trim() ||
                null,
              onlyIfUnassigned,
              conversationType,
              priority:
                100,
              actions
            })
        }
      );

      setName("");
      setKeyword("");
      setQueueId("");
      setMembershipId("");
      setTagId("");
      setAutomaticText("");

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível criar a automação."
      );
    } finally {
      setBusy(
        null
      );
    }
  }

  async function toggle(
    rule:
      AutomationRule
  ) {
    if (
      !canManage
    ) {
      return;
    }

    setBusy(
      rule.id
    );

    setError("");

    try {
      await request(
        `/api/v1/automations/${rule.id}`,
        {
          method:
            "PATCH",
          body:
            JSON.stringify({
              isActive:
                !rule.isActive
            })
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível alterar a automação."
      );
    } finally {
      setBusy(
        null
      );
    }
  }

  if (
    loading ||
    !session
  ) {
    return (
      <main className="dashboard-loading">
        Carregando automações…
      </main>
    );
  }

  return (
    <main className="automation-screen">
      <header className="automation-header">
        <div>
          <button
            className="connections-back"
            onClick={() =>
              router.push(
                "/dashboard"
              )
            }
            type="button"
          >
            ← Visão geral
          </button>

          <span className="eyebrow">
            Operação
          </span>

          <h1>
            Automações
          </h1>

          <p>
            Regras objetivas para organizar atendimentos sem esconder o que foi feito automaticamente.
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
        <div className="inbox-error">
          {error}
        </div>
      )}

      {canManage && (
        <form
          className="automation-builder"
          onSubmit={
            create
          }
        >
          <div className="automation-builder__intro">
            <span className="eyebrow">
              Nova regra
            </span>
            <h2>
              Quando isso acontecer…
            </h2>
          </div>

          <div className="automation-builder__grid">
            <label>
              <span>
                Nome
              </span>
              <input
                maxLength={
                  160
                }
                onChange={
                  event =>
                    setName(
                      event
                        .target
                        .value
                    )
                }
                placeholder="Ex.: Financeiro por palavra-chave"
                required
                value={
                  name
                }
              />
            </label>

            <label>
              <span>
                Gatilho
              </span>
              <select
                onChange={
                  event =>
                    setTrigger(
                      event
                        .target
                        .value as
                        AutomationRule[
                          "trigger"
                        ]
                    )
                }
                value={
                  trigger
                }
              >
                <option value="INBOUND_MESSAGE">
                  Mensagem recebida
                </option>
                <option value="TICKET_CREATED">
                  Novo atendimento
                </option>
              </select>
            </label>

            <label>
              <span>
                Contém
              </span>
              <input
                maxLength={
                  190
                }
                onChange={
                  event =>
                    setKeyword(
                      event
                        .target
                        .value
                    )
                }
                placeholder="Opcional: boleto, suporte…"
                value={
                  keyword
                }
              />
            </label>

            <label>
              <span>
                Tipo
              </span>
              <select
                onChange={
                  event =>
                    setConversationType(
                      event
                        .target
                        .value as
                        AutomationRule[
                          "conversationType"
                        ]
                    )
                }
                value={
                  conversationType
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

          <label className="automation-check">
            <input
              checked={
                onlyIfUnassigned
              }
              onChange={
                event =>
                  setOnlyIfUnassigned(
                    event
                      .target
                      .checked
                  )
              }
              type="checkbox"
            />
            <span>
              Executar somente se o atendimento ainda estiver sem atendente
            </span>
          </label>

          <div className="automation-builder__divider">
            Então…
          </div>

          <div className="automation-builder__grid">
            <label>
              <span>
                Fila
              </span>
              <select
                onChange={
                  event =>
                    setQueueId(
                      event
                        .target
                        .value
                    )
                }
                value={
                  queueId
                }
              >
                <option value="">
                  Não alterar
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
                onChange={
                  event =>
                    setMembershipId(
                      event
                        .target
                        .value
                    )
                }
                value={
                  membershipId
                }
              >
                <option value="">
                  Não atribuir
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
                onChange={
                  event =>
                    setTagId(
                      event
                        .target
                        .value
                    )
                }
                value={
                  tagId
                }
              >
                <option value="">
                  Não adicionar
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
          </div>

          <label className="automation-text-field">
            <span>
              Mensagem automática
            </span>
            <textarea
              maxLength={
                4096
              }
              onChange={
                event =>
                  setAutomaticText(
                    event
                      .target
                      .value
                  )
              }
              placeholder="Opcional. Variáveis: {nome}, {primeiro_nome}, {empresa}"
              rows={
                3
              }
              value={
                automaticText
              }
            />
          </label>

          <div className="automation-builder__footer">
            <small>
              A regra só executa em mensagens recebidas. Mensagens automáticas não disparam outra automação.
            </small>

            <button
              className="primary-button"
              disabled={
                busy ===
                "create"
              }
              type="submit"
            >
              <span>
                {busy ===
                "create"
                  ? "Criando…"
                  : "Criar automação"}
              </span>
              <span>
                +
              </span>
            </button>
          </div>
        </form>
      )}

      <section className="automation-list">
        <div className="automation-list__heading">
          <div>
            <span className="eyebrow">
              Regras
            </span>
            <h2>
              Automações configuradas
            </h2>
          </div>

          <span>
            {automations.length}
          </span>
        </div>

        {automations.length ===
        0 ? (
          <div className="connection-empty">
            <strong>
              Nenhuma automação criada.
            </strong>
            <p>
              As regras ficam visíveis aqui com o último resultado de execução.
            </p>
          </div>
        ) : (
          automations.map(
            rule => {
              const lastRun =
                runByRule.get(
                  rule.id
                );

              return (
                <article
                  className={
                    rule.isActive
                      ? "automation-rule"
                      : "automation-rule automation-rule--inactive"
                  }
                  key={
                    rule.id
                  }
                >
                  <div className="automation-rule__main">
                    <div className="automation-rule__status">
                      <span>
                        {rule.isActive
                          ? "Ativa"
                          : "Pausada"}
                      </span>
                    </div>

                    <div>
                      <h3>
                        {rule.name}
                      </h3>
                      <p>
                        {triggerLabel(
                          rule.trigger
                        )}
                        {rule.keywordContains
                          ? ` · contém “${rule.keywordContains}”`
                          : ""}
                        {rule.onlyIfUnassigned
                          ? " · apenas sem atendente"
                          : ""}
                      </p>
                    </div>
                  </div>

                  <div className="automation-rule__actions">
                    {rule.actions.map(
                      action => (
                        <span
                          key={
                            action.id
                          }
                        >
                          {actionLabel(
                            action
                          )}
                        </span>
                      )
                    )}
                  </div>

                  <div className="automation-rule__last-run">
                    {lastRun ? (
                      <>
                        <span
                          className={
                            `automation-run automation-run--${lastRun.status.toLowerCase()}`
                          }
                        >
                          {lastRun.status ===
                          "SUCCESS"
                            ? "Última execução OK"
                            : lastRun.status ===
                                "FAILED"
                              ? "Última execução falhou"
                              : "Executando"}
                        </span>

                        <time>
                          {new Intl.DateTimeFormat(
                            "pt-BR",
                            {
                              dateStyle:
                                "short",
                              timeStyle:
                                "short"
                            }
                          ).format(
                            new Date(
                              lastRun.createdAt
                            )
                          )}
                        </time>
                      </>
                    ) : (
                      <span>
                        Ainda não executada
                      </span>
                    )}
                  </div>

                  {canManage && (
                    <button
                      className="secondary-button"
                      disabled={
                        busy ===
                        rule.id
                      }
                      onClick={() =>
                        void toggle(
                          rule
                        )
                      }
                      type="button"
                    >
                      {rule.isActive
                        ? "Pausar"
                        : "Ativar"}
                    </button>
                  )}
                </article>
              );
            }
          )
        )}
      </section>
    </main>
  );
}
EOF

# Add navigation from Conversations.
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
    'router.push("/dashboard/automations")'
  )
) {
  const anchor = `          <button
            className="ghost-button"
            onClick={() => router.push("/dashboard/connections")}`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Conversations Connections button anchor not found."
    );
  }

  const button = `          <button
            className="ghost-button"
            onClick={() => router.push("/dashboard/automations")}
            type="button"
          >
            Automações
          </button>
`;

  content =
    content.replace(
      anchor,
      `${button}${anchor}`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Web styles
# ---------------------------------------------------------------------------

if ! grep -Fq -- "WAPP P2.4 / OPERATIONAL AUTOMATIONS" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P2.4 / OPERATIONAL AUTOMATIONS ------------------------------ */

.automation-screen {
  min-height: 100vh;
  padding: 34px clamp(24px, 5vw, 72px) 60px;
  background: var(--surface-subtle);
}

.automation-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 22px;
}

.automation-header h1 {
  margin: 8px 0 7px;
  font-size: clamp(34px, 4vw, 48px);
  letter-spacing: -0.05em;
}

.automation-header p {
  max-width: 650px;
  margin: 0;
  color: var(--muted);
  font-size: 12px;
  line-height: 1.55;
}

.automation-builder,
.automation-list {
  border: 1px solid var(--line);
  border-radius: 16px;
  background: white;
}

.automation-builder {
  padding: 20px;
}

.automation-builder__intro h2,
.automation-list__heading h2 {
  margin: 4px 0 0;
  font-size: 18px;
  letter-spacing: -0.03em;
}

.automation-builder__grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 10px;
  margin-top: 16px;
}

.automation-builder label,
.automation-text-field {
  display: grid;
  gap: 5px;
}

.automation-builder label > span,
.automation-text-field > span {
  color: var(--muted);
  font-size: 9px;
  font-weight: 720;
}

.automation-builder input,
.automation-builder select,
.automation-builder textarea {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 9px;
  outline: 0;
  background: white;
  padding: 9px 10px;
  color: var(--ink);
  font: inherit;
  font-size: 10px;
}

.automation-builder input,
.automation-builder select {
  height: 36px;
}

.automation-builder input:focus,
.automation-builder select:focus,
.automation-builder textarea:focus {
  border-color: rgba(31, 122, 80, 0.38);
  box-shadow: 0 0 0 3px rgba(31, 122, 80, 0.055);
}

.automation-check {
  display: flex !important;
  align-items: center;
  gap: 8px !important;
  margin-top: 13px;
}

.automation-check input {
  width: 14px;
  height: 14px;
}

.automation-builder__divider {
  margin: 18px 0 0;
  border-top: 1px solid var(--line);
  padding-top: 15px;
  color: var(--accent-dark);
  font-size: 10px;
  font-weight: 800;
}

.automation-text-field {
  margin-top: 12px;
}

.automation-text-field textarea {
  min-height: 80px;
  resize: vertical;
}

.automation-builder__footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  margin-top: 14px;
}

.automation-builder__footer small {
  max-width: 600px;
  color: var(--muted);
  font-size: 9px;
  line-height: 1.5;
}

.automation-list {
  margin-top: 14px;
  overflow: hidden;
}

.automation-list__heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 17px 19px;
  border-bottom: 1px solid var(--line);
}

.automation-list__heading > span {
  display: grid;
  min-width: 29px;
  height: 25px;
  place-items: center;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 0 8px;
  font-size: 10px;
  font-weight: 800;
}

.automation-rule {
  display: grid;
  grid-template-columns: minmax(220px, 1.25fr) minmax(240px, 1.4fr) minmax(160px, 0.8fr) auto;
  align-items: center;
  gap: 16px;
  border-bottom: 1px solid #edf0ed;
  padding: 14px 18px;
}

.automation-rule:last-child {
  border-bottom: 0;
}

.automation-rule--inactive {
  opacity: 0.58;
}

.automation-rule__main {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.automation-rule__main > div:last-child {
  min-width: 0;
}

.automation-rule__main h3 {
  overflow: hidden;
  margin: 0;
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.automation-rule__main p {
  overflow: hidden;
  margin: 3px 0 0;
  color: var(--muted);
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.automation-rule__status > span {
  display: inline-flex;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 5px 7px;
  font-size: 8px;
  font-weight: 800;
}

.automation-rule__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.automation-rule__actions > span {
  border: 1px solid var(--line);
  border-radius: 999px;
  background: #fafbfa;
  padding: 5px 7px;
  color: #536057;
  font-size: 8px;
}

.automation-rule__last-run {
  display: grid;
  gap: 3px;
}

.automation-rule__last-run time,
.automation-rule__last-run > span:not(.automation-run) {
  color: var(--muted);
  font-size: 8px;
}

.automation-run {
  font-size: 8px;
  font-weight: 780;
}

.automation-run--success {
  color: var(--accent-dark);
}

.automation-run--failed {
  color: #a33b32;
}

.automation-run--running {
  color: #8a6d20;
}

@media (max-width: 1050px) {
  .automation-builder__grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .automation-rule {
    grid-template-columns: 1fr 1fr;
  }
}

@media (max-width: 680px) {
  .automation-screen {
    padding: 22px 14px 40px;
  }

  .automation-header,
  .automation-builder__footer {
    align-items: stretch;
    flex-direction: column;
  }

  .automation-builder__grid,
  .automation-rule {
    grid-template-columns: 1fr;
  }
}

/* --- /WAPP P2.4 ------------------------------------------------------- */
EOF
fi

cat > docs/P2_04_OPERATIONAL_AUTOMATIONS.md <<'EOF'
# P2.4 Operational automations

P2.4 adds deterministic company-scoped automation rules.

## Triggers

- `TICKET_CREATED`
- `INBOUND_MESSAGE`

Only inbound WhatsApp events schedule rules. Automated outbound messages do not
schedule another automation, preventing message loops.

## Conditions

A rule can restrict execution by:

- keyword contained in the inbound message, case-insensitive;
- only when the ticket is still unassigned;
- direct contact / group / all conversations.

Rules run by ascending priority.

## Actions

Actions execute in order:

- `SET_QUEUE`
- `ASSIGN_MEMBERSHIP`
- `ADD_TAG`
- `SEND_TEXT`

An automated text is stored with no `sentByUserId`. It is intentionally not
attributed to an operator and does not claim the ticket.

Supported variables:

- `{nome}`
- `{primeiro_nome}`
- `{empresa}`

## Durability

When Redis is configured, evaluation is queued in BullMQ `wapp-automations`.

Jobs use one attempt because a rule can contain side effects such as sending a
WhatsApp message. Automatic retries could duplicate an already-delivered side
effect.

Without Redis, development mode uses an explicitly non-durable inline fallback.

## Idempotency

Each rule/source-message/trigger combination has a unique `AutomationRun`
dedupe key. Duplicate webhook processing does not execute the same rule twice.

## Observability

Each matched rule gets an `AutomationRun`:

- RUNNING
- SUCCESS
- FAILED

Successful execution also appends the ticket-history event
`AUTOMATION_APPLIED`.

Rule create/update operations are written to the P1.26 administrative audit.

## RBAC

- OWNER: read/manage
- ADMIN: read/manage
- SUPERVISOR: read/manage
- AGENT: read only

## UI

`/dashboard/automations`

The first P2.4 UI supports:

- create a rule;
- choose trigger and conditions;
- compose queue/assignee/tag/text actions;
- activate/pause a rule;
- inspect its latest execution state.

The API already supports PATCH updates for later richer rule editing.

## Migration

P2.4 introduces:

- `AutomationRule`
- `AutomationAction`
- `AutomationRun`
EOF

echo "[P2.4] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P2.4] Unit tests..."
pnpm test

echo "[P2.4] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P2.4] Typechecking Web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.4] Operational automations installed."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
