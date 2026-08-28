#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.5] Installing durable scheduled messages..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/jobs/job-runtime.ts" \
  "apps/api/src/jobs/job-redis.ts" \
  "apps/api/src/worker.ts" \
  "apps/api/src/modules/tickets/ticket-event.service.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/integrations/whatsapp/evolution.client.ts" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/components/conversations/ticket-history-drawer.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/scheduled-messages \
  apps/api/src/jobs \
  apps/api/prisma/migrations/20260828230000_scheduled_messages \
  apps/web/components/conversations \
  docs

# ---------------------------------------------------------------------------
# Prisma schema
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
    "enum ScheduledMessageStatus {"
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

  const addition = `enum ScheduledMessageStatus {
  PENDING
  PROCESSING
  SENT
  CANCELLED
  FAILED
}

`;

  content =
    content.slice(
      0,
      index
    ) +
    addition +
    content.slice(
      index
    );
}

function addRelationField(
  modelName,
  anchorField,
  relationLine
) {
  const modelStart =
    content.indexOf(
      `model ${modelName} {`
    );

  if (modelStart < 0) {
    throw new Error(
      `${modelName} model not found.`
    );
  }

  const modelEnd =
    content.indexOf(
      "\n}",
      modelStart
    );

  if (modelEnd < 0) {
    throw new Error(
      `${modelName} model end not found.`
    );
  }

  const modelBlock =
    content.slice(
      modelStart,
      modelEnd
    );

  if (
    modelBlock.includes(
      relationLine.trim()
    )
  ) {
    return;
  }

  const anchorIndex =
    content.indexOf(
      anchorField,
      modelStart
    );

  if (
    anchorIndex < 0 ||
    anchorIndex >
      modelEnd
  ) {
    throw new Error(
      `${modelName} relation anchor not found.`
    );
  }

  const lineEnd =
    content.indexOf(
      "\n",
      anchorIndex
    );

  content =
    content.slice(
      0,
      lineEnd + 1
    ) +
    relationLine +
    content.slice(
      lineEnd + 1
    );
}

addRelationField(
  "Company",
  "ticketNotes",
  "  scheduledMessages       ScheduledMessage[]\n"
);

addRelationField(
  "CompanyMembership",
  "ticketNotes",
  "  scheduledMessages       ScheduledMessage[]\n"
);

addRelationField(
  "Ticket",
  "notes",
  "  scheduledMessages       ScheduledMessage[]\n"
);

if (
  !content.includes(
    "model ScheduledMessage {"
  )
) {
  content += `

model ScheduledMessage {
  id                    String                 @id @default(uuid()) @db.Char(36)
  companyId             String                 @db.Char(36)
  ticketId              String                 @db.Char(36)
  createdByMembershipId String                 @db.Char(36)
  body                  String                 @db.Text
  scheduledFor          DateTime
  status                ScheduledMessageStatus @default(PENDING)
  claimedAt             DateTime?
  sentAt                DateTime?
  cancelledAt           DateTime?
  sentMessageId         String?                @db.Char(36)
  error                 String?                @db.Text
  company               Company                @relation(fields: [companyId], references: [id], onDelete: Cascade)
  ticket                Ticket                 @relation(fields: [ticketId], references: [id], onDelete: Cascade)
  createdByMembership   CompanyMembership      @relation(fields: [createdByMembershipId], references: [id], onDelete: Restrict)
  createdAt             DateTime               @default(now())
  updatedAt             DateTime               @updatedAt

  @@index([companyId, status, scheduledFor])
  @@index([ticketId, status, scheduledFor])
  @@index([createdByMembershipId, createdAt])
}
`;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.5] Prisma ScheduledMessage model prepared."
);
NODE

cat > apps/api/prisma/migrations/20260828230000_scheduled_messages/migration.sql <<'EOF'
CREATE TABLE `ScheduledMessage` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NOT NULL,
  `createdByMembershipId` CHAR(36) NOT NULL,
  `body` TEXT NOT NULL,
  `scheduledFor` DATETIME(3) NOT NULL,
  `status` ENUM(
    'PENDING',
    'PROCESSING',
    'SENT',
    'CANCELLED',
    'FAILED'
  ) NOT NULL DEFAULT 'PENDING',
  `claimedAt` DATETIME(3) NULL,
  `sentAt` DATETIME(3) NULL,
  `cancelledAt` DATETIME(3) NULL,
  `sentMessageId` CHAR(36) NULL,
  `error` TEXT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),

  INDEX `ScheduledMessage_companyId_status_scheduledFor_idx`
    (`companyId`, `status`, `scheduledFor`),

  INDEX `ScheduledMessage_ticketId_status_scheduledFor_idx`
    (`ticketId`, `status`, `scheduledFor`),

  INDEX `ScheduledMessage_createdByMembershipId_createdAt_idx`
    (`createdByMembershipId`, `createdAt`),

  CONSTRAINT `ScheduledMessage_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ScheduledMessage_ticketId_fkey`
    FOREIGN KEY (`ticketId`)
    REFERENCES `Ticket`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ScheduledMessage_createdByMembershipId_fkey`
    FOREIGN KEY (`createdByMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

# ---------------------------------------------------------------------------
# Scheduling policy
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/scheduled-messages/scheduled-message.policy.ts <<'EOF'
import type {
  WappRole
} from "../../lib/tokens.js";

export const SCHEDULE_MIN_LEAD_MS =
  30_000;

export const SCHEDULE_MAX_AHEAD_MS =
  365 *
  24 *
  60 *
  60 *
  1_000;

export const STALE_PROCESSING_MS =
  15 *
  60 *
  1_000;

export function scheduleTimeError(
  now: Date,
  scheduledFor: Date
) {
  const delta =
    scheduledFor.getTime() -
    now.getTime();

  if (
    !Number.isFinite(
      scheduledFor.getTime()
    )
  ) {
    return "INVALID";
  }

  if (
    delta <
    SCHEDULE_MIN_LEAD_MS
  ) {
    return "TOO_SOON";
  }

  if (
    delta >
    SCHEDULE_MAX_AHEAD_MS
  ) {
    return "TOO_FAR";
  }

  return null;
}

export function scheduledMessageDelay(
  now: Date,
  scheduledFor: Date
) {
  return Math.max(
    0,
    scheduledFor.getTime() -
      now.getTime()
  );
}

export function canManageScheduledMessage(input: {
  role: WappRole;
  actorMembershipId: string;
  createdByMembershipId: string;
}) {
  return (
    input.actorMembershipId ===
      input.createdByMembershipId ||
    input.role ===
      "OWNER" ||
    input.role ===
      "ADMIN" ||
    input.role ===
      "SUPERVISOR"
  );
}
EOF

cat > apps/api/src/modules/scheduled-messages/scheduled-message.policy.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  canManageScheduledMessage,
  scheduleTimeError,
  scheduledMessageDelay
} from "./scheduled-message.policy.js";

