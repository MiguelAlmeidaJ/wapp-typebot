#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.11] Building operational SLA indicators..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/security/permissions.ts" \
  "apps/api/src/modules/messages/message-ingestion.service.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
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
  apps/api/src/modules/sla \
  apps/api/src/scripts \
  apps/web/components/conversations \
  docs

# ---------------------------------------------------------------------------
# Prisma schema
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

/* Company-level thresholds. */
const companyMatch = schema.match(
  /model Company \{[\s\S]*?\n\}/
);

if (!companyMatch) {
  throw new Error("Company model not found.");
}

let company = companyMatch[0];

if (!/^\s*firstResponseSlaMinutes\s+Int/m.test(company)) {
  const anchor =
    /^(\s*status\s+CompanyStatus\s+@default\(ACTIVE\)\s*)$/m;

  if (!anchor.test(company)) {
    throw new Error(
      "Could not find Company.status anchor."
    );
  }

  company = company.replace(
    anchor,
    `$1
  firstResponseSlaMinutes Int                 @default(15)
  replySlaMinutes         Int                 @default(30)`
  );
}

schema = schema.replace(
  companyMatch[0],
  company
);

/* Ticket operational clocks. */
const ticketMatch = schema.match(
  /model Ticket \{[\s\S]*?\n\}/
);

if (!ticketMatch) {
  throw new Error("Ticket model not found.");
}

let ticket = ticketMatch[0];

if (!/^\s*firstInboundAt\s+DateTime\?/m.test(ticket)) {
  const anchor =
    /^(\s*lastMessageAt\s+DateTime\s+@default\(now\(\)\)\s*)$/m;

  if (!anchor.test(ticket)) {
    throw new Error(
      "Could not find Ticket.lastMessageAt anchor."
    );
  }

  ticket = ticket.replace(
    anchor,
    `$1
  firstInboundAt        DateTime?
  firstResponseAt       DateTime?
  lastInboundAt         DateTime?
  lastOutboundAt        DateTime?
  waitingSince          DateTime?`
  );
}

if (
  !ticket.includes(
    "@@index([companyId, status, waitingSince])"
  )
) {
  const anchor =
    "  @@index([companyId, status, lastMessageAt])";

  if (!ticket.includes(anchor)) {
    throw new Error(
      "Could not find Ticket status index."
    );
  }

  ticket = ticket.replace(
    anchor,
    `${anchor}
  @@index([companyId, status, waitingSince])`
  );
}

schema = schema.replace(
  ticketMatch[0],
  ticket
);

fs.writeFileSync(path, schema);
console.log("Company SLA settings and Ticket clocks installed.");
NODE

# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/security/permissions.ts";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes('| "sla.read"')) {
  const candidates = [
    '  | "tags.manage"',
    '  | "quickReplies.manage"',
    '  | "contacts.manage"'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find permission union anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  | "sla.read"
  | "sla.manage"`
  );
}

function ensureRolePermissions(
  role,
  permissions
) {
  const regex =
    new RegExp(
      `${role}: \\[([\\s\\S]*?)\\n  \\]`
    );

  const match =
    content.match(regex);

  if (!match) {
    throw new Error(
      `Role block ${role} not found.`
    );
  }

  let body =
    match[1] ?? "";

  for (const permission of permissions) {
    if (
      body.includes(
        `"${permission}"`
      )
    ) {
      continue;
    }

    const trimmed =
      body.trimEnd();

    body =
      `${trimmed}${trimmed ? "\n" : ""}    "${permission}",`;
  }

  content = content.replace(
    regex,
    `${role}: [${body}
  ]`
  );
}

ensureRolePermissions(
  "OWNER",
  [
    "sla.read",
    "sla.manage"
  ]
);

ensureRolePermissions(
  "ADMIN",
  [
    "sla.read",
    "sla.manage"
  ]
);

ensureRolePermissions(
  "SUPERVISOR",
  [
    "sla.read",
    "sla.manage"
  ]
);

ensureRolePermissions(
  "AGENT",
  [
    "sla.read"
  ]
);

fs.writeFileSync(path, content);
console.log("SLA permissions installed.");
NODE

# ---------------------------------------------------------------------------
# SLA settings service + routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/sla/sla.service.ts <<'EOF'
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export async function getSlaSettings(
  companyId: string
) {
  const company =
    await prisma.company.findUnique({
      where: {
        id: companyId
      },
      select: {
        id: true,
        firstResponseSlaMinutes:
          true,
        replySlaMinutes:
          true
      }
    });

  if (!company) {
    throw new AppError(
      "Empresa não encontrada.",
      404,
      "COMPANY_NOT_FOUND"
    );
  }

  return company;
}

export async function updateSlaSettings(input: {
  companyId: string;
  firstResponseSlaMinutes: number;
  replySlaMinutes: number;
}) {
  const company =
    await prisma.company.update({
      where: {
        id: input.companyId
      },
      data: {
        firstResponseSlaMinutes:
          input.firstResponseSlaMinutes,
        replySlaMinutes:
          input.replySlaMinutes
      },
      select: {
        id: true,
        firstResponseSlaMinutes:
          true,
        replySlaMinutes:
          true
      }
    });

  publishRealtime(
    input.companyId,
    {
      type: "sla.updated"
    }
  );

  return company;
}
EOF

cat > apps/api/src/modules/sla/sla.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  getSlaSettings,
  updateSlaSettings
} from "./sla.service.js";

const updateSchema = z.object({
  firstResponseSlaMinutes: z
    .number()
    .int()
    .min(1)
    .max(1440),
  replySlaMinutes: z
    .number()
    .int()
    .min(1)
    .max(1440)
});

export async function slaRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/sla/settings",
    async request => {
      const auth =
        await requirePermission(
          request,
          "sla.read"
        );

      return {
        settings:
          await getSlaSettings(
            auth.companyId
          )
      };
    }
  );

  app.put(
    "/api/v1/sla/settings",
    async request => {
      const auth =
        await requirePermission(
          request,
          "sla.manage"
        );

      const input =
        updateSchema.parse(
          request.body
        );

      return {
        settings:
          await updateSlaSettings({
            companyId:
              auth.companyId,
            ...input
          })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register SLA routes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { slaRoutes } from "./modules/sla/sla.routes.js";';

if (!content.includes(importLine)) {
  const candidates = [
    'import { tagRoutes } from "./modules/tags/tag.routes.js";',
    'import { quickReplyRoutes } from "./modules/quick-replies/quick-reply.routes.js";',
    'import { ticketRoutes } from "./modules/tickets/ticket.routes.js";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find route import anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (
  !content.includes(
    "await app.register(slaRoutes);"
  )
) {
  const candidates = [
    "  await app.register(tagRoutes);",
    "  await app.register(quickReplyRoutes);",
    "  await app.register(ticketRoutes);"
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find route registration anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  await app.register(slaRoutes);`
  );
}

