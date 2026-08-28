#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P3.3] Installing tasks and follow-ups..."

for check in \
  "apps/api/prisma/schema.prisma|model Notification {" \
  "apps/api/prisma/schema.prisma|model ContactFieldDefinition {" \
  "apps/api/prisma/schema.prisma|model CrmPipeline {" \
  "apps/api/src/modules/notifications/notification.service.ts|createOrRefreshNotification" \
  "apps/api/src/jobs/job-runtime.ts|createScheduledMessageWorker()" \
  "apps/api/src/worker.ts|createScheduledMessageWorker()" \
  "apps/web/components/contacts/contact-pipeline-summary.tsx|export function ContactPipelineSummary" \
  "apps/api/src/security/permissions.ts|pipelines.manage" \
  "apps/api/src/modules/realtime/realtime.bus.ts|contact.pipeline.updated"
do
  file="${check%%|*}"
  marker="${check#*|}"
  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: P3.3 prerequisite missing: $file -> $marker"
    echo "P3.3 made no changes."
    exit 1
  fi
done

for required in \
  "apps/api/src/app.ts" \
  "apps/api/src/security/permissions.test.ts" \
  "apps/web/components/notifications/notification-center.tsx" \
  "apps/web/lib/realtime-types.ts" \
  "apps/web/lib/permissions.ts" \
  "apps/web/app/dashboard/page.tsx" \
  "apps/web/app/dashboard/contacts/page.tsx" \
  "apps/web/app/globals.css"
do
  [[ -f "$required" ]] || { echo "ERROR: missing $required"; exit 1; }
done

mkdir -p apps/api/src/modules/tasks apps/api/src/jobs \
  apps/api/prisma/migrations/20260829001000_crm_tasks \
  apps/web/app/dashboard/tasks apps/web/components/contacts docs

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/prisma/schema.prisma";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("enum CrmTaskStatus {")) {
  const anchor = "enum MembershipRole {";
  const index = content.indexOf(anchor);
  if (index < 0) throw new Error("MembershipRole enum anchor not found.");
  content = content.slice(0, index) + `enum CrmTaskStatus {
  OPEN
  DONE
  CANCELLED
}

enum CrmTaskPriority {
  LOW
  NORMAL
  HIGH
  URGENT
}

enum CrmTaskEventType {
  CREATED
  UPDATED
  REASSIGNED
  COMPLETED
  CANCELLED
  REMINDER_SENT
  REMINDER_FAILED
}

` + content.slice(index);
}

function bounds(name) {
  const start = content.indexOf(`model ${name} {`);
  if (start < 0) throw new Error(`${name} model not found.`);
  const end = content.indexOf("\n}", start);
  if (end < 0) throw new Error(`${name} model end not found.`);
  return { start, end };
}

function relation(model, field, line) {
  const b = bounds(model);
  const block = content.slice(b.start, b.end);
  if (block.includes(`\n  ${field} `)) return;
  content = content.slice(0, b.end) + `\n${line}` + content.slice(b.end);
}

relation("Company", "crmTasks", "  crmTasks                 CrmTask[]");
relation("Company", "crmTaskEvents", "  crmTaskEvents            CrmTaskEvent[]");
relation("Contact", "crmTasks", "  crmTasks                 CrmTask[]");
relation("Ticket", "crmTasks", "  crmTasks                 CrmTask[]");
relation("CompanyMembership", "assignedCrmTasks", '  assignedCrmTasks         CrmTask[] @relation("CrmTaskAssignee")');
relation("CompanyMembership", "createdCrmTasks", '  createdCrmTasks          CrmTask[] @relation("CrmTaskCreator")');
relation("CompanyMembership", "crmTaskEvents", '  crmTaskEvents            CrmTaskEvent[] @relation("CrmTaskEventActor")');
relation("Contact", "notifications", "  notifications            Notification[]");

{
  let b = bounds("Notification");
  let block = content.slice(b.start, b.end);
  if (!block.includes("\n  contactId ")) {
    const anchor = "  ticketId        String?           @db.Char(36)";
    const at = content.indexOf(anchor, b.start);
    if (at < 0 || at > b.end) throw new Error("Notification ticketId anchor not found.");
    const eol = content.indexOf("\n", at);
    content = content.slice(0, eol + 1) + "  contactId       String?           @db.Char(36)\n" + content.slice(eol + 1);
  }
}
{
  let b = bounds("Notification");
  let block = content.slice(b.start, b.end);
  if (!block.includes("\n  contact          Contact?")) {
    const anchor = "  ticket          Ticket?           @relation(fields: [ticketId], references: [id], onDelete: Cascade)";
    const at = content.indexOf(anchor, b.start);
    if (at < 0 || at > b.end) throw new Error("Notification ticket relation anchor not found.");
    const eol = content.indexOf("\n", at);
    content = content.slice(0, eol + 1) +
      "  contact         Contact?          @relation(fields: [contactId], references: [id], onDelete: Cascade)\n" +
      content.slice(eol + 1);
  }
}
{
  let b = bounds("Notification");
  let block = content.slice(b.start, b.end);
  if (!block.includes("@@index([contactId, updatedAt])")) {
    content = content.slice(0, b.end) + "\n  @@index([contactId, updatedAt])" + content.slice(b.end);
  }
}

if (!content.includes("model CrmTask {")) {
  content += `

model CrmTask {
  id                    String            @id @default(uuid()) @db.Char(36)
  companyId             String            @db.Char(36)
  contactId             String            @db.Char(36)
  ticketId              String?           @db.Char(36)
  assigneeMembershipId  String            @db.Char(36)
  createdByMembershipId String            @db.Char(36)
  title                 String            @db.VarChar(190)
  description           String?           @db.Text
  status                CrmTaskStatus     @default(OPEN)
  priority              CrmTaskPriority   @default(NORMAL)
  dueAt                 DateTime
  reminderAt            DateTime?
  reminderClaimedAt     DateTime?
  reminderSentAt        DateTime?
  reminderFailedAt      DateTime?
  reminderError         String?           @db.VarChar(500)
  completedAt           DateTime?
  cancelledAt           DateTime?
  company               Company           @relation(fields: [companyId], references: [id], onDelete: Cascade)
  contact               Contact           @relation(fields: [contactId], references: [id], onDelete: Cascade)
  ticket                Ticket?           @relation(fields: [ticketId], references: [id], onDelete: SetNull)
  assigneeMembership    CompanyMembership @relation("CrmTaskAssignee", fields: [assigneeMembershipId], references: [id], onDelete: Restrict)
  createdByMembership   CompanyMembership @relation("CrmTaskCreator", fields: [createdByMembershipId], references: [id], onDelete: Restrict)
  events                CrmTaskEvent[]
  createdAt             DateTime          @default(now())
  updatedAt             DateTime          @updatedAt

  @@index([companyId, status, dueAt])
  @@index([assigneeMembershipId, status, dueAt])
  @@index([contactId, status, dueAt])
  @@index([ticketId, status, dueAt])
  @@index([status, reminderAt, reminderSentAt, reminderFailedAt])
}

model CrmTaskEvent {
  id                String             @id @default(uuid()) @db.Char(36)
  companyId         String             @db.Char(36)
  taskId            String             @db.Char(36)
  actorMembershipId String?            @db.Char(36)
  type              CrmTaskEventType
  metadata          Json?
  company           Company            @relation(fields: [companyId], references: [id], onDelete: Cascade)
  task              CrmTask            @relation(fields: [taskId], references: [id], onDelete: Cascade)
  actorMembership   CompanyMembership? @relation("CrmTaskEventActor", fields: [actorMembershipId], references: [id], onDelete: SetNull)
  createdAt         DateTime           @default(now())

  @@index([companyId, createdAt])
  @@index([taskId, createdAt])
}
`;
}

fs.writeFileSync(path, content);
console.log("[P3.3] Prisma task models prepared.");
NODE

