#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P2.6] Installing management reports..."

for required in \
  "apps/api/src/app.ts" \
  "apps/api/src/security/permissions.ts" \
  "apps/api/src/security/permissions.test.ts" \
  "apps/api/src/modules/analytics/operational-analytics.service.ts" \
  "apps/web/lib/permissions.ts" \
  "apps/web/app/dashboard/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/analytics \
  apps/web/app/dashboard/reports \
  docs

# ---------------------------------------------------------------------------
# Shared report metric helpers
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/analytics/management-report.metrics.ts <<'EOF'
export function average(
  values: number[]
) {
  if (
    values.length ===
    0
  ) {
    return null;
  }

  return Math.round(
    values.reduce(
      (
        sum,
        value
      ) =>
        sum +
        value,
      0
    ) /
      values.length
  );
}

export function percent(
  numerator: number,
  denominator: number
) {
  if (
    denominator ===
    0
  ) {
    return null;
  }

  return Math.round(
    (
      numerator /
      denominator
    ) *
      100
  );
}

export function percentChange(
  current: number,
  previous: number
) {
  if (
    previous ===
    0
  ) {
    return current ===
      0
      ? 0
      : null;
  }

  return Math.round(
    (
      (
        current -
        previous
      ) /
      previous
    ) *
      100
  );
}

export function elapsedMinutes(
  from: Date,
  to: Date
) {
  return Math.max(
    0,
    Math.floor(
      (
        to.getTime() -
        from.getTime()
      ) /
        60_000
    )
  );
}
EOF

cat > apps/api/src/modules/analytics/management-report.metrics.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  average,
  elapsedMinutes,
  percent,
  percentChange
} from "./management-report.metrics.js";

test(
  "report averages stay deterministic",
  () => {
    assert.equal(
      average([
        10,
        20,
        31
      ]),
      20
    );

    assert.equal(
      average([]),
      null
    );
  }
);

test(
  "report percentages handle empty samples",
  () => {
    assert.equal(
      percent(
        8,
        10
      ),
      80
    );

    assert.equal(
      percent(
        0,
        0
      ),
      null
    );
  }
);

test(
  "comparison does not invent a percentage over zero baseline",
  () => {
    assert.equal(
      percentChange(
        15,
        10
      ),
      50
    );

    assert.equal(
      percentChange(
        4,
        0
      ),
      null
    );

    assert.equal(
      percentChange(
        0,
        0
      ),
      0
    );
  }
);

test(
  "resolution minutes never become negative",
  () => {
    assert.equal(
      elapsedMinutes(
        new Date(
          "2026-08-28T15:00:00.000Z"
        ),
        new Date(
          "2026-08-28T15:42:00.000Z"
        )
      ),
      42
    );

    assert.equal(
      elapsedMinutes(
        new Date(
          "2026-08-28T16:00:00.000Z"
        ),
        new Date(
          "2026-08-28T15:42:00.000Z"
        )
      ),
      0
    );
  }
);
EOF

# ---------------------------------------------------------------------------
# Management report service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/analytics/management-report.service.ts <<'EOF'
import {
  prisma
} from "../../lib/database.js";
import {
  average,
  elapsedMinutes,
  percent,
  percentChange
} from "./management-report.metrics.js";

const DAY_MS =
  24 *
  60 *
  60 *
  1_000;

function startOfDay(
  value: Date
) {
  const result =
    new Date(
      value
    );

  result.setHours(
    0,
    0,
    0,
    0
  );

  return result;
}

function dayKey(
  value: Date
) {
  return value
    .toISOString()
    .slice(
      0,
      10
    );
}

interface ReportTicket {
  id: string;
  createdAt: Date;
  closedAt:
    | Date
    | null;
  firstInboundAt:
    | Date
    | null;
  firstResponseAt:
    | Date
    | null;
  queue: {
    id: string;
    name: string;
  } | null;
}

function ticketMetrics(
  tickets:
    ReportTicket[],
  from:
    Date,
  to:
    Date,
  firstResponseSlaMinutes:
    number
) {
  const created =
    tickets.filter(
      ticket =>
        ticket.createdAt >=
          from &&
        ticket.createdAt <
          to
    );

  const closed =
    tickets.filter(
      ticket =>
        ticket.closedAt &&
        ticket.closedAt >=
          from &&
        ticket.closedAt <
          to
    );

  const firstResponseSamples =
    tickets
      .filter(
        ticket =>
          ticket.firstInboundAt &&
          ticket.firstInboundAt >=
            from &&
          ticket.firstInboundAt <
            to &&
          ticket.firstResponseAt &&
          ticket.firstResponseAt >=
            ticket.firstInboundAt
      )
      .map(
        ticket =>
          elapsedMinutes(
            ticket
              .firstInboundAt!,
            ticket
              .firstResponseAt!
          )
      );

  const firstResponseCompliant =
    firstResponseSamples.filter(
      minutes =>
        minutes <=
        firstResponseSlaMinutes
    ).length;

  const resolutionSamples =
    closed.map(
      ticket =>
        elapsedMinutes(
          ticket.createdAt,
          ticket.closedAt!
        )
    );

  return {
    created:
      created.length,
    closed:
      closed.length,
    throughputPercent:
      percent(
        closed.length,
        created.length
      ),
    averageFirstResponseMinutes:
      average(
        firstResponseSamples
      ),
    firstResponseSlaPercent:
      percent(
        firstResponseCompliant,
        firstResponseSamples.length
      ),
    firstResponseSamples:
      firstResponseSamples.length,
    averageResolutionMinutes:
      average(
        resolutionSamples
      ),
    resolutionSamples:
      resolutionSamples.length
  };
}

function numberDelta(
  current:
    number,
  previous:
    number
) {
  return {
    current,
    previous,
    changePercent:
      percentChange(
        current,
        previous
      )
  };
}

function nullableDelta(
  current:
    number
    | null,
  previous:
    number
    | null
) {
  return {
    current,
    previous,
    changePercent:
      current !==
        null &&
      previous !==
        null
        ? percentChange(
            current,
            previous
          )
        : null
  };
}

