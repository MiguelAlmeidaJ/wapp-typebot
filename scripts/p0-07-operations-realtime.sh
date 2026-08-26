#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.7] Building queues, assignment and realtime..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/messages/message-ingestion.service.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/whatsapp/whatsapp.service.ts" \
  "apps/web/components/auth-provider.tsx" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/dashboard/connections/page.tsx"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/queues \
  apps/api/src/modules/team \
  apps/api/src/modules/realtime \
  apps/web/app/dashboard/queues \
  apps/web/lib \
  docs

# ---------------------------------------------------------------------------
# Prisma models: queues, assignment and per-connection group policy
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

function modelBlock(name) {
  const regex = new RegExp(`model ${name} \\{[\\s\\S]*?\\n\\}`);
  const match = schema.match(regex);
  if (!match) throw new Error(`Model ${name} not found.`);
  return match[0];
}

function replaceModel(name, transform) {
  const current = modelBlock(name);
  const next = transform(current);
  schema = schema.replace(current, next);
}

replaceModel("Company", model => {
  if (!model.includes("queues")) {
    model = model.replace(
      "  messages            Message[]",
      "  messages            Message[]\n  queues              Queue[]"
    );
  }
  return model;
});

replaceModel("CompanyMembership", model => {
  if (!model.includes("queueMemberships")) {
    model = model.replace(
      "  sessions  Session[]",
      "  sessions         Session[]\n  queueMemberships QueueMember[]\n  assignedTickets  Ticket[]"
    );
  }
  return model;
});

replaceModel("WhatsAppConnection", model => {
  if (!model.includes("acceptGroups")) {
    model = model.replace(
      "  lastEventAt  DateTime?",
      "  lastEventAt  DateTime?\n  acceptGroups Boolean                  @default(false)\n  defaultQueueId String?                @db.Char(36)"
    );
  }

  if (!model.includes("defaultQueue  Queue?")) {
    model = model.replace(
      "  company      Company",
      "  company      Company"
    );
    model = model.replace(
      "  tickets      Ticket[]",
      "  defaultQueue Queue?                   @relation(fields: [defaultQueueId], references: [id], onDelete: SetNull)\n  tickets      Ticket[]"
    );
  }

  if (!model.includes("@@index([companyId, defaultQueueId])")) {
    model = model.replace(
      "  @@index([companyId, createdAt])",
      "  @@index([companyId, createdAt])\n  @@index([companyId, defaultQueueId])"
    );
  }

  return model;
});

replaceModel("Ticket", model => {
  if (!model.includes("queueId")) {
    model = model.replace(
      "  contactId            String        @db.Char(36)",
      "  contactId            String        @db.Char(36)\n  queueId              String?       @db.Char(36)\n  assignedMembershipId String?       @db.Char(36)"
    );
  }

  if (!model.includes("assignedMembership   CompanyMembership?")) {
    model = model.replace(
      "  contact              Contact       @relation(fields: [contactId], references: [id], onDelete: Cascade)",
      "  contact              Contact       @relation(fields: [contactId], references: [id], onDelete: Cascade)\n  queue                Queue?        @relation(fields: [queueId], references: [id], onDelete: SetNull)\n  assignedMembership   CompanyMembership? @relation(fields: [assignedMembershipId], references: [id], onDelete: SetNull)"
    );
  }

  if (!model.includes("@@index([companyId, queueId, status])")) {
    model = model.replace(
      "  @@index([contactId, status])",
      "  @@index([contactId, status])\n  @@index([companyId, queueId, status])\n  @@index([companyId, assignedMembershipId, status])"
    );
  }

  return model;
});

if (!schema.includes("model Queue {")) {
  schema += `\n\nmodel Queue {
  id                 String              @id @default(uuid()) @db.Char(36)
  companyId          String              @db.Char(36)
  name               String              @db.VarChar(120)
  isActive           Boolean             @default(true)
  company            Company             @relation(fields: [companyId], references: [id], onDelete: Cascade)
  members            QueueMember[]
  tickets            Ticket[]
  defaultConnections WhatsAppConnection[]
  createdAt          DateTime            @default(now())
  updatedAt          DateTime            @updatedAt

  @@unique([companyId, name])
  @@index([companyId, isActive])
}

model QueueMember {
  id           String            @id @default(uuid()) @db.Char(36)
  queueId      String            @db.Char(36)
  membershipId String            @db.Char(36)
  queue        Queue             @relation(fields: [queueId], references: [id], onDelete: Cascade)
  membership   CompanyMembership @relation(fields: [membershipId], references: [id], onDelete: Cascade)
  createdAt    DateTime          @default(now())

  @@unique([queueId, membershipId])
  @@index([membershipId])
}
`;
}

fs.writeFileSync(path, schema);
NODE

# ---------------------------------------------------------------------------
# Realtime event bus (in-memory for one API process)
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/realtime/realtime.bus.ts <<'EOF'
import { EventEmitter } from "node:events";
import { randomUUID } from "node:crypto";

export type RealtimeEventType =
  | "message.created"
  | "ticket.updated"
  | "ticket.created"
  | "queue.updated"
  | "connection.updated"
  | "presence.updated";

export interface RealtimeEvent {
  id: string;
  type: RealtimeEventType;
  occurredAt: string;
  ticketId?: string;
  messageId?: string;
  queueId?: string;
  connectionId?: string;
  membershipId?: string;
  online?: boolean;
}

const emitter = new EventEmitter();
emitter.setMaxListeners(0);

const presence = new Map<string, Map<string, number>>();

function companyChannel(companyId: string) {
  return `company:${companyId}`;
}

export function publishRealtime(
  companyId: string,
  event: Omit<RealtimeEvent, "id" | "occurredAt">
) {
  const payload: RealtimeEvent = {
    id: randomUUID(),
    occurredAt: new Date().toISOString(),
    ...event
  };

  emitter.emit(companyChannel(companyId), payload);
}

export function subscribeRealtime(
  companyId: string,
  listener: (event: RealtimeEvent) => void
) {
  const channel = companyChannel(companyId);
  emitter.on(channel, listener);

  return () => {
    emitter.off(channel, listener);
  };
}

export function markPresenceOnline(
  companyId: string,
  membershipId: string
) {
  const companyPresence = presence.get(companyId) ?? new Map<string, number>();
  const previous = companyPresence.get(membershipId) ?? 0;
  companyPresence.set(membershipId, previous + 1);
  presence.set(companyId, companyPresence);

  if (previous === 0) {
    publishRealtime(companyId, {
      type: "presence.updated",
      membershipId,
      online: true
    });
  }
}

export function markPresenceOffline(
  companyId: string,
  membershipId: string
) {
  const companyPresence = presence.get(companyId);
  if (!companyPresence) return;

  const previous = companyPresence.get(membershipId) ?? 0;

  if (previous <= 1) {
    companyPresence.delete(membershipId);

    publishRealtime(companyId, {
      type: "presence.updated",
      membershipId,
      online: false
    });
  } else {
    companyPresence.set(membershipId, previous - 1);
  }

  if (companyPresence.size === 0) {
    presence.delete(companyId);
  }
}

export function listOnlineMembershipIds(companyId: string) {
  return [...(presence.get(companyId)?.keys() ?? [])];
}
EOF


cat > apps/api/src/modules/realtime/realtime.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";

import { requireAuth } from "../auth/auth.guard.js";
import {
  listOnlineMembershipIds,
  markPresenceOffline,
  markPresenceOnline,
  subscribeRealtime,
  type RealtimeEvent
} from "./realtime.bus.js";

export async function realtimeRoutes(app: FastifyInstance) {
  app.get("/api/v1/realtime/presence", async request => {
    const auth = await requireAuth(request);

    return {
      membershipIds: listOnlineMembershipIds(auth.companyId)
    };
  });

  app.get("/api/v1/realtime/events", async (request, reply) => {
    const auth = await requireAuth(request);

    reply.hijack();

    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no"
    });

    const send = (event: RealtimeEvent) => {
      reply.raw.write(`data: ${JSON.stringify(event)}\n\n`);
    };

    const unsubscribe = subscribeRealtime(auth.companyId, send);
    markPresenceOnline(auth.companyId, auth.membershipId);

    reply.raw.write(
      `data: ${JSON.stringify({
        id: "ready",
        type: "realtime.ready",
        occurredAt: new Date().toISOString()
      })}\n\n`
    );

    const heartbeat = setInterval(() => {
      reply.raw.write(": heartbeat\n\n");
    }, 25_000);

    let closed = false;

    const cleanup = () => {
      if (closed) return;
      closed = true;
      clearInterval(heartbeat);
      unsubscribe();
      markPresenceOffline(auth.companyId, auth.membershipId);
    };

    reply.raw.once("close", cleanup);

    return reply;
  });
}
EOF


# ---------------------------------------------------------------------------
# Team and Queue domain
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/team/team.service.ts <<'EOF'
import { prisma } from "../../lib/database.js";

export async function listCompanyMemberships(companyId: string) {
  return prisma.companyMembership.findMany({
    where: {
      companyId,
      isActive: true,
      user: {
        isActive: true
      }
    },
    include: {
      user: {
        select: {
          id: true,
          name: true,
          email: true
        }
      }
    },
    orderBy: {
      user: {
        name: "asc"
      }
    }
  });
}
EOF

cat > apps/api/src/modules/team/team.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";

import { requireAuth } from "../auth/auth.guard.js";
import { listCompanyMemberships } from "./team.service.js";

export async function teamRoutes(app: FastifyInstance) {
  app.get("/api/v1/team/memberships", async request => {
    const auth = await requireAuth(request);

    return {
      memberships: await listCompanyMemberships(auth.companyId)
    };
  });
}
EOF

cat > apps/api/src/modules/queues/queue.service.ts <<'EOF'
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export async function listQueues(companyId: string) {
  return prisma.queue.findMany({
    where: {
      companyId,
      isActive: true
    },
    include: {
      members: {
        include: {
          membership: {
            include: {
              user: {
                select: {
                  id: true,
                  name: true,
                  email: true
                }
              }
            }
          }
        }
      },
      _count: {
        select: {
          tickets: true
        }
      }
    },
    orderBy: {
      name: "asc"
    }
  });
}

export async function createQueue(input: {
  companyId: string;
  name: string;
}) {
  const existing = await prisma.queue.findFirst({
    where: {
      companyId: input.companyId,
      name: input.name.trim()
    }
  });

  if (existing) {
    throw new AppError(
      "Já existe uma fila com este nome.",
      409,
      "QUEUE_ALREADY_EXISTS"
    );
  }

  const queue = await prisma.queue.create({
    data: {
      companyId: input.companyId,
      name: input.name.trim()
    }
  });

  publishRealtime(input.companyId, {
    type: "queue.updated",
    queueId: queue.id
  });

  return queue;
}