fs.writeFileSync(path, content);
console.log("SLA routes registered.");
NODE

# ---------------------------------------------------------------------------
# Inbound/outbound SLA clocks in webhook ingestion
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/messages/message-ingestion.service.ts";

let content =
  fs.readFileSync(path, "utf8");

/* New ticket clock initialization. */
if (
  !content.includes(
    "firstInboundAt: parsed.timestamp"
  )
) {
  const anchor = `      status: parsed.fromMe ? "OPEN" : "PENDING",
      lastMessageAt: parsed.timestamp`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticket create status/lastMessageAt block."
    );
  }

  content = content.replace(
    anchor,
    `      status: parsed.fromMe ? "OPEN" : "PENDING",
      lastMessageAt: parsed.timestamp,
      ...(parsed.fromMe
        ? {
            lastOutboundAt:
              parsed.timestamp
          }
        : {
            firstInboundAt:
              parsed.timestamp,
            lastInboundAt:
              parsed.timestamp,
            waitingSince:
              parsed.timestamp
          })`
  );
}

/* Existing/new ticket update on each message. */
if (
  !content.includes(
    "lastOutboundAt: parsed.timestamp"
  ) ||
  !content.includes(
    "firstResponseAt: parsed.timestamp"
  )
) {
  const anchor = `      ...(parsed.fromMe
        ? {}
        : {
            unreadCount: {
              increment: 1
            }
          })`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticket inbound unread update block."
    );
  }

  const replacement = `      ...(parsed.fromMe
        ? {
            lastOutboundAt:
              parsed.timestamp,
            waitingSince:
              null,
            ...(ticket.firstInboundAt &&
            !ticket.firstResponseAt
              ? {
                  firstResponseAt:
                    parsed.timestamp
                }
              : {})
          }
        : {
            firstInboundAt:
              ticket.firstInboundAt ??
              parsed.timestamp,
            lastInboundAt:
              parsed.timestamp,
            waitingSince:
              parsed.timestamp,
            unreadCount: {
              increment: 1
            }
          })`;

  content = content.replace(
    anchor,
    replacement
  );
}

fs.writeFileSync(path, content);
console.log("Webhook message ingestion now updates SLA clocks.");
NODE

# ---------------------------------------------------------------------------
# Outbound SLA helper + ticket updates
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content =
  fs.readFileSync(path, "utf8");

if (!content.includes("function outboundSlaUpdate(")) {
  const anchor =
    "function canOverrideAssignment(role: WappRole)";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find canOverrideAssignment helper."
    );
  }

  const helper = `function outboundSlaUpdate(
  ticket: {
    firstInboundAt: Date | null;
    firstResponseAt: Date | null;
  },
  timestamp: Date
) {
  return {
    lastOutboundAt: timestamp,
    waitingSince: null,
    ...(ticket.firstInboundAt &&
    !ticket.firstResponseAt
      ? {
          firstResponseAt:
            timestamp
        }
      : {})
  };
}

`;

  content = content.replace(
    anchor,
    `${helper}${anchor}`
  );
}

