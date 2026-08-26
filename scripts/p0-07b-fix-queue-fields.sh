#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEMA="apps/api/prisma/schema.prisma"

if [[ ! -f "$SCHEMA" ]]; then
  echo "ERROR: $SCHEMA not found."
  exit 1
fi

echo "[P0.7b] Repairing queue assignment fields and relations..."

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

function getModel(name) {
  const regex = new RegExp(`model ${name} \\{[\\s\\S]*?\\n\\}`);
  const match = schema.match(regex);

  if (!match) {
    throw new Error(`Model ${name} not found.`);
  }

  return match[0];
}

function replaceModel(name, transform) {
  const current = getModel(name);
  const next = transform(current);
  schema = schema.replace(current, next);
}

replaceModel("Ticket", model => {
  const hasQueueIdField =
    /^\s*queueId\s+String\?\s+@db\.Char\(36\)\s*$/m.test(model);

  const hasAssignedMembershipIdField =
    /^\s*assignedMembershipId\s+String\?\s+@db\.Char\(36\)\s*$/m.test(model);

  if (!hasQueueIdField || !hasAssignedMembershipIdField) {
    const contactField =
      /^(\s*contactId\s+String\s+@db\.Char\(36\)\s*)$/m;

    if (!contactField.test(model)) {
      throw new Error(
        "Could not find Ticket.contactId scalar field to insert queue assignment fields."
      );
    }

    const additions = [];

    if (!hasQueueIdField) {
      additions.push("  queueId              String?       @db.Char(36)");
    }

    if (!hasAssignedMembershipIdField) {
      additions.push(
        "  assignedMembershipId String?       @db.Char(36)"
      );
    }

    model = model.replace(
      contactField,
      `$1\n${additions.join("\n")}`
    );
  }

  if (!/^\s*queue\s+Queue\?\s+@relation\(/m.test(model)) {
    const contactRelation =
      /^(\s*contact\s+Contact\s+@relation\(fields: \[contactId\], references: \[id\], onDelete: Cascade\)\s*)$/m;

    if (!contactRelation.test(model)) {
      throw new Error(
        "Could not find Ticket.contact relation to insert Queue relation."
      );
    }

    model = model.replace(
      contactRelation,
      `$1\n  queue                Queue?        @relation(fields: [queueId], references: [id], onDelete: SetNull)`
    );
  }

  if (
    !/^\s*assignedMembership\s+CompanyMembership\?\s+@relation\(/m.test(
      model
    )
  ) {
    const queueRelation =
      /^(\s*queue\s+Queue\?\s+@relation\(fields: \[queueId\], references: \[id\], onDelete: SetNull\)\s*)$/m;

    if (!queueRelation.test(model)) {
      throw new Error(
        "Could not find Ticket.queue relation to insert assignedMembership relation."
      );
    }

    model = model.replace(
      queueRelation,
      `$1\n  assignedMembership   CompanyMembership? @relation(fields: [assignedMembershipId], references: [id], onDelete: SetNull)`
    );
  }

  if (!model.includes("@@index([companyId, queueId, status])")) {
    const contactIndex = "  @@index([contactId, status])";

    if (!model.includes(contactIndex)) {
      throw new Error(
        "Could not find Ticket contact index to insert queue index."
      );
    }

    model = model.replace(
      contactIndex,
      `${contactIndex}\n  @@index([companyId, queueId, status])`
    );
  }

  if (
    !model.includes(
      "@@index([companyId, assignedMembershipId, status])"
    )
  ) {
    const queueIndex =
      "  @@index([companyId, queueId, status])";

    model = model.replace(
      queueIndex,
      `${queueIndex}\n  @@index([companyId, assignedMembershipId, status])`
    );
  }

  return model;
});

replaceModel("CompanyMembership", model => {
  if (!/^\s*assignedTickets\s+Ticket\[\]\s*$/m.test(model)) {
    const sessions = /^(\s*sessions\s+Session\[\]\s*)$/m;

    if (!sessions.test(model)) {
      throw new Error(
        "Could not find CompanyMembership.sessions relation."
      );
    }

    model = model.replace(
      sessions,
      `$1\n  assignedTickets Ticket[]`
    );
  }

  if (!/^\s*queueMemberships\s+QueueMember\[\]\s*$/m.test(model)) {
    const assigned = /^(\s*assignedTickets\s+Ticket\[\]\s*)$/m;

    model = model.replace(
      assigned,
      `$1\n  queueMemberships QueueMember[]`
    );
  }

  return model;
});

replaceModel("WhatsAppConnection", model => {
  if (!/^\s*acceptGroups\s+Boolean\s+@default\(false\)\s*$/m.test(model)) {
    const lastEventAt = /^(\s*lastEventAt\s+DateTime\?\s*)$/m;

    if (!lastEventAt.test(model)) {
      throw new Error(
        "Could not find WhatsAppConnection.lastEventAt."
      );
    }

    model = model.replace(
      lastEventAt,
      `$1\n  acceptGroups  Boolean @default(false)`
    );
  }

  if (!/^\s*defaultQueueId\s+String\?\s+@db\.Char\(36\)\s*$/m.test(model)) {
    const acceptGroups =
      /^(\s*acceptGroups\s+Boolean\s+@default\(false\)\s*)$/m;

    model = model.replace(
      acceptGroups,
      `$1\n  defaultQueueId String? @db.Char(36)`
    );
  }

  if (!/^\s*defaultQueue\s+Queue\?\s+@relation\(/m.test(model)) {
    const companyRelation =
      /^(\s*company\s+Company\s+@relation\(fields: \[companyId\], references: \[id\], onDelete: Cascade\)\s*)$/m;

    if (!companyRelation.test(model)) {
      throw new Error(
        "Could not find WhatsAppConnection.company relation."
      );
    }

    model = model.replace(
      companyRelation,
      `$1\n  defaultQueue Queue? @relation(fields: [defaultQueueId], references: [id], onDelete: SetNull)`
    );
  }

  if (!model.includes("@@index([companyId, defaultQueueId])")) {
    const createdIndex = "  @@index([companyId, createdAt])";

    if (!model.includes(createdIndex)) {
      throw new Error(
        "Could not find WhatsAppConnection createdAt index."
      );
    }

    model = model.replace(
      createdIndex,
      `${createdIndex}\n  @@index([companyId, defaultQueueId])`
    );
  }

  return model;
});

if (!schema.includes("model Queue {")) {
  throw new Error(
    "Queue model was not created by P0.7. Do not continue automatically."
  );
}

if (!schema.includes("model QueueMember {")) {
  throw new Error(
    "QueueMember model was not created by P0.7. Do not continue automatically."
  );
}

replaceModel("Company", model => {
  if (!/^\s*queues\s+Queue\[\]\s*$/m.test(model)) {
    const messages = /^(\s*messages\s+Message\[\]\s*)$/m;

    if (!messages.test(model)) {
      throw new Error(
        "Could not find Company.messages relation."
      );
    }

    model = model.replace(
      messages,
      `$1\n  queues Queue[]`
    );
  }

  return model;
});

fs.writeFileSync(path, schema);
console.log("P0.7 Prisma assignment fields repaired.");
NODE

echo "[P0.7b] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P0.7b] Validating Prisma schema..."
pnpm --filter @wapp/api exec prisma validate

echo "[P0.7b] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P0.7b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.7b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7b] Repair complete."
echo
echo "Continue with:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name queues_assignment_realtime"