cat > apps/api/prisma/migrations/20260829001000_crm_tasks/migration.sql <<'EOF'
ALTER TABLE `Notification` ADD COLUMN `contactId` CHAR(36) NULL;
CREATE INDEX `Notification_contactId_updatedAt_idx` ON `Notification`(`contactId`, `updatedAt`);
ALTER TABLE `Notification`
  ADD CONSTRAINT `Notification_contactId_fkey`
  FOREIGN KEY (`contactId`) REFERENCES `Contact`(`id`)
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE `CrmTask` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `ticketId` CHAR(36) NULL,
  `assigneeMembershipId` CHAR(36) NOT NULL,
  `createdByMembershipId` CHAR(36) NOT NULL,
  `title` VARCHAR(190) NOT NULL,
  `description` TEXT NULL,
  `status` ENUM('OPEN','DONE','CANCELLED') NOT NULL DEFAULT 'OPEN',
  `priority` ENUM('LOW','NORMAL','HIGH','URGENT') NOT NULL DEFAULT 'NORMAL',
  `dueAt` DATETIME(3) NOT NULL,
  `reminderAt` DATETIME(3) NULL,
  `reminderClaimedAt` DATETIME(3) NULL,
  `reminderSentAt` DATETIME(3) NULL,
  `reminderFailedAt` DATETIME(3) NULL,
  `reminderError` VARCHAR(500) NULL,
  `completedAt` DATETIME(3) NULL,
  `cancelledAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `CrmTask_companyId_status_dueAt_idx` (`companyId`,`status`,`dueAt`),
  INDEX `CrmTask_assigneeMembershipId_status_dueAt_idx` (`assigneeMembershipId`,`status`,`dueAt`),
  INDEX `CrmTask_contactId_status_dueAt_idx` (`contactId`,`status`,`dueAt`),
  INDEX `CrmTask_ticketId_status_dueAt_idx` (`ticketId`,`status`,`dueAt`),
  INDEX `CrmTask_status_reminderAt_reminderSentAt_reminderFailedAt_idx`
    (`status`,`reminderAt`,`reminderSentAt`,`reminderFailedAt`),
  CONSTRAINT `CrmTask_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CrmTask_contactId_fkey` FOREIGN KEY (`contactId`) REFERENCES `Contact`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CrmTask_ticketId_fkey` FOREIGN KEY (`ticketId`) REFERENCES `Ticket`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `CrmTask_assigneeMembershipId_fkey` FOREIGN KEY (`assigneeMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `CrmTask_createdByMembershipId_fkey` FOREIGN KEY (`createdByMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `CrmTaskEvent` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `taskId` CHAR(36) NOT NULL,
  `actorMembershipId` CHAR(36) NULL,
  `type` ENUM('CREATED','UPDATED','REASSIGNED','COMPLETED','CANCELLED','REMINDER_SENT','REMINDER_FAILED') NOT NULL,
  `metadata` JSON NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  INDEX `CrmTaskEvent_companyId_createdAt_idx` (`companyId`,`createdAt`),
  INDEX `CrmTaskEvent_taskId_createdAt_idx` (`taskId`,`createdAt`),
  CONSTRAINT `CrmTaskEvent_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CrmTaskEvent_taskId_fkey` FOREIGN KEY (`taskId`) REFERENCES `CrmTask`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `CrmTaskEvent_actorMembershipId_fkey` FOREIGN KEY (`actorMembershipId`) REFERENCES `CompanyMembership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

cat > apps/api/src/modules/tasks/task.policy.ts <<'EOF'
import type { WappRole } from "../../lib/tokens.js";

export const TASK_MIN_LEAD_MS = 30_000;
export const TASK_REMINDER_STALE_MS = 15 * 60 * 1_000;

export function isTaskManager(role: WappRole) {
  return role === "OWNER" || role === "ADMIN" || role === "SUPERVISOR";
}

export function canAssignTaskTo(input: {
  role: WappRole;
  actorMembershipId: string;
  assigneeMembershipId: string;
}) {
  return isTaskManager(input.role) ||
    input.actorMembershipId === input.assigneeMembershipId;
}

export function canMutateTask(input: {
  role: WappRole;
  actorMembershipId: string;
  assigneeMembershipId: string;
  createdByMembershipId: string;
}) {
  return isTaskManager(input.role) ||
    input.actorMembershipId === input.assigneeMembershipId ||
    input.actorMembershipId === input.createdByMembershipId;
}

export function taskTimeError(input: {
  now: Date;
  dueAt: Date;
  reminderAt: Date | null;
}) {
  if (!Number.isFinite(input.dueAt.getTime())) return "INVALID_DUE";
  if (input.dueAt.getTime() - input.now.getTime() < TASK_MIN_LEAD_MS) return "DUE_TOO_SOON";
  if (!input.reminderAt) return null;
  if (!Number.isFinite(input.reminderAt.getTime())) return "INVALID_REMINDER";
  if (input.reminderAt.getTime() - input.now.getTime() < TASK_MIN_LEAD_MS) return "REMINDER_TOO_SOON";
  if (input.reminderAt > input.dueAt) return "REMINDER_AFTER_DUE";
  return null;
}
EOF

cat > apps/api/src/modules/tasks/task.policy.test.ts <<'EOF'
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  canAssignTaskTo,
  canMutateTask,
  taskTimeError
} from "./task.policy.js";

test("agents self-assign while managers may delegate", () => {
  assert.equal(canAssignTaskTo({
    role: "AGENT",
    actorMembershipId: "a",
    assigneeMembershipId: "a"
  }), true);
  assert.equal(canAssignTaskTo({
    role: "AGENT",
    actorMembershipId: "a",
    assigneeMembershipId: "b"
  }), false);
  assert.equal(canAssignTaskTo({
    role: "SUPERVISOR",
    actorMembershipId: "a",
    assigneeMembershipId: "b"
  }), true);
});

test("task creator or assignee may operate the task", () => {
  assert.equal(canMutateTask({
    role: "AGENT",
    actorMembershipId: "creator",
    assigneeMembershipId: "other",
    createdByMembershipId: "creator"
  }), true);
});

test("reminder must be future and before due date", () => {
  const now = new Date("2026-08-29T10:00:00.000Z");
  assert.equal(taskTimeError({
    now,
    dueAt: new Date("2026-08-29T12:00:00.000Z"),
    reminderAt: new Date("2026-08-29T11:00:00.000Z")
  }), null);
  assert.equal(taskTimeError({
    now,
    dueAt: new Date("2026-08-29T12:00:00.000Z"),
    reminderAt: new Date("2026-08-29T13:00:00.000Z")
  }), "REMINDER_AFTER_DUE");
});
EOF

# ---------------------------------------------------------------------------
# Notification service: contact deep-links + task notification types
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/modules/notifications/notification.service.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const typeStart = content.indexOf("export type NotificationType =");
const typeEnd = content.indexOf(";", typeStart);
if (typeStart < 0 || typeEnd < 0) throw new Error("NotificationType union not found.");
let union = content.slice(typeStart, typeEnd);
for (const type of ["TASK_ASSIGNED", "TASK_REMINDER"]) {
  if (!union.includes(`"${type}"`)) union += `\n  | "${type}"`;
}
content = content.slice(0, typeStart) + union + content.slice(typeEnd);

if (!content.includes("contactId?:\n    string;")) {
  const anchor = `  ticketId?:
    string;
  messageId?:`;
  if (!content.includes(anchor)) throw new Error("Notification input ticketId anchor not found.");
  content = content.replace(anchor, `  ticketId?:
    string;
  contactId?:
    string;
  messageId?:`);
}

if (!content.includes("incrementOccurrence?:\n    boolean;")) {
  const anchor = `  dedupeKey: string;
}) {`;
  if (!content.includes(anchor)) throw new Error("Notification dedupeKey anchor not found.");
  content = content.replace(anchor, `  dedupeKey: string;
  incrementOccurrence?:
    boolean;
}) {`);
}

const assignments = [...content.matchAll(/        ticketId:\n          input\.ticketId,/g)];
if (assignments.length < 2) throw new Error("Notification create/update ticketId assignments not found.");
for (let i = assignments.length - 1; i >= 0; i--) {
  const at = assignments[i].index;
  const marker = `        ticketId:
          input.ticketId,`;
  const after = at + marker.length;
  const nearby = content.slice(after, after + 90);
  if (!nearby.includes("contactId:")) {
    content = content.slice(0, after) + `
        contactId:
          input.contactId,` + content.slice(after);
  }
}

const occurrenceOld = `        occurrenceCount: {
          increment:
            1
        },
        readAt:
          null`;
const occurrenceNew = `        ...(input.incrementOccurrence ===
        false
          ? {}
          : {
              occurrenceCount: {
                increment:
                  1
              }
            }),
        readAt:
          null`;
if (content.includes(occurrenceOld)) {
  content = content.replace(occurrenceOld, occurrenceNew);
} else if (!content.includes("input.incrementOccurrence ===")) {
  throw new Error("Notification occurrenceCount anchor not found.");
}

const rtOld = `      ticketId:
        input.ticketId,
      messageId:`;
const rtNew = `      ticketId:
        input.ticketId,
      contactId:
        input.contactId,
      messageId:`;
if (content.includes(rtOld)) content = content.replace(rtOld, rtNew);

if (!content.includes("export async function notifyTaskReminder")) {
  const anchor = "export async function listNotifications";
  const index = content.indexOf(anchor);
  if (index < 0) throw new Error("listNotifications anchor not found.");
  const addition = `export async function notifyTaskAssignment(input: {
  companyId: string;
  membershipId: string;
  actorMembershipId: string;
  taskId: string;
  contactId: string;
  ticketId?: string | null;
  taskTitle: string;
  contactName: string;
}) {
  if (input.membershipId === input.actorMembershipId) return null;

  const recipient = await activeRecipient(
    input.companyId,
    input.membershipId
  );

  if (!recipient) return null;

  return createOrRefreshNotification({
    companyId: input.companyId,
    membershipId: input.membershipId,
    ticketId: input.ticketId ?? undefined,
    contactId: input.contactId,
    type: "TASK_ASSIGNED",
    title: "Nova tarefa atribuída",
    body: \`\${input.taskTitle} · \${input.contactName}\`,
    dedupeKey: \`task-assignment:\${input.taskId}:\${input.membershipId}\`,
    incrementOccurrence: false
  });
}

export async function notifyTaskReminder(input: {
  companyId: string;
  membershipId: string;
  taskId: string;
  contactId: string;
  ticketId?: string | null;
  taskTitle: string;
  contactName: string;
  remindAt: Date;
}) {
  const recipient = await activeRecipient(
    input.companyId,
    input.membershipId
  );

  if (!recipient) return null;

  return createOrRefreshNotification({
    companyId: input.companyId,
    membershipId: input.membershipId,
    ticketId: input.ticketId ?? undefined,
    contactId: input.contactId,
    type: "TASK_REMINDER",
    title: "Lembrete de tarefa",
    body: \`\${input.taskTitle} · \${input.contactName}\`,
    dedupeKey: \`task-reminder:\${input.taskId}:\${input.remindAt.toISOString()}\`,
    incrementOccurrence: false
  });
}

`;
  content = content.slice(0, index) + addition + content.slice(index);
}

fs.writeFileSync(path, content);
console.log("[P3.3] Notification service extended.");
NODE

# ---------------------------------------------------------------------------
# Task service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tasks/task.service.ts <<'EOF'
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import type { WappRole } from "../../lib/tokens.js";
import {
  notifyTaskAssignment,
  notifyTaskReminder
} from "../notifications/notification.service.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import {
  canAssignTaskTo,
  canMutateTask,
  isTaskManager,
  TASK_REMINDER_STALE_MS,
  taskTimeError
} from "./task.policy.js";

type TaskPriority = "LOW" | "NORMAL" | "HIGH" | "URGENT";

const taskInclude = {
  contact: {
    select: {
      id: true,
      name: true,
      phoneNumber: true,
      email: true
    }
  },
  ticket: {
    select: {
      id: true,
      status: true,
      lastMessage: true,
      lastMessageAt: true
    }
  },
  assigneeMembership: {
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
  },
  events: {
    orderBy: {
      createdAt: "desc" as const
    },
    take: 6,
    select: {
      id: true,
      type: true,
      metadata: true,
      createdAt: true,
      actorMembership: {
        select: {
          user: {
            select: {
              name: true
            }
          }
        }
      }
    }
  }
};

function timeErrorMessage(code: string) {
  const messages: Record<string, string> = {
    INVALID_DUE: "Prazo inválido.",
    DUE_TOO_SOON: "Defina o prazo com pelo menos 30 segundos de antecedência.",
    INVALID_REMINDER: "Horário do lembrete inválido.",
    REMINDER_TOO_SOON: "Defina o lembrete com pelo menos 30 segundos de antecedência.",
    REMINDER_AFTER_DUE: "O lembrete não pode acontecer depois do prazo."
  };
  return messages[code] ?? "Datas da tarefa são inválidas.";
}

async function requireContact(companyId: string, contactId: string) {
  const contact = await prisma.contact.findFirst({
    where: {
      id: contactId,
      companyId,
      isGroup: false
    },
    select: {
      id: true,
      name: true
    }
  });

  if (!contact) {
    throw new AppError(
      "Contato não encontrado ou não elegível para tarefa.",
      404,
      "TASK_CONTACT_NOT_FOUND"
    );
  }

  return contact;
}

async function requireAssignee(companyId: string, membershipId: string) {
  const membership = await prisma.companyMembership.findFirst({
    where: {
      id: membershipId,
      companyId,
      isActive: true,
      user: {
        isActive: true
      }
    },
    select: {
      id: true,
      userId: true,
      role: true,
      user: {
        select: {
          id: true,
          name: true
        }
      }
    }
  });

  if (!membership) {
    throw new AppError(
      "Responsável não encontrado ou inativo.",
      422,
      "TASK_ASSIGNEE_INVALID"
    );
  }

  return membership;
}

async function validateTicket(
  companyId: string,
  contactId: string,
  ticketId: string | null | undefined
) {
  if (!ticketId) return null;

  const ticket = await prisma.ticket.findFirst({
    where: {
      id: ticketId,
      companyId,
      contactId
    },
    select: {
      id: true
    }
  });

  if (!ticket) {
    throw new AppError(
      "O atendimento escolhido não pertence a este contato.",
      422,
      "TASK_TICKET_INVALID"
    );
  }

  return ticket;
}

export async function createTask(input: {
  companyId: string;
  actorMembershipId: string;
  role: WappRole;
  contactId: string;
  ticketId?: string | null;
  assigneeMembershipId: string;
  title: string;
  description?: string | null;
  priority: TaskPriority;
  dueAt: Date;
  reminderAt: Date | null;
}) {
  const [contact, assignee] = await Promise.all([
    requireContact(input.companyId, input.contactId),
    requireAssignee(input.companyId, input.assigneeMembershipId),
    validateTicket(input.companyId, input.contactId, input.ticketId)
  ]);

  if (!canAssignTaskTo({
    role: input.role,
    actorMembershipId: input.actorMembershipId,
    assigneeMembershipId: assignee.id
  })) {
    throw new AppError(
      "Atendentes só podem criar tarefas para si mesmos.",
      403,
      "TASK_ASSIGNMENT_FORBIDDEN"
    );
  }

  const timeError = taskTimeError({
    now: new Date(),
    dueAt: input.dueAt,
    reminderAt: input.reminderAt
  });

  if (timeError) {
    throw new AppError(
      timeErrorMessage(timeError),
      422,
      "TASK_TIME_INVALID"
    );
  }

  const task = await prisma.$transaction(async tx => {
    const created = await tx.crmTask.create({
      data: {
        companyId: input.companyId,
        contactId: input.contactId,
        ticketId: input.ticketId ?? null,
        assigneeMembershipId: assignee.id,
        createdByMembershipId: input.actorMembershipId,
        title: input.title.trim(),
        description: input.description?.trim() || null,
        priority: input.priority,
        dueAt: input.dueAt,
        reminderAt: input.reminderAt
      }
    });

    await tx.crmTaskEvent.create({
      data: {
        companyId: input.companyId,
        taskId: created.id,
        actorMembershipId: input.actorMembershipId,
        type: "CREATED",
        metadata: toPrismaJson({
          assigneeMembershipId: assignee.id,
          dueAt: input.dueAt.toISOString(),
          reminderAt: input.reminderAt?.toISOString() ?? null,
          priority: input.priority
        })
      }
    });

    return created;
  });

  await notifyTaskAssignment({
    companyId: input.companyId,
    membershipId: assignee.id,
    actorMembershipId: input.actorMembershipId,
    taskId: task.id,
    contactId: input.contactId,
    ticketId: input.ticketId,
    taskTitle: task.title,
    contactName: contact.name
  });

  publishRealtime(input.companyId, {
    type: "task.updated",
    taskId: task.id,
    contactId: input.contactId,
    membershipId: assignee.id
  });

  return prisma.crmTask.findUniqueOrThrow({
    where: {
      id: task.id
    },
    include: taskInclude
  });
}

export async function listTasks(input: {
  companyId: string;
  actorMembershipId: string;
  role: WappRole;
  scope: "ME" | "ALL";
  status: "OPEN" | "DONE" | "CANCELLED";
  contactId?: string;
  overdueOnly: boolean;
  limit: number;
}) {
  if (input.scope === "ALL" && !isTaskManager(input.role)) {
    throw new AppError(
      "Somente gestores podem consultar tarefas de toda a equipe.",
      403,
      "TASK_SCOPE_FORBIDDEN"
    );
  }

  return prisma.crmTask.findMany({
    where: {
      companyId: input.companyId,
      status: input.status,
      ...(input.scope === "ME"
        ? {
            assigneeMembershipId: input.actorMembershipId
          }
        : {}),
      ...(input.contactId
        ? {
            contactId: input.contactId
          }
        : {}),
      ...(input.overdueOnly && input.status === "OPEN"
        ? {
            dueAt: {
              lt: new Date()
            }
          }
        : {})
    },
    include: taskInclude,
    orderBy: input.status === "OPEN"
      ? [
          {
            dueAt: "asc"
          },
          {
            createdAt: "desc"
          }
        ]
      : [
          {
            updatedAt: "desc"
          }
        ],
    take: Math.min(Math.max(input.limit, 1), 200)
  });
}

export async function getContactTaskContext(input: {
  companyId: string;
  actorMembershipId: string;
  role: WappRole;
  contactId: string;
}) {
  await requireContact(input.companyId, input.contactId);

  const [tasks, assignees, tickets] = await Promise.all([
    prisma.crmTask.findMany({
      where: {
        companyId: input.companyId,
        contactId: input.contactId
      },
      include: taskInclude,
      orderBy: [
        {
          dueAt: "asc"
        },
        {
          updatedAt: "desc"
        }
      ],
      take: 100
    }),
    prisma.companyMembership.findMany({
      where: {
        companyId: input.companyId,
        isActive: true,
        user: {
          isActive: true
        },
        ...(isTaskManager(input.role)
          ? {}
          : {
              id: input.actorMembershipId
            })
      },
      select: {
        id: true,
        role: true,
        user: {
          select: {
            id: true,
            name: true
          }
        }
      },
      orderBy: {
        user: {
          name: "asc"
        }
      }
    }),
    prisma.ticket.findMany({
      where: {
        companyId: input.companyId,
        contactId: input.contactId
      },
      select: {
        id: true,
        status: true,
        lastMessage: true,
        lastMessageAt: true
      },
      orderBy: {
        lastMessageAt: "desc"
      },
      take: 20
    })
  ]);

  return {
    tasks,
    assignees,
    tickets,
    actorMembershipId:
      input.actorMembershipId
  };
}

async function requireTaskForMutation(input: {
  companyId: string;
  taskId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const task = await prisma.crmTask.findFirst({
    where: {
      id: input.taskId,
      companyId: input.companyId
    },
    include: {
      contact: {
        select: {
          id: true,
          name: true
        }
      }
    }
  });

  if (!task) {
    throw new AppError(
      "Tarefa não encontrada.",
      404,
      "TASK_NOT_FOUND"
    );
  }

  if (!canMutateTask({
    role: input.role,
    actorMembershipId: input.actorMembershipId,
    assigneeMembershipId: task.assigneeMembershipId,
    createdByMembershipId: task.createdByMembershipId
  })) {
    throw new AppError(
      "Você não pode alterar esta tarefa.",
      403,
      "TASK_FORBIDDEN"
    );
  }

  return task;
}

export async function updateTask(input: {
  companyId: string;
  taskId: string;
  actorMembershipId: string;
  role: WappRole;
  title?: string;
  description?: string | null;
  priority?: TaskPriority;
  dueAt?: Date;
  reminderAt?: Date | null;
  ticketId?: string | null;
  assigneeMembershipId?: string;
}) {
  const task = await requireTaskForMutation(input);

  if (task.status !== "OPEN") {
    throw new AppError(
      "Somente tarefas abertas podem ser alteradas.",
      409,
      "TASK_NOT_OPEN"
    );
  }

  const nextAssigneeId =
    input.assigneeMembershipId ?? task.assigneeMembershipId;

  if (
    input.assigneeMembershipId &&
    input.assigneeMembershipId !== task.assigneeMembershipId &&
    !isTaskManager(input.role)
  ) {
    throw new AppError(
      "Somente gestores podem transferir tarefas.",
      403,
      "TASK_REASSIGN_FORBIDDEN"
    );
  }

  const assignee = await requireAssignee(
    input.companyId,
    nextAssigneeId
  );

  if (input.ticketId !== undefined) {
    await validateTicket(
      input.companyId,
      task.contactId,
      input.ticketId
    );
  }

  const nextDueAt = input.dueAt ?? task.dueAt;
  const nextReminderAt =
    input.reminderAt !== undefined ? input.reminderAt : task.reminderAt;

  const timeError = taskTimeError({
    now: new Date(),
    dueAt: nextDueAt,
    reminderAt: nextReminderAt
  });

  if (timeError) {
    throw new AppError(
      timeErrorMessage(timeError),
      422,
      "TASK_TIME_INVALID"
    );
  }

  const reminderChanged =
    input.reminderAt !== undefined &&
    (input.reminderAt?.getTime() ?? null) !==
      (task.reminderAt?.getTime() ?? null);

  const assigneeChanged =
    assignee.id !== task.assigneeMembershipId;

  const changedFields = [
    input.title !== undefined ? "title" : null,
    input.description !== undefined ? "description" : null,
    input.priority !== undefined ? "priority" : null,
    input.dueAt !== undefined ? "dueAt" : null,
    input.reminderAt !== undefined ? "reminderAt" : null,
    input.ticketId !== undefined ? "ticketId" : null,
    assigneeChanged ? "assignee" : null
  ].filter((value): value is string => Boolean(value));

  const updated = await prisma.$transaction(async tx => {
    const next = await tx.crmTask.update({
      where: {
        id: task.id
      },
      data: {
        ...(input.title !== undefined
          ? {
              title: input.title.trim()
            }
          : {}),
        ...(input.description !== undefined
          ? {
              description: input.description?.trim() || null
            }
          : {}),
        ...(input.priority !== undefined
          ? {
              priority: input.priority
            }
          : {}),
        ...(input.dueAt !== undefined
          ? {
              dueAt: input.dueAt
            }
          : {}),
        ...(input.reminderAt !== undefined
          ? {
              reminderAt: input.reminderAt
            }
          : {}),
        ...(input.ticketId !== undefined
          ? {
              ticketId: input.ticketId
            }
          : {}),
        ...(assigneeChanged
          ? {
              assigneeMembershipId: assignee.id
            }
          : {}),
        ...(reminderChanged
          ? {
              reminderClaimedAt: null,
              reminderSentAt: null,
              reminderFailedAt: null,
              reminderError: null
            }
          : {})
      }
    });

    await tx.crmTaskEvent.create({
      data: {
        companyId: input.companyId,
        taskId: task.id,
        actorMembershipId: input.actorMembershipId,
        type: "UPDATED",
        metadata: toPrismaJson({
          changedFields
        })
      }
    });

    if (assigneeChanged) {
      await tx.crmTaskEvent.create({
        data: {
          companyId: input.companyId,
          taskId: task.id,
          actorMembershipId: input.actorMembershipId,
          type: "REASSIGNED",
          metadata: toPrismaJson({
            fromMembershipId: task.assigneeMembershipId,
            toMembershipId: assignee.id
          })
        }
      });
    }

    return next;
  });

  if (assigneeChanged) {
    await notifyTaskAssignment({
      companyId: input.companyId,
      membershipId: assignee.id,
      actorMembershipId: input.actorMembershipId,
      taskId: task.id,
      contactId: task.contactId,
      ticketId: updated.ticketId,
      taskTitle: updated.title,
      contactName: task.contact.name
    });
  }

  publishRealtime(input.companyId, {
    type: "task.updated",
    taskId: task.id,
    contactId: task.contactId,
    membershipId: assignee.id
  });

  return prisma.crmTask.findUniqueOrThrow({
    where: {
      id: task.id
    },
    include: taskInclude
  });
}

export async function completeTask(input: {
  companyId: string;
  taskId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const task = await requireTaskForMutation(input);
  if (task.status !== "OPEN") {
    throw new AppError("A tarefa já foi finalizada.", 409, "TASK_NOT_OPEN");
  }

  const now = new Date();
  await prisma.$transaction([
    prisma.crmTask.update({
      where: {
        id: task.id
      },
      data: {
        status: "DONE",
        completedAt: now,
        reminderClaimedAt: null
      }
    }),
    prisma.crmTaskEvent.create({
      data: {
        companyId: input.companyId,
        taskId: task.id,
        actorMembershipId: input.actorMembershipId,
        type: "COMPLETED"
      }
    })
  ]);

  publishRealtime(input.companyId, {
    type: "task.updated",
    taskId: task.id,
    contactId: task.contactId,
    membershipId: task.assigneeMembershipId
  });

  return prisma.crmTask.findUniqueOrThrow({
    where: {
      id: task.id
    },
    include: taskInclude
  });
}

export async function cancelTask(input: {
  companyId: string;
  taskId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const task = await requireTaskForMutation(input);
  if (task.status !== "OPEN") {
    throw new AppError("A tarefa já foi finalizada.", 409, "TASK_NOT_OPEN");
  }

  const now = new Date();
  await prisma.$transaction([
    prisma.crmTask.update({
      where: {
        id: task.id
      },
      data: {
        status: "CANCELLED",
        cancelledAt: now,
        reminderClaimedAt: null
      }
    }),
    prisma.crmTaskEvent.create({
      data: {
        companyId: input.companyId,
        taskId: task.id,
        actorMembershipId: input.actorMembershipId,
        type: "CANCELLED"
      }
    })
  ]);

  publishRealtime(input.companyId, {
    type: "task.updated",
    taskId: task.id,
    contactId: task.contactId,
    membershipId: task.assigneeMembershipId
  });

  return prisma.crmTask.findUniqueOrThrow({
    where: {
      id: task.id
    },
    include: taskInclude
  });
}

export async function deliverTaskReminder(
  taskId: string,
  expectedRemindAt: string
) {
  const task = await prisma.crmTask.findUnique({
    where: {
      id: taskId
    },
    include: {
      contact: {
        select: {
          id: true,
          name: true
        }
      },
      assigneeMembership: {
        include: {
          user: true
        }
      }
    }
  });

  if (
    !task ||
    task.status !== "OPEN" ||
    !task.reminderAt ||
    task.reminderSentAt ||
    task.reminderFailedAt
  ) {
    return {
      delivered: false,
      reason: "inactive_or_already_handled"
    };
  }

  if (task.reminderAt.toISOString() !== expectedRemindAt) {
    return {
      delivered: false,
      reason: "stale_job"
    };
  }

  const now = new Date();
  if (task.reminderAt.getTime() > now.getTime() + 2_000) {
    return {
      delivered: false,
      reason: "not_due"
    };
  }

  const claimed = await prisma.crmTask.updateMany({
    where: {
      id: task.id,
      status: "OPEN",
      reminderSentAt: null,
      reminderFailedAt: null,
      OR: [
        {
          reminderClaimedAt: null
        },
        {
          reminderClaimedAt: {
            lt: new Date(now.getTime() - TASK_REMINDER_STALE_MS)
          }
        }
      ]
    },
    data: {
      reminderClaimedAt: now
    }
  });

  if (claimed.count !== 1) {
    return {
      delivered: false,
      reason: "already_claimed"
    };
  }

  if (!task.assigneeMembership.isActive || !task.assigneeMembership.user.isActive) {
    await prisma.$transaction([
      prisma.crmTask.update({
        where: {
          id: task.id
        },
        data: {
          reminderClaimedAt: null,
          reminderFailedAt: now,
          reminderError: "O responsável pela tarefa está inativo."
        }
      }),
      prisma.crmTaskEvent.create({
        data: {
          companyId: task.companyId,
          taskId: task.id,
          actorMembershipId: null,
          type: "REMINDER_FAILED",
          metadata: toPrismaJson({
            reason: "assignee_inactive"
          })
        }
      })
    ]);

    return {
      delivered: false,
      reason: "assignee_inactive"
    };
  }

  try {
    const notification = await notifyTaskReminder({
      companyId: task.companyId,
      membershipId: task.assigneeMembershipId,
      taskId: task.id,
      contactId: task.contactId,
      ticketId: task.ticketId,
      taskTitle: task.title,
      contactName: task.contact.name,
      remindAt: task.reminderAt
    });

    if (!notification) {
      await prisma.$transaction([
        prisma.crmTask.update({
          where: {
            id: task.id
          },
          data: {
            reminderClaimedAt: null,
            reminderFailedAt: now,
            reminderError: "Não foi possível localizar um responsável ativo."
          }
        }),
        prisma.crmTaskEvent.create({
          data: {
            companyId: task.companyId,
            taskId: task.id,
            actorMembershipId: null,
            type: "REMINDER_FAILED",
            metadata: toPrismaJson({
              reason: "recipient_unavailable"
            })
          }
        })
      ]);

      return {
        delivered: false,
        reason: "recipient_unavailable"
      };
    }

    await prisma.$transaction(async tx => {
      const updated = await tx.crmTask.updateMany({
        where: {
          id: task.id,
          status: "OPEN",
          reminderSentAt: null,
          reminderFailedAt: null
        },
        data: {
          reminderClaimedAt: null,
          reminderSentAt: new Date(),
          reminderError: null
        }
      });

      if (updated.count === 1) {
        await tx.crmTaskEvent.create({
          data: {
            companyId: task.companyId,
            taskId: task.id,
            actorMembershipId: null,
            type: "REMINDER_SENT",
            metadata: toPrismaJson({
              notificationId: notification.id
            })
          }
        });
      }
    });

    publishRealtime(task.companyId, {
      type: "task.updated",
      taskId: task.id,
      contactId: task.contactId,
      membershipId: task.assigneeMembershipId
    });

    return {
      delivered: true
    };
  } catch (error) {
    await prisma.crmTask.updateMany({
      where: {
        id: task.id,
        reminderSentAt: null,
        reminderFailedAt: null
      },
      data: {
        reminderClaimedAt: null
      }
    });
    throw error;
  }
}

export async function reconcileTaskReminders() {
  return prisma.crmTask.findMany({
    where: {
      status: "OPEN",
      reminderAt: {
        lte: new Date()
      },
      reminderSentAt: null,
      reminderFailedAt: null
    },
    select: {
      id: true,
      reminderAt: true
    },
    orderBy: {
      reminderAt: "asc"
    },
    take: 100
  });
}
EOF

# ---------------------------------------------------------------------------
# Durable reminder queue + worker
# ---------------------------------------------------------------------------

cat > apps/api/src/jobs/task-reminder.queue.ts <<'EOF'
import { Queue } from "bullmq";
import { env } from "../config/env.js";
import { jobProducerRedisOptions } from "./job-redis.js";

export const TASK_REMINDER_QUEUE_NAME = "wapp-task-reminders";
export const TASK_REMINDER_DELIVER_JOB = "deliver";
export const TASK_REMINDER_SWEEP_JOB = "sweep";

let queue: Queue | null = null;

export function getTaskReminderQueue() {
  if (!queue) {
    queue = new Queue(TASK_REMINDER_QUEUE_NAME, {
      connection: jobProducerRedisOptions()
    });
  }
  return queue;
}

export async function enqueueTaskReminder(input: {
  taskId: string;
  reminderAt: Date;
}) {
  if (!env.REDIS_URL) return false;

  await getTaskReminderQueue().add(
    TASK_REMINDER_DELIVER_JOB,
    {
      taskId: input.taskId,
      expectedRemindAt: input.reminderAt.toISOString()
    },
    {
      jobId: `task-reminder-${input.taskId}-${input.reminderAt.getTime()}`,
      delay: Math.max(0, input.reminderAt.getTime() - Date.now()),
      attempts: 3,
      backoff: {
        type: "exponential",
        delay: 5_000
      },
      removeOnComplete: {
        count: 2_000
      },
      removeOnFail: {
        count: 2_000
      }
    }
  );

  return true;
}

export async function ensureTaskReminderSweep() {
  if (!env.REDIS_URL) return;

  await getTaskReminderQueue().upsertJobScheduler(
    "wapp-task-reminder-sweep",
    {
      every: 60_000
    },
    {
      name: TASK_REMINDER_SWEEP_JOB,
      data: {}
    }
  );
}

export async function closeTaskReminderQueue() {
  const current = queue;
  queue = null;
  if (current) await current.close();
}
EOF

cat > apps/api/src/jobs/task-reminder.worker.ts <<'EOF'
import { Worker } from "bullmq";
import {
  deliverTaskReminder,
  reconcileTaskReminders
} from "../modules/tasks/task.service.js";
import { jobWorkerRedisOptions } from "./job-redis.js";
import {
  enqueueTaskReminder,
  TASK_REMINDER_DELIVER_JOB,
  TASK_REMINDER_QUEUE_NAME,
  TASK_REMINDER_SWEEP_JOB
} from "./task-reminder.queue.js";

export function createTaskReminderWorker() {
  const worker = new Worker(
    TASK_REMINDER_QUEUE_NAME,
    async job => {
      if (job.name === TASK_REMINDER_DELIVER_JOB) {
        const taskId =
          typeof job.data?.taskId === "string" ? job.data.taskId : null;
        const expectedRemindAt =
          typeof job.data?.expectedRemindAt === "string"
            ? job.data.expectedRemindAt
            : null;

        if (!taskId || !expectedRemindAt) {
          throw new Error("taskId and expectedRemindAt are required.");
        }

        return deliverTaskReminder(taskId, expectedRemindAt);
      }

      if (job.name === TASK_REMINDER_SWEEP_JOB) {
        const due = await reconcileTaskReminders();

        for (const task of due) {
          if (task.reminderAt) {
            await enqueueTaskReminder({
              taskId: task.id,
              reminderAt: task.reminderAt
            });
          }
        }

        return {
          queued: due.length
        };
      }

      throw new Error(`Unknown task reminder job: ${job.name}`);
    },
    {
      connection: jobWorkerRedisOptions(),
      concurrency: 3
    }
  );

  worker.on("failed", (job, error) => {
    console.error("[task-reminders] job failed", {
      jobId: job?.id,
      error: error.message
    });
  });

  return worker;
}
EOF

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tasks/task.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { enqueueTaskReminder } from "../../jobs/task-reminder.queue.js";
import { requirePermission } from "../auth/auth.guard.js";
import {
  cancelTask,
  completeTask,
  createTask,
  getContactTaskContext,
  listTasks,
  updateTask
} from "./task.service.js";

const idSchema = z.object({
  id: z.string().uuid()
});

const prioritySchema = z.enum([
  "LOW",
  "NORMAL",
  "HIGH",
  "URGENT"
]);

const createSchema = z.object({
  contactId: z.string().uuid(),
  ticketId: z.string().uuid().nullable().optional(),
  assigneeMembershipId: z.string().uuid(),
  title: z.string().trim().min(2).max(190),
  description: z.string().trim().max(10_000).nullable().optional(),
  priority: prioritySchema.default("NORMAL"),
  dueAt: z.string().datetime({
    offset: true
  }),
  reminderAt: z.string().datetime({
    offset: true
  }).nullable().optional()
});

const updateSchema = z.object({
  title: z.string().trim().min(2).max(190).optional(),
  description: z.string().trim().max(10_000).nullable().optional(),
  priority: prioritySchema.optional(),
  dueAt: z.string().datetime({
    offset: true
  }).optional(),
  reminderAt: z.string().datetime({
    offset: true
  }).nullable().optional(),
  ticketId: z.string().uuid().nullable().optional(),
  assigneeMembershipId: z.string().uuid().optional()
}).refine(value => Object.keys(value).length > 0, {
  message: "Informe ao menos uma alteração."
});

const listQuery = z.object({
  scope: z.enum([
    "ME",
    "ALL"
  ]).default("ME"),
  status: z.enum([
    "OPEN",
    "DONE",
    "CANCELLED"
  ]).default("OPEN"),
  contactId: z.string().uuid().optional(),
  overdueOnly: z.enum([
    "true",
    "false"
  ]).default("false").transform(value => value === "true"),
  limit: z.coerce.number().int().min(1).max(200).default(100)
});

export async function taskRoutes(app: FastifyInstance) {
  app.get("/api/v1/tasks", async request => {
    const auth = await requirePermission(request, "tasks.read");
    const query = listQuery.parse(request.query);

    return {
      tasks: await listTasks({
        companyId: auth.companyId,
        actorMembershipId: auth.membershipId,
        role: auth.role,
        ...query
      })
    };
  });

  app.get("/api/v1/contacts/:id/tasks/context", async request => {
    const auth = await requirePermission(request, "tasks.read");
    const params = idSchema.parse(request.params);

    return getContactTaskContext({
      companyId: auth.companyId,
      actorMembershipId: auth.membershipId,
      role: auth.role,
      contactId: params.id
    });
  });

  app.post("/api/v1/tasks", async (request, reply) => {
    const auth = await requirePermission(request, "tasks.manage");
    const input = createSchema.parse(request.body);

    const task = await createTask({
      companyId: auth.companyId,
      actorMembershipId: auth.membershipId,
      role: auth.role,
      ...input,
      dueAt: new Date(input.dueAt),
      reminderAt: input.reminderAt ? new Date(input.reminderAt) : null
    });

    let reminderQueued = false;

    if (task.reminderAt) {
      try {
        reminderQueued = await enqueueTaskReminder({
          taskId: task.id,
          reminderAt: task.reminderAt
        });
      } catch (error) {
        request.log.error({
          error,
          taskId: task.id
        }, "task reminder enqueue failed; sweep will reconcile");
      }
    }

    return reply.status(201).send({
      task,
      reminderQueued
    });
  });

  app.patch("/api/v1/tasks/:id", async request => {
    const auth = await requirePermission(request, "tasks.manage");
    const params = idSchema.parse(request.params);
    const input = updateSchema.parse(request.body);

    const task = await updateTask({
      companyId: auth.companyId,
      taskId: params.id,
      actorMembershipId: auth.membershipId,
      role: auth.role,
      ...input,
      ...(input.dueAt
        ? {
            dueAt: new Date(input.dueAt)
          }
        : {}),
      ...(input.reminderAt !== undefined
        ? {
            reminderAt: input.reminderAt ? new Date(input.reminderAt) : null
          }
        : {})
    });

    if (
      task.status === "OPEN" &&
      task.reminderAt &&
      !task.reminderSentAt &&
      !task.reminderFailedAt
    ) {
      try {
        await enqueueTaskReminder({
          taskId: task.id,
          reminderAt: task.reminderAt
        });
      } catch (error) {
        request.log.error({
          error,
          taskId: task.id
        }, "updated task reminder enqueue failed; sweep will reconcile");
      }
    }

    return {
      task
    };
  });

  app.post("/api/v1/tasks/:id/complete", async request => {
    const auth = await requirePermission(request, "tasks.manage");
    const params = idSchema.parse(request.params);

    return {
      task: await completeTask({
        companyId: auth.companyId,
        taskId: params.id,
        actorMembershipId: auth.membershipId,
        role: auth.role
      })
    };
  });

  app.post("/api/v1/tasks/:id/cancel", async request => {
    const auth = await requirePermission(request, "tasks.manage");
    const params = idSchema.parse(request.params);

    return {
      task: await cancelTask({
        companyId: auth.companyId,
        taskId: params.id,
        actorMembershipId: auth.membershipId,
        role: auth.role
      })
    };
  });
}
EOF

# ---------------------------------------------------------------------------
# Job runtime + standalone worker
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

function patchRuntime(path, standalone) {
  let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

  if (!content.includes("task-reminder.worker.js")) {
    const anchor = standalone
      ? 'import { prisma } from "./lib/database.js";'
      : 'import { env } from "../config/env.js";';

    if (!content.includes(anchor)) {
      throw new Error(`runtime import anchor not found in ${path}`);
    }

    const prefix = standalone ? "./jobs/" : "./";
    content = content.replace(anchor, `${anchor}
import {
  createTaskReminderWorker
} from "${prefix}task-reminder.worker.js";
import {
  closeTaskReminderQueue,
  ensureTaskReminderSweep
} from "${prefix}task-reminder.queue.js";`);
  }

  if (!content.includes("createTaskReminderWorker()")) {
    const anchor = standalone
      ? "  createScheduledMessageWorker()"
      : "    createScheduledMessageWorker()";

    if (!content.includes(anchor)) {
      throw new Error(`scheduled message worker anchor not found in ${path}`);
    }

    content = content.replace(anchor, `${anchor},
${standalone ? "  " : "    "}createTaskReminderWorker()`);
  }

  if (standalone) {
    if (!content.includes("await ensureTaskReminderSweep();")) {
      const anchor = "await ensureScheduledMessageSweep();";
      if (!content.includes(anchor)) throw new Error("standalone scheduler anchor not found.");
      content = content.replace(anchor, `${anchor}
await ensureTaskReminderSweep();`);
    }
  } else if (!content.includes("void ensureTaskReminderSweep()")) {
    const anchor = `  void ensureScheduledMessageSweep()
    .catch(error => {
      console.error(
        "[scheduled-messages] scheduler setup failed",
        error
      );
    });`;
    if (!content.includes(anchor)) throw new Error("embedded scheduler block not found.");
    content = content.replace(anchor, `${anchor}

  void ensureTaskReminderSweep()
    .catch(error => {
      console.error(
        "[task-reminders] scheduler setup failed",
        error
      );
    });`);
  }

  if (!content.includes("closeTaskReminderQueue()")) {
    const anchor = standalone
      ? "    closeScheduledMessageQueue()"
      : "    closeScheduledMessageQueue()";
    if (!content.includes(anchor)) throw new Error(`queue close anchor not found in ${path}`);
    content = content.replace(anchor, `${anchor},
    closeTaskReminderQueue()`);
  }

  fs.writeFileSync(path, content);
}

patchRuntime("apps/api/src/jobs/job-runtime.ts", false);
patchRuntime("apps/api/src/worker.ts", true);
console.log("[P3.3] Task reminder workers registered.");
NODE

# ---------------------------------------------------------------------------
# Central RBAC and permission tests
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/security/permissions.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const typeStart = content.indexOf("export type WappPermission =");
const typeEnd = content.indexOf(";", typeStart);
if (typeStart < 0 || typeEnd < 0) throw new Error("WappPermission union not found.");

let union = content.slice(typeStart, typeEnd);
for (const permission of ["tasks.read", "tasks.manage", "tasks.admin"]) {
  if (!union.includes(`"${permission}"`)) union += `\n  | "${permission}"`;
}
content = content.slice(0, typeStart) + union + content.slice(typeEnd);

function bounds(role) {
  const start = content.indexOf(`  ${role}: [`);
  if (start < 0) throw new Error(`${role} permission block not found.`);
  const open = content.indexOf("[", start);
  let depth = 0, inString = false, quote = "", escape = false;

  for (let i = open; i < content.length; i++) {
    const c = content[i];
    if (inString) {
      if (escape) escape = false;
      else if (c === "\\") escape = true;
      else if (c === quote) inString = false;
      continue;
    }
    if (c === '"' || c === "'") {
      inString = true;
      quote = c;
      continue;
    }
    if (c === "[") depth++;
    else if (c === "]") {
      depth--;
      if (depth === 0) return { start: open, end: i };
    }
  }
  throw new Error(`${role} permission array end not found.`);
}

const wanted = {
  OWNER: ["tasks.read", "tasks.manage", "tasks.admin"],
  ADMIN: ["tasks.read", "tasks.manage", "tasks.admin"],
  SUPERVISOR: ["tasks.read", "tasks.manage", "tasks.admin"],
  AGENT: ["tasks.read", "tasks.manage"]
};

for (const role of ["AGENT", "SUPERVISOR", "ADMIN", "OWNER"]) {
  const b = bounds(role);
  const block = content.slice(b.start, b.end + 1);
  const missing = wanted[role].filter(p => !block.includes(`"${p}"`));
  if (!missing.length) continue;

  const before = content.slice(0, b.end).replace(/\s+$/, "");
  const after = content.slice(b.end);
  const sep = before.endsWith("[") ? "\n" : before.endsWith(",") ? "\n" : ",\n";
  content = before + sep +
    missing.map(p => `    "${p}"`).join(",\n") +
    "\n  " + after;
}

fs.writeFileSync(path, content);
NODE

node <<'NODE'
const fs = require("node:fs");
const permissionPath = "apps/api/src/security/permissions.ts";
const testPath = "apps/api/src/security/permissions.test.ts";

const source = fs.readFileSync(permissionPath, "utf8").replace(/\r\n/g, "\n");
let test = fs.readFileSync(testPath, "utf8").replace(/\r\n/g, "\n");

const start = source.indexOf("export type WappPermission =");
const end = source.indexOf(";", start);
const permissions = Array.from(
  source.slice(start, end).matchAll(/"([^"]+)"/g),
  match => match[1]
);

const declarationStart = test.indexOf("const allPermissions:");
const describeStart = test.indexOf("describe(", declarationStart);
if (declarationStart < 0 || describeStart < 0) {
  throw new Error("permissions.test allPermissions boundary not found.");
}

const declaration = `const allPermissions:
  WappPermission[] = [
${permissions.map(p => `    "${p}"`).join(",\n")}
  ];

`;

test = test.slice(0, declarationStart) + declaration + test.slice(describeStart);

if (!test.includes('"task work is operational while team-wide scope is managerial"')) {
  test += `

describe(
  "CRM task permissions",
  () => {
    it(
      "task work is operational while team-wide scope is managerial",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN",
            "SUPERVISOR"
          ] as const
        ) {
          assert.equal(roleHasPermission(role, "tasks.read"), true);
          assert.equal(roleHasPermission(role, "tasks.manage"), true);
          assert.equal(roleHasPermission(role, "tasks.admin"), true);
        }

        assert.equal(roleHasPermission("AGENT", "tasks.read"), true);
        assert.equal(roleHasPermission("AGENT", "tasks.manage"), true);
        assert.equal(roleHasPermission("AGENT", "tasks.admin"), false);
      }
    );
  }
);
`;
}

fs.writeFileSync(testPath, test);
console.log(`[P3.3] permissions.test rebuilt with ${permissions.length} permissions.`);
NODE

# ---------------------------------------------------------------------------
# App registration + realtime
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const importLine = 'import { taskRoutes } from "./modules/tasks/task.routes.js";';
if (!content.includes(importLine)) {
  const anchor = 'import { pipelineRoutes } from "./modules/pipelines/pipeline.routes.js";';
  if (!content.includes(anchor)) throw new Error("P3.2 pipelineRoutes import anchor not found.");
  content = content.replace(anchor, `${anchor}\n${importLine}`);
}

if (!content.includes("await app.register(taskRoutes);")) {
  const anchor = "  await app.register(pipelineRoutes);";
  if (!content.includes(anchor)) throw new Error("P3.2 pipelineRoutes registration anchor not found.");
  content = content.replace(anchor, `${anchor}\n  await app.register(taskRoutes);`);
}

fs.writeFileSync(path, content);
NODE

node <<'NODE'
const fs = require("node:fs");

for (const path of [
  "apps/api/src/modules/realtime/realtime.bus.ts",
  "apps/web/lib/realtime-types.ts"
]) {
  let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
  const typeStart = content.indexOf("export type RealtimeEventType =");
  const typeEnd = content.indexOf(";", typeStart);
  if (typeStart < 0 || typeEnd < 0) throw new Error(`RealtimeEventType not found in ${path}`);
  let union = content.slice(typeStart, typeEnd);
  if (!union.includes('"task.updated"')) union += '\n  | "task.updated"';
  content = content.slice(0, typeStart) + union + content.slice(typeEnd);

  const interfaceStart = content.indexOf("export interface RealtimeEvent {");
  const interfaceEnd = content.indexOf("\n}", interfaceStart);
  if (interfaceStart < 0 || interfaceEnd < 0) throw new Error(`RealtimeEvent interface not found in ${path}`);
  let block = content.slice(interfaceStart, interfaceEnd);
  if (!block.includes("taskId?: string;")) block += "\n  taskId?: string;";
  content = content.slice(0, interfaceStart) + block + content.slice(interfaceEnd);

  fs.writeFileSync(path, content);
}

console.log("[P3.3] task.updated realtime contract installed.");
NODE

# ---------------------------------------------------------------------------
# Notification Center contact deep-link
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/components/notifications/notification-center.tsx";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("contactId:")) {
  const anchor = `  ticketId:
    | string
    | null;
  messageId:`;
  if (!content.includes(anchor)) throw new Error("NotificationCenter ticketId interface anchor not found.");
  content = content.replace(anchor, `  ticketId:
    | string
    | null;
  contactId:
    | string
    | null;
  messageId:`);
}

const clickOld = `            if (
              item.ticketId
            ) {
              router.push(
                \`/dashboard/conversations?ticket=\${item.ticketId}\`
              );
            }

            browserNotification.close();`;

const clickNew = `            if (
              item.ticketId
            ) {
              router.push(
                \`/dashboard/conversations?ticket=\${item.ticketId}\`
              );
            } else if (
              item.contactId
            ) {
              router.push(
                \`/dashboard/contacts?contact=\${item.contactId}\`
              );
            }

            browserNotification.close();`;

if (content.includes(clickOld)) content = content.replace(clickOld, clickNew);

const openOld = `    if (
      item.ticketId
    ) {
      router.push(
        \`/dashboard/conversations?ticket=\${item.ticketId}\`
      );
    }
  }`;

const openNew = `    if (
      item.ticketId
    ) {
      router.push(
        \`/dashboard/conversations?ticket=\${item.ticketId}\`
      );
    } else if (
      item.contactId
    ) {
      router.push(
        \`/dashboard/contacts?contact=\${item.contactId}\`
      );
    }
  }`;

if (content.includes(openOld)) content = content.replace(openOld, openNew);

if ((content.match(/item\.contactId/g) ?? []).length < 2) {
  throw new Error("NotificationCenter contact deep-link insertion incomplete.");
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Contacts ?contact= deep-link (also closes the P3.2 card-link gap)
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/app/dashboard/contacts/page.tsx";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (content.includes('import { useRouter } from "next/navigation";')) {
  content = content.replace(
    'import { useRouter } from "next/navigation";',
    'import { useRouter, useSearchParams } from "next/navigation";'
  );
}

if (!content.includes("const searchParams = useSearchParams();")) {
  const anchor = "  const router = useRouter();";
  if (!content.includes(anchor)) throw new Error("Contacts router anchor not found.");
  content = content.replace(anchor, `${anchor}
  const searchParams = useSearchParams();
  const targetContactId =
    searchParams.get(
      "contact"
    );`);
}

const selectionOld = `      setSelectedId(current => {
        if (
          current &&
          payload.contacts.some(
            contact => contact.id === current
          )
        ) {
          return current;
        }

        return payload.contacts[0]?.id ?? null;
      });`;

const selectionNew = `      setSelectedId(current => {
        if (
          targetContactId
        ) {
          return targetContactId;
        }

        if (
          current &&
          payload.contacts.some(
            contact => contact.id === current
          )
        ) {
          return current;
        }

        return payload.contacts[0]?.id ?? null;
      });`;

if (content.includes(selectionOld)) {
  content = content.replace(selectionOld, selectionNew);
} else if (!content.includes("targetContactId")) {
  throw new Error("Contacts selection callback anchor not found.");
}

content = content.replace(
  "  }, [filter, page, request, search]);",
  "  }, [filter, page, request, search, targetContactId]);"
);

if (!content.includes('router.replace(\n        "/dashboard/contacts"')) {
  const anchor = `  useEffect(() => {
    if (!selectedId) {
      setDetail(null);`;
  if (!content.includes(anchor)) throw new Error("Contacts selectedId effect anchor not found.");

  const effect = `  useEffect(() => {
    if (
      targetContactId &&
      detail?.id ===
        targetContactId
    ) {
      router.replace(
        "/dashboard/contacts",
        {
          scroll:
            false
        }
      );
    }
  }, [
    detail?.id,
    router,
    targetContactId
  ]);

`;

  content = content.replace(anchor, `${effect}${anchor}`);
}

fs.writeFileSync(path, content);
console.log("[P3.3] Contacts deep-link support installed.");
NODE

# ---------------------------------------------------------------------------
# Frontend permissions + navigation
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/lib/permissions.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const typeStart = content.indexOf("export type UiPermission =");
const typeEnd = content.indexOf(";", typeStart);
if (typeStart < 0 || typeEnd < 0) throw new Error("UiPermission union not found.");

let union = content.slice(typeStart, typeEnd);
for (const permission of ["tasks.view", "tasks.admin"]) {
  if (!union.includes(`"${permission}"`)) union += `\n  | "${permission}"`;
}
content = content.slice(0, typeStart) + union + content.slice(typeEnd);

function bounds(role) {
  const start = content.indexOf(`  ${role}: [`);
  if (start < 0) throw new Error(`${role} UI permission block not found.`);
  const open = content.indexOf("[", start);
  let depth = 0, inString = false, quote = "", escape = false;

  for (let i = open; i < content.length; i++) {
    const c = content[i];
    if (inString) {
      if (escape) escape = false;
      else if (c === "\\") escape = true;
      else if (c === quote) inString = false;
      continue;
    }
    if (c === '"' || c === "'") {
      inString = true;
      quote = c;
      continue;
    }
    if (c === "[") depth++;
    else if (c === "]") {
      depth--;
      if (depth === 0) return { start: open, end: i };
    }
  }
  throw new Error(`${role} UI permission array end not found.`);
}

const wanted = {
  OWNER: ["tasks.view", "tasks.admin"],
  ADMIN: ["tasks.view", "tasks.admin"],
  SUPERVISOR: ["tasks.view", "tasks.admin"],
  AGENT: ["tasks.view"]
};

for (const role of ["AGENT", "SUPERVISOR", "ADMIN", "OWNER"]) {
  const b = bounds(role);
  const block = content.slice(b.start, b.end + 1);
  const missing = wanted[role].filter(p => !block.includes(`"${p}"`));
  if (!missing.length) continue;

  const before = content.slice(0, b.end).replace(/\s+$/, "");
  const after = content.slice(b.end);
  const sep = before.endsWith("[") ? "\n" : before.endsWith(",") ? "\n" : ",\n";
  content = before + sep +
    missing.map(p => `    "${p}"`).join(",\n") +
    "\n  " + after;
}

fs.writeFileSync(path, content);
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/app/dashboard/page.tsx";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes('href: "/dashboard/tasks"')) {
  const anchor = `  {
    label: "Pipeline",
    href: "/dashboard/pipeline",
    permission: "pipeline.view"
  },`;
  if (!content.includes(anchor)) throw new Error("P3.2 Pipeline navigation anchor not found.");
  content = content.replace(anchor, `${anchor}
  {
    label: "Tarefas",
    href: "/dashboard/tasks",
    permission: "tasks.view"
  },`);
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Contact task panel
# ---------------------------------------------------------------------------

cat > apps/web/components/contacts/contact-tasks-panel.tsx <<'EOF'
"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type TaskStatus = "OPEN" | "DONE" | "CANCELLED";
type TaskPriority = "LOW" | "NORMAL" | "HIGH" | "URGENT";

interface Task {
  id: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: TaskPriority;
  dueAt: string;
  reminderAt: string | null;
  reminderSentAt: string | null;
  reminderFailedAt: string | null;
  reminderError: string | null;
  ticket: {
    id: string;
    status: string;
    lastMessage: string | null;
    lastMessageAt: string;
  } | null;
  assigneeMembership: {
    id: string;
    user: {
      id: string;
      name: string;
    };
  };
}

interface ContextPayload {
  actorMembershipId: string;
  tasks: Task[];
  assignees: Array<{
    id: string;
    role: string;
    user: {
      id: string;
      name: string;
    };
  }>;
  tickets: Array<{
    id: string;
    status: string;
    lastMessage: string | null;
    lastMessageAt: string;
  }>;
}

const priorityLabel = {
  LOW: "Baixa",
  NORMAL: "Normal",
  HIGH: "Alta",
  URGENT: "Urgente"
} as const;

function localDateTime(date: Date) {
  return new Date(
    date.getTime() -
    date.getTimezoneOffset() * 60_000
  ).toISOString().slice(0, 16);
}

function newDefaultDue() {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  date.setHours(10, 0, 0, 0);
  return date;
}

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short"
  }).format(new Date(value));
}