function patchFunction(
  source,
  functionName
) {
  const start =
    source.indexOf(
      `export async function ${functionName}(`
    );

  if (start < 0) {
    throw new Error(
      `${functionName} not found.`
    );
  }

  const next =
    source.indexOf(
      "\nexport async function ",
      start + 10
    );

  const end =
    next >= 0
      ? next
      : source.length;

  let block =
    source.slice(start, end);

  if (
    block.includes(
      "...outboundSlaUpdate("
    )
  ) {
    return source;
  }

  const regex =
    /(lastMessageAt:\s*timestamp)(\s*\n\s*})/;

  if (!regex.test(block)) {
    throw new Error(
      `Could not find ticket lastMessageAt update inside ${functionName}.`
    );
  }

  block = block.replace(
    regex,
    `$1,
      ...outboundSlaUpdate(
        ticket,
        timestamp
      )$2`
  );

  return (
    source.slice(0, start) +
    block +
    source.slice(end)
  );
}

content =
  patchFunction(
    content,
    "sendTicketText"
  );

content =
  patchFunction(
    content,
    "sendTicketMedia"
  );

fs.writeFileSync(path, content);
console.log("Wapp outbound sends now stop SLA waiting clocks.");
NODE

# ---------------------------------------------------------------------------
# Realtime type
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
    content.includes('| "tag.updated"') &&
    !content.includes('| "sla.updated"')
  ) {
    content = content.replace(
      '| "tag.updated"',
      '| "tag.updated"\n  | "sla.updated"'
    );
  } else if (
    !content.includes('| "sla.updated"')
  ) {
    const candidates = [
      '| "quick-reply.updated"',
      '| "note.created"',
      '| "ticket.updated"'
    ];

    const anchor =
      candidates.find(candidate =>
        content.includes(candidate)
      );

    if (!anchor) {
      throw new Error(
        `Could not find realtime type anchor in ${path}.`
      );
    }

    content = content.replace(
      anchor,
      `${anchor}\n  | "sla.updated"`
    );
  }

  fs.writeFileSync(path, content);
}

console.log("sla.updated realtime installed.");
NODE

# ---------------------------------------------------------------------------
# Backfill existing tickets
# ---------------------------------------------------------------------------

cat > apps/api/src/scripts/backfill-ticket-sla.ts <<'EOF'
import { prisma } from "../lib/database.js";

async function main() {
  const tickets =
    await prisma.ticket.findMany({
      select: {
        id: true,
        status: true
      },
      orderBy: {
        createdAt: "asc"
      }
    });

  let updated = 0;

  for (const ticket of tickets) {
    const [
      firstInbound,
      lastInbound,
      lastOutbound
    ] = await Promise.all([
      prisma.message.findFirst({
        where: {
          ticketId:
            ticket.id,
          direction:
            "INBOUND"
        },
        select: {
          timestamp: true
        },
        orderBy: {
          timestamp: "asc"
        }
      }),
      prisma.message.findFirst({
        where: {
          ticketId:
            ticket.id,
          direction:
            "INBOUND"
        },
        select: {
          timestamp: true
        },
        orderBy: {
          timestamp: "desc"
        }
      }),
      prisma.message.findFirst({
        where: {
          ticketId:
            ticket.id,
          direction:
            "OUTBOUND"
        },
        select: {
          timestamp: true
        },
        orderBy: {
          timestamp: "desc"
        }
      })
    ]);

    const firstResponse =
      firstInbound
        ? await prisma.message.findFirst({
            where: {
              ticketId:
                ticket.id,
              direction:
                "OUTBOUND",
              timestamp: {
                gte:
                  firstInbound.timestamp
              }
            },
            select: {
              timestamp: true
            },
            orderBy: {
              timestamp: "asc"
            }
          })
        : null;

    const waitingSince =
      ticket.status !== "CLOSED" &&
      lastInbound &&
      (
        !lastOutbound ||
        lastInbound.timestamp >
          lastOutbound.timestamp
      )
        ? lastInbound.timestamp
        : null;

    await prisma.ticket.update({
      where: {
        id: ticket.id
      },
      data: {
        firstInboundAt:
          firstInbound?.timestamp ??
          null,
        firstResponseAt:
          firstResponse?.timestamp ??
          null,
        lastInboundAt:
          lastInbound?.timestamp ??
          null,
        lastOutboundAt:
          lastOutbound?.timestamp ??
          null,
        waitingSince
      }
    });

    updated += 1;

    if (
      updated % 50 === 0
    ) {
      console.log(
        `[SLA] ${updated}/${tickets.length} tickets`
      );
    }
  }

  console.log(
    `[SLA] Backfill complete: ${updated} ticket(s).`
  );
}