test(
  "scheduled time must have a safe future lead",
  () => {
    const now =
      new Date(
        "2026-08-28T15:00:00.000Z"
      );

    assert.equal(
      scheduleTimeError(
        now,
        new Date(
          "2026-08-28T15:00:10.000Z"
        )
      ),
      "TOO_SOON"
    );

    assert.equal(
      scheduleTimeError(
        now,
        new Date(
          "2026-08-28T15:10:00.000Z"
        )
      ),
      null
    );
  }
);

test(
  "BullMQ delay never becomes negative",
  () => {
    const now =
      new Date(
        "2026-08-28T15:00:00.000Z"
      );

    assert.equal(
      scheduledMessageDelay(
        now,
        new Date(
          "2026-08-28T14:59:00.000Z"
        )
      ),
      0
    );
  }
);

test(
  "agents can cancel their own schedules but not another agent schedule",
  () => {
    assert.equal(
      canManageScheduledMessage({
        role:
          "AGENT",
        actorMembershipId:
          "a",
        createdByMembershipId:
          "a"
      }),
      true
    );

    assert.equal(
      canManageScheduledMessage({
        role:
          "AGENT",
        actorMembershipId:
          "a",
        createdByMembershipId:
          "b"
      }),
      false
    );

    assert.equal(
      canManageScheduledMessage({
        role:
          "SUPERVISOR",
        actorMembershipId:
          "a",
        createdByMembershipId:
          "b"
      }),
      true
    );
  }
);
EOF

# ---------------------------------------------------------------------------
# Queue + worker
# ---------------------------------------------------------------------------

cat > apps/api/src/jobs/scheduled-message.queue.ts <<'EOF'
import {
  Queue
} from "bullmq";

import {
  env
} from "../config/env.js";
import {
  scheduledMessageDelay
} from "../modules/scheduled-messages/scheduled-message.policy.js";
import {
  jobProducerRedisOptions
} from "./job-redis.js";

export const SCHEDULED_MESSAGE_QUEUE_NAME =
  "wapp-scheduled-messages";

export const SCHEDULED_MESSAGE_DELIVER_JOB =
  "deliver";

export const SCHEDULED_MESSAGE_SWEEP_JOB =
  "sweep";

interface DeliveryData {
  scheduledMessageId: string;
}

let queue:
  | Queue
  | null =
  null;

export function getScheduledMessageQueue() {
  if (!queue) {
    queue =
      new Queue(
        SCHEDULED_MESSAGE_QUEUE_NAME,
        {
          connection:
            jobProducerRedisOptions()
        }
      );
  }

  return queue;
}

export async function enqueueScheduledMessageDelivery(input: {
  scheduledMessageId: string;
  scheduledFor: Date;
}) {
  if (
    !env.REDIS_URL
  ) {
    return false;
  }

  await getScheduledMessageQueue()
    .add(
      SCHEDULED_MESSAGE_DELIVER_JOB,
      {
        scheduledMessageId:
          input.scheduledMessageId
      } satisfies DeliveryData,
      {
        jobId:
          `scheduled-message-${input.scheduledMessageId}`,
        delay:
          scheduledMessageDelay(
            new Date(),
            input.scheduledFor
          ),
        attempts:
          1,
        removeOnComplete: {
          count:
            2000
        },
        removeOnFail: {
          count:
            2000
        }
      }
    );

  return true;
}

export async function ensureScheduledMessageSweep() {
  if (
    !env.REDIS_URL
  ) {
    return;
  }

  await getScheduledMessageQueue()
    .upsertJobScheduler(
      "wapp-scheduled-message-sweep",
      {
        every:
          60_000
      },
      {
        name:
          SCHEDULED_MESSAGE_SWEEP_JOB,
        data: {}
      }
    );
}

export async function removeScheduledMessageJob(
  scheduledMessageId: string
) {
  if (
    !env.REDIS_URL
  ) {
    return;
  }

  const job =
    await getScheduledMessageQueue()
      .getJob(
        `scheduled-message-${scheduledMessageId}`
      );

  if (
    job &&
    ![
      "active",
      "completed",
      "failed"
    ].includes(
      await job.getState()
    )
  ) {
    await job.remove();
  }
}

export async function closeScheduledMessageQueue() {
  const current =
    queue;

  queue =
    null;

  if (
    current
  ) {
    await current.close();
  }
}
EOF

cat > apps/api/src/jobs/scheduled-message.worker.ts <<'EOF'
import {
  Worker
} from "bullmq";

import {
  deliverScheduledMessage,
  reconcileScheduledMessages
} from "../modules/scheduled-messages/scheduled-message.service.js";
import {
  jobWorkerRedisOptions
} from "./job-redis.js";
import {
  SCHEDULED_MESSAGE_DELIVER_JOB,
  SCHEDULED_MESSAGE_QUEUE_NAME,
  SCHEDULED_MESSAGE_SWEEP_JOB,
  enqueueScheduledMessageDelivery
} from "./scheduled-message.queue.js";