export function ContactTasksPanel({
  contactId,
  contactName
}: {
  contactId: string;
  contactName: string;
}) {
  const router = useRouter();
  const {
    request,
    subscribe
  } = useAuth();

  const [context, setContext] =
    useState<ContextPayload | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] =
    useState("");
  const [priority, setPriority] =
    useState<TaskPriority>("NORMAL");
  const [assigneeId, setAssigneeId] =
    useState("");
  const [ticketId, setTicketId] =
    useState("");

  const initialDue = useMemo(
    () => newDefaultDue(),
    [contactId]
  );

  const [dueAt, setDueAt] = useState(
    localDateTime(initialDue)
  );
  const [reminderAt, setReminderAt] =
    useState(
      localDateTime(
        new Date(
          initialDue.getTime() -
          60 * 60 * 1_000
        )
      )
    );

  const [creating, setCreating] =
    useState(false);
  const [actionId, setActionId] =
    useState<string | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const load = useCallback(async () => {
    const payload =
      await request<ContextPayload>(
        `/api/v1/contacts/${contactId}/tasks/context`
      );

    setContext(payload);
    setAssigneeId(current =>
      current &&
      payload.assignees.some(
        item => item.id === current
      )
        ? current
        : payload.assignees.find(
            item =>
              item.id ===
              payload.actorMembershipId
          )?.id ??
          payload.assignees[0]?.id ??
          ""
    );
  }, [
    contactId,
    request
  ]);

  useEffect(() => {
    void load().catch(() => {
      setError(
        "Não foi possível carregar as tarefas do contato."
      );
    });
  }, [load]);

  useEffect(
    () =>
      subscribe(
        "/api/v1/realtime/events",
        event => {
          if (
            event.type === "task.updated" &&
            event.contactId === contactId
          ) {
            void load().catch(() => {});
          }
        }
      ),
    [contactId, load, subscribe]
  );

  const sortedTasks = useMemo(
    () =>
      [...(context?.tasks ?? [])].sort(
        (left, right) => {
          if (
            left.status === "OPEN" &&
            right.status !== "OPEN"
          ) {
            return -1;
          }

          if (
            left.status !== "OPEN" &&
            right.status === "OPEN"
          ) {
            return 1;
          }

          return (
            new Date(left.dueAt).getTime() -
            new Date(right.dueAt).getTime()
          );
        }
      ),
    [context?.tasks]
  );

  async function createTask(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!assigneeId) return;

    setCreating(true);
    setError("");
    setNotice("");

    try {
      const result = await request<{
        reminderQueued: boolean;
      }>("/api/v1/tasks", {
        method: "POST",
        body: JSON.stringify({
          contactId,
          ticketId: ticketId || null,
          assigneeMembershipId: assigneeId,
          title: title.trim(),
          description:
            description.trim() || null,
          priority,
          dueAt: new Date(
            dueAt
          ).toISOString(),
          reminderAt: reminderAt
            ? new Date(
                reminderAt
              ).toISOString()
            : null
        })
      });

      const nextDue = newDefaultDue();

      setTitle("");
      setDescription("");
      setPriority("NORMAL");
      setTicketId("");
      setDueAt(
        localDateTime(
          nextDue
        )
      );
      setReminderAt(
        localDateTime(
          new Date(
            nextDue.getTime() -
            60 * 60 * 1_000
          )
        )
      );
      setNotice(
        result.reminderQueued ||
        !reminderAt
          ? "Tarefa criada."
          : "Tarefa criada. O reconciliador cuidará do lembrete quando a fila estiver disponível."
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível criar a tarefa."
      );
    } finally {
      setCreating(false);
    }
  }

  async function runAction(
    taskId: string,
    action: "complete" | "cancel"
  ) {
    setActionId(taskId);
    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/tasks/${taskId}/${action}`,
        {
          method: "POST"
        }
      );

      setNotice(
        action === "complete"
          ? "Tarefa concluída."
          : "Tarefa cancelada."
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar a tarefa."
      );
    } finally {
      setActionId(null);
    }
  }

  return (
    <section className="contact-tasks">
      <header>
        <div>
          <span className="eyebrow">
            Follow-up
          </span>
          <strong>Tarefas</strong>
          <small>
            Próximas ações com {contactName}.
          </small>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              "/dashboard/tasks"
            )
          }
          type="button"
        >
          Abrir agenda
        </button>
      </header>

      {error && (
        <div className="contact-tasks__feedback contact-tasks__feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="contact-tasks__feedback">
          {notice}
        </div>
      )}

      <div className="contact-tasks__layout">
        <form
          className="contact-task-form"
          onSubmit={createTask}
        >
          <strong>Nova tarefa</strong>

          <label>
            <span>Título</span>
            <input
              maxLength={190}
              onChange={event =>
                setTitle(
                  event.target.value
                )
              }
              placeholder="Ex.: Retornar proposta"
              required
              value={title}
            />
          </label>

          <label>
            <span>Responsável</span>
            <select
              onChange={event =>
                setAssigneeId(
                  event.target.value
                )
              }
              required
              value={assigneeId}
            >
              {context?.assignees.map(
                item => (
                  <option
                    key={item.id}
                    value={item.id}
                  >
                    {item.user.name}
                  </option>
                )
              )}
            </select>
          </label>

          <div className="contact-task-form__row">
            <label>
              <span>Prazo</span>
              <input
                onChange={event =>
                  setDueAt(
                    event.target.value
                  )
                }
                required
                type="datetime-local"
                value={dueAt}
              />
            </label>

            <label>
              <span>Lembrete</span>
              <input
                onChange={event =>
                  setReminderAt(
                    event.target.value
                  )
                }
                type="datetime-local"
                value={reminderAt}
              />
            </label>
          </div>

          <div className="contact-task-form__row">
            <label>
              <span>Prioridade</span>
              <select
                onChange={event =>
                  setPriority(
                    event.target
                      .value as
                      TaskPriority
                  )
                }
                value={priority}
              >
                {Object.entries(
                  priorityLabel
                ).map(
                  ([key, label]) => (
                    <option
                      key={key}
                      value={key}
                    >
                      {label}
                    </option>
                  )
                )}
              </select>
            </label>

            <label>
              <span>Atendimento</span>
              <select
                onChange={event =>
                  setTicketId(
                    event.target.value
                  )
                }
                value={ticketId}
              >
                <option value="">
                  Sem vínculo
                </option>

                {context?.tickets.map(
                  ticket => (
                    <option
                      key={ticket.id}
                      value={ticket.id}
                    >
                      {ticket.status} ·{" "}
                      {dateTimeLabel(
                        ticket.lastMessageAt
                      )}
                    </option>
                  )
                )}
              </select>
            </label>
          </div>

          <label>
            <span>Detalhes</span>
            <textarea
              maxLength={10_000}
              onChange={event =>
                setDescription(
                  event.target.value
                )
              }
              placeholder="Contexto opcional para o follow-up."
              rows={3}
              value={description}
            />
          </label>

          <button
            className="primary-button"
            disabled={
              creating ||
              !title.trim() ||
              !assigneeId
            }
            type="submit"
          >
            <span>
              {creating
                ? "Criando…"
                : "Criar tarefa"}
            </span>
          </button>
        </form>

        <div className="contact-task-list">
          <header>
            <strong>Acompanhamento</strong>
            <span>
              {sortedTasks.filter(
                task =>
                  task.status === "OPEN"
              ).length} abertas
            </span>
          </header>

          {sortedTasks.map(task => {
            const overdue =
              task.status === "OPEN" &&
              new Date(
                task.dueAt
              ).getTime() <
                Date.now();

            return (
              <article
                className={
                  overdue
                    ? "contact-task-item contact-task-item--overdue"
                    : `contact-task-item contact-task-item--${task.status.toLowerCase()}`
                }
                key={task.id}
              >
                <div className="contact-task-item__top">
                  <div>
                    <span
                      className={
                        `task-priority task-priority--${task.priority.toLowerCase()}`
                      }
                    >
                      {priorityLabel[
                        task.priority
                      ]}
                    </span>

                    {overdue && (
                      <span className="task-overdue">
                        Atrasada
                      </span>
                    )}
                  </div>

                  <time>
                    {dateTimeLabel(
                      task.dueAt
                    )}
                  </time>
                </div>

                <strong>{task.title}</strong>

                {task.description && (
                  <p>
                    {task.description}
                  </p>
                )}

                <div className="contact-task-item__meta">
                  <span>
                    {task
                      .assigneeMembership
                      .user.name}
                  </span>

                  {task.ticket && (
                    <button
                      onClick={() =>
                        router.push(
                          `/dashboard/conversations?ticket=${task.ticket?.id}`
                        )
                      }
                      type="button"
                    >
                      Abrir atendimento
                    </button>
                  )}
                </div>

                {task.reminderFailedAt &&
                  task.reminderError && (
                  <small className="contact-task-item__reminder-error">
                    Lembrete:{" "}
                    {task.reminderError}
                  </small>
                )}

                {task.status === "OPEN" && (
                  <div className="contact-task-item__actions">
                    <button
                      disabled={
                        actionId ===
                        task.id
                      }
                      onClick={() =>
                        void runAction(
                          task.id,
                          "complete"
                        )
                      }
                      type="button"
                    >
                      Concluir
                    </button>

                    <button
                      disabled={
                        actionId ===
                        task.id
                      }
                      onClick={() =>
                        void runAction(
                          task.id,
                          "cancel"
                        )
                      }
                      type="button"
                    >
                      Cancelar
                    </button>
                  </div>
                )}
              </article>
            );
          })}

          {sortedTasks.length === 0 && (
            <div className="contact-tasks__empty">
              Nenhuma tarefa registrada para este contato.
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/app/dashboard/contacts/page.tsx";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const importLine =
  'import { ContactTasksPanel } from "@/components/contacts/contact-tasks-panel";';

if (!content.includes(importLine)) {
  const anchor =
    'import { ContactPipelineSummary } from "@/components/contacts/contact-pipeline-summary";';
  if (!content.includes(anchor)) {
    throw new Error("P3.2 ContactPipelineSummary import not found.");
  }
  content = content.replace(anchor, `${anchor}\n${importLine}`);
}

if (!content.includes("<ContactTasksPanel")) {
  const anchor = "              <ContactPipelineSummary";
  if (!content.includes(anchor)) {
    throw new Error("P3.2 ContactPipelineSummary mount not found.");
  }
  content = content.replace(anchor, `              <ContactTasksPanel
                contactId={
                  detail.id
                }
                contactName={
                  detail.name
                }
              />

${anchor}`);
}

fs.writeFileSync(path, content);
console.log("[P3.3] Contact task panel mounted.");
NODE

# ---------------------------------------------------------------------------
# Global task agenda
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/tasks/page.tsx <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";
import { roleCan } from "@/lib/permissions";

type TaskStatus =
  | "OPEN"
  | "DONE"
  | "CANCELLED";

interface Task {
  id: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority:
    | "LOW"
    | "NORMAL"
    | "HIGH"
    | "URGENT";
  dueAt: string;
  reminderAt: string | null;
  reminderSentAt: string | null;
  reminderFailedAt: string | null;
  contact: {
    id: string;
    name: string;
    phoneNumber: string | null;
    email: string | null;
  };
  ticket: {
    id: string;
    status: string;
  } | null;
  assigneeMembership: {
    id: string;
    user: {
      id: string;
      name: string;
    };
  };
}

const priorityLabel = {
  LOW: "Baixa",
  NORMAL: "Normal",
  HIGH: "Alta",
  URGENT: "Urgente"
} as const;

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      dateStyle: "short",
      timeStyle: "short"
    }
  ).format(new Date(value));
}

export default function TasksPage() {
  const router = useRouter();
  const {
    session,
    loading,
    request,
    subscribe
  } = useAuth();

  const [tasks, setTasks] =
    useState<Task[]>([]);
  const [status, setStatus] =
    useState<TaskStatus>("OPEN");
  const [scope, setScope] =
    useState<"ME" | "ALL">("ME");
  const [overdueOnly, setOverdueOnly] =
    useState(false);
  const [busy, setBusy] =
    useState(true);
  const [actionId, setActionId] =
    useState<string | null>(null);
  const [error, setError] = useState("");

  const canAdmin =
    session
      ? roleCan(
          session.role,
          "tasks.admin"
        )
      : false;

  const load = useCallback(async () => {
    setBusy(true);

    try {
      const params =
        new URLSearchParams({
          scope,
          status,
          overdueOnly:
            String(overdueOnly),
          limit: "150"
        });

      const payload =
        await request<{
          tasks: Task[];
        }>(
          `/api/v1/tasks?${params.toString()}`
        );

      setTasks(payload.tasks);
      setError("");
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível carregar as tarefas."
      );
    } finally {
      setBusy(false);
    }
  }, [
    overdueOnly,
    request,
    scope,
    status
  ]);

  useEffect(() => {
    if (
      !loading &&
      !session
    ) {
      router.replace("/login");
      return;
    }

    if (
      session &&
      !roleCan(
        session.role,
        "tasks.view"
      )
    ) {
      router.replace("/dashboard");
      return;
    }

    if (session) {
      void load();
    }
  }, [
    load,
    loading,
    router,
    session
  ]);

  useEffect(() => {
    if (!session) return;

    return subscribe(
      "/api/v1/realtime/events",
      event => {
        if (
          event.type ===
          "task.updated"
        ) {
          void load();
        }
      }
    );
  }, [
    load,
    session,
    subscribe
  ]);

  useEffect(() => {
    if (
      !canAdmin &&
      scope === "ALL"
    ) {
      setScope("ME");
    }
  }, [
    canAdmin,
    scope
  ]);

  const summary = useMemo(() => {
    const now = Date.now();

    return {
      total: tasks.length,
      overdue: tasks.filter(
        task =>
          task.status === "OPEN" &&
          new Date(
            task.dueAt
          ).getTime() <
            now
      ).length,
      today: tasks.filter(task => {
        const date =
          new Date(task.dueAt);
        const today =
          new Date();

        return (
          date.getFullYear() ===
            today.getFullYear() &&
          date.getMonth() ===
            today.getMonth() &&
          date.getDate() ===
            today.getDate()
        );
      }).length
    };
  }, [tasks]);

  async function action(
    taskId: string,
    type: "complete" | "cancel"
  ) {
    setActionId(taskId);

    try {
      await request(
        `/api/v1/tasks/${taskId}/${type}`,
        {
          method: "POST"
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar a tarefa."
      );
    } finally {
      setActionId(null);
    }
  }

  if (
    loading ||
    !session
  ) {
    return (
      <main className="dashboard-loading">
        Carregando tarefas…
      </main>
    );
  }

  return (
    <main className="tasks-screen">
      <header className="tasks-header">
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
            CRM
          </span>

          <h1>Tarefas</h1>

          <p>
            Agenda de follow-ups, prazos e lembretes vinculados aos contatos.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              "/dashboard/contacts"
            )
          }
          type="button"
        >
          Nova tarefa pela ficha do contato
        </button>
      </header>

      {error && (
        <div className="tasks-feedback tasks-feedback--error">
          {error}
        </div>
      )}

      <section className="tasks-summary">
        <article>
          <span>Na visão atual</span>
          <strong>{summary.total}</strong>
        </article>

        <article>
          <span>Para hoje</span>
          <strong>{summary.today}</strong>
        </article>

        <article>
          <span>Atrasadas</span>
          <strong>
            {summary.overdue}
          </strong>
        </article>
      </section>

      <section className="tasks-toolbar">
        <div className="tasks-switch">
          {(
            [
              ["OPEN", "Abertas"],
              ["DONE", "Concluídas"],
              [
                "CANCELLED",
                "Canceladas"
              ]
            ] as const
          ).map(
            ([value, label]) => (
              <button
                className={
                  status === value
                    ? "tasks-switch__item tasks-switch__item--active"
                    : "tasks-switch__item"
                }
                key={value}
                onClick={() =>
                  setStatus(value)
                }
                type="button"
              >
                {label}
              </button>
            )
          )}
        </div>

        {canAdmin && (
          <div className="tasks-switch">
            <button
              className={
                scope === "ME"
                  ? "tasks-switch__item tasks-switch__item--active"
                  : "tasks-switch__item"
              }
              onClick={() =>
                setScope("ME")
              }
              type="button"
            >
              Minhas
            </button>

            <button
              className={
                scope === "ALL"
                  ? "tasks-switch__item tasks-switch__item--active"
                  : "tasks-switch__item"
              }
              onClick={() =>
                setScope("ALL")
              }
              type="button"
            >
              Equipe
            </button>
          </div>
        )}

        {status === "OPEN" && (
          <label className="tasks-overdue-filter">
            <input
              checked={overdueOnly}
              onChange={event =>
                setOverdueOnly(
                  event.target.checked
                )
              }
              type="checkbox"
            />
            Somente atrasadas
          </label>
        )}
      </section>

      {busy ? (
        <div className="tasks-empty">
          Atualizando agenda…
        </div>
      ) : tasks.length === 0 ? (
        <div className="tasks-empty">
          Nenhuma tarefa nesta visão.
        </div>
      ) : (
        <section className="tasks-list">
          {tasks.map(task => {
            const overdue =
              task.status === "OPEN" &&
              new Date(
                task.dueAt
              ).getTime() <
                Date.now();

            return (
              <article
                className={
                  overdue
                    ? "task-row task-row--overdue"
                    : "task-row"
                }
                key={task.id}
              >
                <div className="task-row__when">
                  <strong>
                    {dateTimeLabel(
                      task.dueAt
                    )}
                  </strong>
                  <span>
                    {overdue
                      ? "Atrasada"
                      : task.status}
                  </span>
                </div>

                <button
                  className="task-row__contact"
                  onClick={() =>
                    router.push(
                      `/dashboard/contacts?contact=${task.contact.id}`
                    )
                  }
                  type="button"
                >
                  <span>
                    {task.contact.name
                      .slice(0, 1)
                      .toUpperCase()}
                  </span>

                  <div>
                    <strong>
                      {task.contact.name}
                    </strong>
                    <small>
                      {task
                        .contact
                        .phoneNumber ??
                        task
                          .contact
                          .email ??
                        "Contato"}
                    </small>
                  </div>
                </button>

                <div className="task-row__copy">
                  <div>
                    <span
                      className={
                        `task-priority task-priority--${task.priority.toLowerCase()}`
                      }
                    >
                      {priorityLabel[
                        task.priority
                      ]}
                    </span>

                    <strong>
                      {task.title}
                    </strong>
                  </div>

                  <small>
                    Responsável:{" "}
                    {task
                      .assigneeMembership
                      .user.name}
                  </small>
                </div>

                <div className="task-row__actions">
                  {task.ticket && (
                    <button
                      onClick={() =>
                        router.push(
                          `/dashboard/conversations?ticket=${task.ticket?.id}`
                        )
                      }
                      type="button"
                    >
                      Conversa
                    </button>
                  )}

                  {task.status === "OPEN" && (
                    <>
                      <button
                        disabled={
                          actionId === task.id
                        }
                        onClick={() =>
                          void action(
                            task.id,
                            "complete"
                          )
                        }
                        type="button"
                      >
                        Concluir
                      </button>

                      <button
                        disabled={
                          actionId === task.id
                        }
                        onClick={() =>
                          void action(
                            task.id,
                            "cancel"
                          )
                        }
                        type="button"
                      >
                        Cancelar
                      </button>
                    </>
                  )}
                </div>
              </article>
            );
          })}
        </section>
      )}
    </main>
  );
}
EOF

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

if ! grep -Fq -- "WAPP P3.3 / TASKS AND FOLLOW-UPS" apps/web/app/globals.css; then
cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P3.3 / TASKS AND FOLLOW-UPS -------------------------------- */

.contact-tasks {
  margin-top: 12px;
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
}

.contact-tasks > header,
.tasks-header,
.tasks-toolbar,
.contact-task-item__top,
.contact-task-item__meta,
.contact-task-item__actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.contact-tasks > header {
  border-bottom: 1px solid var(--line);
  padding: 11px 13px;
}

.contact-tasks > header > div {
  display: grid;
  gap: 2px;
}

.contact-tasks > header strong {
  font-size: 10px;
}

.contact-tasks > header small {
  color: var(--muted);
  font-size: 7px;
}

.contact-tasks__feedback,
.tasks-feedback {
  margin: 9px 12px 0;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 8px 9px;
  font-size: 8px;
}

.contact-tasks__feedback--error,
.tasks-feedback--error {
  background: rgba(163, 59, 50, 0.07);
  color: #973a32;
}

.contact-tasks__layout {
  display: grid;
  grid-template-columns: minmax(260px, 0.75fr) minmax(0, 1.25fr);
}

.contact-task-form {
  display: grid;
  align-content: start;
  gap: 9px;
  border-right: 1px solid var(--line);
  background: #fafbfa;
  padding: 13px;
}

.contact-task-form > strong {
  font-size: 10px;
}

.contact-task-form label {
  display: grid;
  gap: 4px;
}

.contact-task-form label > span {
  color: var(--muted);
  font-size: 7px;
  font-weight: 750;
}

.contact-task-form input,
.contact-task-form select,
.contact-task-form textarea {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 8px;
  outline: 0;
  background: white;
  padding: 7px 8px;
  color: var(--ink);
  font: inherit;
  font-size: 9px;
}

.contact-task-form input,
.contact-task-form select {
  min-height: 36px;
}

.contact-task-form textarea {
  resize: vertical;
}

.contact-task-form__row {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 7px;
}

.contact-task-form .primary-button {
  width: fit-content;
}

.contact-task-list {
  display: grid;
  align-content: start;
  max-height: 540px;
  overflow-y: auto;
  padding: 0 13px 13px;
  scrollbar-width: thin;
}

.contact-task-list > header {
  position: sticky;
  top: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  z-index: 2;
  border-bottom: 1px solid var(--line);
  background: white;
  padding: 12px 0 9px;
}

.contact-task-list > header strong {
  font-size: 10px;
}

.contact-task-list > header span {
  color: var(--muted);
  font-size: 7px;
}

.contact-task-item {
  display: grid;
  gap: 6px;
  border-bottom: 1px solid #edf0ed;
  padding: 10px 1px;
}

.contact-task-item:last-child {
  border-bottom: 0;
}

.contact-task-item--done,
.contact-task-item--cancelled {
  opacity: 0.58;
}

.contact-task-item--overdue {
  border-left: 2px solid #a84e49;
  padding-left: 8px;
}

.contact-task-item__top > div {
  display: flex;
  align-items: center;
  gap: 5px;
}

.contact-task-item__top time,
.contact-task-item__meta > span {
  color: var(--muted);
  font-size: 7px;
}

.contact-task-item > strong {
  font-size: 9px;
}

.contact-task-item > p {
  display: -webkit-box;
  overflow: hidden;
  margin: 0;
  color: #59635d;
  font-size: 8px;
  line-height: 1.45;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.contact-task-item__meta button,
.contact-task-item__actions button {
  border: 0;
  background: transparent;
  color: var(--accent-dark);
  padding: 3px 0;
  font-size: 7px;
  font-weight: 760;
  cursor: pointer;
}

.contact-task-item__actions {
  justify-content: flex-end;
}

.contact-task-item__actions button:last-child {
  color: #973a32;
}

.contact-task-item__reminder-error {
  color: #973a32;
  font-size: 7px;
}

.task-priority,
.task-overdue {
  width: fit-content;
  border-radius: 999px;
  padding: 3px 6px;
  font-size: 7px;
  font-weight: 790;
}

.task-priority {
  background: #eef1ef;
  color: #68716c;
}

.task-priority--high {
  background: rgba(193, 128, 63, 0.1);
  color: #9b612a;
}

.task-priority--urgent,
.task-overdue {
  background: rgba(168, 78, 73, 0.1);
  color: #973a32;
}

.task-priority--low {
  background: rgba(79, 121, 167, 0.09);
  color: #496d95;
}

.contact-tasks__empty {
  padding: 24px 0;
  color: var(--muted);
  font-size: 8px;
  text-align: center;
}

.tasks-screen {
  min-height: 100vh;
  background: var(--surface-subtle);
  padding: 32px clamp(18px, 4vw, 56px) 56px;
}

.tasks-header {
  align-items: flex-end;
  gap: 20px;
}

.tasks-header h1 {
  margin: 6px 0 5px;
  font-size: clamp(32px, 4vw, 48px);
  letter-spacing: -0.05em;
}

.tasks-header p {
  max-width: 620px;
  margin: 0;
  color: var(--muted);
  font-size: 10px;
  line-height: 1.5;
}

.tasks-feedback {
  margin-inline: 0;
  margin-top: 12px;
}

.tasks-summary {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  overflow: hidden;
  margin-top: 14px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: white;
}

.tasks-summary article {
  display: grid;
  gap: 2px;
  border-right: 1px solid var(--line);
  padding: 12px 14px;
}

.tasks-summary article:last-child {
  border-right: 0;
}

.tasks-summary span {
  color: var(--muted);
  font-size: 7px;
}

.tasks-summary strong {
  font-size: 20px;
  letter-spacing: -0.04em;
}

.tasks-toolbar {
  margin-top: 10px;
}

.tasks-switch {
  display: inline-flex;
  border: 1px solid var(--line);
  border-radius: 9px;
  background: white;
  padding: 3px;
}

.tasks-switch__item {
  min-height: 28px;
  border: 0;
  border-radius: 7px;
  background: transparent;
  color: var(--muted);
  padding: 0 10px;
  font-size: 8px;
  font-weight: 740;
  cursor: pointer;
}

.tasks-switch__item--active {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.tasks-overdue-filter {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  color: var(--muted);
  font-size: 8px;
}

.tasks-empty {
  margin-top: 10px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: white;
  padding: 28px;
  color: var(--muted);
  font-size: 9px;
  text-align: center;
}

.tasks-list {
  overflow: hidden;
  margin-top: 10px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: white;
}

.task-row {
  display: grid;
  grid-template-columns: 145px minmax(190px, 0.75fr) minmax(240px, 1.3fr) auto;
  align-items: center;
  gap: 14px;
  border-bottom: 1px solid #edf0ed;
  padding: 11px 13px;
}

.task-row:last-child {
  border-bottom: 0;
}

.task-row--overdue {
  box-shadow: inset 3px 0 0 #a84e49;
}

.task-row__when,
.task-row__contact > div,
.task-row__copy {
  display: grid;
  gap: 2px;
}

.task-row__when strong {
  font-size: 8px;
}

.task-row__when span,
.task-row__contact small,
.task-row__copy small {
  color: var(--muted);
  font-size: 7px;
}

.task-row__contact {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 8px;
  border: 0;
  background: transparent;
  padding: 0;
  text-align: left;
  cursor: pointer;
}

.task-row__contact > span {
  display: grid;
  width: 30px;
  height: 30px;
  flex: 0 0 30px;
  place-items: center;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 8px;
  font-weight: 850;
}

.task-row__contact strong,
.task-row__copy strong {
  overflow: hidden;
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.task-row__copy > div {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 6px;
}

.task-row__actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 7px;
}

.task-row__actions button {
  border: 0;
  background: transparent;
  color: var(--accent-dark);
  padding: 4px 0;
  font-size: 7px;
  font-weight: 760;
  cursor: pointer;
}

.task-row__actions button:last-child {
  color: #973a32;
}

@media (max-width: 980px) {
  .contact-tasks__layout {
    grid-template-columns: 1fr;
  }

  .contact-task-form {
    border-right: 0;
    border-bottom: 1px solid var(--line);
  }

  .task-row {
    grid-template-columns: 125px minmax(180px, 0.8fr) minmax(190px, 1fr);
  }

  .task-row__actions {
    grid-column: 2 / -1;
  }
}

@media (max-width: 760px) {
  .contact-tasks > header,
  .tasks-header,
  .tasks-toolbar {
    align-items: flex-start;
    flex-direction: column;
  }

  .contact-task-form__row {
    grid-template-columns: 1fr;
  }

  .contact-task-form input,
  .contact-task-form select,
  .contact-task-form textarea {
    min-height: 42px;
    font-size: 16px;
  }

  .tasks-screen {
    min-height: 100dvh;
    padding: 20px 12px
      calc(82px + env(safe-area-inset-bottom, 0px));
  }

  .tasks-header .ghost-button {
    width: 100%;
  }

  .tasks-summary {
    grid-template-columns: repeat(3, 1fr);
  }

  .tasks-switch {
    width: 100%;
    overflow-x: auto;
  }

  .tasks-switch__item {
    min-height: 38px;
    flex: 1 0 auto;
  }

  .task-row {
    grid-template-columns: 1fr;
    gap: 8px;
    padding: 12px;
  }

  .task-row__actions {
    grid-column: auto;
    justify-content: flex-start;
  }

  .task-row__actions button {
    min-height: 36px;
  }
}

/* --- /WAPP P3.3 ------------------------------------------------------ */
EOF
fi

# ---------------------------------------------------------------------------
# Test registration + docs
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
const current = pkg.scripts?.test;
if (typeof current !== "string") throw new Error("API test script missing.");

const file = "src/modules/tasks/task.policy.test.ts";
if (!current.includes(file)) {
  pkg.scripts.test = `${current} ${file}`;
}

fs.writeFileSync(path, `${JSON.stringify(pkg, null, 2)}\n`);
NODE

cat > docs/P3_03_TASKS_FOLLOWUPS.md <<'EOF'
# P3.3 Tasks and follow-ups

P3.3 adds an operational follow-up layer over Contacts.

A task has one contact, one responsible membership, one creator and may
optionally link to a ticket.

Statuses:

- OPEN
- DONE
- CANCELLED

Priorities:

- LOW
- NORMAL
- HIGH
- URGENT

Every task has a due date. A reminder is optional, must be future and cannot be
after the due date.

## Durable reminders

MySQL is the source of truth.

BullMQ queue:

`wapp-task-reminders`

A delayed job is created per reminder and a one-minute sweep reconciles due
tasks if Redis or a worker was unavailable at the original enqueue time.

Delivery uses an atomic reminder claim and deterministic notification dedupe.
Worker retry therefore does not intentionally produce duplicate reminders.

If the responsible membership becomes inactive before delivery, the reminder
is marked failed and remains visible on the task.

## Notifications

P3.3 extends P2.7 with:

- TASK_ASSIGNED
- TASK_REMINDER

Notification gets an optional `contactId`.

Deep-link priority:

1. linked ticket -> Conversations
2. otherwise linked contact -> Contacts

P3.3 also makes `/dashboard/contacts?contact=<id>` reliable, which closes the
same deep-link path used by P3.2 pipeline cards.

## RBAC

All roles can read and operate their own work.

AGENT can create tasks only for themselves and cannot reassign tasks or open
the team-wide agenda.

OWNER / ADMIN / SUPERVISOR can delegate, reassign and view team tasks.

## Immutable history

`CrmTaskEvent` records:

- CREATED
- UPDATED
- REASSIGNED
- COMPLETED
- CANCELLED
- REMINDER_SENT
- REMINDER_FAILED

## UI

Contact profile gets quick task creation and task history.

Global agenda:

`/dashboard/tasks`

It includes open/completed/cancelled views, overdue filtering, My Tasks, a
managerial Team view, and deep links to contact/ticket.

## Migration

P3.3 introduces:

- CrmTask
- CrmTaskEvent
- task enums
- Notification.contactId
EOF

echo "[P3.3] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P3.3] Unit tests..."
pnpm test

echo "[P3.3] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.3] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.3] CODE VALIDATION PASS."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