export async function getManagementReport(input: {
  companyId: string;
  days:
    | 7
    | 30
    | 90;
  queueId?:
    string;
}) {
  const now =
    new Date();

  const today =
    startOfDay(
      now
    );

  const currentFrom =
    new Date(
      today.getTime() -
      (
        input.days -
        1
      ) *
        DAY_MS
    );

  const previousFrom =
    new Date(
      currentFrom.getTime() -
      input.days *
        DAY_MS
    );

  const currentTo =
    new Date(
      now.getTime() +
      1
    );

  const company =
    await prisma.company.findUniqueOrThrow({
      where: {
        id:
          input.companyId
      },
      select: {
        firstResponseSlaMinutes:
          true,
        replySlaMinutes:
          true
      }
    });

  if (
    input.queueId
  ) {
    const queue =
      await prisma.queue.findFirst({
        where: {
          id:
            input.queueId,
          companyId:
            input.companyId
        },
        select: {
          id:
            true
        }
      });

    if (
      !queue
    ) {
      throw new Error(
        "REPORT_QUEUE_NOT_FOUND"
      );
    }
  }

  const ticketWhere = {
    companyId:
      input.companyId,
    ...(input.queueId
      ? {
          queueId:
            input.queueId
        }
      : {}),
    OR: [
      {
        createdAt: {
          gte:
            previousFrom,
          lt:
            currentTo
        }
      },
      {
        closedAt: {
          gte:
            previousFrom,
          lt:
            currentTo
        }
      },
      {
        firstInboundAt: {
          gte:
            previousFrom,
          lt:
            currentTo
        }
      }
    ]
  };

  const [
    tickets,
    activeTickets,
    currentCloseEvents,
    previousCloseEvents,
    currentReopenCount,
    previousReopenCount,
    currentOutboundGroups,
    previousOutboundGroups,
    memberships
  ] =
    await Promise.all([
      prisma.ticket.findMany({
        where:
          ticketWhere,
        select: {
          id:
            true,
          createdAt:
            true,
          closedAt:
            true,
          firstInboundAt:
            true,
          firstResponseAt:
            true,
          queue: {
            select: {
              id:
                true,
              name:
                true
            }
          }
        }
      }),
      prisma.ticket.findMany({
        where: {
          companyId:
            input.companyId,
          status: {
            in: [
              "OPEN",
              "PENDING"
            ]
          },
          ...(input.queueId
            ? {
                queueId:
                  input.queueId
              }
            : {})
        },
        select: {
          id:
            true,
          status:
            true,
          queueId:
            true,
          assignedMembershipId:
            true,
          firstInboundAt:
            true,
          firstResponseAt:
            true,
          waitingSince:
            true
        }
      }),
      prisma.ticketEvent.findMany({
        where: {
          companyId:
            input.companyId,
          type:
            "CLOSED",
          createdAt: {
            gte:
              currentFrom,
            lt:
              currentTo
          },
          ...(input.queueId
            ? {
                ticket: {
                  queueId:
                    input.queueId
                }
              }
            : {})
        },
        select: {
          actorMembershipId:
            true
        }
      }),
      prisma.ticketEvent.findMany({
        where: {
          companyId:
            input.companyId,
          type:
            "CLOSED",
          createdAt: {
            gte:
              previousFrom,
            lt:
              currentFrom
          },
          ...(input.queueId
            ? {
                ticket: {
                  queueId:
                    input.queueId
                }
              }
            : {})
        },
        select: {
          actorMembershipId:
            true
        }
      }),
      prisma.ticketEvent.count({
        where: {
          companyId:
            input.companyId,
          type:
            "REOPENED",
          createdAt: {
            gte:
              currentFrom,
            lt:
              currentTo
          },
          ...(input.queueId
            ? {
                ticket: {
                  queueId:
                    input.queueId
                }
              }
            : {})
        }
      }),
      prisma.ticketEvent.count({
        where: {
          companyId:
            input.companyId,
          type:
            "REOPENED",
          createdAt: {
            gte:
              previousFrom,
            lt:
              currentFrom
          },
          ...(input.queueId
            ? {
                ticket: {
                  queueId:
                    input.queueId
                }
              }
            : {})
        }
      }),
      prisma.message.groupBy({
        by: [
          "sentByUserId"
        ],
        where: {
          companyId:
            input.companyId,
          direction:
            "OUTBOUND",
          sentByUserId: {
            not:
              null
          },
          timestamp: {
            gte:
              currentFrom,
            lt:
              currentTo
          },
          ...(input.queueId
            ? {
                ticket: {
                  queueId:
                    input.queueId
                }
              }
            : {})
        },
        _count: {
          _all:
            true
        }
      }),
      prisma.message.groupBy({
        by: [
          "sentByUserId"
        ],
        where: {
          companyId:
            input.companyId,
          direction:
            "OUTBOUND",
          sentByUserId: {
            not:
              null
          },
          timestamp: {
            gte:
              previousFrom,
            lt:
              currentFrom
          },
          ...(input.queueId
            ? {
                ticket: {
                  queueId:
                    input.queueId
                }
              }
            : {})
        },
        _count: {
          _all:
            true
        }
      }),
      prisma.companyMembership.findMany({
        where: {
          companyId:
            input.companyId
        },
        select: {
          id:
            true,
          userId:
            true,
          role:
            true,
          isActive:
            true,
          user: {
            select: {
              id:
                true,
              name:
                true,
              isActive:
                true
            }
          }
        }
      })
    ]);

  const current =
    ticketMetrics(
      tickets,
      currentFrom,
      currentTo,
      company
        .firstResponseSlaMinutes
    );

  const previous =
    ticketMetrics(
      tickets,
      previousFrom,
      currentFrom,
      company
        .firstResponseSlaMinutes
    );

  const queueMap =
    new Map<
      string,
      {
        id:
          string
          | null;
        name:
          string;
        tickets:
          ReportTicket[];
      }
    >();

  for (
    const ticket
    of tickets
  ) {
    const key =
      ticket.queue?.id ??
      "__none__";

    const entry =
      queueMap.get(
        key
      ) ?? {
        id:
          ticket.queue?.id ??
          null,
        name:
          ticket.queue?.name ??
          "Sem fila",
        tickets: []
      };

    entry.tickets.push(
      ticket
    );

    queueMap.set(
      key,
      entry
    );
  }

  const activeByQueue =
    new Map<
      string,
      number
    >();

  for (
    const ticket
    of activeTickets
  ) {
    const key =
      ticket.queueId ??
      "__none__";

    activeByQueue.set(
      key,
      (
        activeByQueue.get(
          key
        ) ??
        0
      ) +
        1
    );
  }

  const byQueue =
    [...queueMap.values()]
      .map(
        entry => {
          const metrics =
            ticketMetrics(
              entry.tickets,
              currentFrom,
              currentTo,
              company
                .firstResponseSlaMinutes
            );

          return {
            id:
              entry.id,
            name:
              entry.name,
            active:
              activeByQueue.get(
                entry.id ??
                "__none__"
              ) ??
              0,
            ...metrics
          };
        }
      )
      .filter(
        entry =>
          entry.created >
            0 ||
          entry.closed >
            0 ||
          entry.active >
            0
      )
      .sort(
        (
          a,
          b
        ) =>
          b.closed -
            a.closed ||
          b.created -
            a.created ||
          b.active -
            a.active
      )
      .slice(
        0,
        20
      );

  const closeByMembership =
    new Map<
      string,
      number
    >();

  const previousCloseByMembership =
    new Map<
      string,
      number
    >();

  for (
    const event
    of currentCloseEvents
  ) {
    if (
      !event.actorMembershipId
    ) {
      continue;
    }

    closeByMembership.set(
      event.actorMembershipId,
      (
        closeByMembership.get(
          event.actorMembershipId
        ) ??
        0
      ) +
        1
    );
  }

  for (
    const event
    of previousCloseEvents
  ) {
    if (
      !event.actorMembershipId
    ) {
      continue;
    }

    previousCloseByMembership.set(
      event.actorMembershipId,
      (
        previousCloseByMembership.get(
          event.actorMembershipId
        ) ??
        0
      ) +
        1
    );
  }

  const outboundByUser =
    new Map<
      string,
      number
    >();

  const previousOutboundByUser =
    new Map<
      string,
      number
    >();

  for (
    const group
    of currentOutboundGroups
  ) {
    if (
      group.sentByUserId
    ) {
      outboundByUser.set(
        group.sentByUserId,
        group
          ._count
          ._all
      );
    }
  }

  for (
    const group
    of previousOutboundGroups
  ) {
    if (
      group.sentByUserId
    ) {
      previousOutboundByUser.set(
        group.sentByUserId,
        group
          ._count
          ._all
      );
    }
  }

  const activeByMembership =
    new Map<
      string,
      number
    >();

  for (
    const ticket
    of activeTickets
  ) {
    if (
      !ticket
        .assignedMembershipId
    ) {
      continue;
    }

    activeByMembership.set(
      ticket
        .assignedMembershipId,
      (
        activeByMembership.get(
          ticket
            .assignedMembershipId
        ) ??
        0
      ) +
        1
    );
  }

  const byAssignee =
    memberships
      .map(
        membership => {
          const closed =
            closeByMembership.get(
              membership.id
            ) ??
            0;

          const previousClosed =
            previousCloseByMembership.get(
              membership.id
            ) ??
            0;

          const outbound =
            outboundByUser.get(
              membership.userId
            ) ??
            0;

          const previousOutbound =
            previousOutboundByUser.get(
              membership.userId
            ) ??
            0;

          return {
            id:
              membership.id,
            name:
              membership.user.name,
            role:
              membership.role,
            isActive:
              membership.isActive &&
              membership
                .user
                .isActive,
            active:
              activeByMembership.get(
                membership.id
              ) ??
              0,
            closed,
            closedChangePercent:
              percentChange(
                closed,
                previousClosed
              ),
            outboundMessages:
              outbound,
            outboundChangePercent:
              percentChange(
                outbound,
                previousOutbound
              )
          };
        }
      )
      .filter(
        entry =>
          entry.active >
            0 ||
          entry.closed >
            0 ||
          entry.outboundMessages >
            0
      )
      .sort(
        (
          a,
          b
        ) =>
          b.closed -
            a.closed ||
          b.outboundMessages -
            a.outboundMessages ||
          b.active -
            a.active
      )
      .slice(
        0,
        30
      );

  let waitingNow =
    0;

  let breachedNow =
    0;

  let unassignedNow =
    0;

  for (
    const ticket
    of activeTickets
  ) {
    if (
      !ticket
        .assignedMembershipId
    ) {
      unassignedNow +=
        1;
    }

    const firstWaiting =
      ticket
        .firstInboundAt &&
      !ticket
        .firstResponseAt
        ? elapsedMinutes(
            ticket
              .firstInboundAt,
            now
          )
        : null;

    const replyWaiting =
      ticket
        .waitingSince
        ? elapsedMinutes(
            ticket
              .waitingSince,
            now
          )
        : null;

    const waiting =
      firstWaiting !==
        null ||
      replyWaiting !==
        null;

    const breached =
      (
        firstWaiting !==
          null &&
        firstWaiting >=
          company
            .firstResponseSlaMinutes
      ) ||
      (
        replyWaiting !==
          null &&
        replyWaiting >=
          company
            .replySlaMinutes
      );

    if (
      waiting
    ) {
      waitingNow +=
        1;
    }

    if (
      breached
    ) {
      breachedNow +=
        1;
    }
  }

  const trendMap =
    new Map<
      string,
      {
        date:
          string;
        created:
          number;
        closed:
          number;
      }
    >();

  for (
    let index =
      0;
    index <
      input.days;
    index +=
      1
  ) {
    const date =
      new Date(
        currentFrom.getTime() +
        index *
          DAY_MS
      );

    const key =
      dayKey(
        date
      );

    trendMap.set(
      key,
      {
        date:
          key,
        created:
          0,
        closed:
          0
      }
    );
  }

  for (
    const ticket
    of tickets
  ) {
    if (
      ticket.createdAt >=
        currentFrom &&
      ticket.createdAt <
        currentTo
    ) {
      const day =
        trendMap.get(
          dayKey(
            ticket.createdAt
          )
        );

      if (
        day
      ) {
        day.created +=
          1;
      }
    }

    if (
      ticket.closedAt &&
      ticket.closedAt >=
        currentFrom &&
      ticket.closedAt <
        currentTo
    ) {
      const day =
        trendMap.get(
          dayKey(
            ticket.closedAt
          )
        );

      if (
        day
      ) {
        day.closed +=
          1;
      }
    }
  }

  const currentOutboundTotal =
    currentOutboundGroups.reduce(
      (
        sum,
        group
      ) =>
        sum +
        group
          ._count
          ._all,
      0
    );

  const previousOutboundTotal =
    previousOutboundGroups.reduce(
      (
        sum,
        group
      ) =>
        sum +
        group
          ._count
          ._all,
      0
    );

  return {
    period: {
      days:
        input.days,
      from:
        currentFrom
          .toISOString(),
      to:
        now.toISOString(),
      previousFrom:
        previousFrom
          .toISOString(),
      previousTo:
        currentFrom
          .toISOString(),
      queueId:
        input.queueId ??
        null
    },
    sla: {
      firstResponseMinutes:
        company
          .firstResponseSlaMinutes,
      replyMinutes:
        company
          .replySlaMinutes
    },
    currentState: {
      active:
        activeTickets.length,
      waiting:
        waitingNow,
      breached:
        breachedNow,
      unassigned:
        unassignedNow
    },
    comparison: {
      created:
        numberDelta(
          current.created,
          previous.created
        ),
      closed:
        numberDelta(
          current.closed,
          previous.closed
        ),
      reopened:
        numberDelta(
          currentReopenCount,
          previousReopenCount
        ),
      outboundMessages:
        numberDelta(
          currentOutboundTotal,
          previousOutboundTotal
        ),
      averageFirstResponseMinutes:
        nullableDelta(
          current
            .averageFirstResponseMinutes,
          previous
            .averageFirstResponseMinutes
        ),
      firstResponseSlaPercent:
        nullableDelta(
          current
            .firstResponseSlaPercent,
          previous
            .firstResponseSlaPercent
        ),
      averageResolutionMinutes:
        nullableDelta(
          current
            .averageResolutionMinutes,
          previous
            .averageResolutionMinutes
        ),
      throughputPercent:
        nullableDelta(
          current
            .throughputPercent,
          previous
            .throughputPercent
        )
    },
    samples: {
      firstResponse:
        current
          .firstResponseSamples,
      resolution:
        current
          .resolutionSamples
    },
    trend:
      [...trendMap.values()],
    byQueue,
    byAssignee
  };
}
EOF