export function createScheduledMessageWorker() {
  const worker =
    new Worker(
      SCHEDULED_MESSAGE_QUEUE_NAME,
      async job => {
        if (
          job.name ===
          SCHEDULED_MESSAGE_DELIVER_JOB
        ) {
          const scheduledMessageId =
            typeof job.data
                ?.scheduledMessageId ===
              "string"
              ? job.data
                  .scheduledMessageId
              : null;

          if (
            !scheduledMessageId
          ) {
            throw new Error(
              "scheduledMessageId is required."
            );
          }

          return deliverScheduledMessage(
            scheduledMessageId
          );
        }

        if (
          job.name ===
          SCHEDULED_MESSAGE_SWEEP_JOB
        ) {
          const due =
            await reconcileScheduledMessages();

          for (
            const item
            of due
          ) {
            await enqueueScheduledMessageDelivery({
              scheduledMessageId:
                item.id,
              scheduledFor:
                item.scheduledFor
            });
          }

          return {
            queued:
              due.length
          };
        }

        throw new Error(
          `Unknown scheduled-message job: ${job.name}`
        );
      },
      {
        connection:
          jobWorkerRedisOptions(),
        concurrency:
          3
      }
    );

  worker.on(
    "failed",
    (
      job,
      error
    ) => {
      console.error(
        "[scheduled-messages] job failed",
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

# ---------------------------------------------------------------------------
# Scheduled message service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/scheduled-messages/scheduled-message.service.ts <<'EOF'
import {
  AppError
} from "../../errors/app-error.js";
import {
  evolutionWhatsAppClient
} from "../../integrations/whatsapp/evolution.client.js";
import type {
  WappRole
} from "../../lib/tokens.js";
import {
  prisma
} from "../../lib/database.js";
import {
  toPrismaJson
} from "../../lib/prisma-json.js";
import {
  publishRealtime
} from "../realtime/realtime.bus.js";
import {
  recordTicketEvent
} from "../tickets/ticket-event.service.js";
import {
  canManageScheduledMessage,
  scheduleTimeError,
  STALE_PROCESSING_MS
} from "./scheduled-message.policy.js";

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

  const id =
    getString(
      key?.id
    );

  if (
    !id
  ) {
    throw new Error(
      "WhatsApp provider did not return a message id."
    );
  }

  return id;
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

function canOverrideAssignment(
  role:
    WappRole
) {
  return (
    role ===
      "OWNER" ||
    role ===
      "ADMIN" ||
    role ===
      "SUPERVISOR"
  );
}

async function requireSchedulableTicket(input: {
  companyId: string;
  ticketId: string;
  actorMembershipId: string;
  role: WappRole;
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
        contact:
          true,
        whatsappConnection:
          true
      }
    });

  if (
    !ticket
  ) {
    throw new AppError(
      "Atendimento não encontrado.",
      404,
      "TICKET_NOT_FOUND"
    );
  }

  if (
    ticket.status ===
    "CLOSED"
  ) {
    throw new AppError(
      "Não é possível agendar mensagem em atendimento encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  if (
    ticket.assignedMembershipId &&
    ticket.assignedMembershipId !==
      input.actorMembershipId &&
    !canOverrideAssignment(
      input.role
    )
  ) {
    throw new AppError(
      "Este atendimento está atribuído a outro atendente.",
      403,
      "TICKET_ASSIGNED_TO_ANOTHER_AGENT"
    );
  }

  const membership =
    await prisma.companyMembership.findFirst({
      where: {
        id:
          input.actorMembershipId,
        companyId:
          input.companyId,
        isActive:
          true,
        user: {
          isActive:
            true
        }
      },
      include: {
        user:
          true
      }
    });

  if (
    !membership
  ) {
    throw new AppError(
      "Atendente não encontrado na empresa ativa.",
      422,
      "INVALID_SCHEDULE_AUTHOR"
    );
  }

  if (
    ticket.queueId &&
    !canOverrideAssignment(
      input.role
    )
  ) {
    const configuredMembers =
      await prisma.queueMember.count({
        where: {
          queueId:
            ticket.queueId
        }
      });

    if (
      configuredMembers >
      0
    ) {
      const queueMembership =
        await prisma.queueMember.findUnique({
          where: {
            queueId_membershipId: {
              queueId:
                ticket.queueId,
              membershipId:
                input.actorMembershipId
            }
          },
          select: {
            id:
              true
          }
        });

      if (
        !queueMembership
      ) {
        throw new AppError(
          "Você não pertence à fila deste atendimento.",
          403,
          "AGENT_NOT_IN_QUEUE"
        );
      }
    }
  }

  return {
    ticket,
    membership
  };
}

export async function listTicketScheduledMessages(input: {
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
        id:
          true
      }
    });

  if (
    !ticket
  ) {
    throw new AppError(
      "Atendimento não encontrado.",
      404,
      "TICKET_NOT_FOUND"
    );
  }

  return prisma.scheduledMessage.findMany({
    where: {
      companyId:
        input.companyId,
      ticketId:
        input.ticketId
    },
    include: {
      createdByMembership: {
        select: {
          id:
            true,
          user: {
            select: {
              id:
                true,
              name:
                true
            }
          }
        }
      }
    },
    orderBy: [
      {
        scheduledFor:
          "asc"
      },
      {
        createdAt:
          "asc"
      }
    ],
    take:
      100
  });
}

export async function createScheduledMessage(input: {
  companyId: string;
  ticketId: string;
  actorMembershipId: string;
  role: WappRole;
  body: string;
  scheduledFor: Date;
}) {
  const body =
    input.body.trim();

  if (
    !body
  ) {
    throw new AppError(
      "Digite a mensagem que será agendada.",
      422,
      "SCHEDULE_BODY_REQUIRED"
    );
  }

  if (
    body.length >
    4096
  ) {
    throw new AppError(
      "A mensagem agendada excede 4096 caracteres.",
      422,
      "SCHEDULE_BODY_TOO_LONG"
    );
  }

  const timeError =
    scheduleTimeError(
      new Date(),
      input.scheduledFor
    );

  if (
    timeError ===
    "INVALID"
  ) {
    throw new AppError(
      "Data de agendamento inválida.",
      422,
      "INVALID_SCHEDULE_TIME"
    );
  }

  if (
    timeError ===
    "TOO_SOON"
  ) {
    throw new AppError(
      "Agende a mensagem com pelo menos 30 segundos de antecedência.",
      422,
      "SCHEDULE_TOO_SOON"
    );
  }

  if (
    timeError ===
    "TOO_FAR"
  ) {
    throw new AppError(
      "O agendamento não pode ultrapassar 365 dias.",
      422,
      "SCHEDULE_TOO_FAR"
    );
  }

  await requireSchedulableTicket({
    companyId:
      input.companyId,
    ticketId:
      input.ticketId,
    actorMembershipId:
      input.actorMembershipId,
    role:
      input.role
  });

  const scheduledMessage =
    await prisma.scheduledMessage.create({
      data: {
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        createdByMembershipId:
          input.actorMembershipId,
        body,
        scheduledFor:
          input.scheduledFor
      },
      include: {
        createdByMembership: {
          select: {
            id:
              true,
            user: {
              select: {
                id:
                  true,
                name:
                  true
              }
            }
          }
        }
      }
    });

  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      input.ticketId,
    actorMembershipId:
      input.actorMembershipId,
    type:
      "MESSAGE_SCHEDULED",
    metadata: {
      scheduledMessageId:
        scheduledMessage.id,
      scheduledFor:
        scheduledMessage
          .scheduledFor
          .toISOString()
    }
  });

  return scheduledMessage;
}

export async function cancelScheduledMessage(input: {
  companyId: string;
  scheduledMessageId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const existing =
    await prisma.scheduledMessage.findFirst({
      where: {
        id:
          input.scheduledMessageId,
        companyId:
          input.companyId
      }
    });

  if (
    !existing
  ) {
    throw new AppError(
      "Agendamento não encontrado.",
      404,
      "SCHEDULE_NOT_FOUND"
    );
  }

  if (
    !canManageScheduledMessage({
      role:
        input.role,
      actorMembershipId:
        input.actorMembershipId,
      createdByMembershipId:
        existing
          .createdByMembershipId
    })
  ) {
    throw new AppError(
      "Você não pode cancelar o agendamento de outro atendente.",
      403,
      "SCHEDULE_FORBIDDEN"
    );
  }

  if (
    existing.status !==
    "PENDING"
  ) {
    throw new AppError(
      "Somente agendamentos pendentes podem ser cancelados.",
      409,
      "SCHEDULE_NOT_PENDING"
    );
  }

  const result =
    await prisma.scheduledMessage.updateMany({
      where: {
        id:
          existing.id,
        status:
          "PENDING"
      },
      data: {
        status:
          "CANCELLED",
        cancelledAt:
          new Date()
      }
    });

  if (
    result.count !==
    1
  ) {
    throw new AppError(
      "O agendamento já começou a ser processado.",
      409,
      "SCHEDULE_ALREADY_PROCESSING"
    );
  }

  const cancelled =
    await prisma.scheduledMessage.findUniqueOrThrow({
      where: {
        id:
          existing.id
      },
      include: {
        createdByMembership: {
          select: {
            id:
              true,
            user: {
              select: {
                id:
                  true,
                name:
                  true
              }
            }
          }
        }
      }
    });

  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      existing.ticketId,
    actorMembershipId:
      input.actorMembershipId,
    type:
      "SCHEDULED_MESSAGE_CANCELLED",
    metadata: {
      scheduledMessageId:
        existing.id,
      scheduledFor:
        existing
          .scheduledFor
          .toISOString()
    }
  });

  return cancelled;
}