export async function replaceQueueMembers(input: {
  companyId: string;
  queueId: string;
  membershipIds: string[];
}) {
  const queue = await prisma.queue.findFirst({
    where: {
      id: input.queueId,
      companyId: input.companyId,
      isActive: true
    }
  });

  if (!queue) {
    throw new AppError(
      "Fila não encontrada.",
      404,
      "QUEUE_NOT_FOUND"
    );
  }

  const uniqueMembershipIds = [...new Set(input.membershipIds)];

  if (uniqueMembershipIds.length > 0) {
    const validMemberships = await prisma.companyMembership.count({
      where: {
        companyId: input.companyId,
        id: {
          in: uniqueMembershipIds
        },
        isActive: true,
        user: {
          isActive: true
        }
      }
    });

    if (validMemberships !== uniqueMembershipIds.length) {
      throw new AppError(
        "Um ou mais atendentes não pertencem à empresa ativa.",
        422,
        "INVALID_QUEUE_MEMBERS"
      );
    }
  }

  await prisma.$transaction(async tx => {
    await tx.queueMember.deleteMany({
      where: {
        queueId: queue.id
      }
    });

    if (uniqueMembershipIds.length > 0) {
      await tx.queueMember.createMany({
        data: uniqueMembershipIds.map(membershipId => ({
          queueId: queue.id,
          membershipId
        }))
      });
    }
  });

  publishRealtime(input.companyId, {
    type: "queue.updated",
    queueId: queue.id
  });

  return listQueues(input.companyId);
}
EOF

cat > apps/api/src/modules/queues/queue.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth, requireRoles } from "../auth/auth.guard.js";
import {
  createQueue,
  listQueues,
  replaceQueueMembers
} from "./queue.service.js";

const queueIdSchema = z.object({
  id: z.string().uuid()
});

const createQueueSchema = z.object({
  name: z.string().trim().min(2).max(120)
});

const queueMembersSchema = z.object({
  membershipIds: z.array(z.string().uuid()).max(500)
});

export async function queueRoutes(app: FastifyInstance) {
  app.get("/api/v1/queues", async request => {
    const auth = await requireAuth(request);

    return {
      queues: await listQueues(auth.companyId)
    };
  });

  app.post("/api/v1/queues", async (request, reply) => {
    const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
    const input = createQueueSchema.parse(request.body);

    return reply.status(201).send({
      queue: await createQueue({
        companyId: auth.companyId,
        name: input.name
      })
    });
  });

  app.put("/api/v1/queues/:id/members", async request => {
    const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
    const params = queueIdSchema.parse(request.params);
    const input = queueMembersSchema.parse(request.body);

    return {
      queues: await replaceQueueMembers({
        companyId: auth.companyId,
        queueId: params.id,
        membershipIds: input.membershipIds
      })
    };
  });
}
EOF

# ---------------------------------------------------------------------------
# WhatsApp connection settings: groups + default queue
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/whatsapp/whatsapp.service.ts <<'EOF'
import { randomBytes } from "node:crypto";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

function normalizeInstancePart(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 45);
}

function instanceName(companySlug: string, name: string) {
  const company = normalizeInstancePart(companySlug) || "company";
  const connection = normalizeInstancePart(name) || "whatsapp";
  const suffix = randomBytes(4).toString("hex");

  return `wapp-${company}-${connection}-${suffix}`.slice(0, 100);
}

function webhookUrl() {
  return `${env.EVOLUTION_WEBHOOK_BASE_URL}/api/v1/webhooks/evolution/${env.EVOLUTION_WEBHOOK_SECRET}`;
}

function mapEvolutionState(
  state: string
): "CREATED" | "CONNECTING" | "CONNECTED" | "DISCONNECTED" | "ERROR" {
  switch (state.toLowerCase()) {
    case "open":
    case "connected":
      return "CONNECTED";
    case "connecting":
      return "CONNECTING";
    case "close":
    case "closed":
    case "disconnected":
      return "DISCONNECTED";
    default:
      return "CREATED";
  }
}

export async function listConnections(companyId: string) {
  return prisma.whatsAppConnection.findMany({
    where: {
      companyId
    },
    include: {
      defaultQueue: {
        select: {
          id: true,
          name: true
        }
      }
    },
    orderBy: {
      createdAt: "desc"
    }
  });
}

export async function createConnection(input: {
  companyId: string;
  companySlug: string;
  name: string;
}) {
  const generatedInstanceName = instanceName(
    input.companySlug,
    input.name
  );

  const connection = await prisma.whatsAppConnection.create({
    data: {
      companyId: input.companyId,
      name: input.name.trim(),
      instanceName: generatedInstanceName,
      provider: "EVOLUTION_BAILEYS",
      status: "CREATED",
      acceptGroups: false
    }
  });

  try {
    const qr = await evolutionWhatsAppClient.createInstance({
      instanceName: generatedInstanceName,
      webhookUrl: webhookUrl()
    });

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: "CONNECTING",
        lastError: null,
        lastEventAt: new Date()
      }
    });

    return {
      connection: {
        ...connection,
        status: "CONNECTING" as const
      },
      qr
    };
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Evolution API error";

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: "ERROR",
        lastError: message,
        lastEventAt: new Date()
      }
    });

    throw error;
  }
}

export async function getCompanyConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await prisma.whatsAppConnection.findFirst({
    where: {
      id: connectionId,
      companyId
    }
  });

  if (!connection) {
    throw new AppError(
      "Conexão WhatsApp não encontrada.",
      404,
      "WHATSAPP_CONNECTION_NOT_FOUND"
    );
  }

  return connection;
}

export async function updateConnectionSettings(input: {
  companyId: string;
  connectionId: string;
  acceptGroups?: boolean;
  defaultQueueId?: string | null;
}) {
  await getCompanyConnection(input.companyId, input.connectionId);

  if (input.defaultQueueId) {
    const queue = await prisma.queue.findFirst({
      where: {
        id: input.defaultQueueId,
        companyId: input.companyId,
        isActive: true
      }
    });

    if (!queue) {
      throw new AppError(
        "Fila padrão não encontrada.",
        404,
        "DEFAULT_QUEUE_NOT_FOUND"
      );
    }
  }

  const connection = await prisma.whatsAppConnection.update({
    where: {
      id: input.connectionId
    },
    data: {
      ...(input.acceptGroups !== undefined
        ? { acceptGroups: input.acceptGroups }
        : {}),
      ...(input.defaultQueueId !== undefined
        ? { defaultQueueId: input.defaultQueueId }
        : {})
    },
    include: {
      defaultQueue: {
        select: {
          id: true,
          name: true
        }
      }
    }
  });

  publishRealtime(input.companyId, {
    type: "connection.updated",
    connectionId: connection.id
  });

  return connection;
}

export async function connectConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await getCompanyConnection(
    companyId,
    connectionId
  );

  const qr = await evolutionWhatsAppClient.connect(
    connection.instanceName
  );

  await prisma.whatsAppConnection.update({
    where: {
      id: connection.id
    },
    data: {
      status: "CONNECTING",
      lastError: null,
      lastEventAt: new Date()
    }
  });

  return {
    qr
  };
}

export async function syncConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await getCompanyConnection(
    companyId,
    connectionId
  );

  try {
    const state = await evolutionWhatsAppClient.connectionState(
      connection.instanceName
    );

    const updated = await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: mapEvolutionState(state.state),
        lastError: null,
        lastEventAt: new Date()
      }
    });

    publishRealtime(companyId, {
      type: "connection.updated",
      connectionId: connection.id
    });

    return updated;
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Evolution API error";

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        lastError: message,
        lastEventAt: new Date()
      }
    });

    throw error;
  }
}

export async function sendTestMessage(input: {
  companyId: string;
  connectionId: string;
  number: string;
  text: string;
}) {
  const connection = await getCompanyConnection(
    input.companyId,
    input.connectionId
  );

  if (connection.status !== "CONNECTED") {
    throw new AppError(
      "Conecte o WhatsApp antes de enviar mensagens.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  return evolutionWhatsAppClient.sendText({
    instanceName: connection.instanceName,
    number: input.number,
    text: input.text
  });
}
EOF

cat > apps/api/src/modules/whatsapp/whatsapp.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import {
  requireAuth,
  requireRoles
} from "../auth/auth.guard.js";
import {
  connectConnection,
  createConnection,
  listConnections,
  sendTestMessage,
  syncConnection,
  updateConnectionSettings
} from "./whatsapp.service.js";

const connectionIdSchema = z.object({
  id: z.string().uuid()
});

const createConnectionSchema = z.object({
  name: z.string().trim().min(2).max(120)
});

const connectionSettingsSchema = z.object({
  acceptGroups: z.boolean().optional(),
  defaultQueueId: z.string().uuid().nullable().optional()
});

const testMessageSchema = z.object({
  number: z
    .string()
    .trim()
    .regex(/^\d{10,15}$/, "Use somente números com DDI e DDD."),
  text: z.string().trim().min(1).max(4096)
});