main()
  .catch(error => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
EOF

# ---------------------------------------------------------------------------
# SLA monitor component
# ---------------------------------------------------------------------------

cat > apps/web/components/conversations/sla-monitor-drawer.tsx <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type SlaFilter =
  | "ALL"
  | "WAITING"
  | "RISK"
  | "BREACHED";

interface SlaSettings {
  id: string;
  firstResponseSlaMinutes: number;
  replySlaMinutes: number;
}

interface SlaTicket {
  id: string;
  status:
    | "OPEN"
    | "PENDING";
  lastMessage: string | null;
  lastMessageAt: string;
  firstInboundAt: string | null;
  firstResponseAt: string | null;
  lastInboundAt: string | null;
  lastOutboundAt: string | null;
  waitingSince: string | null;
  contact: {
    id: string;
    name: string;
    phoneNumber: string | null;
    isGroup: boolean;
  };
  queue: {
    id: string;
    name: string;
  } | null;
  assignedMembership: {
    id: string;
    user: {
      id: string;
      name: string;
      email: string;
    };
  } | null;
}

interface TicketsResponse {
  tickets: SlaTicket[];
}

interface SettingsResponse {
  settings: SlaSettings;
}

type SlaSeverity =
  | "OK"
  | "WAITING"
  | "RISK"
  | "BREACHED";

function elapsedMinutes(
  from: string | null,
  now: number
) {
  if (!from) {
    return 0;
  }

  return Math.max(
    0,
    Math.floor(
      (
        now -
        new Date(from).getTime()
      ) /
        60_000
    )
  );
}

function durationLabel(
  minutes: number
) {
  if (minutes < 60) {
    return `${minutes}m`;
  }

  const hours =
    Math.floor(
      minutes / 60
    );

  const remainder =
    minutes % 60;

  if (hours < 24) {
    return remainder
      ? `${hours}h ${remainder}m`
      : `${hours}h`;
  }

  const days =
    Math.floor(
      hours / 24
    );

  const remainingHours =
    hours % 24;

  return remainingHours
    ? `${days}d ${remainingHours}h`
    : `${days}d`;
}

function severityFor(
  elapsed: number,
  limit: number
): SlaSeverity {
  if (elapsed >= limit) {
    return "BREACHED";
  }

  if (
    elapsed >=
    Math.ceil(
      limit * 0.7
    )
  ) {
    return "RISK";
  }

  return "WAITING";
}

export function SlaMonitorDrawer({
  onClose,
  onOpenTicket
}: {
  onClose: () => void;
  onOpenTicket: (
    ticketId: string
  ) => void;
}) {
  const {
    request,
    session,
    subscribe
  } = useAuth();

  const [tickets, setTickets] =
    useState<SlaTicket[]>([]);
  const [settings, setSettings] =
    useState<SlaSettings | null>(null);
  const [filter, setFilter] =
    useState<SlaFilter>("ALL");
  const [now, setNow] =
    useState(
      () => Date.now()
    );
  const [loading, setLoading] =
    useState(true);
  const [saving, setSaving] =
    useState(false);
  const [error, setError] =
    useState("");
  const [firstResponseMinutes, setFirstResponseMinutes] =
    useState("15");
  const [replyMinutes, setReplyMinutes] =
    useState("30");

  const canManage =
    session
      ? [
          "OWNER",
          "ADMIN",
          "SUPERVISOR"
        ].includes(
          session.role
        )
      : false;

  const load =
    useCallback(async () => {
      try {
        const [
          ticketPayload,
          settingsPayload
        ] =
          await Promise.all([
            request<TicketsResponse>(
              "/api/v1/tickets?status=ACTIVE"
            ),
            request<SettingsResponse>(
              "/api/v1/sla/settings"
            )
          ]);

        setTickets(
          ticketPayload.tickets
        );
        setSettings(
          settingsPayload.settings
        );
        setFirstResponseMinutes(
          String(
            settingsPayload
              .settings
              .firstResponseSlaMinutes
          )
        );
        setReplyMinutes(
          String(
            settingsPayload
              .settings
              .replySlaMinutes
          )
        );
        setError("");
      } catch {
        setError(
          "Não foi possível carregar os indicadores de SLA."
        );
      } finally {
        setLoading(false);
      }
    }, [request]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const interval =
      window.setInterval(
        () => {
          setNow(
            Date.now()
          );
        },
        30_000
      );

    return () => {
      window.clearInterval(
        interval
      );
    };
  }, []);

  useEffect(() => {
    return subscribe(event => {
      if (
        event.type ===
          "ticket.created" ||
        event.type ===
          "ticket.updated" ||
        event.type ===
          "message.created" ||
        event.type ===
          "sla.updated"
      ) {
        void load();
      }
    });
  }, [
    load,
    subscribe
  ]);

  const rows =
    useMemo(() => {
      if (!settings) {
        return [];
      }

      return tickets
        .map(ticket => {
          const waitingMinutes =
            elapsedMinutes(
              ticket.waitingSince,
              now
            );

          const firstResponseWaiting =
            Boolean(
              ticket.firstInboundAt &&
              !ticket.firstResponseAt
            );

          const firstResponseElapsed =
            firstResponseWaiting
              ? elapsedMinutes(
                  ticket.firstInboundAt,
                  now
                )
              : ticket.firstInboundAt &&
                  ticket.firstResponseAt
                ? Math.max(
                    0,
                    Math.floor(
                      (
                        new Date(
                          ticket.firstResponseAt
                        ).getTime() -
                        new Date(
                          ticket.firstInboundAt
                        ).getTime()
                      ) /
                        60_000
                    )
                  )
                : 0;

          const responseSeverity =
            ticket.waitingSince
              ? severityFor(
                  waitingMinutes,
                  settings.replySlaMinutes
                )
              : "OK";

          const firstSeverity =
            firstResponseWaiting
              ? severityFor(
                  firstResponseElapsed,
                  settings
                    .firstResponseSlaMinutes
                )
              : "OK";

          const severity: SlaSeverity =
            responseSeverity ===
              "BREACHED" ||
            firstSeverity ===
              "BREACHED"
              ? "BREACHED"
              : responseSeverity ===
                    "RISK" ||
                  firstSeverity ===
                    "RISK"
                ? "RISK"
                : ticket.waitingSince ||
                    firstResponseWaiting
                  ? "WAITING"
                  : "OK";

          const score =
            severity ===
            "BREACHED"
              ? 4
              : severity ===
                  "RISK"
                ? 3
                : severity ===
                    "WAITING"
                  ? 2
                  : 1;

          return {
            ticket,
            waitingMinutes,
            firstResponseElapsed,
            firstResponseWaiting,
            severity,
            score
          };
        })
        .filter(row => {
          if (
            filter === "ALL"
          ) {
            return true;
          }

          if (
            filter === "WAITING"
          ) {
            return (
              row.ticket
                .waitingSince !==
                null ||
              row.firstResponseWaiting
            );
          }

          return (
            row.severity ===
            filter
          );
        })
        .sort(
          (a, b) =>
            b.score -
              a.score ||
            b.waitingMinutes -
              a.waitingMinutes ||
            new Date(
              a.ticket
                .lastMessageAt
            ).getTime() -
              new Date(
                b.ticket
                  .lastMessageAt
              ).getTime()
        );
    }, [
      filter,
      now,
      settings,
      tickets
    ]);

  const counts =
    useMemo(() => {
      if (!settings) {
        return {
          waiting: 0,
          risk: 0,
          breached: 0
        };
      }

      let waiting = 0;
      let risk = 0;
      let breached = 0;

      for (const ticket of tickets) {
        const currentWaiting =
          ticket.waitingSince
            ? severityFor(
                elapsedMinutes(
                  ticket.waitingSince,
                  now
                ),
                settings
                  .replySlaMinutes
              )
            : "OK";

        const firstWaiting =
          ticket.firstInboundAt &&
          !ticket.firstResponseAt
            ? severityFor(
                elapsedMinutes(
                  ticket.firstInboundAt,
                  now
                ),
                settings
                  .firstResponseSlaMinutes
              )
            : "OK";

        if (
          currentWaiting ===
            "BREACHED" ||
          firstWaiting ===
            "BREACHED"
        ) {
          breached += 1;
        } else if (
          currentWaiting ===
            "RISK" ||
          firstWaiting ===
            "RISK"
        ) {
          risk += 1;
        }

        if (
          ticket.waitingSince ||
          (
            ticket.firstInboundAt &&
            !ticket.firstResponseAt
          )
        ) {
          waiting += 1;
        }
      }

      return {
        waiting,
        risk,
        breached
      };
    }, [
      now,
      settings,
      tickets
    ]);

  async function saveSettings() {
    const first =
      Number(
        firstResponseMinutes
      );

    const reply =
      Number(
        replyMinutes
      );

    if (
      !Number.isInteger(first) ||
      !Number.isInteger(reply) ||
      first < 1 ||
      reply < 1 ||
      first > 1440 ||
      reply > 1440
    ) {
      setError(
        "Informe tempos entre 1 e 1440 minutos."
      );
      return;
    }

    setSaving(true);
    setError("");

    try {
      const payload =
        await request<SettingsResponse>(
          "/api/v1/sla/settings",
          {
            method: "PUT",
            body: JSON.stringify({
              firstResponseSlaMinutes:
                first,
              replySlaMinutes:
                reply
            })
          }
        );

      setSettings(
        payload.settings
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar o SLA."
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <aside className="sla-monitor">
      <header className="sla-monitor__header">
        <div>
          <span className="eyebrow">
            Operação
          </span>
          <strong>
            Monitor de SLA
          </strong>
          <small>
            Relógio baseado em mensagens reais de entrada e resposta.
          </small>
        </div>

        <button
          aria-label="Fechar monitor de SLA"
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      {error && (
        <div className="sla-monitor__error">
          {error}
        </div>
      )}

      <section className="sla-summary">
        <button
          className={
            filter === "WAITING"
              ? "sla-summary-card sla-summary-card--active"
              : "sla-summary-card"
          }
          onClick={() =>
            setFilter("WAITING")
          }
          type="button"
        >
          <span>Aguardando</span>
          <strong>
            {counts.waiting}
          </strong>
        </button>

        <button
          className={
            filter === "RISK"
              ? "sla-summary-card sla-summary-card--risk sla-summary-card--active"
              : "sla-summary-card sla-summary-card--risk"
          }
          onClick={() =>
            setFilter("RISK")
          }
          type="button"
        >
          <span>Em risco</span>
          <strong>
            {counts.risk}
          </strong>
        </button>

        <button
          className={
            filter === "BREACHED"
              ? "sla-summary-card sla-summary-card--breached sla-summary-card--active"
              : "sla-summary-card sla-summary-card--breached"
          }
          onClick={() =>
            setFilter("BREACHED")
          }
          type="button"
        >
          <span>Estourados</span>
          <strong>
            {counts.breached}
          </strong>
        </button>

        <button
          className={
            filter === "ALL"
              ? "sla-summary-card sla-summary-card--active"
              : "sla-summary-card"
          }
          onClick={() =>
            setFilter("ALL")
          }
          type="button"
        >
          <span>Ativos</span>
          <strong>
            {tickets.length}
          </strong>
        </button>
      </section>

      {canManage &&
        settings && (
          <section className="sla-settings">
            <label>
              <span>
                Primeira resposta
              </span>
              <div>
                <input
                  inputMode="numeric"
                  max={1440}
                  min={1}
                  onChange={event =>
                    setFirstResponseMinutes(
                      event.target.value
                    )
                  }
                  type="number"
                  value={
                    firstResponseMinutes
                  }
                />
                <small>min</small>
              </div>
            </label>

            <label>
              <span>
                Próxima resposta
              </span>
              <div>
                <input
                  inputMode="numeric"
                  max={1440}
                  min={1}
                  onChange={event =>
                    setReplyMinutes(
                      event.target.value
                    )
                  }
                  type="number"
                  value={
                    replyMinutes
                  }
                />
                <small>min</small>
              </div>
            </label>

            <button
              disabled={saving}
              onClick={() =>
                void saveSettings()
              }
              type="button"
            >
              {saving
                ? "Salvando…"
                : "Salvar SLA"}
            </button>
          </section>
        )}

      <div className="sla-monitor__list">
        {loading ? (
          <div className="sla-monitor__empty">
            Carregando indicadores…
          </div>
        ) : rows.length === 0 ? (
          <div className="sla-monitor__empty">
            Nenhum atendimento neste filtro.
          </div>
        ) : (
          rows.map(row => (
            <article
              className={`sla-ticket sla-ticket--${row.severity.toLowerCase()}`}
              key={
                row.ticket.id
              }
            >
              <div className="sla-ticket__heading">
                <div>
                  <strong>
                    {
                      row.ticket
                        .contact
                        .name
                    }
                  </strong>
                  <span>
                    {
                      row.ticket
                        .queue
                        ?.name ??
                      "Sem fila"
                    }
                    {" · "}
                    {
                      row.ticket
                        .assignedMembership
                        ?.user
                        .name ??
                      "Sem atendente"
                    }
                  </span>
                </div>

                <span className="sla-ticket__severity">
                  {row.severity ===
                  "BREACHED"
                    ? "SLA estourado"
                    : row.severity ===
                        "RISK"
                      ? "Em risco"
                      : row.severity ===
                          "WAITING"
                        ? "Aguardando"
                        : "Em dia"}
                </span>
              </div>

              <div className="sla-ticket__metrics">
                {row.ticket
                  .waitingSince ? (
                  <div>
                    <span>
                      Cliente aguardando
                    </span>
                    <strong>
                      {durationLabel(
                        row.waitingMinutes
                      )}
                    </strong>
                    <small>
                      limite{" "}
                      {
                        settings
                          ?.replySlaMinutes
                      }
                      m
                    </small>
                  </div>
                ) : (
                  <div>
                    <span>
                      Resposta atual
                    </span>
                    <strong>
                      Em dia
                    </strong>
                    <small>
                      sem espera do cliente
                    </small>
                  </div>
                )}

                <div>
                  <span>
                    1ª resposta
                  </span>

                  {!row.ticket
                    .firstInboundAt ? (
                    <>
                      <strong>
                        —
                      </strong>
                      <small>
                        sem entrada
                      </small>
                    </>
                  ) : row.firstResponseWaiting ? (
                    <>
                      <strong>
                        {durationLabel(
                          row
                            .firstResponseElapsed
                        )}
                      </strong>
                      <small>
                        aguardando resposta
                      </small>
                    </>
                  ) : (
                    <>
                      <strong>
                        {durationLabel(
                          row
                            .firstResponseElapsed
                        )}
                      </strong>
                      <small>
                        {row.firstResponseElapsed <=
                        (
                          settings
                            ?.firstResponseSlaMinutes ??
                          0
                        )
                          ? "dentro do SLA"
                          : "fora do SLA"}
                      </small>
                    </>
                  )}
                </div>
              </div>

              <p>
                {row.ticket
                  .lastMessage ??
                  "Sem mensagem"}
              </p>

              <button
                onClick={() =>
                  onOpenTicket(
                    row.ticket.id
                  )
                }
                type="button"
              >
                Abrir atendimento
              </button>
            </article>
          ))
        )}
      </div>
    </aside>
  );
}
EOF

# ---------------------------------------------------------------------------
# Conversations integration
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { SlaMonitorDrawer } from "@/components/conversations/sla-monitor-drawer";';

if (!content.includes(importLine)) {
  const candidates = [
    'import { ClosedTicketsDrawer } from "@/components/conversations/closed-tickets-drawer";',
    'import { ConversationSearch } from "@/components/conversations/conversation-search";',
    'import { MessageMedia } from "@/components/messages/message-media";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find Conversations import anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (
  !content.includes(
    "const [slaMonitorOpen"
  )
) {
  const candidates = [
    `  const [closedTicketsOpen, setClosedTicketsOpen] =
    useState(false);`,
    `  const [conversationSearchOpen, setConversationSearchOpen] =
    useState(false);`,
    `  const [tagPickerOpen, setTagPickerOpen] =
    useState(false);`
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find Conversations overlay state anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [slaMonitorOpen, setSlaMonitorOpen] =
    useState(false);`
  );
}

/*
 * Toolbar button before "Atual:".
 */
if (
  !content.includes(
    'className="sla-monitor-toggle"'
  )
) {
  const toolbarIndexes = [
    content.indexOf(
      'className="closed-tickets-toggle'
    ),
    content.indexOf(
      'className="conversation-search-toggle'
    ),
    content.indexOf(
      'className="ticket-tags-toggle"'
    )
  ].filter(value => value >= 0);

  if (toolbarIndexes.length === 0) {
    throw new Error(
      "Could not find toolbar control anchor."
    );
  }

  const fromIndex =
    Math.max(
      ...toolbarIndexes
    );

  const smallIndex =
    content.indexOf(
      "\n\n                <small>",
      fromIndex
    );

  if (smallIndex < 0) {
    throw new Error(
      "Could not find assignment summary after toolbar."
    );
  }

  const button = `

                <button
                  className={
                    slaMonitorOpen
                      ? "sla-monitor-toggle sla-monitor-toggle--active"
                      : "sla-monitor-toggle"
                  }
                  onClick={() => {
                    setSlaMonitorOpen(
                      current => !current
                    );
                    setClosedTicketsOpen(false);
                    setConversationSearchOpen(false);
                    setTagPickerOpen(false);
                    setTagManagerOpen(false);
                    setNotesOpen(false);
                    setQuickReplyManagerOpen(false);
                  }}
                  type="button"
                >
                  SLA
                </button>`;

  content =
    content.slice(0, smallIndex) +
    button +
    content.slice(smallIndex);
}

/*
 * Drawer is isolated from message/composer grid.
 */
if (
  !content.includes(
    "<SlaMonitorDrawer"
  )
) {
  const anchor =
    `              <div className="conversation-body">`;

  if (!content.includes(anchor)) {
    throw new Error(
      "conversation-body anchor not found."
    );
  }

  const drawer = `${anchor}
                {slaMonitorOpen && (
                  <SlaMonitorDrawer
                    onClose={() =>
                      setSlaMonitorOpen(false)
                    }
                    onOpenTicket={ticketId => {
                      setSelectedId(ticketId);
                      setSlaMonitorOpen(false);
                    }}
                  />
                )}`;

  content = content.replace(
    anchor,
    drawer
  );
}

fs.writeFileSync(path, content);
console.log("SLA monitor integrated into Conversations.");
NODE

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.11 / Operational SLA" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.11 / Operational SLA ------------------------------------- */

.sla-monitor-toggle {
  display: inline-flex;
  min-height: 40px;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--line);
  border-radius: 11px;
  background: #fff;
  color: var(--ink);
  padding: 0 12px;
  font-size: 10px;
  font-weight: 800;
}

.sla-monitor-toggle:hover,
.sla-monitor-toggle--active {
  border-color: #b9cec0;
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.sla-monitor {
  position: absolute;
  z-index: 42;
  inset: 0;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-rows:
    auto
    auto
    auto
    minmax(0, 1fr);
  overflow: hidden;
  background: #f8faf8;
}

.sla-monitor__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  border-bottom: 1px solid var(--line);
  background: #fff;
  padding: 15px 17px;
}

.sla-monitor__header > div {
  display: grid;
  gap: 4px;
}

.sla-monitor__header strong {
  font-size: 15px;
}

.sla-monitor__header small {
  color: var(--muted);
  font-size: 9px;
}

.sla-monitor__header > button {
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

.sla-monitor__error {
  border-bottom: 1px solid #efd2cf;
  background: var(--danger-soft);
  color: var(--danger);
  padding: 8px 12px;
  font-size: 9px;
}

.sla-summary {
  display: grid;
  grid-template-columns:
    repeat(4, minmax(0, 1fr));
  gap: 7px;
  border-bottom: 1px solid var(--line);
  background: #fff;
  padding: 10px 12px;
}

.sla-summary-card {
  display: grid;
  gap: 3px;
  border: 1px solid var(--line);
  border-radius: 11px;
  background: #fff;
  padding: 9px 10px;
  text-align: left;
}

.sla-summary-card span {
  color: var(--muted);
  font-size: 8px;
}

.sla-summary-card strong {
  font-size: 18px;
}

.sla-summary-card--risk strong {
  color: #a56b21;
}

.sla-summary-card--breached strong {
  color: var(--danger);
}

.sla-summary-card--active {
  border-color: #adc9b7;
  box-shadow:
    inset 0 0 0 1px
    #d5e8dc;
}

.sla-settings {
  display: grid;
  grid-template-columns:
    minmax(130px, 1fr)
    minmax(130px, 1fr)
    auto;
  align-items: end;
  gap: 8px;
  border-bottom: 1px solid var(--line);
  background: #fff;
  padding: 9px 12px;
}

.sla-settings label {
  display: grid;
  gap: 4px;
}

.sla-settings label > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 700;
}

.sla-settings label > div {
  display: grid;
  grid-template-columns:
    minmax(0, 1fr)
    30px;
  align-items: center;
  border: 1px solid var(--line);
  border-radius: 9px;
  background: var(--surface-subtle);
}

.sla-settings input {
  width: 100%;
  height: 34px;
  border: 0;
  outline: none;
  background: transparent;
  padding: 0 8px;
  font-size: 9px;
}

.sla-settings small {
  color: var(--muted);
  font-size: 8px;
}

.sla-settings > button {
  height: 36px;
  border: 0;
  border-radius: 9px;
  background: var(--sidebar);
  color: #fff;
  padding: 0 10px;
  font-size: 8px;
  font-weight: 800;
}

.sla-monitor__list {
  min-height: 0;
  overflow-y: auto;
  padding: 10px 12px 18px;
  scrollbar-gutter: stable;
}

.sla-ticket {
  display: grid;
  gap: 9px;
  margin-bottom: 8px;
  border: 1px solid var(--line);
  border-left-width: 4px;
  border-radius: 12px;
  background: #fff;
  padding: 11px 12px;
}

.sla-ticket--ok {
  border-left-color: #75a98a;
}

.sla-ticket--waiting {
  border-left-color: #91a49a;
}

.sla-ticket--risk {
  border-left-color: #d39a4a;
  background: #fffdf8;
}

.sla-ticket--breached {
  border-left-color: #c7655d;
  background: #fff9f8;
}

.sla-ticket__heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.sla-ticket__heading > div {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.sla-ticket__heading strong {
  overflow: hidden;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sla-ticket__heading span {
  color: var(--muted);
  font-size: 8px;
}

.sla-ticket__severity {
  flex: 0 0 auto;
  border-radius: 999px;
  background: var(--surface-subtle);
  padding: 4px 7px;
  font-size: 7px !important;
  font-weight: 800;
}

.sla-ticket--risk
.sla-ticket__severity {
  background: #f5ead8;
  color: #8b5d20;
}

.sla-ticket--breached
.sla-ticket__severity {
  background: var(--danger-soft);
  color: var(--danger);
}

.sla-ticket__metrics {
  display: grid;
  grid-template-columns:
    repeat(2, minmax(0, 1fr));
  gap: 7px;
}

.sla-ticket__metrics > div {
  display: grid;
  gap: 2px;
  border-radius: 9px;
  background: var(--surface-subtle);
  padding: 8px 9px;
}

.sla-ticket__metrics span,
.sla-ticket__metrics small {
  color: var(--muted);
  font-size: 7px;
}

.sla-ticket__metrics strong {
  font-size: 11px;
}

.sla-ticket > p {
  overflow: hidden;
  margin: 0;
  color: var(--muted);
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sla-ticket > button {
  justify-self: end;
  border: 0;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 6px 8px;
  font-size: 8px;
  font-weight: 800;
}

.sla-monitor__empty {
  display: grid;
  min-height: 180px;
  place-items: center;
  color: var(--muted);
  padding: 22px;
  font-size: 9px;
}

@media (max-width: 680px) {
  .sla-summary {
    grid-template-columns:
      repeat(2, minmax(0, 1fr));
  }

  .sla-settings {
    grid-template-columns: 1fr;
  }

  .sla-ticket__metrics {
    grid-template-columns: 1fr;
  }

  .sla-monitor-toggle {
    min-height: 36px;
    padding: 0 9px;
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/OPERATIONAL_SLA.md <<'EOF'
# Operational SLA

P1.11 adds response-time clocks to Wapp tickets.

## Company settings

Each company defines:

- `firstResponseSlaMinutes`
- `replySlaMinutes`

Defaults:

- first response: 15 minutes
- next response: 30 minutes

OWNER, ADMIN and SUPERVISOR can change these values.

AGENT can read the SLA monitor but cannot change thresholds.

## Ticket clocks

Wapp stores:

- `firstInboundAt`
- `firstResponseAt`
- `lastInboundAt`
- `lastOutboundAt`
- `waitingSince`

These are operational timestamps, not UI-only calculations.

### Inbound

When a customer message arrives:

- first inbound is preserved;
- last inbound is updated;
- `waitingSince` starts/restarts.

### Outbound

When an outbound message is sent either through Wapp or detected through the
WhatsApp webhook:

- last outbound is updated;
- `waitingSince` is cleared;
- first response is recorded if this is the first reply after the first inbound.

## Monitor severity

For a running SLA clock:

- below 70% of limit: waiting
- 70%-99%: risk
- 100%+: breached

The monitor refreshes elapsed labels every 30 seconds.

Realtime ticket/message/SLA events refresh the source data.

## Existing tickets

After the Prisma migration, run the backfill script once:

`pnpm --filter @wapp/api exec tsx src/scripts/backfill-ticket-sla.ts`

It reconstructs the clocks from existing Message history.

The backfill does not change messages, assignment, queue, tags, notes or ticket
status.
EOF

echo "[P1.11] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.11] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.11] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.11] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.11] Operational SLA installed."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name operational_sla"
echo "  pnpm --filter @wapp/api exec tsx src/scripts/backfill-ticket-sla.ts"
echo "  pnpm dev"
echo
echo "Test:"
echo "  1. open SLA monitor"
echo "  2. set short test limits, e.g. 2 and 3 minutes"
echo "  3. send inbound message and do not reply"
echo "  4. confirm waiting -> risk -> breached"
echo "  5. reply from Wapp and confirm waiting clock clears"
echo "  6. confirm AGENT can view but cannot edit SLA settings"