async function markFailed(
  scheduledMessageId: string,
  error: string
) {
  const failed =
    await prisma.scheduledMessage.update({
      where: {
        id:
          scheduledMessageId
      },
      data: {
        status:
          "FAILED",
        error:
          error.slice(
            0,
            4000
          )
      }
    });

  await recordTicketEvent({
    companyId:
      failed.companyId,
    ticketId:
      failed.ticketId,
    actorMembershipId:
      failed.createdByMembershipId,
    type:
      "SCHEDULED_MESSAGE_FAILED",
    metadata: {
      scheduledMessageId:
        failed.id,
      reason:
        failed.error
    }
  });

  return failed;
}

export async function deliverScheduledMessage(
  scheduledMessageId: string
) {
  const now =
    new Date();

  const claimed =
    await prisma.scheduledMessage.updateMany({
      where: {
        id:
          scheduledMessageId,
        status:
          "PENDING",
        scheduledFor: {
          lte:
            new Date(
              now.getTime() +
              2_000
            )
        }
      },
      data: {
        status:
          "PROCESSING",
        claimedAt:
          now,
        error:
          null
      }
    });

  if (
    claimed.count !==
    1
  ) {
    return {
      delivered:
        false,
      reason:
        "not_due_or_not_pending"
    };
  }

  const scheduled =
    await prisma.scheduledMessage.findUnique({
      where: {
        id:
          scheduledMessageId
      },
      include: {
        ticket: {
          include: {
            contact:
              true,
            whatsappConnection:
              true
          }
        },
        createdByMembership: {
          include: {
            user:
              true
          }
        }
      }
    });

  if (
    !scheduled
  ) {
    return {
      delivered:
        false,
      reason:
        "missing_after_claim"
    };
  }

  if (
    !scheduled
      .createdByMembership
      .isActive ||
    !scheduled
      .createdByMembership
      .user.isActive
  ) {
    await markFailed(
      scheduled.id,
      "O usuário que criou o agendamento não está mais ativo."
    );

    return {
      delivered:
        false,
      reason:
        "author_inactive"
    };
  }

  if (
    scheduled.ticket.status ===
    "CLOSED"
  ) {
    await markFailed(
      scheduled.id,
      "O atendimento foi encerrado antes do horário agendado."
    );

    return {
      delivered:
        false,
      reason:
        "ticket_closed"
    };
  }

  if (
    scheduled
      .ticket
      .whatsappConnection
      .status !==
    "CONNECTED"
  ) {
    await markFailed(
      scheduled.id,
      "A conexão WhatsApp estava offline no horário do envio."
    );

    return {
      delivered:
        false,
      reason:
        "connection_offline"
    };
  }

  try {
    const result =
      await evolutionWhatsAppClient.sendText({
        instanceName:
          scheduled
            .ticket
            .whatsappConnection
            .instanceName,
        number:
          scheduled
            .ticket
            .contact
            .remoteJid,
        text:
          scheduled.body
      });

    const timestamp =
      sentTimestamp(
        result
      );

    const externalId =
      sentExternalId(
        result
      );

    const message =
      await prisma.message.upsert({
        where: {
          whatsappConnectionId_externalId: {
            whatsappConnectionId:
              scheduled
                .ticket
                .whatsappConnectionId,
            externalId
          }
        },
        update: {},
        create: {
          companyId:
            scheduled.companyId,
          ticketId:
            scheduled.ticketId,
          whatsappConnectionId:
            scheduled
              .ticket
              .whatsappConnectionId,
          sentByUserId:
            scheduled
              .createdByMembership
              .userId,
          externalId,
          direction:
            "OUTBOUND",
          type:
            "TEXT",
          deliveryStatus:
            "PENDING",
          body:
            scheduled.body,
          timestamp,
          rawPayload:
            toPrismaJson(
              result
            )
        }
      });

    await prisma.$transaction([
      prisma.ticket.update({
        where: {
          id:
            scheduled.ticketId
        },
        data: {
          lastMessage:
            scheduled.body,
          lastMessageAt:
            timestamp,
          lastOutboundAt:
            timestamp,
          waitingSince:
            null,
          ...(scheduled
            .ticket
            .firstInboundAt &&
          !scheduled
            .ticket
            .firstResponseAt
            ? {
                firstResponseAt:
                  timestamp
              }
            : {})
        }
      }),
      prisma.scheduledMessage.update({
        where: {
          id:
            scheduled.id
        },
        data: {
          status:
            "SENT",
          sentAt:
            timestamp,
          sentMessageId:
            message.id,
          error:
            null
        }
      })
    ]);

    await recordTicketEvent({
      companyId:
        scheduled.companyId,
      ticketId:
        scheduled.ticketId,
      actorMembershipId:
        scheduled
          .createdByMembershipId,
      type:
        "SCHEDULED_MESSAGE_SENT",
      metadata: {
        scheduledMessageId:
          scheduled.id,
        messageId:
          message.id,
        scheduledFor:
          scheduled
            .scheduledFor
            .toISOString()
      }
    });

    publishRealtime(
      scheduled.companyId,
      {
        type:
          "message.created",
        ticketId:
          scheduled.ticketId,
        messageId:
          message.id
      }
    );

    publishRealtime(
      scheduled.companyId,
      {
        type:
          "ticket.updated",
        ticketId:
          scheduled.ticketId
      }
    );

    return {
      delivered:
        true,
      messageId:
        message.id
    };
  } catch (error) {
    const message =
      error instanceof
        Error
        ? error.message
        : "Falha desconhecida ao enviar a mensagem agendada.";

    await markFailed(
      scheduled.id,
      message
    );

    return {
      delivered:
        false,
      reason:
        "send_failed"
    };
  }
}

export async function reconcileScheduledMessages() {
  const now =
    new Date();

  await prisma.scheduledMessage.updateMany({
    where: {
      status:
        "PROCESSING",
      claimedAt: {
        lt:
          new Date(
            now.getTime() -
            STALE_PROCESSING_MS
          )
      }
    },
    data: {
      status:
        "FAILED",
      error:
        "Execução interrompida. A entrega pode ser incerta; confira o WhatsApp antes de reagendar."
    }
  });

  return prisma.scheduledMessage.findMany({
    where: {
      status:
        "PENDING",
      scheduledFor: {
        lte:
          now
      }
    },
    select: {
      id:
        true,
      scheduledFor:
        true
    },
    orderBy: {
      scheduledFor:
        "asc"
    },
    take:
      100
  });
}
EOF

# ---------------------------------------------------------------------------
# API routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/scheduled-messages/scheduled-message.routes.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  enqueueScheduledMessageDelivery,
  removeScheduledMessageJob
} from "../../jobs/scheduled-message.queue.js";
import {
  requireAuth
} from "../auth/auth.guard.js";
import {
  cancelScheduledMessage,
  createScheduledMessage,
  listTicketScheduledMessages
} from "./scheduled-message.service.js";