export async function whatsappRoutes(app: FastifyInstance) {
  app.get("/api/v1/whatsapp/connections", async request => {
    const auth = await requireAuth(request);

    return {
      connections: await listConnections(auth.companyId)
    };
  });

  app.post("/api/v1/whatsapp/connections", async (request, reply) => {
    const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
    const input = createConnectionSchema.parse(request.body);

    const result = await createConnection({
      companyId: auth.companyId,
      companySlug: auth.company.slug,
      name: input.name
    });

    return reply.status(201).send(result);
  });

  app.patch(
    "/api/v1/whatsapp/connections/:id/settings",
    async request => {
      const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
      const params = connectionIdSchema.parse(request.params);
      const input = connectionSettingsSchema.parse(request.body);

      return {
        connection: await updateConnectionSettings({
          companyId: auth.companyId,
          connectionId: params.id,
          ...input
        })
      };
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/connect",
    async request => {
      const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
      const params = connectionIdSchema.parse(request.params);

      return connectConnection(auth.companyId, params.id);
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/sync",
    async request => {
      const auth = await requireAuth(request);
      const params = connectionIdSchema.parse(request.params);

      return {
        connection: await syncConnection(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/test-message",
    async request => {
      const auth = await requireRoles(request, [
        "OWNER",
        "ADMIN",
        "SUPERVISOR"
      ]);

      const params = connectionIdSchema.parse(request.params);
      const input = testMessageSchema.parse(request.body);

      return {
        result: await sendTestMessage({
          companyId: auth.companyId,
          connectionId: params.id,
          number: input.number,
          text: input.text
        })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Message ingestion: group policy, pending queue and realtime
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/messages/message-ingestion.service.ts <<'EOF'
import type { WhatsAppConnection } from "../../generated/prisma/client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import {
  parseEvolutionMessage,
  type ParsedEvolutionMessage
} from "./evolution-message.parser.js";

function activeTicketKey(
  connectionId: string,
  contactId: string
) {
  return `${connectionId}:${contactId}`;
}

function displayName(message: ParsedEvolutionMessage) {
  if (message.isGroup) {
    return `Grupo ${message.remoteJid.split("@")[0]}`;
  }

  return (
    message.pushName ??
    message.phoneNumber ??
    message.remoteJid.split("@")[0] ??
    "Contato"
  );
}

function preview(message: ParsedEvolutionMessage) {
  return message.body ?? `[${message.type.toLowerCase()}]`;
}

export async function ingestEvolutionMessage(
  payload: Record<string, unknown>,
  connection: WhatsAppConnection
) {
  const parsed = parseEvolutionMessage(payload);

  if (!parsed) {
    return {
      ignored: true,
      reason: "unsupported_or_non_message"
    };
  }

  if (parsed.isGroup && !connection.acceptGroups) {
    return {
      ignored: true,
      reason: "groups_disabled_for_connection"
    };
  }

  const existing = await prisma.message.findUnique({
    where: {
      whatsappConnectionId_externalId: {
        whatsappConnectionId: connection.id,
        externalId: parsed.externalId
      }
    }
  });

  if (existing) {
    return {
      ignored: true,
      reason: "duplicate",
      messageId: existing.id
    };
  }

  const contact = await prisma.contact.upsert({
    where: {
      companyId_remoteJid: {
        companyId: connection.companyId,
        remoteJid: parsed.remoteJid
      }
    },
    update: {
      ...(parsed.pushName && !parsed.isGroup
        ? { name: parsed.pushName }
        : {}),
      ...(parsed.phoneNumber
        ? { phoneNumber: parsed.phoneNumber }
        : {}),
      lastSeenAt: parsed.fromMe ? undefined : parsed.timestamp
    },
    create: {
      companyId: connection.companyId,
      remoteJid: parsed.remoteJid,
      phoneNumber: parsed.phoneNumber,
      name: displayName(parsed),
      isGroup: parsed.isGroup,
      lastSeenAt: parsed.fromMe ? undefined : parsed.timestamp
    }
  });

  const key = activeTicketKey(connection.id, contact.id);
  const before = await prisma.ticket.findUnique({
    where: {
      activeKey: key
    },
    select: {
      id: true
    }
  });

  const ticket = await prisma.ticket.upsert({
    where: {
      activeKey: key
    },
    update: {},
    create: {
      companyId: connection.companyId,
      whatsappConnectionId: connection.id,
      contactId: contact.id,
      queueId: connection.defaultQueueId,
      activeKey: key,
      status: parsed.fromMe ? "OPEN" : "PENDING",
      lastMessageAt: parsed.timestamp
    }
  });

  const message = await prisma.message.create({
    data: {
      companyId: connection.companyId,
      ticketId: ticket.id,
      whatsappConnectionId: connection.id,
      externalId: parsed.externalId,
      direction: parsed.fromMe ? "OUTBOUND" : "INBOUND",
      type: parsed.type,
      body: parsed.body,
      mediaMimeType: parsed.mediaMimeType,
      mediaFileName: parsed.mediaFileName,
      quotedExternalId: parsed.quotedExternalId,
      timestamp: parsed.timestamp,
      rawPayload: toPrismaJson(parsed.rawPayload)
    }
  });

  await prisma.ticket.update({
    where: {
      id: ticket.id
    },
    data: {
      lastMessage: preview(parsed),
      lastMessageAt: parsed.timestamp,
      ...(parsed.fromMe
        ? {}
        : {
            unreadCount: {
              increment: 1
            }
          })
    }
  });

  if (!before) {
    publishRealtime(connection.companyId, {
      type: "ticket.created",
      ticketId: ticket.id
    });
  }

  publishRealtime(connection.companyId, {
    type: "message.created",
    ticketId: ticket.id,
    messageId: message.id
  });

  return {
    ignored: false,
    ticketId: ticket.id,
    contactId: contact.id,
    messageId: message.id
  };
}
EOF

# ---------------------------------------------------------------------------
# Ticket assignment, transfer and active lists
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tickets/ticket.service.ts <<'EOF'
import { randomUUID } from "node:crypto";

import { AppError } from "../../errors/app-error.js";
import type { Prisma } from "../../generated/prisma/client.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import type { WappRole } from "../../lib/tokens.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export type TicketListStatus =
  | "ACTIVE"
  | "OPEN"
  | "PENDING"
  | "CLOSED";

const ticketInclude = {
  contact: true,
  whatsappConnection: {
    select: {
      id: true,
      name: true,
      status: true,
      phoneNumber: true
    }
  },
  queue: {
    select: {
      id: true,
      name: true
    }
  },
  assignedMembership: {
    include: {
      user: {
        select: {
          id: true,
          name: true,
          email: true
        }
      }
    }
  },
  messages: {
    orderBy: {
      timestamp: "desc"
    },
    take: 1,
    select: {
      id: true,
      direction: true,
      type: true,
      body: true,
      timestamp: true
    }
  }
} satisfies Prisma.TicketInclude;

function getObject(value: unknown) {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : undefined;
}

function getString(value: unknown) {
  return typeof value === "string" && value.length > 0
    ? value
    : undefined;
}

function sentExternalId(result: unknown) {
  const body = getObject(result);
  const key = getObject(body?.key);

  return getString(key?.id) ?? `wapp-local-${randomUUID()}`;
}

function sentTimestamp(result: unknown) {
  const body = getObject(result);
  const raw = body?.messageTimestamp;

  const seconds =
    typeof raw === "number"
      ? raw
      : typeof raw === "string"
        ? Number(raw)
        : NaN;

  return Number.isFinite(seconds)
    ? new Date(seconds * 1000)
    : new Date();
}

function canOverrideAssignment(role: WappRole) {
  return role === "OWNER" || role === "ADMIN" || role === "SUPERVISOR";
}

function assertCanOperateTicket(
  assignedMembershipId: string | null,
  actorMembershipId: string,
  role: WappRole
) {
  if (
    assignedMembershipId &&
    assignedMembershipId !== actorMembershipId &&
    !canOverrideAssignment(role)
  ) {
    throw new AppError(
      "Este atendimento está atribuído a outro atendente.",
      403,
      "TICKET_ASSIGNED_TO_ANOTHER_AGENT"
    );
  }
}

export async function listTickets(
  companyId: string,
  status: TicketListStatus
) {
  const where: Prisma.TicketWhereInput = {
    companyId,
    ...(status === "ACTIVE"
      ? {
          status: {
            in: ["OPEN", "PENDING"]
          }
        }
      : { status })
  };

  return prisma.ticket.findMany({
    where,
    include: ticketInclude,
    orderBy: {
      lastMessageAt: "desc"
    },
    take: 200
  });
}

export async function getTicket(
  companyId: string,
  ticketId: string
) {
  const ticket = await prisma.ticket.findFirst({
    where: {
      id: ticketId,
      companyId
    },
    include: {
      contact: true,
      whatsappConnection: true,
      queue: true,
      assignedMembership: {
        include: {
          user: true
        }
      }
    }
  });

  if (!ticket) {
    throw new AppError(
      "Atendimento não encontrado.",
      404,
      "TICKET_NOT_FOUND"
    );
  }

  return ticket;
}

async function validateMembership(
  companyId: string,
  membershipId: string
) {
  const membership = await prisma.companyMembership.findFirst({
    where: {
      id: membershipId,
      companyId,
      isActive: true,
      user: {
        isActive: true
      }
    }
  });

  if (!membership) {
    throw new AppError(
      "Atendente não encontrado na empresa ativa.",
      422,
      "INVALID_ASSIGNEE"
    );
  }

  return membership;
}

async function validateQueue(
  companyId: string,
  queueId: string
) {
  const queue = await prisma.queue.findFirst({
    where: {
      id: queueId,
      companyId,
      isActive: true
    }
  });

  if (!queue) {
    throw new AppError(
      "Fila não encontrada.",
      422,
      "INVALID_QUEUE"
    );
  }

  return queue;
}

async function validateQueueMembership(
  queueId: string,
  membershipId: string,
  allowOverride = false
) {
  const membersCount = await prisma.queueMember.count({
    where: { queueId }
  });

  if (membersCount === 0 || allowOverride) {
    return;
  }

  const link = await prisma.queueMember.findUnique({
    where: {
      queueId_membershipId: {
        queueId,
        membershipId
      }
    }
  });

  if (!link) {
    throw new AppError(
      "Você não pertence à fila deste atendimento.",
      403,
      "AGENT_NOT_IN_QUEUE"
    );
  }
}

export async function listTicketMessages(
  companyId: string,
  ticketId: string
) {
  await getTicket(companyId, ticketId);

  return prisma.message.findMany({
    where: {
      companyId,
      ticketId
    },
    orderBy: {
      timestamp: "asc"
    },
    take: 200
  });
}

export async function markTicketRead(
  companyId: string,
  ticketId: string
) {
  await getTicket(companyId, ticketId);

  return prisma.ticket.update({
    where: { id: ticketId },
    data: { unreadCount: 0 }
  });
}

export async function claimTicket(input: {
  companyId: string;
  ticketId: string;
  membershipId: string;
  role: WappRole;
}) {
  const ticket = await getTicket(input.companyId, input.ticketId);

  if (ticket.status === "CLOSED") {
    throw new AppError(
      "Este atendimento já foi encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.membershipId,
    input.role
  );

  await validateMembership(input.companyId, input.membershipId);

  if (ticket.queueId) {
    await validateQueueMembership(
      ticket.queueId,
      input.membershipId,
      canOverrideAssignment(input.role)
    );
  }

  const updated = await prisma.ticket.update({
    where: { id: ticket.id },
    data: {
      assignedMembershipId: input.membershipId,
      status: "OPEN"
    },
    include: ticketInclude
  });

  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: ticket.id
  });

  return updated;
}

export async function transferTicket(input: {
  companyId: string;
  ticketId: string;
  actorMembershipId: string;
  role: WappRole;
  queueId?: string | null;
  membershipId?: string | null;
}) {
  const ticket = await getTicket(input.companyId, input.ticketId);

  if (ticket.status === "CLOSED") {
    throw new AppError(
      "Este atendimento já foi encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.actorMembershipId,
    input.role
  );

  const queueId =
    input.queueId === undefined ? ticket.queueId : input.queueId;
  const membershipId =
    input.membershipId === undefined
      ? ticket.assignedMembershipId
      : input.membershipId;

  if (queueId) {
    await validateQueue(input.companyId, queueId);
  }

  if (membershipId) {
    await validateMembership(input.companyId, membershipId);

    if (queueId) {
      const configuredMembers = await prisma.queueMember.count({
        where: { queueId }
      });

      if (configuredMembers > 0) {
        const link = await prisma.queueMember.findUnique({
          where: {
            queueId_membershipId: {
              queueId,
              membershipId
            }
          }
        });

        if (!link) {
          throw new AppError(
            "O atendente escolhido não pertence a esta fila.",
            422,
            "ASSIGNEE_NOT_IN_QUEUE"
          );
        }
      }
    }
  }

  const updated = await prisma.ticket.update({
    where: { id: ticket.id },
    data: {
      queueId,
      assignedMembershipId: membershipId,
      status: membershipId ? "OPEN" : "PENDING"
    },
    include: ticketInclude
  });

  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: ticket.id
  });

  return updated;
}

export async function closeTicket(input: {
  companyId: string;
  ticketId: string;
  membershipId: string;
  role: WappRole;
}) {
  const current = await getTicket(input.companyId, input.ticketId);

  assertCanOperateTicket(
    current.assignedMembershipId,
    input.membershipId,
    input.role
  );

  const ticket = await prisma.ticket.update({
    where: { id: input.ticketId },
    data: {
      status: "CLOSED",
      activeKey: null,
      unreadCount: 0,
      closedAt: new Date()
    }
  });

  publishRealtime(input.companyId, {
    type: "ticket.updated",
    ticketId: input.ticketId
  });

  return ticket;
}

export async function sendTicketText(input: {
  companyId: string;
  ticketId: string;
  userId: string;
  membershipId: string;
  role: WappRole;
  text: string;
}) {
  let ticket = await getTicket(input.companyId, input.ticketId);

  if (ticket.status === "CLOSED") {
    throw new AppError(
      "Este atendimento já foi encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.membershipId,
    input.role
  );

  if (!ticket.assignedMembershipId) {
    await claimTicket({
      companyId: input.companyId,
      ticketId: ticket.id,
      membershipId: input.membershipId,
      role: input.role
    });

    ticket = await getTicket(input.companyId, input.ticketId);
  }

  if (ticket.whatsappConnection.status !== "CONNECTED") {
    throw new AppError(
      "A conexão WhatsApp deste atendimento está offline.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  const result = await evolutionWhatsAppClient.sendText({
    instanceName: ticket.whatsappConnection.instanceName,
    number: ticket.contact.remoteJid,
    text: input.text
  });

  const timestamp = sentTimestamp(result);
  const externalId = sentExternalId(result);

  const message = await prisma.message.upsert({
    where: {
      whatsappConnectionId_externalId: {
        whatsappConnectionId: ticket.whatsappConnectionId,
        externalId
      }
    },
    update: {},
    create: {
      companyId: input.companyId,
      ticketId: ticket.id,
      whatsappConnectionId: ticket.whatsappConnectionId,
      sentByUserId: input.userId,
      externalId,
      direction: "OUTBOUND",
      type: "TEXT",
      body: input.text,
      timestamp,
      rawPayload: toPrismaJson(result)
    }
  });

  await prisma.ticket.update({
    where: { id: ticket.id },
    data: {
      lastMessage: input.text,
      lastMessageAt: timestamp
    }
  });

  publishRealtime(input.companyId, {
    type: "message.created",
    ticketId: ticket.id,
    messageId: message.id
  });

  return message;
}
EOF


cat > apps/api/src/modules/tickets/ticket.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../auth/auth.guard.js";
import {
  claimTicket,
  closeTicket,
  listTicketMessages,
  listTickets,
  markTicketRead,
  sendTicketText,
  transferTicket
} from "./ticket.service.js";

const ticketIdSchema = z.object({
  id: z.string().uuid()
});

const listSchema = z.object({
  status: z
    .enum(["ACTIVE", "OPEN", "PENDING", "CLOSED"])
    .default("ACTIVE")
});

const sendTextSchema = z.object({
  text: z.string().trim().min(1).max(4096)
});

const transferSchema = z.object({
  queueId: z.string().uuid().nullable().optional(),
  membershipId: z.string().uuid().nullable().optional()
});

export async function ticketRoutes(app: FastifyInstance) {
  app.get("/api/v1/tickets", async request => {
    const auth = await requireAuth(request);
    const query = listSchema.parse(request.query);

    return {
      tickets: await listTickets(auth.companyId, query.status)
    };
  });

  app.get(
    "/api/v1/tickets/:id/messages",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        messages: await listTicketMessages(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/read",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        ticket: await markTicketRead(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/claim",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        ticket: await claimTicket({
          companyId: auth.companyId,
          ticketId: params.id,
          membershipId: auth.membershipId,
          role: auth.role
        })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/transfer",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);
      const input = transferSchema.parse(request.body);

      return {
        ticket: await transferTicket({
          companyId: auth.companyId,
          ticketId: params.id,
          actorMembershipId: auth.membershipId,
          role: auth.role,
          ...input
        })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/close",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        ticket: await closeTicket({
          companyId: auth.companyId,
          ticketId: params.id,
          membershipId: auth.membershipId,
          role: auth.role
        })
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/messages",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);
      const input = sendTextSchema.parse(request.body);

      return {
        message: await sendTicketText({
          companyId: auth.companyId,
          ticketId: params.id,
          userId: auth.userId,
          membershipId: auth.membershipId,
          role: auth.role,
          text: input.text
        })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Evolution webhook: connection and message events feed realtime
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/webhooks/evolution-webhook.routes.ts <<'EOF'
import { timingSafeEqual } from "node:crypto";

import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { ingestEvolutionMessage } from "../messages/message-ingestion.service.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

const paramsSchema = z.object({
  secret: z.string().min(1)
});

function secretsMatch(received: string, expected: string) {
  const receivedBuffer = Buffer.from(received);
  const expectedBuffer = Buffer.from(expected);

  return (
    receivedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(receivedBuffer, expectedBuffer)
  );
}

function normalizeEvent(value: unknown) {
  return String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/[.\-\s]+/g, "_");
}

function getInstanceName(body: Record<string, unknown>) {
  if (typeof body.instance === "string") {
    return body.instance;
  }

  if (typeof body.instanceName === "string") {
    return body.instanceName;
  }

  const data = body.data;

  if (data && typeof data === "object") {
    const dataRecord = data as Record<string, unknown>;

    if (typeof dataRecord.instance === "string") {
      return dataRecord.instance;
    }

    if (typeof dataRecord.instanceName === "string") {
      return dataRecord.instanceName;
    }
  }

  return undefined;
}

function connectionState(body: Record<string, unknown>) {
  const data = body.data;

  if (!data || typeof data !== "object") {
    return undefined;
  }

  const record = data as Record<string, unknown>;

  if (typeof record.state === "string") {
    return record.state;
  }

  if (typeof record.status === "string") {
    return record.status;
  }

  return undefined;
}

function mapState(state: string | undefined) {
  switch (state?.toLowerCase()) {
    case "open":
    case "connected":
      return "CONNECTED" as const;
    case "connecting":
      return "CONNECTING" as const;
    case "close":
    case "closed":
    case "disconnected":
      return "DISCONNECTED" as const;
    default:
      return undefined;
  }
}

export async function evolutionWebhookRoutes(
  app: FastifyInstance
) {
  app.post(
    "/api/v1/webhooks/evolution/:secret",
    async (request, reply) => {
      const params = paramsSchema.parse(request.params);

      if (
        !secretsMatch(
          params.secret,
          env.EVOLUTION_WEBHOOK_SECRET
        )
      ) {
        throw new AppError(
          "Webhook não autorizado.",
          401,
          "WEBHOOK_UNAUTHORIZED"
        );
      }

      if (!request.body || typeof request.body !== "object") {
        return reply.status(204).send();
      }

      const body = request.body as Record<string, unknown>;
      const event = normalizeEvent(body.event);
      const instance = getInstanceName(body);

      if (!instance) {
        request.log.warn(
          { event },
          "Evolution webhook without instance name"
        );
        return reply.status(204).send();
      }

      const connection = await prisma.whatsAppConnection.findUnique({
        where: {
          instanceName: instance
        }
      });

      if (!connection) {
        request.log.warn(
          { event, instance },
          "Evolution webhook for unknown instance"
        );
        return reply.status(204).send();
      }

      if (event === "CONNECTION_UPDATE") {
        const mappedState = mapState(connectionState(body));

        if (mappedState) {
          const data =
            body.data && typeof body.data === "object"
              ? (body.data as Record<string, unknown>)
              : {};

          const owner =
            typeof data.wuid === "string"
              ? data.wuid
              : typeof data.number === "string"
                ? data.number
                : undefined;

          await prisma.whatsAppConnection.update({
            where: {
              id: connection.id
            },
            data: {
              status: mappedState,
              phoneNumber: owner?.replace(/\D/g, "") || undefined,
              lastError: null,
              lastEventAt: new Date()
            }
          });

          publishRealtime(connection.companyId, {
            type: "connection.updated",
            connectionId: connection.id
          });
        }
      } else if (event === "MESSAGES_UPSERT") {
        const result = await ingestEvolutionMessage(
          body,
          connection
        );

        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance,
            result
          },
          "Evolution message processed"
        );
      } else {
        await prisma.whatsAppConnection.update({
          where: {
            id: connection.id
          },
          data: {
            lastEventAt: new Date()
          }
        });
      }

      return {
        received: true
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register backend routes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/app.ts";
let content = fs.readFileSync(path, "utf8");

const imports = [
  'import { queueRoutes } from "./modules/queues/queue.routes.js";',
  'import { realtimeRoutes } from "./modules/realtime/realtime.routes.js";',
  'import { teamRoutes } from "./modules/team/team.routes.js";'
];

const importAnchor =
  'import { ticketRoutes } from "./modules/tickets/ticket.routes.js";';

if (!content.includes(importAnchor)) {
  throw new Error("ticketRoutes import anchor not found.");
}

for (const line of imports) {
  if (!content.includes(line)) {
    content = content.replace(importAnchor, `${importAnchor}\n${line}`);
  }
}

const registerAnchor = "  await app.register(ticketRoutes);";
if (!content.includes(registerAnchor)) {
  throw new Error("ticketRoutes register anchor not found.");
}

for (const line of [
  "  await app.register(queueRoutes);",
  "  await app.register(teamRoutes);",
  "  await app.register(realtimeRoutes);"
]) {
  if (!content.includes(line)) {
    content = content.replace(registerAnchor, `${registerAnchor}\n${line}`);
  }
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Auth provider: authenticated SSE stream with refresh support
# ---------------------------------------------------------------------------

cat > apps/web/lib/realtime-types.ts <<'EOF'
export type RealtimeEventType =
  | "realtime.ready"
  | "message.created"
  | "ticket.updated"
  | "ticket.created"
  | "queue.updated"
  | "connection.updated"
  | "presence.updated";

export interface RealtimeEvent {
  id: string;
  type: RealtimeEventType;
  occurredAt: string;
  ticketId?: string;
  messageId?: string;
  queueId?: string;
  connectionId?: string;
  membershipId?: string;
  online?: boolean;
}
EOF

cat > apps/web/components/auth-provider.tsx <<'EOF'
"use client";

import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";

import {
  ApiError,
  apiFetch,
  expectJson
} from "@/lib/api";
import type {
  AuthSession,
  CompanyRequiredDetails,
  LoginResponse,
  RefreshResponse
} from "@/lib/auth-types";
import type { RealtimeEvent } from "@/lib/realtime-types";

interface LoginInput {
  email: string;
  password: string;
  companySlug?: string;
}

interface AuthContextValue {
  session: AuthSession | null;
  loading: boolean;
  login(input: LoginInput): Promise<void>;
  logout(): Promise<void>;
  request<T>(path: string, init?: RequestInit): Promise<T>;
  subscribe(
    path: string,
    onEvent: (event: RealtimeEvent) => void
  ): () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

async function refreshAccessToken(): Promise<string> {
  const response = await apiFetch("/api/v1/auth/refresh", {
    method: "POST"
  });

  const payload = await expectJson<RefreshResponse>(response);
  return payload.accessToken;
}

function wait(milliseconds: number) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const accessTokenRef = useRef<string | null>(null);
  const refreshPromiseRef = useRef<Promise<string> | null>(null);

  const [session, setSession] = useState<AuthSession | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshToken = useCallback(async () => {
    if (!refreshPromiseRef.current) {
      refreshPromiseRef.current = refreshAccessToken().finally(() => {
        refreshPromiseRef.current = null;
      });
    }

    const accessToken = await refreshPromiseRef.current;
    accessTokenRef.current = accessToken;
    return accessToken;
  }, []);

  const authenticatedFetch = useCallback(
    async (path: string, init: RequestInit = {}) => {
      let accessToken = accessTokenRef.current;

      if (!accessToken) {
        accessToken = await refreshToken();
      }

      const execute = (token: string) =>
        apiFetch(path, {
          ...init,
          headers: {
            ...init.headers,
            Authorization: `Bearer ${token}`
          }
        });

      let response = await execute(accessToken);

      if (response.status === 401) {
        accessToken = await refreshToken();
        response = await execute(accessToken);
      }

      return response;
    },
    [refreshToken]
  );

  const loadSession = useCallback(async () => {
    const response = await authenticatedFetch("/api/v1/auth/me");
    const payload = await expectJson<AuthSession>(response);
    setSession(payload);
    return payload;
  }, [authenticatedFetch]);

  useEffect(() => {
    let active = true;

    async function bootstrap() {
      try {
        await refreshToken();

        if (!active) {
          return;
        }

        await loadSession();
      } catch {
        accessTokenRef.current = null;

        if (active) {
          setSession(null);
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    }

    void bootstrap();

    return () => {
      active = false;
    };
  }, [loadSession, refreshToken]);

  const login = useCallback(
    async (input: LoginInput) => {
      const response = await apiFetch("/api/v1/auth/login", {
        method: "POST",
        body: JSON.stringify(input)
      });

      const payload = await expectJson<LoginResponse>(response);

      accessTokenRef.current = payload.accessToken;
      setSession({
        user: payload.user,
        company: payload.company,
        role: payload.role
      });
    },
    []
  );

  const logout = useCallback(async () => {
    try {
      await apiFetch("/api/v1/auth/logout", {
        method: "POST"
      });
    } finally {
      accessTokenRef.current = null;
      setSession(null);
    }
  }, []);

  const request = useCallback(
    async <T,>(path: string, init: RequestInit = {}) => {
      const response = await authenticatedFetch(path, init);
      return expectJson<T>(response);
    },
    [authenticatedFetch]
  );

  const subscribe = useCallback(
    (
      path: string,
      onEvent: (event: RealtimeEvent) => void
    ) => {
      let cancelled = false;
      let controller: AbortController | null = null;

      async function connect() {
        while (!cancelled) {
          controller = new AbortController();

          try {
            const response = await authenticatedFetch(path, {
              headers: {
                Accept: "text/event-stream"
              },
              signal: controller.signal
            });

            if (!response.ok || !response.body) {
              throw new Error(
                `Realtime stream failed with ${response.status}.`
              );
            }

            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let buffer = "";

            while (!cancelled) {
              const { done, value } = await reader.read();

              if (done) {
                break;
              }

              buffer += decoder.decode(value, { stream: true });

              let boundary = buffer.indexOf("\n\n");

              while (boundary >= 0) {
                const block = buffer.slice(0, boundary);
                buffer = buffer.slice(boundary + 2);

                const data = block
                  .split("\n")
                  .filter(line => line.startsWith("data:"))
                  .map(line => line.slice(5).trim())
                  .join("\n");

                if (data) {
                  try {
                    onEvent(JSON.parse(data) as RealtimeEvent);
                  } catch {
                    // Ignore malformed frames and keep the stream alive.
                  }
                }

                boundary = buffer.indexOf("\n\n");
              }
            }
          } catch (error) {
            if (
              cancelled ||
              (error instanceof DOMException && error.name === "AbortError")
            ) {
              return;
            }
          }

          if (!cancelled) {
            await wait(1_500);
          }
        }
      }

      void connect();

      return () => {
        cancelled = true;
        controller?.abort();
      };
    },
    [authenticatedFetch]
  );

  const value = useMemo<AuthContextValue>(
    () => ({
      session,
      loading,
      login,
      logout,
      request,
      subscribe
    }),
    [session, loading, login, logout, request, subscribe]
  );

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error("useAuth must be used inside AuthProvider.");
  }

  return context;
}

export function getCompanyChoices(error: unknown) {
  if (!(error instanceof ApiError) || error.code !== "COMPANY_REQUIRED") {
    return [];
  }

  const details = error.details as CompanyRequiredDetails | undefined;
  return details?.companies ?? [];
}
EOF

# ---------------------------------------------------------------------------
# Queues UI
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/queues/page.tsx <<'EOF'
"use client";

import { type FormEvent, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

interface TeamMembership {
  id: string;
  role: "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";
  user: {
    id: string;
    name: string;
    email: string;
  };
}

interface QueueMember {
  id: string;
  membershipId: string;
  membership: TeamMembership;
}

interface QueueItem {
  id: string;
  name: string;
  isActive: boolean;
  members: QueueMember[];
  _count: {
    tickets: number;
  };
}

interface QueuesResponse {
  queues: QueueItem[];
}

interface TeamResponse {
  memberships: TeamMembership[];
}

export default function QueuesPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();

  const [queues, setQueues] = useState<QueueItem[]>([]);
  const [team, setTeam] = useState<TeamMembership[]>([]);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [onlineMembershipIds, setOnlineMembershipIds] = useState<string[]>([]);

  const load = useCallback(async () => {
    const [queuesPayload, teamPayload, presencePayload] = await Promise.all([
      request<QueuesResponse>("/api/v1/queues"),
      request<TeamResponse>("/api/v1/team/memberships"),
      request<{ membershipIds: string[] }>("/api/v1/realtime/presence")
    ]);

    setQueues(queuesPayload.queues);
    setTeam(teamPayload.memberships);
    setOnlineMembershipIds(presencePayload.membershipIds);
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void load();
    }
  }, [load, loading, router, session]);

  useEffect(() => {
    if (!session) return;

    return subscribe("/api/v1/realtime/events", event => {
      if (event.type === "queue.updated") {
        void load();
      }

      if (event.type === "presence.updated" && event.membershipId) {
        setOnlineMembershipIds(current => {
          const next = new Set(current);
          if (event.online) next.add(event.membershipId!);
          else next.delete(event.membershipId!);
          return [...next];
        });
      }
    });
  }, [load, session, subscribe]);

  async function create(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy("create");
    setError("");

    try {
      await request("/api/v1/queues", {
        method: "POST",
        body: JSON.stringify({ name })
      });
      setName("");
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível criar a fila."
      );
    } finally {
      setBusy(null);
    }
  }

  async function toggleMember(
    queue: QueueItem,
    membershipId: string,
    checked: boolean
  ) {
    setBusy(queue.id);
    setError("");

    const current = new Set(
      queue.members.map(member => member.membershipId)
    );

    if (checked) {
      current.add(membershipId);
    } else {
      current.delete(membershipId);
    }

    try {
      const payload = await request<QueuesResponse>(
        `/api/v1/queues/${queue.id}/members`,
        {
          method: "PUT",
          body: JSON.stringify({
            membershipIds: [...current]
          })
        }
      );

      setQueues(payload.queues);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar os atendentes."
      );
    } finally {
      setBusy(null);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando filas…</main>;
  }

  const canManage = session.role === "OWNER" || session.role === "ADMIN";

  return (
    <main className="queue-screen">
      <header className="queue-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">Operação</span>
          <h1>Filas</h1>
          <p>
            Organize os atendimentos e defina quais pessoas podem atuar em cada
            fila.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() => router.push("/dashboard/conversations")}
          type="button"
        >
          Conversas
        </button>
      </header>

      {error && <div className="inbox-error">{error}</div>}

      {canManage && (
        <form className="queue-create" onSubmit={create}>
          <div>
            <strong>Nova fila</strong>
            <span>Ex.: Comercial, Suporte, Financeiro</span>
          </div>
          <input
            maxLength={120}
            onChange={event => setName(event.target.value)}
            placeholder="Nome da fila"
            required
            value={name}
          />
          <button
            className="primary-button"
            disabled={busy === "create"}
            type="submit"
          >
            <span>{busy === "create" ? "Criando…" : "Criar fila"}</span>
            <span>+</span>
          </button>
        </form>
      )}

      <section className="queue-grid">
        {queues.length === 0 ? (
          <div className="connection-empty">
            <strong>Nenhuma fila criada.</strong>
            <p>Crie a primeira fila para começar a distribuir atendimentos.</p>
          </div>
        ) : (
          queues.map(queue => {
            const memberIds = new Set(
              queue.members.map(member => member.membershipId)
            );

            return (
              <article className="queue-card" key={queue.id}>
                <div className="queue-card__heading">
                  <div>
                    <span className="eyebrow">Fila</span>
                    <h2>{queue.name}</h2>
                  </div>
                  <span className="role-badge">
                    {queue.members.length} atendente
                    {queue.members.length === 1 ? "" : "s"}
                  </span>
                </div>

                <div className="queue-members">
                  {team.map(membership => (
                    <label className="queue-member" key={membership.id}>
                      <input
                        checked={memberIds.has(membership.id)}
                        disabled={!canManage || busy === queue.id}
                        onChange={event =>
                          void toggleMember(
                            queue,
                            membership.id,
                            event.target.checked
                          )
                        }
                        type="checkbox"
                      />
                      <span className="queue-member__avatar">
                        {membership.user.name.slice(0, 1).toUpperCase()}
                      </span>
                      <span className="queue-member__copy">
                        <strong>
                          {membership.user.name}
                          <span
                            className={
                              onlineMembershipIds.includes(membership.id)
                                ? "presence-dot presence-dot--online"
                                : "presence-dot"
                            }
                            title={
                              onlineMembershipIds.includes(membership.id)
                                ? "Online"
                                : "Offline"
                            }
                          />
                        </strong>
                        <small>{membership.role}</small>
                      </span>
                    </label>
                  ))}
                </div>
              </article>
            );
          })
        )}
      </section>
    </main>
  );
}
EOF

# ---------------------------------------------------------------------------
# Connections UI: group toggle and default queue
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/connections/page.tsx <<'EOF'
"use client";

import QRCode from "qrcode";
import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type ConnectionStatus =
  | "CREATED"
  | "CONNECTING"
  | "CONNECTED"
  | "DISCONNECTED"
  | "ERROR";

interface QueueOption {
  id: string;
  name: string;
}

interface WhatsAppConnection {
  id: string;
  name: string;
  provider: "EVOLUTION_BAILEYS" | "META_CLOUD";
  instanceName: string;
  status: ConnectionStatus;
  phoneNumber: string | null;
  profileName: string | null;
  lastError: string | null;
  lastEventAt: string | null;
  acceptGroups: boolean;
  defaultQueueId: string | null;
  defaultQueue?: QueueOption | null;
  createdAt: string;
}

interface QrPayload {
  code?: string;
  base64?: string;
  pairingCode?: string;
  count?: number;
}

interface ListResponse {
  connections: WhatsAppConnection[];
}

interface QueuesResponse {
  queues: QueueOption[];
}

interface CreateResponse {
  connection: WhatsAppConnection;
  qr: QrPayload;
}

interface ConnectResponse {
  qr: QrPayload;
}

interface SyncResponse {
  connection: WhatsAppConnection;
}

interface SettingsResponse {
  connection: WhatsAppConnection;
}

const statusLabels: Record<ConnectionStatus, string> = {
  CREATED: "Criada",
  CONNECTING: "Aguardando QR",
  CONNECTED: "Conectada",
  DISCONNECTED: "Desconectada",
  ERROR: "Erro"
};

function normalizeBase64(value?: string) {
  if (!value) return undefined;
  if (value.startsWith("data:image")) return value;
  return `data:image/png;base64,${value}`;
}

export default function ConnectionsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();

  const [connections, setConnections] = useState<WhatsAppConnection[]>([]);
  const [queues, setQueues] = useState<QueueOption[]>([]);
  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [qrConnectionId, setQrConnectionId] = useState<string | null>(null);
  const [qrImage, setQrImage] = useState<string | null>(null);
  const [pairingCode, setPairingCode] = useState<string | null>(null);
  const [testConnectionId, setTestConnectionId] = useState<string | null>(null);
  const [testNumber, setTestNumber] = useState("");
  const [testText, setTestText] = useState("Teste enviado pelo Wapp.");
  const [testResult, setTestResult] = useState("");

  const loadConnections = useCallback(async () => {
    const payload = await request<ListResponse>(
      "/api/v1/whatsapp/connections"
    );
    setConnections(payload.connections);
  }, [request]);

  const loadQueues = useCallback(async () => {
    const payload = await request<QueuesResponse>("/api/v1/queues");
    setQueues(payload.queues);
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void Promise.all([loadConnections(), loadQueues()]).catch(() => {
        setError("Não foi possível carregar as conexões.");
      });
    }
  }, [loading, loadConnections, loadQueues, router, session]);

  useEffect(() => {
    if (!session) return;

    return subscribe("/api/v1/realtime/events", event => {
      if (
        event.type === "connection.updated" ||
        event.type === "queue.updated"
      ) {
        void loadConnections();
        void loadQueues();
      }
    });
  }, [loadConnections, loadQueues, session, subscribe]);

  useEffect(() => {
    if (!session) return;

    const timer = window.setInterval(() => {
      void Promise.all(
        connections
          .filter(connection =>
            ["CONNECTING", "CONNECTED", "DISCONNECTED"].includes(
              connection.status
            )
          )
          .map(async connection => {
            try {
              const payload = await request<SyncResponse>(
                `/api/v1/whatsapp/connections/${connection.id}/sync`,
                { method: "POST" }
              );

              setConnections(current =>
                current.map(item =>
                  item.id === payload.connection.id
                    ? { ...item, ...payload.connection }
                    : item
                )
              );

              if (
                payload.connection.id === qrConnectionId &&
                payload.connection.status === "CONNECTED"
              ) {
                setQrConnectionId(null);
                setQrImage(null);
                setPairingCode(null);
              }
            } catch {
              // Status stays visible on the card.
            }
          })
      );
    }, 8000);

    return () => window.clearInterval(timer);
  }, [connections, qrConnectionId, request, session]);

  async function showQr(connectionId: string, qr: QrPayload) {
    setQrConnectionId(connectionId);
    setPairingCode(qr.pairingCode ?? null);

    const imageFromEvolution = normalizeBase64(qr.base64);
    if (imageFromEvolution) {
      setQrImage(imageFromEvolution);
      return;
    }

    if (qr.code) {
      const image = await QRCode.toDataURL(qr.code, {
        width: 340,
        margin: 2,
        errorCorrectionLevel: "M"
      });
      setQrImage(image);
      return;
    }

    setQrImage(null);
  }

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setCreating(true);

    try {
      const payload = await request<CreateResponse>(
        "/api/v1/whatsapp/connections",
        {
          method: "POST",
          body: JSON.stringify({ name })
        }
      );

      setConnections(current => [
        payload.connection,
        ...current.filter(item => item.id !== payload.connection.id)
      ]);
      setName("");
      await showQr(payload.connection.id, payload.qr);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível criar a conexão."
      );
    } finally {
      setCreating(false);
    }
  }

  async function updateSettings(
    connection: WhatsAppConnection,
    settings: {
      acceptGroups?: boolean;
      defaultQueueId?: string | null;
    }
  ) {
    setBusyId(connection.id);

    try {
      const payload = await request<SettingsResponse>(
        `/api/v1/whatsapp/connections/${connection.id}/settings`,
        {
          method: "PATCH",
          body: JSON.stringify(settings)
        }
      );

      setConnections(current =>
        current.map(item =>
          item.id === payload.connection.id
            ? payload.connection
            : item
        )
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar a conexão."
      );
    } finally {
      setBusyId(null);
    }
  }

  async function handleConnect(connection: WhatsAppConnection) {
    setBusyId(connection.id);
    setError("");

    try {
      const payload = await request<ConnectResponse>(
        `/api/v1/whatsapp/connections/${connection.id}/connect`,
        { method: "POST" }
      );
      await showQr(connection.id, payload.qr);
      await loadConnections();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível gerar o QR Code."
      );
    } finally {
      setBusyId(null);
    }
  }

  async function handleSync(connection: WhatsAppConnection) {
    setBusyId(connection.id);
    try {
      const payload = await request<SyncResponse>(
        `/api/v1/whatsapp/connections/${connection.id}/sync`,
        { method: "POST" }
      );
      setConnections(current =>
        current.map(item =>
          item.id === payload.connection.id
            ? { ...item, ...payload.connection }
            : item
        )
      );
    } finally {
      setBusyId(null);
    }
  }

  async function handleTestMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!testConnectionId) return;

    setBusyId(testConnectionId);
    setTestResult("");

    try {
      await request(
        `/api/v1/whatsapp/connections/${testConnectionId}/test-message`,
        {
          method: "POST",
          body: JSON.stringify({
            number: testNumber,
            text: testText
          })
        }
      );
      setTestResult("Mensagem enviada pela Evolution API.");
    } catch (caught) {
      setTestResult(
        caught instanceof ApiError
          ? caught.message
          : "Falha ao enviar mensagem."
      );
    } finally {
      setBusyId(null);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando conexões…</main>;
  }

  const isAdmin = session.role === "OWNER" || session.role === "ADMIN";

  return (
    <main className="connections-screen">
      <header className="connections-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">WhatsApp</span>
          <h1>Conexões</h1>
          <p>
            Configure o comportamento de cada número, inclusive grupos e fila
            padrão de entrada.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() => router.push("/dashboard/queues")}
          type="button"
        >
          Gerenciar filas
        </button>
      </header>

      {error && <div className="form-error">{error}</div>}

      {isAdmin && (
        <form className="connection-create" onSubmit={handleCreate}>
          <div>
            <strong>Nova conexão</strong>
            <span>Novas conexões ignoram grupos por padrão.</span>
          </div>
          <input
            maxLength={120}
            onChange={event => setName(event.target.value)}
            placeholder="Ex.: Comercial, Suporte, Matriz"
            required
            value={name}
          />
          <button
            className="primary-button connection-create__button"
            disabled={creating}
            type="submit"
          >
            <span>{creating ? "Criando…" : "Criar conexão"}</span>
            <span>+</span>
          </button>
        </form>
      )}

      <section className="connection-list">
        {connections.length === 0 ? (
          <div className="connection-empty">
            <strong>Nenhuma conexão criada.</strong>
            <p>Crie a primeira instância para iniciar o vínculo.</p>
          </div>
        ) : (
          connections.map(connection => (
            <article className="connection-card" key={connection.id}>
              <div className="connection-card__main">
                <div>
                  <div className="connection-card__title">
                    <h2>{connection.name}</h2>
                    <span
                      className={`connection-status connection-status--${connection.status.toLowerCase()}`}
                    >
                      {statusLabels[connection.status]}
                    </span>
                  </div>
                  <p>{connection.instanceName}</p>
                  <div className="connection-meta">
                    <span>
                      Provider <strong>Evolution / Baileys</strong>
                    </span>
                    {connection.phoneNumber && (
                      <span>
                        Número <strong>{connection.phoneNumber}</strong>
                      </span>
                    )}
                  </div>

                  {isAdmin && (
                    <div className="connection-settings">
                      <label className="connection-toggle">
                        <input
                          checked={connection.acceptGroups}
                          disabled={busyId === connection.id}
                          onChange={event =>
                            void updateSettings(connection, {
                              acceptGroups: event.target.checked
                            })
                          }
                          type="checkbox"
                        />
                        <span>
                          <strong>Aceitar grupos</strong>
                          <small>
                            Desligado: novas mensagens de grupo são ignoradas.
                          </small>
                        </span>
                      </label>

                      <label className="connection-queue-setting">
                        <span>Fila padrão</span>
                        <select
                          disabled={busyId === connection.id}
                          onChange={event =>
                            void updateSettings(connection, {
                              defaultQueueId: event.target.value || null
                            })
                          }
                          value={connection.defaultQueueId ?? ""}
                        >
                          <option value="">Sem fila padrão</option>
                          {queues.map(queue => (
                            <option key={queue.id} value={queue.id}>
                              {queue.name}
                            </option>
                          ))}
                        </select>
                      </label>
                    </div>
                  )}

                  {connection.lastError && (
                    <div className="connection-error">
                      {connection.lastError}
                    </div>
                  )}
                </div>

                <div className="connection-actions">
                  {isAdmin && connection.status !== "CONNECTED" && (
                    <button
                      className="secondary-button"
                      disabled={busyId === connection.id}
                      onClick={() => handleConnect(connection)}
                      type="button"
                    >
                      Gerar QR
                    </button>
                  )}
                  <button
                    className="ghost-button"
                    disabled={busyId === connection.id}
                    onClick={() => handleSync(connection)}
                    type="button"
                  >
                    Atualizar status
                  </button>
                  {connection.status === "CONNECTED" && (
                    <button
                      className="secondary-button"
                      onClick={() => setTestConnectionId(connection.id)}
                      type="button"
                    >
                      Testar envio
                    </button>
                  )}
                </div>
              </div>
            </article>
          ))
        )}
      </section>

      {qrConnectionId && (
        <div className="modal-backdrop">
          <section className="qr-modal">
            <button
              aria-label="Fechar"
              className="modal-close"
              onClick={() => {
                setQrConnectionId(null);
                setQrImage(null);
                setPairingCode(null);
              }}
              type="button"
            >
              ×
            </button>
            <span className="eyebrow">Conectar aparelho</span>
            <h2>Escaneie pelo WhatsApp</h2>
            <p>
              No celular, abra WhatsApp → Aparelhos conectados → Conectar um
              aparelho.
            </p>
            {qrImage ? (
              <div className="qr-frame">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img alt="QR Code do WhatsApp" src={qrImage} />
              </div>
            ) : (
              <div className="qr-waiting">
                O QR ainda não foi retornado. Tente novamente em alguns segundos.
              </div>
            )}
            {pairingCode && (
              <div className="pairing-code">
                Código de pareamento: <strong>{pairingCode}</strong>
              </div>
            )}
          </section>
        </div>
      )}

      {testConnectionId && (
        <div className="modal-backdrop">
          <form className="test-modal" onSubmit={handleTestMessage}>
            <button
              aria-label="Fechar"
              className="modal-close"
              onClick={() => {
                setTestConnectionId(null);
                setTestResult("");
              }}
              type="button"
            >
              ×
            </button>
            <span className="eyebrow">Teste controlado</span>
            <h2>Enviar mensagem</h2>
            <p>Use DDI + DDD + número, somente dígitos.</p>
            <label className="field">
              <span>Número</span>
              <input
                inputMode="numeric"
                onChange={event =>
                  setTestNumber(event.target.value.replace(/\D/g, ""))
                }
                placeholder="5531999999999"
                required
                value={testNumber}
              />
            </label>
            <label className="field">
              <span>Mensagem</span>
              <textarea
                onChange={event => setTestText(event.target.value)}
                required
                rows={4}
                value={testText}
              />
            </label>
            <button
              className="primary-button"
              disabled={busyId === testConnectionId}
              type="submit"
            >
              <span>
                {busyId === testConnectionId ? "Enviando…" : "Enviar teste"}
              </span>
              <span>→</span>
            </button>
            {testResult && (
              <div className="connection-test-result">{testResult}</div>
            )}
          </form>
        </div>
      )}
    </main>
  );
}
EOF

# ---------------------------------------------------------------------------
# Conversations UI: pending/open, claim, transfer and realtime
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/conversations/page.tsx <<'EOF'
"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

interface Contact {
  id: string;
  name: string;
  remoteJid: string;
  phoneNumber: string | null;
  isGroup: boolean;
}

interface Connection {
  id: string;
  name: string;
  status: string;
  phoneNumber: string | null;
}

interface QueueInfo {
  id: string;
  name: string;
}

interface TeamMembership {
  id: string;
  role: "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";
  user: {
    id: string;
    name: string;
    email: string;
  };
}

type AssignedMembership = TeamMembership;

interface TicketMessagePreview {
  id: string;
  direction: "INBOUND" | "OUTBOUND";
  type: MessageType;
  body: string | null;
  timestamp: string;
}

interface Ticket {
  id: string;
  status: "OPEN" | "PENDING" | "CLOSED";
  unreadCount: number;
  lastMessage: string | null;
  lastMessageAt: string;
  queueId: string | null;
  assignedMembershipId: string | null;
  contact: Contact;
  whatsappConnection: Connection;
  queue: QueueInfo | null;
  assignedMembership: AssignedMembership | null;
  messages: TicketMessagePreview[];
}

type MessageType =
  | "TEXT"
  | "IMAGE"
  | "AUDIO"
  | "VIDEO"
  | "DOCUMENT"
  | "STICKER"
  | "LOCATION"
  | "CONTACT"
  | "UNKNOWN";

interface Message {
  id: string;
  externalId: string;
  direction: "INBOUND" | "OUTBOUND";
  type: MessageType;
  body: string | null;
  mediaMimeType: string | null;
  mediaFileName: string | null;
  timestamp: string;
  sentByUserId: string | null;
}

interface QueueOption {
  id: string;
  name: string;
  members?: Array<{
    membershipId: string;
  }>;
}

interface TicketsResponse {
  tickets: Ticket[];
}

interface MessagesResponse {
  messages: Message[];
}

interface QueuesResponse {
  queues: QueueOption[];
}

interface TeamResponse {
  memberships: TeamMembership[];
}

function messageFallback(type: MessageType) {
  const labels: Record<MessageType, string> = {
    TEXT: "Mensagem",
    IMAGE: "Imagem",
    AUDIO: "Áudio",
    VIDEO: "Vídeo",
    DOCUMENT: "Documento",
    STICKER: "Sticker",
    LOCATION: "Localização",
    CONTACT: "Contato",
    UNKNOWN: "Mensagem"
  };

  return `[${labels[type]}]`;
}

function ticketPreview(ticket: Ticket) {
  return (
    ticket.lastMessage ??
    ticket.messages[0]?.body ??
    (ticket.messages[0]
      ? messageFallback(ticket.messages[0].type)
      : "Nova conversa")
  );
}

function timeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

export default function ConversationsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();

  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [queues, setQueues] = useState<QueueOption[]>([]);
  const [team, setTeam] = useState<TeamMembership[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [closing, setClosing] = useState(false);
  const [claiming, setClaiming] = useState(false);
  const [transferring, setTransferring] = useState(false);
  const [transferQueueId, setTransferQueueId] = useState("");
  const [transferMembershipId, setTransferMembershipId] = useState("");
  const [error, setError] = useState("");
  const bottomRef = useRef<HTMLDivElement | null>(null);

  const selectedTicket = useMemo(
    () => tickets.find(ticket => ticket.id === selectedId) ?? null,
    [selectedId, tickets]
  );

  const pendingCount = tickets.filter(
    ticket => ticket.status === "PENDING"
  ).length;
  const openCount = tickets.filter(ticket => ticket.status === "OPEN").length;

  const loadTickets = useCallback(async () => {
    const payload = await request<TicketsResponse>(
      "/api/v1/tickets?status=ACTIVE"
    );

    setTickets(payload.tickets);
    setSelectedId(current => {
      if (current && payload.tickets.some(ticket => ticket.id === current)) {
        return current;
      }
      return payload.tickets[0]?.id ?? null;
    });
  }, [request]);

  const loadReferenceData = useCallback(async () => {
    const [queuesPayload, teamPayload, presencePayload] = await Promise.all([
      request<QueuesResponse>("/api/v1/queues"),
      request<TeamResponse>("/api/v1/team/memberships"),
      request<{ membershipIds: string[] }>("/api/v1/realtime/presence")
    ]);

    setQueues(queuesPayload.queues);
    setTeam(teamPayload.memberships);
    setOnlineMembershipIds(presencePayload.membershipIds);
  }, [request]);

  const loadMessages = useCallback(
    async (ticketId: string) => {
      const payload = await request<MessagesResponse>(
        `/api/v1/tickets/${ticketId}/messages`
      );
      setMessages(payload.messages);
      await request(`/api/v1/tickets/${ticketId}/read`, {
        method: "POST"
      });
    },
    [request]
  );

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void Promise.all([loadTickets(), loadReferenceData()]).catch(() => {
        setError("Não foi possível carregar os atendimentos.");
      });
    }
  }, [loadReferenceData, loadTickets, loading, router, session]);

  useEffect(() => {
    if (!selectedId) {
      setMessages([]);
      return;
    }

    void loadMessages(selectedId).catch(() => {
      setError("Não foi possível carregar as mensagens.");
    });
  }, [loadMessages, selectedId]);

  useEffect(() => {
    if (!selectedTicket) {
      setTransferQueueId("");
      setTransferMembershipId("");
      return;
    }

    setTransferQueueId(selectedTicket.queueId ?? "");
    setTransferMembershipId(selectedTicket.assignedMembershipId ?? "");
  }, [selectedTicket]);

  useEffect(() => {
    if (!session) return;

    return subscribe("/api/v1/realtime/events", event => {
      if (
        event.type === "ticket.created" ||
        event.type === "ticket.updated" ||
        event.type === "message.created"
      ) {
        void loadTickets();

        if (selectedId && (!event.ticketId || event.ticketId === selectedId)) {
          void loadMessages(selectedId);
        }
      }

      if (event.type === "queue.updated") {
        void loadReferenceData();
      }
    });
  }, [
    loadMessages,
    loadReferenceData,
    loadTickets,
    selectedId,
    session,
    subscribe
  ]);

  useEffect(() => {
    if (!session) return;

    const fallback = window.setInterval(() => {
      void loadTickets();
    }, 30_000);

    return () => window.clearInterval(fallback);
  }, [loadTickets, session]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({
      behavior: "smooth",
      block: "end"
    });
  }, [messages]);

  async function handleClaim() {
    if (!selectedId) return;
    setClaiming(true);
    setError("");

    try {
      await request(`/api/v1/tickets/${selectedId}/claim`, {
        method: "POST"
      });
      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível assumir o atendimento."
      );
    } finally {
      setClaiming(false);
    }
  }

  async function handleTransfer() {
    if (!selectedId) return;
    setTransferring(true);
    setError("");

    try {
      await request(`/api/v1/tickets/${selectedId}/transfer`, {
        method: "POST",
        body: JSON.stringify({
          queueId: transferQueueId || null,
          membershipId: transferMembershipId || null
        })
      });
      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível transferir o atendimento."
      );
    } finally {
      setTransferring(false);
    }
  }

  async function handleSend(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedId || !text.trim()) return;

    setSending(true);
    setError("");

    try {
      await request(`/api/v1/tickets/${selectedId}/messages`, {
        method: "POST",
        body: JSON.stringify({ text: text.trim() })
      });
      setText("");
      await Promise.all([loadMessages(selectedId), loadTickets()]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível enviar a mensagem."
      );
    } finally {
      setSending(false);
    }
  }

  async function handleClose() {
    if (!selectedId) return;
    setClosing(true);

    try {
      await request(`/api/v1/tickets/${selectedId}/close`, {
        method: "POST"
      });
      setMessages([]);
      setSelectedId(null);
      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível encerrar o atendimento."
      );
    } finally {
      setClosing(false);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando conversas…</main>;
  }

  return (
    <main className="inbox-screen">
      <header className="inbox-topbar">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">Atendimento · tempo real</span>
          <h1>Conversas</h1>
        </div>
        <div className="inbox-topbar__right">
          <span>{session.company.name}</span>
          <button
            className="ghost-button"
            onClick={() => router.push("/dashboard/queues")}
            type="button"
          >
            Filas
          </button>
          <button
            className="ghost-button"
            onClick={() => router.push("/dashboard/connections")}
            type="button"
          >
            Conexões
          </button>
        </div>
      </header>

      {error && <div className="inbox-error">{error}</div>}

      <section className="inbox">
        <aside className="ticket-list">
          <div className="ticket-list__heading ticket-list__heading--stacked">
            <strong>Atendimentos ativos</strong>
            <div className="ticket-counters">
              <span>{pendingCount} aguardando</span>
              <span>{openCount} em atendimento</span>
            </div>
          </div>

          <div className="ticket-list__items">
            {tickets.length === 0 ? (
              <div className="ticket-list__empty">
                <strong>Nenhuma conversa ativa.</strong>
                <p>Novas mensagens entram aqui em tempo real.</p>
              </div>
            ) : (
              tickets.map(ticket => (
                <button
                  className={
                    ticket.id === selectedId
                      ? "ticket-item ticket-item--active"
                      : "ticket-item"
                  }
                  key={ticket.id}
                  onClick={() => setSelectedId(ticket.id)}
                  type="button"
                >
                  <div className="ticket-avatar">
                    {ticket.contact.name.slice(0, 1).toUpperCase()}
                  </div>
                  <div className="ticket-item__body">
                    <div className="ticket-item__row">
                      <strong>{ticket.contact.name}</strong>
                      <time>{timeLabel(ticket.lastMessageAt)}</time>
                    </div>
                    <div className="ticket-item__row">
                      <span className="ticket-item__preview">
                        {ticketPreview(ticket)}
                      </span>
                      {ticket.unreadCount > 0 && (
                        <span className="unread-badge">
                          {ticket.unreadCount}
                        </span>
                      )}
                    </div>
                    <div className="ticket-item__footer">
                      <small>{ticket.queue?.name ?? "Sem fila"}</small>
                      <span
                        className={
                          ticket.status === "PENDING"
                            ? "ticket-state ticket-state--pending"
                            : "ticket-state ticket-state--open"
                        }
                      >
                        {ticket.status === "PENDING" ? "Aguardando" : "Atendendo"}
                      </span>
                    </div>
                  </div>
                </button>
              ))
            )}
          </div>
        </aside>

        <section className="chat-panel">
          {!selectedTicket ? (
            <div className="chat-empty">
              <div className="chat-empty__mark">W</div>
              <strong>Suas conversas vão aparecer aqui.</strong>
              <p>O realtime substitui o polling de três segundos do P0.6.</p>
            </div>
          ) : (
            <>
              <header className="chat-header chat-header--p07">
                <div className="chat-header__contact">
                  <div className="ticket-avatar">
                    {selectedTicket.contact.name.slice(0, 1).toUpperCase()}
                  </div>
                  <div>
                    <strong>{selectedTicket.contact.name}</strong>
                    <span>
                      {selectedTicket.contact.phoneNumber ??
                        selectedTicket.contact.remoteJid}
                    </span>
                  </div>
                </div>

                <div className="chat-header__actions">
                  {!selectedTicket.assignedMembership && (
                      <button
                        className="primary-button claim-button"
                        disabled={claiming}
                        onClick={handleClaim}
                        type="button"
                      >
                        <span>{claiming ? "Assumindo…" : "Assumir"}</span>
                      </button>
                    )}
                  <button
                    className="ghost-button"
                    disabled={closing}
                    onClick={handleClose}
                    type="button"
                  >
                    {closing ? "Encerrando…" : "Encerrar"}
                  </button>
                </div>
              </header>

              <div className="assignment-bar">
                <div>
                  <span>Fila</span>
                  <select
                    onChange={event => {
                      setTransferQueueId(event.target.value);
                      setTransferMembershipId("");
                    }}
                    value={transferQueueId}
                  >
                    <option value="">Sem fila</option>
                    {queues.map(queue => (
                      <option key={queue.id} value={queue.id}>
                        {queue.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <span>Atendente</span>
                  <select
                    onChange={event =>
                      setTransferMembershipId(event.target.value)
                    }
                    value={transferMembershipId}
                  >
                    <option value="">Aguardando alguém assumir</option>
                    {team
                      .filter(membership => {
                        if (!transferQueueId) return true;
                        const queue = queues.find(
                          item => item.id === transferQueueId
                        );
                        const memberIds = queue?.members?.map(
                          member => member.membershipId
                        );
                        return !memberIds?.length || memberIds.includes(membership.id);
                      })
                      .map(membership => (
                        <option key={membership.id} value={membership.id}>
                          {membership.user.name} · {membership.role}
                        </option>
                      ))}
                  </select>
                </div>

                <button
                  className="secondary-button"
                  disabled={transferring}
                  onClick={handleTransfer}
                  type="button"
                >
                  {transferring ? "Transferindo…" : "Aplicar transferência"}
                </button>

                <small>
                  Atual: {selectedTicket.queue?.name ?? "sem fila"} · {" "}
                  {selectedTicket.assignedMembership?.user.name ?? "sem atendente"}
                </small>
              </div>

              <div className="message-list message-list--assignment">
                {messages.map(message => (
                  <div
                    className={
                      message.direction === "OUTBOUND"
                        ? "message-row message-row--out"
                        : "message-row message-row--in"
                    }
                    key={message.id}
                  >
                    <article className="message-bubble">
                      {message.type !== "TEXT" && (
                        <span className="message-kind">
                          {messageFallback(message.type)}
                        </span>
                      )}
                      <p>{message.body ?? messageFallback(message.type)}</p>
                      {message.mediaFileName && (
                        <small className="message-file">
                          {message.mediaFileName}
                        </small>
                      )}
                      <time>{dateTimeLabel(message.timestamp)}</time>
                    </article>
                  </div>
                ))}
                <div ref={bottomRef} />
              </div>

              <form className="composer" onSubmit={handleSend}>
                <textarea
                  maxLength={4096}
                  onChange={event => setText(event.target.value)}
                  onKeyDown={event => {
                    if (event.key === "Enter" && !event.shiftKey) {
                      event.preventDefault();
                      event.currentTarget.form?.requestSubmit();
                    }
                  }}
                  placeholder="Digite uma mensagem…"
                  rows={1}
                  value={text}
                />
                <button
                  className="composer__send"
                  disabled={sending || !text.trim()}
                  type="submit"
                >
                  {sending ? "…" : "→"}
                </button>
              </form>
            </>
          )}
        </section>
      </section>
    </main>
  );
}
EOF

# ---------------------------------------------------------------------------
# Dashboard navigation + presence stream
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");
const path = "apps/web/app/dashboard/page.tsx";
let content = fs.readFileSync(path, "utf8");

if (!content.includes('item === "Filas"')) {
  const anchor = `                  if (item === "Conexões") {
                    router.push("/dashboard/connections");
                  }`;
  const replacement = `${anchor}

                  if (item === "Filas") {
                    router.push("/dashboard/queues");
                  }`;

  if (content.includes(anchor)) {
    content = content.replace(anchor, replacement);
  } else {
    console.warn("[P0.7] Dashboard navigation anchor not found.");
  }
}

content = content.replace(
  "const { session, loading, logout, request } = useAuth();",
  "const { session, loading, logout, request, subscribe } = useAuth();"
);

if (!content.includes('subscribe("/api/v1/realtime/events"')) {
  const authEffect = `  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
    }
  }, [loading, router, session]);`;

  const presenceEffect = `${authEffect}

  useEffect(() => {
    if (!session) return;
    return subscribe("/api/v1/realtime/events", () => {});
  }, [session, subscribe]);`;

  if (content.includes(authEffect)) {
    content = content.replace(authEffect, presenceEffect);
  } else {
    console.warn("[P0.7] Dashboard auth effect anchor not found.");
  }
}

fs.writeFileSync(path, content);
NODE

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P0.7 / Queues, assignment and connection policy -------------- */

.queue-screen {
  min-height: 100vh;
  background: var(--background);
  padding: 44px clamp(20px, 5vw, 72px) 80px;
}

.queue-header {
  display: flex;
  max-width: 1180px;
  align-items: flex-end;
  justify-content: space-between;
  gap: 30px;
  margin: 0 auto 28px;
}

.queue-header h1 {
  margin: 8px 0 12px;
  font-size: clamp(42px, 6vw, 64px);
  font-weight: 640;
  letter-spacing: -0.055em;
  line-height: 1;
}

.queue-header p {
  max-width: 620px;
  margin: 0;
  color: var(--muted);
  line-height: 1.6;
}

.queue-screen > .inbox-error,
.queue-create,
.queue-grid {
  max-width: 1180px;
  margin-left: auto;
  margin-right: auto;
}

.queue-create {
  display: grid;
  grid-template-columns: minmax(220px, 1fr) minmax(260px, 0.8fr) 170px;
  align-items: center;
  gap: 18px;
  border: 1px solid var(--line);
  border-radius: 18px;
  background: white;
  padding: 21px;
}

.queue-create > div {
  display: grid;
  gap: 5px;
}

.queue-create strong {
  font-size: 13px;
}

.queue-create span {
  color: var(--muted);
  font-size: 10px;
}

.queue-create input {
  height: 50px;
  border: 1px solid var(--line);
  border-radius: 12px;
  outline: none;
  background: var(--surface-subtle);
  padding: 0 14px;
}

.queue-create .primary-button {
  margin: 0;
}

.queue-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
  margin-top: 16px;
}

.queue-card {
  border: 1px solid var(--line);
  border-radius: 18px;
  background: white;
  padding: 22px;
}

.queue-card__heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 18px;
}

.queue-card h2 {
  margin: 7px 0 0;
  font-size: 20px;
  letter-spacing: -0.03em;
}

.queue-members {
  display: grid;
  gap: 8px;
}

.queue-member {
  display: grid;
  grid-template-columns: 18px 36px 1fr;
  align-items: center;
  gap: 10px;
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 10px 11px;
}

.queue-member__avatar {
  display: grid;
  width: 34px;
  height: 34px;
  place-items: center;
  border-radius: 10px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 11px;
  font-weight: 800;
}

.queue-member__copy {
  display: grid;
  gap: 2px;
}

.queue-member__copy strong {
  font-size: 11px;
}

.queue-member__copy small {
  color: var(--muted);
  font-size: 9px;
}

.connection-settings {
  display: grid;
  max-width: 650px;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-top: 17px;
}

.connection-toggle,
.connection-queue-setting {
  display: flex;
  min-height: 62px;
  align-items: center;
  gap: 10px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: var(--surface-subtle);
  padding: 10px 12px;
}

.connection-toggle > span {
  display: grid;
  gap: 3px;
}

.connection-toggle strong,
.connection-queue-setting > span {
  font-size: 10px;
  font-weight: 750;
}

.connection-toggle small {
  color: var(--muted);
  font-size: 8px;
  line-height: 1.4;
}

.connection-queue-setting {
  display: grid;
  grid-template-columns: 85px 1fr;
}

.connection-queue-setting select,
.assignment-bar select {
  min-width: 0;
  height: 38px;
  border: 1px solid var(--line);
  border-radius: 9px;
  outline: none;
  background: white;
  padding: 0 9px;
  font-size: 10px;
}

.ticket-list__heading--stacked {
  height: 76px;
  align-items: flex-start;
  flex-direction: column;
  justify-content: center;
  gap: 7px;
}

.ticket-counters {
  display: flex;
  gap: 6px;
}

.ticket-counters span {
  display: inline-flex;
  width: auto;
  min-width: 0;
  height: auto;
  border-radius: 999px;
  padding: 5px 8px;
  font-size: 8px;
}

.ticket-list__items {
  height: calc(100% - 76px);
}

.ticket-item__footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-top: 4px;
}