# ---------------------------------------------------------------------------
# Route
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/analytics/management-report.routes.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  AppError
} from "../../errors/app-error.js";
import {
  requirePermission
} from "../auth/auth.guard.js";
import {
  getManagementReport
} from "./management-report.service.js";

const querySchema =
  z.object({
    days:
      z.coerce
        .number()
        .int()
        .refine(
          (
            value
          ): value is
            | 7
            | 30
            | 90 =>
            [
              7,
              30,
              90
            ].includes(
              value
            ),
          {
            message:
              "days deve ser 7, 30 ou 90."
          }
        )
        .default(
          30
        ),
    queueId:
      z.string()
        .uuid()
        .optional()
  });

export async function managementReportRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/reports/management",
    async request => {
      const auth =
        await requirePermission(
          request,
          "reports.read"
        );

      const query =
        querySchema.parse(
          request.query
        );

      try {
        return await getManagementReport({
          companyId:
            auth.companyId,
          days:
            query.days,
          queueId:
            query.queueId
        });
      } catch (error) {
        if (
          error instanceof
            Error &&
          error.message ===
            "REPORT_QUEUE_NOT_FOUND"
        ) {
          throw new AppError(
            "Fila não encontrada para este relatório.",
            404,
            "REPORT_QUEUE_NOT_FOUND"
          );
        }

        throw error;
      }
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Backend RBAC
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
    '| "reports.read"'
  )
) {
  const anchor =
    '  | "contacts.read"';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "backend permission type anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `  | "reports.read"
${anchor}`
    );
}

for (
  const role
  of [
    "OWNER",
    "ADMIN",
    "SUPERVISOR"
  ]
) {
  const anchor =
    `  ${role}: [`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      `${role} backend permission block not found.`
    );
  }

  const start =
    content.indexOf(
      anchor
    );

  const nextRole =
    content.indexOf(
      "\n  ",
      start +
      anchor.length
    );

  const scanEnd =
    nextRole >=
      0
      ? nextRole
      : content.length;

  const head =
    content.slice(
      start,
      scanEnd
    );

  if (
    !head.includes(
      '"reports.read"'
    )
  ) {
    content =
      content.replace(
        anchor,
        `${anchor}
    "reports.read",`
      );
  }
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P2.6] Backend reports.read permission installed."
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
    '"reports.read",'
  )
) {
  const allPermissionsAnchor =
    `    "observability.read",`;

  if (
    !content.includes(
      allPermissionsAnchor
    )
  ) {
    throw new Error(
      "allPermissions observability anchor not found."
    );
  }

  content =
    content.replace(
      allPermissionsAnchor,
      `${allPermissionsAnchor}
    "reports.read",`
    );
}

if (
  !content.includes(
    '"management reports are restricted to managerial roles"'
  )
) {
  content += `

describe(
  "management report permissions",
  () => {
    it(
      "management reports are restricted to managerial roles",
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
              "reports.read"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "reports.read"
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
  'import { managementReportRoutes } from "./modules/analytics/management-report.routes.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { operationalAnalyticsRoutes } from "./modules/analytics/operational-analytics.routes.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "operational analytics import anchor not found."
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
    "await app.register(managementReportRoutes);"
  )
) {
  const anchor =
    `  await app.register(operationalAnalyticsRoutes);`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "operational analytics registration anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  await app.register(managementReportRoutes);`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Frontend RBAC + navigation
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const permissionPath =
  "apps/web/lib/permissions.ts";

let permissions =
  fs.readFileSync(
    permissionPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !permissions.includes(
    '| "reports.view"'
  )
) {
  const anchor =
    '  | "contacts.view"';

  if (
    !permissions.includes(
      anchor
    )
  ) {
    throw new Error(
      "UI permission type anchor not found."
    );
  }

  permissions =
    permissions.replace(
      anchor,
      `  | "reports.view"
${anchor}`
    );
}

for (
  const role
  of [
    "OWNER",
    "ADMIN",
    "SUPERVISOR"
  ]
) {
  const anchor =
    `  ${role}: [`;

  if (
    !permissions.includes(
      anchor
    )
  ) {
    throw new Error(
      `${role} UI permission block not found.`
    );
  }

  const start =
    permissions.indexOf(
      anchor
    );

  const next =
    permissions.indexOf(
      "\n  ",
      start +
      anchor.length
    );

  const block =
    permissions.slice(
      start,
      next >=
        0
        ? next
        : permissions.length
    );

  if (
    !block.includes(
      '"reports.view"'
    )
  ) {
    permissions =
      permissions.replace(
        anchor,
        `${anchor}
    "reports.view",`
      );
  }
}

fs.writeFileSync(
  permissionPath,
  permissions
);

const pagePath =
  "apps/web/app/dashboard/page.tsx";

let page =
  fs.readFileSync(
    pagePath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !page.includes(
    'href: "/dashboard/reports"'
  )
) {
  const anchor = `  {
    label: "Contatos",
    href: "/dashboard/contacts",
    permission: "contacts.view"
  },`;

  if (
    !page.includes(
      anchor
    )
  ) {
    throw new Error(
      "dashboard contacts navigation anchor not found."
    );
  }

  const item = `${anchor}
  {
    label: "Relatórios",
    href: "/dashboard/reports",
    permission: "reports.view"
  },`;

  page =
    page.replace(
      anchor,
      item
    );
}

fs.writeFileSync(
  pagePath,
  page
);

console.log(
  "[P2.6] Frontend reports permission and navigation installed."
);
NODE

# ---------------------------------------------------------------------------
# Reports page
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/reports/page.tsx <<'EOF'
"use client";

import {
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
import {
  roleCan
} from "@/lib/permissions";

interface QueueItem {
  id: string;
  name: string;
}

interface ComparisonMetric {
  current:
    number
    | null;
  previous:
    number
    | null;
  changePercent:
    number
    | null;
}

interface ManagementReport {
  period: {
    days:
      7
      | 30
      | 90;
    from:
      string;
    to:
      string;
    queueId:
      string
      | null;
  };
  sla: {
    firstResponseMinutes:
      number;
    replyMinutes:
      number;
  };
  currentState: {
    active:
      number;
    waiting:
      number;
    breached:
      number;
    unassigned:
      number;
  };
  comparison: {
    created:
      ComparisonMetric;
    closed:
      ComparisonMetric;
    reopened:
      ComparisonMetric;
    outboundMessages:
      ComparisonMetric;
    averageFirstResponseMinutes:
      ComparisonMetric;
    firstResponseSlaPercent:
      ComparisonMetric;
    averageResolutionMinutes:
      ComparisonMetric;
    throughputPercent:
      ComparisonMetric;
  };
  samples: {
    firstResponse:
      number;
    resolution:
      number;
  };
  trend:
    Array<{
      date:
        string;
      created:
        number;
      closed:
        number;
    }>;
  byQueue:
    Array<{
      id:
        string
        | null;
      name:
        string;
      active:
        number;
      created:
        number;
      closed:
        number;
      throughputPercent:
        number
        | null;
      averageFirstResponseMinutes:
        number
        | null;
      firstResponseSlaPercent:
        number
        | null;
      averageResolutionMinutes:
        number
        | null;
    }>;
  byAssignee:
    Array<{
      id:
        string;
      name:
        string;
      role:
        string;
      isActive:
        boolean;
      active:
        number;
      closed:
        number;
      closedChangePercent:
        number
        | null;
      outboundMessages:
        number;
      outboundChangePercent:
        number
        | null;
    }>;
}

function minutesLabel(
  value:
    number
    | null
) {
  if (
    value ===
    null
  ) {
    return "—";
  }

  if (
    value <
    60
  ) {
    return `${value} min`;
  }

  const hours =
    Math.floor(
      value /
      60
    );

  const minutes =
    value %
    60;

  if (
    hours <
    24
  ) {
    return minutes
      ? `${hours}h ${minutes}min`
      : `${hours}h`;
  }

  const days =
    Math.floor(
      hours /
      24
    );

  const remainingHours =
    hours %
    24;

  return remainingHours
    ? `${days}d ${remainingHours}h`
    : `${days}d`;
}

function percentLabel(
  value:
    number
    | null
) {
  return value ===
    null
    ? "—"
    : `${value}%`;
}

function changeLabel(
  value:
    number
    | null,
  inverse =
    false
) {
  if (
    value ===
    null
  ) {
    return {
      text:
        "sem base anterior",
      className:
        "report-change report-change--neutral"
    };
  }

  if (
    value ===
    0
  ) {
    return {
      text:
        "sem variação",
      className:
        "report-change report-change--neutral"
    };
  }

  const positive =
    inverse
      ? value <
        0
      : value >
        0;

  return {
    text:
      `${value > 0 ? "+" : ""}${value}%`,
    className:
      positive
        ? "report-change report-change--good"
        : "report-change report-change--bad"
  };
}

function SummaryCard({
  label,
  value,
  helper,
  change,
  inverse
}: {
  label:
    string;
  value:
    string;
  helper:
    string;
  change:
    number
    | null;
  inverse?:
    boolean;
}) {
  const presentation =
    changeLabel(
      change,
      inverse
    );

  return (
    <article className="management-summary-card">
      <span>
        {label}
      </span>

      <strong>
        {value}
      </strong>

      <div>
        <small>
          {helper}
        </small>

        <span
          className={
            presentation.className
          }
        >
          {presentation.text}
        </span>
      </div>
    </article>
  );
}

export default function ReportsPage() {
  const router =
    useRouter();

  const {
    session,
    loading,
    request
  } =
    useAuth();

  const [
    days,
    setDays
  ] =
    useState<
      7
      | 30
      | 90
    >(
      30
    );

  const [
    queueId,
    setQueueId
  ] =
    useState("");

  const [
    queues,
    setQueues
  ] =
    useState<
      QueueItem[]
    >([]);

  const [
    report,
    setReport
  ] =
    useState<
      ManagementReport
      | null
    >(
      null
    );

  const [
    busy,
    setBusy
  ] =
    useState(
      true
    );

  const [
    error,
    setError
  ] =
    useState("");

  const canView =
    session
      ? roleCan(
          session.role,
          "reports.view"
        )
      : false;

  const load =
    useCallback(
      async () => {
        if (
          !canView
        ) {
          return;
        }

        setBusy(
          true
        );

        setError("");

        try {
          const params =
            new URLSearchParams({
              days:
                String(
                  days
                )
            });

          if (
            queueId
          ) {
            params.set(
              "queueId",
              queueId
            );
          }

          const [
            reportPayload,
            queuePayload
          ] =
            await Promise.all([
              request<
                ManagementReport
              >(
                `/api/v1/reports/management?${params.toString()}`
              ),
              request<{
                queues:
                  QueueItem[];
              }>(
                "/api/v1/queues"
              )
            ]);

          setReport(
            reportPayload
          );

          setQueues(
            queuePayload
              .queues
          );
        } catch (caught) {
          setError(
            caught instanceof
              ApiError
              ? caught.message
              : "Não foi possível carregar os relatórios."
          );
        } finally {
          setBusy(
            false
          );
        }
      },
      [
        canView,
        days,
        queueId,
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

      if (
        session &&
        !roleCan(
          session.role,
          "reports.view"
        )
      ) {
        router.replace(
          "/dashboard"
        );

        return;
      }

      if (
        session
      ) {
        void load();
      }
    },
    [
      load,
      loading,
      router,
      session
    ]
  );

  const chartMax =
    useMemo(
      () =>
        Math.max(
          1,
          ...(
            report?.trend.flatMap(
              item => [
                item.created,
                item.closed
              ]
            ) ??
            [
              1
            ]
          )
        ),
      [
        report
      ]
    );

  if (
    loading ||
    !session ||
    !canView
  ) {
    return (
      <main className="dashboard-loading">
        Carregando relatórios…
      </main>
    );
  }

  return (
    <main className="management-reports">
      <header className="management-reports__header">
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
            Gestão
          </span>

          <h1>
            Relatórios
          </h1>

          <p>
            Leia capacidade, produtividade e qualidade sem confundir fotografia atual com autoria histórica.
          </p>
        </div>

        <div className="management-report-filters">
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
                Todas as filas
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

          <div className="management-period-switch">
            {(
              [
                7,
                30,
                90
              ] as const
            ).map(
              value => (
                <button
                  className={
                    days ===
                    value
                      ? "management-period-switch__item management-period-switch__item--active"
                      : "management-period-switch__item"
                  }
                  key={
                    value
                  }
                  onClick={() =>
                    setDays(
                      value
                    )
                  }
                  type="button"
                >
                  {value}d
                </button>
              )
            )}
          </div>
        </div>
      </header>

      {error && (
        <div className="inbox-error">
          {error}
        </div>
      )}

      {busy && (
        <div className="management-report-loading">
          Atualizando indicadores…
        </div>
      )}

      {!busy &&
        report && (
        <>
          <section className="management-state-strip">
            <div>
              <span>
                Ativos agora
              </span>
              <strong>
                {report
                  .currentState
                  .active}
              </strong>
            </div>

            <div>
              <span>
                Aguardando resposta
              </span>
              <strong>
                {report
                  .currentState
                  .waiting}
              </strong>
            </div>

            <div>
              <span>
                SLA estourado
              </span>
              <strong>
                {report
                  .currentState
                  .breached}
              </strong>
            </div>

            <div>
              <span>
                Sem atendente
              </span>
              <strong>
                {report
                  .currentState
                  .unassigned}
              </strong>
            </div>
          </section>

          <section className="management-summary-grid">
            <SummaryCard
              change={
                report
                  .comparison
                  .created
                  .changePercent
              }
              helper={`vs. ${report.comparison.created.previous} no período anterior`}
              label="Novos atendimentos"
              value={
                String(
                  report
                    .comparison
                    .created
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .closed
                  .changePercent
              }
              helper={`vs. ${report.comparison.closed.previous} no período anterior`}
              label="Encerrados"
              value={
                String(
                  report
                    .comparison
                    .closed
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .firstResponseSlaPercent
                  .changePercent
              }
              helper={`${report.samples.firstResponse} respostas medidas`}
              label="SLA 1ª resposta"
              value={
                percentLabel(
                  report
                    .comparison
                    .firstResponseSlaPercent
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .averageFirstResponseMinutes
                  .changePercent
              }
              helper={`meta: ${report.sla.firstResponseMinutes} min`}
              inverse
              label="Tempo 1ª resposta"
              value={
                minutesLabel(
                  report
                    .comparison
                    .averageFirstResponseMinutes
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .averageResolutionMinutes
                  .changePercent
              }
              helper={`${report.samples.resolution} encerramentos medidos`}
              inverse
              label="Tempo de resolução"
              value={
                minutesLabel(
                  report
                    .comparison
                    .averageResolutionMinutes
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .outboundMessages
                  .changePercent
              }
              helper={`vs. ${report.comparison.outboundMessages.previous} no período anterior`}
              label="Mensagens enviadas"
              value={
                String(
                  report
                    .comparison
                    .outboundMessages
                    .current
                )
              }
            />
          </section>

          <section className="management-report-layout">
            <article className="management-report-panel management-report-panel--trend">
              <header>
                <div>
                  <span className="eyebrow">
                    Fluxo
                  </span>
                  <h2>
                    Entrada x encerramento
                  </h2>
                </div>

                <div className="management-chart-legend">
                  <span>
                    <i />
                    Criados
                  </span>

                  <span>
                    <i />
                    Encerrados
                  </span>
                </div>
              </header>

              <div className="management-trend-chart">
                {report
                  .trend
                  .map(
                    (
                      item,
                      index
                    ) => (
                      <div
                        className="management-trend-day"
                        key={
                          item.date
                        }
                        title={`${item.date}: ${item.created} criados, ${item.closed} encerrados`}
                      >
                        <div className="management-trend-day__bars">
                          <span
                            style={{
                              height:
                                `${Math.max(
                                  item.created >
                                    0
                                    ? 6
                                    : 0,
                                  (
                                    item.created /
                                    chartMax
                                  ) *
                                    100
                                )}%`
                            }}
                          />

                          <span
                            style={{
                              height:
                                `${Math.max(
                                  item.closed >
                                    0
                                    ? 6
                                    : 0,
                                  (
                                    item.closed /
                                    chartMax
                                  ) *
                                    100
                                )}%`
                            }}
                          />
                        </div>

                        {(report.period.days ===
                          7 ||
                          index %
                            Math.ceil(
                              report.period.days /
                              7
                            ) ===
                            0) && (
                          <small>
                            {new Intl.DateTimeFormat(
                              "pt-BR",
                              {
                                day:
                                  "2-digit",
                                month:
                                  "2-digit"
                              }
                            ).format(
                              new Date(
                                `${item.date}T12:00:00`
                              )
                            )}
                          </small>
                        )}
                      </div>
                    )
                  )}
              </div>
            </article>

            <article className="management-report-panel management-report-panel--health">
              <header>
                <div>
                  <span className="eyebrow">
                    Leitura
                  </span>
                  <h2>
                    Saúde da operação
                  </h2>
                </div>
              </header>

              <div className="management-health-list">
                <div>
                  <span>
                    Encerrados / criados
                  </span>
                  <strong>
                    {percentLabel(
                      report
                        .comparison
                        .throughputPercent
                        .current
                    )}
                  </strong>
                </div>

                <div>
                  <span>
                    Reaberturas
                  </span>
                  <strong>
                    {report
                      .comparison
                      .reopened
                      .current}
                  </strong>
                </div>

                <div>
                  <span>
                    Meta de resposta
                  </span>
                  <strong>
                    {report
                      .sla
                      .firstResponseMinutes} min
                  </strong>
                </div>

                <div>
                  <span>
                    Meta entre respostas
                  </span>
                  <strong>
                    {report
                      .sla
                      .replyMinutes} min
                  </strong>
                </div>
              </div>

              <p>
                “Encerrados / criados” é throughput do período, não taxa de conversão. Pode superar 100% quando a equipe reduz backlog antigo.
              </p>
            </article>
          </section>

          <section className="management-report-panel">
            <header>
              <div>
                <span className="eyebrow">
                  Filas
                </span>
                <h2>
                  Desempenho operacional
                </h2>
              </div>
            </header>

            <div className="management-report-table">
              <div className="management-report-table__row management-report-table__row--head">
                <span>
                  Fila
                </span>
                <span>
                  Ativos
                </span>
                <span>
                  Criados
                </span>
                <span>
                  Encerrados
                </span>
                <span>
                  SLA 1ª resp.
                </span>
                <span>
                  T. 1ª resp.
                </span>
                <span>
                  T. resolução
                </span>
              </div>

              {report
                .byQueue
                .map(
                  queue => (
                    <div
                      className="management-report-table__row"
                      key={
                        queue.id ??
                        "__none__"
                      }
                    >
                      <strong>
                        {queue.name}
                      </strong>
                      <span>
                        {queue.active}
                      </span>
                      <span>
                        {queue.created}
                      </span>
                      <span>
                        {queue.closed}
                      </span>
                      <span>
                        {percentLabel(
                          queue
                            .firstResponseSlaPercent
                        )}
                      </span>
                      <span>
                        {minutesLabel(
                          queue
                            .averageFirstResponseMinutes
                        )}
                      </span>
                      <span>
                        {minutesLabel(
                          queue
                            .averageResolutionMinutes
                        )}
                      </span>
                    </div>
                  )
                )}

              {report
                .byQueue
                .length ===
                0 && (
                <div className="management-report-empty">
                  Nenhum dado de fila neste período.
                </div>
              )}
            </div>
          </section>

          <section className="management-report-panel">
            <header>
              <div>
                <span className="eyebrow">
                  Equipe
                </span>
                <h2>
                  Produção atribuível
                </h2>
              </div>

              <small className="management-report-panel__note">
                Encerramentos usam o ator real do histórico; mensagens usam o remetente real.
              </small>
            </header>

            <div className="management-agent-list">
              {report
                .byAssignee
                .map(
                  member => {
                    const closedChange =
                      changeLabel(
                        member
                          .closedChangePercent
                      );

                    const outboundChange =
                      changeLabel(
                        member
                          .outboundChangePercent
                      );

                    return (
                      <article
                        className="management-agent-row"
                        key={
                          member.id
                        }
                      >
                        <div className="management-agent-row__identity">
                          <span>
                            {member.name
                              .slice(
                                0,
                                1
                              )
                              .toUpperCase()}
                          </span>

                          <div>
                            <strong>
                              {member.name}
                            </strong>
                            <small>
                              {member.role}
                              {!member.isActive
                                ? " · inativo"
                                : ""}
                            </small>
                          </div>
                        </div>

                        <div>
                          <span>
                            Ativos
                          </span>
                          <strong>
                            {member.active}
                          </strong>
                        </div>

                        <div>
                          <span>
                            Encerrados
                          </span>
                          <strong>
                            {member.closed}
                          </strong>
                          <small
                            className={
                              closedChange.className
                            }
                          >
                            {closedChange.text}
                          </small>
                        </div>

                        <div>
                          <span>
                            Mensagens
                          </span>
                          <strong>
                            {member.outboundMessages}
                          </strong>
                          <small
                            className={
                              outboundChange.className
                            }
                          >
                            {outboundChange.text}
                          </small>
                        </div>
                      </article>
                    );
                  }
                )}

              {report
                .byAssignee
                .length ===
                0 && (
                <div className="management-report-empty">
                  Nenhuma produção atribuível neste período.
                </div>
              )}
            </div>
          </section>
        </>
      )}
    </main>
  );
}
EOF

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

if ! grep -Fq -- "WAPP P2.6 / MANAGEMENT REPORTS" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P2.6 / MANAGEMENT REPORTS ---------------------------------- */

.management-reports {
  min-height: 100vh;
  padding: 34px clamp(24px, 5vw, 72px) 64px;
  background: var(--surface-subtle);
}

.management-reports__header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 28px;
  margin-bottom: 18px;
}

.management-reports__header h1 {
  margin: 7px 0 7px;
  font-size: clamp(34px, 4vw, 48px);
  letter-spacing: -0.05em;
}

.management-reports__header p {
  max-width: 670px;
  margin: 0;
  color: var(--muted);
  font-size: 11px;
  line-height: 1.55;
}

.management-report-filters {
  display: flex;
  align-items: flex-end;
  gap: 10px;
}

.management-report-filters label {
  display: grid;
  gap: 4px;
}

.management-report-filters label > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 750;
}

.management-report-filters select {
  min-width: 180px;
  height: 34px;
  border: 1px solid var(--line);
  border-radius: 9px;
  outline: 0;
  background: white;
  padding: 0 9px;
  color: var(--ink);
  font: inherit;
  font-size: 9px;
}

.management-period-switch {
  display: flex;
  height: 34px;
  align-items: center;
  border: 1px solid var(--line);
  border-radius: 9px;
  background: white;
  padding: 3px;
}

.management-period-switch__item {
  min-width: 44px;
  height: 26px;
  border: 0;
  border-radius: 7px;
  background: transparent;
  color: var(--muted);
  font-size: 9px;
  font-weight: 750;
  cursor: pointer;
}

.management-period-switch__item--active {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.management-report-loading {
  margin-bottom: 12px;
  border: 1px solid var(--line);
  border-radius: 11px;
  background: white;
  padding: 10px 12px;
  color: var(--muted);
  font-size: 9px;
}

.management-state-strip {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
}

.management-state-strip > div {
  display: grid;
  gap: 2px;
  border-right: 1px solid var(--line);
  padding: 12px 15px;
}

.management-state-strip > div:last-child {
  border-right: 0;
}

.management-state-strip span {
  color: var(--muted);
  font-size: 8px;
}

.management-state-strip strong {
  font-size: 19px;
  letter-spacing: -0.04em;
}

.management-summary-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  margin-top: 10px;
}

.management-summary-card {
  display: grid;
  gap: 8px;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
  padding: 14px 15px;
}

.management-summary-card > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 700;
}

.management-summary-card > strong {
  font-size: 24px;
  letter-spacing: -0.045em;
}

.management-summary-card > div {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.management-summary-card small {
  overflow: hidden;
  color: var(--muted);
  font-size: 7px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.report-change {
  flex: 0 0 auto;
  border-radius: 999px;
  padding: 3px 6px;
  font-size: 7px;
  font-weight: 780;
}

.report-change--good {
  background: rgba(31, 122, 80, 0.08);
  color: var(--accent-dark);
}

.report-change--bad {
  background: rgba(163, 59, 50, 0.08);
  color: #973a32;
}

.report-change--neutral {
  background: var(--surface-subtle);
  color: var(--muted);
}

.management-report-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.7fr) minmax(250px, 0.7fr);
  gap: 10px;
  margin-top: 10px;
}

.management-report-panel {
  overflow: hidden;
  margin-top: 10px;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: white;
}

.management-report-layout
  .management-report-panel {
  margin-top: 0;
}

.management-report-panel > header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  border-bottom: 1px solid var(--line);
  padding: 14px 16px;
}

.management-report-panel > header h2 {
  margin: 3px 0 0;
  font-size: 14px;
  letter-spacing: -0.025em;
}

.management-report-panel__note {
  max-width: 430px;
  color: var(--muted);
  font-size: 8px;
  line-height: 1.45;
  text-align: right;
}

.management-chart-legend {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--muted);
  font-size: 8px;
}

.management-chart-legend span {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.management-chart-legend i {
  display: block;
  width: 7px;
  height: 7px;
  border-radius: 2px;
  background: #b7c0ba;
}

.management-chart-legend span:last-child i {
  background: var(--accent-dark);
}

.management-trend-chart {
  display: flex;
  height: 210px;
  align-items: stretch;
  gap: clamp(2px, 0.4vw, 7px);
  padding: 20px 16px 13px;
}

.management-trend-day {
  display: grid;
  min-width: 0;
  flex: 1 1 0;
  grid-template-rows: minmax(0, 1fr) 15px;
  gap: 5px;
}

.management-trend-day__bars {
  display: flex;
  min-height: 0;
  align-items: flex-end;
  justify-content: center;
  gap: 2px;
}

.management-trend-day__bars span {
  width: min(8px, 45%);
  border-radius: 3px 3px 1px 1px;
  background: #b7c0ba;
}

.management-trend-day__bars span:last-child {
  background: var(--accent-dark);
}

.management-trend-day small {
  overflow: visible;
  color: var(--muted);
  font-size: 6px;
  text-align: center;
  white-space: nowrap;
}

.management-health-list {
  display: grid;
  padding: 5px 15px 8px;
}

.management-health-list > div {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  border-bottom: 1px solid #edf0ed;
  padding: 10px 1px;
}

.management-health-list > div:last-child {
  border-bottom: 0;
}

.management-health-list span {
  color: var(--muted);
  font-size: 9px;
}

.management-health-list strong {
  font-size: 11px;
}

.management-report-panel--health > p {
  margin: 0;
  border-top: 1px solid var(--line);
  background: #fafbfa;
  padding: 11px 15px;
  color: var(--muted);
  font-size: 8px;
  line-height: 1.5;
}

.management-report-table {
  overflow-x: auto;
}

.management-report-table__row {
  display: grid;
  grid-template-columns: minmax(160px, 1.4fr) repeat(6, minmax(82px, 0.7fr));
  min-width: 760px;
  align-items: center;
  gap: 10px;
  border-bottom: 1px solid #edf0ed;
  padding: 10px 16px;
}

.management-report-table__row:last-child {
  border-bottom: 0;
}

.management-report-table__row--head {
  background: #fafbfa;
  color: var(--muted);
  font-size: 7px;
  font-weight: 760;
  letter-spacing: 0.035em;
  text-transform: uppercase;
}

.management-report-table__row:not(
  .management-report-table__row--head
) {
  font-size: 9px;
}

.management-report-table__row strong {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.management-agent-list {
  display: grid;
}

.management-agent-row {
  display: grid;
  grid-template-columns: minmax(210px, 1.4fr) repeat(3, minmax(110px, 0.6fr));
  align-items: center;
  gap: 14px;
  border-bottom: 1px solid #edf0ed;
  padding: 11px 16px;
}

.management-agent-row:last-child {
  border-bottom: 0;
}

.management-agent-row__identity {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 9px;
}

.management-agent-row__identity > span {
  display: grid;
  width: 30px;
  height: 30px;
  flex: 0 0 30px;
  place-items: center;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 9px;
  font-weight: 850;
}

.management-agent-row__identity > div,
.management-agent-row > div:not(
  .management-agent-row__identity
) {
  display: grid;
  min-width: 0;
  gap: 2px;
}

.management-agent-row__identity strong {
  overflow: hidden;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.management-agent-row span,
.management-agent-row small {
  color: var(--muted);
  font-size: 7px;
}

.management-agent-row
  > div:not(
    .management-agent-row__identity
  )
  > strong {
  font-size: 12px;
}

.management-agent-row .report-change {
  width: fit-content;
  padding: 0;
  background: transparent;
}

.management-report-empty {
  padding: 28px 16px;
  color: var(--muted);
  font-size: 9px;
  text-align: center;
}

@media (max-width: 1050px) {
  .management-reports__header {
    align-items: flex-start;
    flex-direction: column;
  }

  .management-summary-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .management-report-layout {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 720px) {
  .management-reports {
    padding: 22px 14px 44px;
  }

  .management-report-filters {
    width: 100%;
    align-items: stretch;
    flex-direction: column;
  }

  .management-report-filters select {
    width: 100%;
  }

  .management-period-switch {
    width: 100%;
  }

  .management-period-switch__item {
    flex: 1 1 0;
  }

  .management-state-strip,
  .management-summary-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .management-state-strip > div:nth-child(2) {
    border-right: 0;
  }

  .management-state-strip > div:nth-child(-n + 2) {
    border-bottom: 1px solid var(--line);
  }

  .management-agent-row {
    grid-template-columns: 1fr 1fr;
  }

  .management-agent-row__identity {
    grid-column: 1 / -1;
  }

  .management-report-panel__note {
    display: none;
  }
}

/* --- /WAPP P2.6 ------------------------------------------------------ */
EOF
fi

# ---------------------------------------------------------------------------
# Unit test registration
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
  "src/modules/analytics/management-report.metrics.test.ts";

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

cat > docs/P2_06_MANAGEMENT_REPORTS.md <<'EOF'
# P2.6 Management reports

P2.6 adds a management layer on top of the P1.13 operational analytics.

Endpoint:

`GET /api/v1/reports/management?days=7|30|90&queueId=<optional uuid>`

Permission:

`reports.read`

Allowed roles:

- OWNER
- ADMIN
- SUPERVISOR

AGENT does not receive management-report access.

## Current operational state

The report exposes the current number of:

- active tickets;
- tickets waiting for a reply;
- tickets currently beyond SLA;
- unassigned tickets.

These are snapshots, not period totals.

## Period comparison

The selected period is compared with the immediately preceding period of the
same size.

Metrics:

- created tickets;
- closed tickets;
- reopened tickets;
- outbound messages sent by actual Wapp users;
- average first-response time;
- first-response SLA compliance;
- average resolution time;
- closed/created throughput.

When the previous value is zero, Wapp returns a null percentage change rather
than inventing an infinite percentage.

## Agent attribution

P2.6 deliberately avoids attributing historical production to the ticket's
current assignee.

Closed-ticket production uses the `CLOSED` TicketEvent
`actorMembershipId`.

Outbound-message production uses Message `sentByUserId`.

The current active-ticket count still uses current assignment because that is
a workload snapshot.

This makes transfer-heavy workflows materially more trustworthy.

## Queue metrics

Queue metrics use the queue currently/finally associated with each ticket.
The schema does not yet persist a complete historical queue dimension for every
metric sample. This limitation is explicit and should be considered when a
ticket moves between queues during the reporting period.

## Time metrics

First response:

`firstInboundAt -> firstResponseAt`

Resolution:

`createdAt -> closedAt`

These are elapsed wall-clock durations. Business-hours calendars are not part
of P2.6.

## UI

`/dashboard/reports`

Includes:

- 7 / 30 / 90-day period control;
- queue filter;
- current-state strip;
- comparison KPI cards;
- created-vs-closed daily trend;
- queue performance table;
- attributable agent production table.

No database migration is required for P2.6.
EOF

echo "[P2.6] Unit tests..."
pnpm test

echo "[P2.6] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P2.6] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.6] CODE VALIDATION PASS."
echo "No Prisma migration is required."
echo
echo "Next:"
echo "  pnpm test:integration"
echo "  pnpm dev"