const ticketParams =
  z.object({
    id:
      z.string()
        .uuid()
  });

const scheduleParams =
  z.object({
    id:
      z.string()
        .uuid()
  });

const createSchema =
  z.object({
    body:
      z.string()
        .trim()
        .min(1)
        .max(4096),
    scheduledFor:
      z.string()
        .datetime({
          offset:
            true
        })
  });

export async function scheduledMessageRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/tickets/:id/scheduled-messages",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        ticketParams.parse(
          request.params
        );

      return {
        scheduledMessages:
          await listTicketScheduledMessages({
            companyId:
              auth.companyId,
            ticketId:
              params.id
          })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/scheduled-messages",
    async (
      request,
      reply
    ) => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        ticketParams.parse(
          request.params
        );

      const input =
        createSchema.parse(
          request.body
        );

      const scheduledMessage =
        await createScheduledMessage({
          companyId:
            auth.companyId,
          ticketId:
            params.id,
          actorMembershipId:
            auth.membershipId,
          role:
            auth.role,
          body:
            input.body,
          scheduledFor:
            new Date(
              input.scheduledFor
            )
        });

      let queued =
        false;

      try {
        queued =
          await enqueueScheduledMessageDelivery({
            scheduledMessageId:
              scheduledMessage.id,
            scheduledFor:
              scheduledMessage
                .scheduledFor
          });
      } catch (error) {
        request.log.error(
          {
            error,
            scheduledMessageId:
              scheduledMessage.id
          },
          "scheduled-message enqueue failed; database reconciliation will retry"
        );
      }

      return reply
        .status(
          201
        )
        .send({
          scheduledMessage,
          queued
        });
    }
  );

  app.delete(
    "/api/v1/scheduled-messages/:id",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        scheduleParams.parse(
          request.params
        );

      const scheduledMessage =
        await cancelScheduledMessage({
          companyId:
            auth.companyId,
          scheduledMessageId:
            params.id,
          actorMembershipId:
            auth.membershipId,
          role:
            auth.role
        });

      try {
        await removeScheduledMessageJob(
          scheduledMessage.id
        );
      } catch (error) {
        request.log.warn(
          {
            error,
            scheduledMessageId:
              scheduledMessage.id
          },
          "scheduled-message queue cleanup failed"
        );
      }

      return {
        scheduledMessage
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register API route
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
  'import { scheduledMessageRoutes } from "./modules/scheduled-messages/scheduled-message.routes.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { quickReplyRoutes } from "./modules/quick-replies/quick-reply.routes.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "quickReplyRoutes import anchor not found."
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
    "await app.register(scheduledMessageRoutes);"
  )
) {
  const anchor =
    `  await app.register(quickReplyRoutes);`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "quickReplyRoutes registration anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  await app.register(scheduledMessageRoutes);`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Job runtime
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

if (
  !content.includes(
    'from "./scheduled-message.worker.js"'
  )
) {
  const anchor =
    'import { env } from "../config/env.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "job runtime env import anchor not found."
    );
  }

  const imports = `import {
  createScheduledMessageWorker
} from "./scheduled-message.worker.js";
import {
  closeScheduledMessageQueue,
  ensureScheduledMessageSweep
} from "./scheduled-message.queue.js";`;

  content =
    content.replace(
      anchor,
      `${anchor}
${imports}`
    );
}

if (
  !content.includes(
    "createScheduledMessageWorker()"
  )
) {
  const anchor =
    `    createAutomationWorker()`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "automation worker array anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor},
    createScheduledMessageWorker()`
    );
}

if (
  !content.includes(
    "ensureScheduledMessageSweep()"
  )
) {
  const anchor =
    `  void ensureMaintenanceSchedule()
    .catch(error => {
      console.error(
        "[maintenance] scheduler setup failed",
        error
      );
    });`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "maintenance scheduler anchor not found."
    );
  }

  const addition = `${anchor}

  void ensureScheduledMessageSweep()
    .catch(error => {
      console.error(
        "[scheduled-messages] scheduler setup failed",
        error
      );
    });`;

  content =
    content.replace(
      anchor,
      addition
    );
}

if (
  !content.includes(
    "closeScheduledMessageQueue()"
  )
) {
  const anchor =
    `    closeAutomationQueue()`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "automation queue close anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor},
    closeScheduledMessageQueue()`
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
    'from "./jobs/scheduled-message.worker.js"'
  )
) {
  const anchor =
    'import { prisma } from "./lib/database.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "worker prisma import anchor not found."
    );
  }

  const imports = `import {
  createScheduledMessageWorker
} from "./jobs/scheduled-message.worker.js";
import {
  closeScheduledMessageQueue,
  ensureScheduledMessageSweep
} from "./jobs/scheduled-message.queue.js";`;

  content =
    content.replace(
      anchor,
      `${anchor}
${imports}`
    );
}

if (
  !content.includes(
    "createScheduledMessageWorker()"
  )
) {
  const anchor =
    `  createAutomationWorker()`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "standalone automation worker anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor},
  createScheduledMessageWorker()`
    );
}

if (
  !content.includes(
    "await ensureScheduledMessageSweep();"
  )
) {
  const anchor =
    `await ensureMaintenanceSchedule();`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "standalone maintenance schedule anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
await ensureScheduledMessageSweep();`
    );
}