.ticket-item__footer small {
  margin: 0;
}

.ticket-state {
  border-radius: 999px;
  padding: 4px 6px;
  font-size: 7px;
  font-weight: 800;
  text-transform: uppercase;
}

.ticket-state--pending {
  background: #f4ecd8;
  color: #7b6226;
}

.ticket-state--open {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.chat-panel:has(.assignment-bar) {
  grid-template-rows: 66px auto minmax(0, 1fr) auto;
}

.claim-button {
  width: auto;
  height: 36px;
  margin: 0;
  padding: 0 13px;
  font-size: 10px;
}

.assignment-bar {
  display: grid;
  grid-template-columns: minmax(140px, 0.65fr) minmax(190px, 1fr) auto;
  align-items: end;
  gap: 10px;
  border-bottom: 1px solid var(--line);
  background: #fbfcfa;
  padding: 10px 16px;
}

.assignment-bar > div {
  display: grid;
  gap: 4px;
}

.assignment-bar > div > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 750;
  text-transform: uppercase;
}

.assignment-bar > small {
  grid-column: 1 / -1;
  color: #929a95;
  font-size: 8px;
}

.message-list--assignment {
  min-height: 0;
}

.queue-member__copy strong {
  display: flex;
  align-items: center;
  gap: 7px;
}