if (
  !content.includes(
    "closeScheduledMessageQueue()"
  )
) {
  const anchor =
    `    closeAutomationQueue()`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "standalone automation queue close anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor},
    closeScheduledMessageQueue()`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Ticket event contract.
# Also self-heal the P2.4 event if automation code exists locally.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const eventPath =
  "apps/api/src/modules/tickets/ticket-event.service.ts";

const automationPath =
  "apps/api/src/modules/automations/automation.service.ts";

let content =
  fs.readFileSync(
    eventPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const start =
  content.indexOf(
    "export type TicketEventType ="
  );

if (
  start < 0
) {
  throw new Error(
    "TicketEventType declaration not found."
  );
}

const end =
  content.indexOf(
    ";",
    start
  );

if (
  end < 0
) {
  throw new Error(
    "TicketEventType declaration end not found."
  );
}

let block =
  content.slice(
    start,
    end
  );

const additions = [
  "MESSAGE_SCHEDULED",
  "SCHEDULED_MESSAGE_CANCELLED",
  "SCHEDULED_MESSAGE_SENT",
  "SCHEDULED_MESSAGE_FAILED"
];

if (
  fs.existsSync(
    automationPath
  ) &&
  fs.readFileSync(
    automationPath,
    "utf8"
  ).includes(
    '"AUTOMATION_APPLIED"'
  )
) {
  additions.unshift(
    "AUTOMATION_APPLIED"
  );
}

for (
  const type
  of additions
) {
  if (
    !block.includes(
      `"${type}"`
    )
  ) {
    block +=
      `\n  | "${type}"`;
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

fs.writeFileSync(
  eventPath,
  content
);

console.log(
  "[P2.5] Ticket event contract extended."
);
NODE

# ---------------------------------------------------------------------------
# Ticket history rendering
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/components/conversations/ticket-history-drawer.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const titleAnchor =
  `    case "TAGS_UPDATED":
      return "Etiquetas atualizadas";`;

if (
  !content.includes(
    'case "MESSAGE_SCHEDULED":'
  )
) {
  if (
    !content.includes(
      titleAnchor
    )
  ) {
    throw new Error(
      "ticket history title anchor not found."
    );
  }

  const addition = `${titleAnchor}
    case "MESSAGE_SCHEDULED":
      return "Mensagem agendada";
    case "SCHEDULED_MESSAGE_CANCELLED":
      return "Agendamento cancelado";
    case "SCHEDULED_MESSAGE_SENT":
      return "Mensagem agendada enviada";
    case "SCHEDULED_MESSAGE_FAILED":
      return "Falha no agendamento";`;

  content =
    content.replace(
      titleAnchor,
      addition
    );
}

const detailAnchor =
  `    default:
      return "Evento operacional registrado.";`;

if (
  !content.includes(
    'case "SCHEDULED_MESSAGE_SENT": {'
  )
) {
  if (
    !content.includes(
      detailAnchor
    )
  ) {
    throw new Error(
      "ticket history detail default anchor not found."
    );
  }

  const addition = `    case "MESSAGE_SCHEDULED": {
      const scheduledFor =
        text(
          metadata,
          "scheduledFor"
        );

      return scheduledFor
        ? \`Envio programado para \${dateTimeLabel(scheduledFor)}.\`
        : "Uma mensagem foi programada para envio.";
    }

    case "SCHEDULED_MESSAGE_CANCELLED":
      return "O envio programado foi cancelado.";

    case "SCHEDULED_MESSAGE_SENT": {
      const scheduledFor =
        text(
          metadata,
          "scheduledFor"
        );

      return scheduledFor
        ? \`Mensagem programada para \${dateTimeLabel(scheduledFor)} enviada pelo sistema.\`
        : "A mensagem agendada foi enviada.";
    }

    case "SCHEDULED_MESSAGE_FAILED": {
      const reason =
        text(
          metadata,
          "reason"
        );

      return reason
        ? \`Falha no envio agendado: \${reason}\`
        : "O envio agendado falhou.";
    }

${detailAnchor}`;

  content =
    content.replace(
      detailAnchor,
      addition
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Web component
# ---------------------------------------------------------------------------

cat > apps/web/components/conversations/scheduled-message-drawer.tsx <<'EOF'
"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";

import {
  useAuth
} from "@/components/auth-provider";
import {
  ApiError
} from "@/lib/api";

interface ScheduledMessage {
  id: string;
  body: string;
  scheduledFor: string;
  status:
    | "PENDING"
    | "PROCESSING"
    | "SENT"
    | "CANCELLED"
    | "FAILED";
  sentAt:
    | string
    | null;
  cancelledAt:
    | string
    | null;
  error:
    | string
    | null;
  createdByMembership: {
    id: string;
    user: {
      id: string;
      name: string;
    };
  };
}

function localDateTimeInput(
  date: Date
) {
  const shifted =
    new Date(
      date.getTime() -
      date
        .getTimezoneOffset() *
      60_000
    );

  return shifted
    .toISOString()
    .slice(
      0,
      16
    );
}

function statusLabel(
  status:
    ScheduledMessage[
      "status"
    ]
) {
  switch (
    status
  ) {
    case "PENDING":
      return "Agendada";
    case "PROCESSING":
      return "Enviando";
    case "SENT":
      return "Enviada";
    case "CANCELLED":
      return "Cancelada";
    case "FAILED":
      return "Falhou";
  }
}

function dateTimeLabel(
  value: string
) {
  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      dateStyle:
        "short",
      timeStyle:
        "short"
    }
  ).format(
    new Date(
      value
    )
  );
}

export function ScheduledMessageDrawer({
  ticketId,
  contactName,
  draftText,
  onClose,
  onScheduled
}: {
  ticketId: string;
  contactName: string;
  draftText: string;
  onClose: () => void;
  onScheduled: () => void;
}) {
  const {
    request
  } =
    useAuth();

  const [
    body,
    setBody
  ] =
    useState(
      draftText
    );

  const [
    scheduledFor,
    setScheduledFor
  ] =
    useState(
      localDateTimeInput(
        new Date(
          Date.now() +
          15 *
          60 *
          1_000
        )
      )
    );

  const [
    items,
    setItems
  ] =
    useState<
      ScheduledMessage[]
    >([]);

  const [
    loading,
    setLoading
  ] =
    useState(
      true
    );

  const [
    saving,
    setSaving
  ] =
    useState(
      false
    );

  const [
    cancellingId,
    setCancellingId
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

  const [
    notice,
    setNotice
  ] =
    useState("");

  const load =
    useCallback(
      async () => {
        const payload =
          await request<{
            scheduledMessages:
              ScheduledMessage[];
          }>(
            `/api/v1/tickets/${ticketId}/scheduled-messages`
          );

        setItems(
          payload
            .scheduledMessages
        );

        setLoading(
          false
        );
      },
      [
        request,
        ticketId
      ]
    );

  useEffect(
    () => {
      void load()
        .catch(
          caught => {
            setError(
              caught instanceof
                ApiError
                ? caught.message
                : "Não foi possível carregar os agendamentos."
            );

            setLoading(
              false
            );
          }
        );
    },
    [
      load
    ]
  );

  async function submit(
    event:
      FormEvent<
        HTMLFormElement
      >
  ) {
    event.preventDefault();

    if (
      !body.trim() ||
      !scheduledFor
    ) {
      return;
    }

    setSaving(
      true
    );

    setError("");
    setNotice("");

    try {
      const payload =
        await request<{
          scheduledMessage:
            ScheduledMessage;
          queued:
            boolean;
        }>(
          `/api/v1/tickets/${ticketId}/scheduled-messages`,
          {
            method:
              "POST",
            body:
              JSON.stringify({
                body:
                  body.trim(),
                scheduledFor:
                  new Date(
                    scheduledFor
                  ).toISOString()
              })
          }
        );

      setNotice(
        payload.queued
          ? "Mensagem agendada."
          : "Agendamento salvo. O worker irá reconciliar o envio quando a fila estiver disponível."
      );

      await load();

      onScheduled();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível agendar a mensagem."
      );
    } finally {
      setSaving(
        false
      );
    }
  }

  async function cancel(
    id: string
  ) {
    setCancellingId(
      id
    );

    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/scheduled-messages/${id}`,
        {
          method:
            "DELETE"
        }
      );

      setNotice(
        "Agendamento cancelado."
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível cancelar o agendamento."
      );
    } finally {
      setCancellingId(
        null
      );
    }
  }

  return (
    <section className="scheduled-message-drawer">
      <header className="scheduled-message-drawer__header">
        <div>
          <span className="eyebrow">
            Envio programado
          </span>

          <strong>
            Agendar mensagem
          </strong>

          <small>
            {contactName}
          </small>
        </div>

        <button
          aria-label="Fechar agendamento"
          onClick={
            onClose
          }
          type="button"
        >
          ×
        </button>
      </header>

      <form
        className="scheduled-message-form"
        onSubmit={
          submit
        }
      >
        <label>
          <span>
            Mensagem
          </span>

          <textarea
            maxLength={
              4096
            }
            onChange={
              event =>
                setBody(
                  event
                    .target
                    .value
                )
            }
            placeholder="Escreva ou aplique uma resposta rápida antes de abrir o agendamento."
            required
            rows={
              3
            }
            value={
              body
            }
          />
        </label>

        <label>
          <span>
            Data e horário
          </span>

          <input
            min={
              localDateTimeInput(
                new Date(
                  Date.now() +
                  30_000
                )
              )
            }
            onChange={
              event =>
                setScheduledFor(
                  event
                    .target
                    .value
                )
            }
            required
            type="datetime-local"
            value={
              scheduledFor
            }
          />
        </label>

        <div className="scheduled-message-form__footer">
          <small>
            Respostas rápidas funcionam como templates: aplique uma no composer e depois abra o agendamento.
          </small>

          <button
            className="primary-button"
            disabled={
              saving ||
              !body.trim()
            }
            type="submit"
          >
            <span>
              {saving
                ? "Agendando…"
                : "Agendar"}
            </span>
          </button>
        </div>
      </form>

      {error && (
        <div className="scheduled-message-feedback scheduled-message-feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="scheduled-message-feedback">
          {notice}
        </div>
      )}

      <div className="scheduled-message-list">
        <div className="scheduled-message-list__heading">
          <strong>
            Histórico de agendamentos
          </strong>

          <span>
            {items.length}
          </span>
        </div>

        {loading ? (
          <div className="scheduled-message-empty">
            Carregando…
          </div>
        ) : items.length ===
          0 ? (
          <div className="scheduled-message-empty">
            Nenhuma mensagem agendada neste atendimento.
          </div>
        ) : (
          items
            .slice(
              0,
              10
            )
            .map(
              item => (
                <article
                  className={
                    `scheduled-message-item scheduled-message-item--${item.status.toLowerCase()}`
                  }
                  key={
                    item.id
                  }
                >
                  <div className="scheduled-message-item__top">
                    <span>
                      {statusLabel(
                        item.status
                      )}
                    </span>

                    <time>
                      {dateTimeLabel(
                        item.scheduledFor
                      )}
                    </time>
                  </div>

                  <p>
                    {item.body}
                  </p>

                  <div className="scheduled-message-item__meta">
                    <span>
                      {item
                        .createdByMembership
                        .user.name}
                    </span>

                    {item.status ===
                      "PENDING" && (
                      <button
                        disabled={
                          cancellingId ===
                          item.id
                        }
                        onClick={() =>
                          void cancel(
                            item.id
                          )
                        }
                        type="button"
                      >
                        {cancellingId ===
                        item.id
                          ? "Cancelando…"
                          : "Cancelar"}
                      </button>
                    )}
                  </div>

                  {item.status ===
                    "FAILED" &&
                    item.error && (
                      <small className="scheduled-message-item__error">
                        {item.error}
                      </small>
                    )}
                </article>
              )
            )
        )}
      </div>
    </section>
  );
}
EOF

# ---------------------------------------------------------------------------
# Mount scheduler in canonical composer without changing scroll ownership.
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

const importLine =
  'import { ScheduledMessageDrawer } from "@/components/conversations/scheduled-message-drawer";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { TicketHistoryDrawer } from "@/components/conversations/ticket-history-drawer";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "TicketHistoryDrawer import anchor not found."
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
    "const [scheduledMessagesOpen, setScheduledMessagesOpen]"
  )
) {
  const anchor =
    `  const [reactionPickerMessageId, setReactionPickerMessageId] =`;

  const index =
    content.indexOf(
      anchor
    );

  if (
    index < 0
  ) {
    throw new Error(
      "reaction picker state anchor not found."
    );
  }

  const lineEnd =
    content.indexOf(
      ";",
      index
    );

  if (
    lineEnd < 0
  ) {
    throw new Error(
      "reaction picker state end not found."
    );
  }

  const addition = `
  const [scheduledMessagesOpen, setScheduledMessagesOpen] =
    useState(false);`;

  content =
    content.slice(
      0,
      lineEnd + 1
    ) +
    addition +
    content.slice(
      lineEnd + 1
    );
}

if (
  !content.includes(
    "<ScheduledMessageDrawer"
  )
) {
  const anchor =
    `                <form
                  className="conversation-composer conversation-composer--attachments conversation-composer--voice conversation-composer--quick-replies"`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "canonical conversation composer anchor not found."
    );
  }

  const panel = `                {scheduledMessagesOpen && (
                  <ScheduledMessageDrawer
                    contactName={
                      selectedTicket.contact.name
                    }
                    draftText={
                      text
                    }
                    onClose={() =>
                      setScheduledMessagesOpen(
                        false
                      )
                    }
                    onScheduled={() => {
                      setText("");
                      setReplyingTo(null);
                      setScheduledMessagesOpen(
                        false
                      );
                      setOperationNotice(
                        "Mensagem agendada com sucesso."
                      );
                    }}
                    ticketId={
                      selectedTicket.id
                    }
                  />
                )}

`;

  content =
    content.replace(
      anchor,
      `${panel}${anchor}`
    );
}

if (
  !content.includes(
    'className="composer__schedule"'
  )
) {
  const anchor =
    `                  <button
                    aria-label="Respostas rápidas"`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "quick reply composer button anchor not found."
    );
  }

  const button = `                  <button
                    aria-label="Agendar mensagem"
                    className={
                      scheduledMessagesOpen
                        ? "composer__schedule composer__schedule--active"
                        : "composer__schedule"
                    }
                    disabled={
                      sending ||
                      recording ||
                      !!attachment ||
                      !!replyingTo
                    }
                    onClick={() =>
                      setScheduledMessagesOpen(
                        current =>
                          !current
                      )
                    }
                    title={
                      replyingTo
                        ? "Respostas citadas não podem ser agendadas no P2.5"
                        : "Agendar mensagem"
                    }
                    type="button"
                  >
                    ◷
                  </button>

`;

  content =
    content.replace(
      anchor,
      `${button}${anchor}`
    );
}

// Close scheduler when changing/closing the current ticket.
const noSelectedAnchor = `    if (!selectedId) {
      setMessages([]);`;

if (
  content.includes(
    noSelectedAnchor
  ) &&
  !content.includes(
    `    if (!selectedId) {
      setScheduledMessagesOpen(false);
      setMessages([]);`
  )
) {
  content =
    content.replace(
      noSelectedAnchor,
      `    if (!selectedId) {
      setScheduledMessagesOpen(false);
      setMessages([]);`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.5] Scheduled message composer mounted."
);
NODE

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

if ! grep -Fq -- "WAPP P2.5 / SCHEDULED MESSAGES" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P2.5 / SCHEDULED MESSAGES ---------------------------------- */

.composer__schedule {
  display: grid;
  width: 32px;
  height: 32px;
  flex: 0 0 32px;
  place-items: center;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--muted);
  font-size: 16px;
  cursor: pointer;
}

.composer__schedule:hover,
.composer__schedule--active {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.composer__schedule:disabled {
  cursor: not-allowed;
  opacity: 0.35;
}

.scheduled-message-drawer {
  max-height: min(440px, 48vh);
  overflow-y: auto;
  border-top: 1px solid var(--line);
  background: rgba(255, 255, 255, 0.98);
  padding: 14px 16px;
}

.scheduled-message-drawer__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.scheduled-message-drawer__header > div {
  display: grid;
  gap: 2px;
}

.scheduled-message-drawer__header strong {
  font-size: 13px;
}

.scheduled-message-drawer__header small {
  color: var(--muted);
  font-size: 9px;
}

.scheduled-message-drawer__header > button {
  width: 28px;
  height: 28px;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--muted);
  font-size: 16px;
  cursor: pointer;
}

.scheduled-message-drawer__header > button:hover {
  background: var(--surface-subtle);
  color: var(--ink);
}

.scheduled-message-form {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 190px;
  gap: 10px;
  margin-top: 12px;
}

.scheduled-message-form label {
  display: grid;
  gap: 4px;
}

.scheduled-message-form label > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 740;
}

.scheduled-message-form textarea,
.scheduled-message-form input {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 9px;
  outline: 0;
  background: white;
  padding: 8px 9px;
  color: var(--ink);
  font: inherit;
  font-size: 10px;
}

.scheduled-message-form textarea {
  min-height: 72px;
  resize: vertical;
}

.scheduled-message-form input {
  height: 36px;
}

.scheduled-message-form textarea:focus,
.scheduled-message-form input:focus {
  border-color: rgba(31, 122, 80, 0.36);
  box-shadow: 0 0 0 3px rgba(31, 122, 80, 0.05);
}

.scheduled-message-form__footer {
  grid-column: 1 / -1;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
}

.scheduled-message-form__footer small {
  max-width: 600px;
  color: var(--muted);
  font-size: 8px;
  line-height: 1.45;
}

.scheduled-message-feedback {
  margin-top: 9px;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 8px 9px;
  font-size: 9px;
}

.scheduled-message-feedback--error {
  background: rgba(163, 59, 50, 0.08);
  color: #973a32;
}

.scheduled-message-list {
  margin-top: 13px;
  border-top: 1px solid var(--line);
  padding-top: 11px;
}

.scheduled-message-list__heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 5px;
}

.scheduled-message-list__heading strong {
  font-size: 10px;
}

.scheduled-message-list__heading > span {
  display: grid;
  min-width: 22px;
  height: 20px;
  place-items: center;
  border-radius: 999px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 0 6px;
  font-size: 8px;
  font-weight: 800;
}

.scheduled-message-item {
  display: grid;
  gap: 5px;
  border-bottom: 1px solid #edf0ed;
  padding: 9px 1px;
}

.scheduled-message-item:last-child {
  border-bottom: 0;
}

.scheduled-message-item__top,
.scheduled-message-item__meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.scheduled-message-item__top > span {
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 4px 7px;
  font-size: 7px;
  font-weight: 800;
}

.scheduled-message-item--failed
  .scheduled-message-item__top
  > span {
  background: rgba(163, 59, 50, 0.08);
  color: #973a32;
}

.scheduled-message-item--cancelled {
  opacity: 0.55;
}

.scheduled-message-item__top time,
.scheduled-message-item__meta > span {
  color: var(--muted);
  font-size: 8px;
}

.scheduled-message-item p {
  overflow: hidden;
  margin: 0;
  color: #425047;
  font-size: 9px;
  line-height: 1.45;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scheduled-message-item__meta button {
  border: 0;
  background: transparent;
  color: #973a32;
  padding: 0;
  font-size: 8px;
  font-weight: 740;
  cursor: pointer;
}

.scheduled-message-item__error {
  color: #973a32;
  font-size: 8px;
  line-height: 1.4;
}

.scheduled-message-empty {
  color: var(--muted);
  padding: 12px 0 4px;
  font-size: 9px;
}

@media (max-width: 720px) {
  .scheduled-message-form {
    grid-template-columns: 1fr;
  }

  .scheduled-message-form__footer {
    grid-column: auto;
    align-items: stretch;
    flex-direction: column;
  }
}

/* --- /WAPP P2.5 ------------------------------------------------------ */
EOF
fi

# ---------------------------------------------------------------------------
# Register test file
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
  "src/modules/scheduled-messages/scheduled-message.policy.test.ts";

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
# Documentation
# ---------------------------------------------------------------------------

cat > docs/P2_05_TEMPLATES_AND_SCHEDULING.md <<'EOF'
# P2.5 Templates and scheduled messages

P2.5 deliberately reuses Wapp Quick Replies as the reusable template catalog.
Creating a second template table would duplicate ownership, variables,
activation and permissions that already exist in Quick Replies.

Operational flow:

1. type a message or insert a Quick Reply in the composer;
2. open the clock control;
3. choose the final text and local date/time;
4. Wapp persists the schedule in MySQL before queueing delivery.

## Database source of truth

`ScheduledMessage` statuses:

- `PENDING`
- `PROCESSING`
- `SENT`
- `CANCELLED`
- `FAILED`

The database is authoritative. Redis/BullMQ is the execution transport.

## Delivery durability

At creation Wapp adds a delayed BullMQ job.

A `wapp-scheduled-message-sweep` scheduler also runs every minute. It finds
database records that are already due but still `PENDING` and re-enqueues them.
This recovers schedules when Redis or a worker was unavailable at creation or
at the original delivery time.

## Duplicate-send safety

Delivery claims a schedule atomically:

`PENDING -> PROCESSING`

Only one worker can claim it.

Automatic BullMQ retries are disabled because retrying an outbound WhatsApp
side effect after an uncertain failure can duplicate a message.

A schedule stuck in `PROCESSING` for more than 15 minutes becomes `FAILED`
with an explicit "delivery may be uncertain" warning. It is never resent
automatically.

## Authorization

An AGENT can schedule messages only for a ticket they are allowed to operate.

If a ticket is assigned to another agent, only OWNER / ADMIN / SUPERVISOR can
create the schedule.

An AGENT can cancel only their own pending schedule. OWNER / ADMIN /
SUPERVISOR can cancel any pending schedule in their company.

If the author membership or user becomes inactive before delivery, the
scheduled message fails instead of sending under a disabled identity.

## Ticket lifecycle

A message is not sent if its ticket was closed before the scheduled time.

A disconnected WhatsApp connection produces `FAILED` instead of an automatic
retry.

Successful scheduled sends are normal outbound `Message` records and update
ticket last-message / outbound SLA fields.

## History

Operational ticket history records:

- `MESSAGE_SCHEDULED`
- `SCHEDULED_MESSAGE_CANCELLED`
- `SCHEDULED_MESSAGE_SENT`
- `SCHEDULED_MESSAGE_FAILED`

## Scope

P2.5 schedules text only.

Quoted replies, media, voice notes and reactions remain immediate-only.
EOF

echo "[P2.5] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P2.5] Unit tests..."
pnpm test

echo "[P2.5] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.5] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.5] CODE VALIDATION PASS."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