.presence-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #c2c8c4;
}

.presence-dot--online {
  background: var(--accent);
  box-shadow: 0 0 0 3px rgba(31, 122, 80, 0.1);
}

@media (max-width: 900px) {
  .queue-create,
  .queue-grid,
  .connection-settings {
    grid-template-columns: 1fr;
  }

  .assignment-bar {
    grid-template-columns: 1fr 1fr;
  }

  .assignment-bar .secondary-button {
    grid-column: 1 / -1;
  }
}
EOF

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/OPERATIONS.md <<'EOF'
# P0.7 Operations

P0.7 adds operational ownership on top of the conversation domain.

## Ticket lifecycle

```text
Inbound message
    |
    v
PENDING + optional default queue
    |
    +-- agent claims ----------> OPEN
    |
    +-- transferred to queue --> PENDING
    |
    +-- transferred to agent --> OPEN
    |
    v
CLOSED
```

Sending a message from an unassigned PENDING ticket automatically claims it for
that Wapp membership before sending.

## Queues

Queues belong to a company. Memberships can be assigned to zero or more queues.

If a queue has configured members, Wapp only allows assignment to a membership
that belongs to that queue. An empty queue membership list is treated as an
unrestricted queue during this milestone.

A WhatsApp connection may define a default queue. New tickets from that
connection enter that queue automatically.

## Groups

`WhatsAppConnection.acceptGroups` is false by default.

Evolution may still deliver group events to the Wapp webhook, but Wapp drops
those events before creating Contact/Ticket/Message when the connection has
groups disabled. This makes the policy independent for each connection.

Existing group tickets created before P0.7 are not deleted automatically.

## Realtime

P0.7 replaces the three-second inbox polling loop with an authenticated
Server-Sent Events stream:

```text
Wapp API EventEmitter -> authenticated SSE -> Next client
```

The same SSE connection also maintains an in-memory online/offline presence count per membership (multiple tabs are counted safely).

This in-memory bus is correct for the current single API process. Before running
multiple API replicas, the bus should be moved to Redis Pub/Sub so every replica
sees the same events.
EOF

echo "[P0.7] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P0.7] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P0.7] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.7] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7] Code generated successfully."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name queues_assignment_realtime"
echo "  pnpm dev"
echo
echo "Open:"
echo "  http://localhost:3000/dashboard/queues"
echo "  http://localhost:3000/dashboard/connections"
echo "  http://localhost:3000/dashboard/conversations"
