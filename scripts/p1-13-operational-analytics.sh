#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.13] Building operational analytics dashboard..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/auth/auth.guard.ts" \
  "apps/web/components/auth-provider.tsx" \
  "apps/web/app/dashboard/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -q "firstResponseSlaMinutes" apps/api/prisma/schema.prisma; then
  echo "ERROR: P1.13 requires P1.11 operational SLA."
  exit 1
fi

if ! grep -q "waitingSince" apps/api/prisma/schema.prisma; then
  echo "ERROR: P1.13 requires Ticket SLA clocks from P1.11."
  exit 1
fi

mkdir -p \
  apps/api/src/modules/analytics \
  apps/web/components/dashboard \
  docs

# ---------------------------------------------------------------------------
# Backend analytics service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/analytics/operational-analytics.service.ts <<'EOF'
import { prisma } from "../../lib/database.js";

const DAY_MS =
  24 * 60 * 60 * 1000;

function startOfDay(
  value: Date
) {
  const date =
    new Date(value);

  date.setHours(
    0,
    0,
    0,
    0
  );

  return date;
}

function dayKey(
  value: Date
) {
  return value
    .toISOString()
    .slice(0, 10);
}

function elapsedMinutes(
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

export async function getOperationalAnalytics(input: {
  companyId: string;
  days: 7 | 30 | 90;
}) {
  const now =
    new Date();

  const today =
    startOfDay(now);

  const from =
    new Date(
      today.getTime() -
        (
          input.days -
          1
        ) *
          DAY_MS
    );

  const company =
    await prisma.company.findUniqueOrThrow({
      where: {
        id: input.companyId
      },
      select: {
        firstResponseSlaMinutes:
          true,
        replySlaMinutes:
          true
      }
    });

  const [
    activeTickets,
    periodTickets
  ] =
    await Promise.all([
      prisma.ticket.findMany({
        where: {
          companyId:
            input.companyId,
          status: {
            in: [
              "OPEN",
              "PENDING"
            ]
          }
        },
        select: {
          id: true,
          status: true,
          waitingSince: true,
          firstInboundAt: true,
          firstResponseAt: true,
          queue: {
            select: {
              id: true,
              name: true
            }
          },
          assignedMembership: {
            select: {
              id: true,
              user: {
                select: {
                  id: true,
                  name: true
                }
              }
            }
          }
        }
      }),
      prisma.ticket.findMany({
        where: {
          companyId:
            input.companyId,
          OR: [
            {
              createdAt: {
                gte: from
              }
            },
            {
              closedAt: {
                gte: from
              }
            },
            {
              firstInboundAt: {
                gte: from
              }
            }
          ]
        },
        select: {
          id: true,
          createdAt: true,
          closedAt: true,
          firstInboundAt: true,
          firstResponseAt: true
        }
      })
    ]);

  let waitingNow = 0;
  let breachedNow = 0;
  let riskNow = 0;

  const queueMap =
    new Map<
      string,
      {
        id: string | null;
        name: string;
        active: number;
        waiting: number;
        breached: number;
      }
    >();

  const assigneeMap =
    new Map<
      string,
      {
        id: string | null;
        name: string;
        active: number;
        waiting: number;
        breached: number;
      }
    >();

  for (const ticket of activeTickets) {
    const firstWaiting =
      ticket.firstInboundAt &&
      !ticket.firstResponseAt
        ? elapsedMinutes(
            ticket.firstInboundAt,
            now
          )
        : null;

    const replyWaiting =
      ticket.waitingSince
        ? elapsedMinutes(
            ticket.waitingSince,
            now
          )
        : null;

    const firstBreached =
      firstWaiting !== null &&
      firstWaiting >=
        company
          .firstResponseSlaMinutes;

    const replyBreached =
      replyWaiting !== null &&
      replyWaiting >=
        company.replySlaMinutes;

    const firstRisk =
      firstWaiting !== null &&
      !firstBreached &&
      firstWaiting >=
        Math.ceil(
          company
            .firstResponseSlaMinutes *
            0.7
        );

    const replyRisk =
      replyWaiting !== null &&
      !replyBreached &&
      replyWaiting >=
        Math.ceil(
          company
            .replySlaMinutes *
            0.7
        );

    const waiting =
      Boolean(
        ticket.waitingSince ||
        (
          ticket.firstInboundAt &&
          !ticket.firstResponseAt
        )
      );

    const breached =
      firstBreached ||
      replyBreached;

    const risk =
      !breached &&
      (
        firstRisk ||
        replyRisk
      );

    if (waiting) {
      waitingNow += 1;
    }

    if (breached) {
      breachedNow += 1;
    } else if (risk) {
      riskNow += 1;
    }

    const queueKey =
      ticket.queue?.id ??
      "__none__";

    const queue =
      queueMap.get(
        queueKey
      ) ?? {
        id:
          ticket.queue?.id ??
          null,
        name:
          ticket.queue?.name ??
          "Sem fila",
        active: 0,
        waiting: 0,
        breached: 0
      };

    queue.active += 1;

    if (waiting) {
      queue.waiting += 1;
    }

    if (breached) {
      queue.breached += 1;
    }

    queueMap.set(
      queueKey,
      queue
    );

    const assigneeKey =
      ticket
        .assignedMembership
        ?.id ??
      "__none__";

    const assignee =
      assigneeMap.get(
        assigneeKey
      ) ?? {
        id:
          ticket
            .assignedMembership
            ?.id ??
          null,
        name:
          ticket
            .assignedMembership
            ?.user.name ??
          "Sem atendente",
        active: 0,
        waiting: 0,
        breached: 0
      };

    assignee.active += 1;

    if (waiting) {
      assignee.waiting += 1;
    }

    if (breached) {
      assignee.breached += 1;
    }

    assigneeMap.set(
      assigneeKey,
      assignee
    );
  }

  const createdInPeriod =
    periodTickets.filter(
      ticket =>
        ticket.createdAt >=
        from
    );

  const closedInPeriod =
    periodTickets.filter(
      ticket =>
        ticket.closedAt &&
        ticket.closedAt >=
          from
    );

  const firstResponseSamples =
    periodTickets
      .filter(
        ticket =>
          ticket.firstInboundAt &&
          ticket.firstInboundAt >=
            from &&
          ticket.firstResponseAt &&
          ticket.firstResponseAt >=
            ticket.firstInboundAt
      )
      .map(ticket =>
        elapsedMinutes(
          ticket.firstInboundAt!,
          ticket.firstResponseAt!
        )
      );

  const averageFirstResponseMinutes =
    firstResponseSamples.length
      ? Math.round(
          firstResponseSamples.reduce(
            (sum, value) =>
              sum + value,
            0
          ) /
            firstResponseSamples.length
        )
      : null;

  const compliantFirstResponses =
    firstResponseSamples.filter(
      minutes =>
        minutes <=
        company
          .firstResponseSlaMinutes
    ).length;

  const firstResponseSlaPercent =
    firstResponseSamples.length
      ? Math.round(
          (
            compliantFirstResponses /
            firstResponseSamples.length
          ) *
            100
        )
      : null;

  const trendMap =
    new Map<
      string,
      {
        date: string;
        created: number;
        closed: number;
      }
    >();

  for (
    let index = 0;
    index < input.days;
    index += 1
  ) {
    const date =
      new Date(
        from.getTime() +
          index *
            DAY_MS
      );

    const key =
      dayKey(date);

    trendMap.set(
      key,
      {
        date: key,
        created: 0,
        closed: 0
      }
    );
  }

  for (const ticket of createdInPeriod) {
    const key =
      dayKey(
        ticket.createdAt
      );

    const day =
      trendMap.get(key);

    if (day) {
      day.created += 1;
    }
  }

  for (const ticket of closedInPeriod) {
    if (!ticket.closedAt) {
      continue;
    }

    const key =
      dayKey(
        ticket.closedAt
      );

    const day =
      trendMap.get(key);

    if (day) {
      day.closed += 1;
    }
  }

  const byQueue =
    [...queueMap.values()]
      .sort(
        (a, b) =>
          b.active -
          a.active
      )
      .slice(0, 12);

  const byAssignee =
    [...assigneeMap.values()]
      .sort(
        (a, b) =>
          b.active -
          a.active
      )
      .slice(0, 12);

  return {
    period: {
      days:
        input.days,
      from:
        from.toISOString(),
      to:
        now.toISOString()
    },
    sla: {
      firstResponseSlaMinutes:
        company
          .firstResponseSlaMinutes,
      replySlaMinutes:
        company.replySlaMinutes
    },
    summary: {
      active:
        activeTickets.length,
      waiting:
        waitingNow,
      risk:
        riskNow,
      breached:
        breachedNow,
      created:
        createdInPeriod.length,
      closed:
        closedInPeriod.length,
      averageFirstResponseMinutes,
      firstResponseSlaPercent,
      firstResponseSamples:
        firstResponseSamples.length
    },
    trend:
      [...trendMap.values()],
    byQueue,
    byAssignee
  };
}
EOF

cat > apps/api/src/modules/analytics/operational-analytics.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import { getOperationalAnalytics } from "./operational-analytics.service.js";

const querySchema = z.object({
  days: z.coerce
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
        ].includes(value),
      {
        message:
          "days deve ser 7, 30 ou 90."
      }
    )
    .default(7)
});

export async function operationalAnalyticsRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/analytics/operational",
    async request => {
      const auth =
        await requirePermission(
          request,
          "sla.read"
        );

      const query =
        querySchema.parse(
          request.query
        );

      return getOperationalAnalytics({
        companyId:
          auth.companyId,
        days:
          query.days
      });
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register API route
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/src/app.ts";
let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { operationalAnalyticsRoutes } from "./modules/analytics/operational-analytics.routes.js";';

if (!content.includes(importLine)) {
  const candidates = [
    'import { slaRoutes } from "./modules/sla/sla.routes.js";',
    'import { ticketRoutes } from "./modules/tickets/ticket.routes.js";',
    'import { tagRoutes } from "./modules/tags/tag.routes.js";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find app.ts import anchor."
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
    "await app.register(operationalAnalyticsRoutes);"
  )
) {
  const candidates = [
    "  await app.register(slaRoutes);",
    "  await app.register(ticketRoutes);",
    "  await app.register(tagRoutes);"
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find app.ts registration anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  await app.register(operationalAnalyticsRoutes);`
  );
}

fs.writeFileSync(path, content);
console.log("Operational analytics route registered.");
NODE

# ---------------------------------------------------------------------------
# Dashboard component
# ---------------------------------------------------------------------------

cat > apps/web/components/dashboard/operational-dashboard.tsx <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";

type PeriodDays =
  | 7
  | 30
  | 90;

interface OperationalAnalytics {
  period: {
    days: PeriodDays;
    from: string;
    to: string;
  };
  sla: {
    firstResponseSlaMinutes: number;
    replySlaMinutes: number;
  };
  summary: {
    active: number;
    waiting: number;
    risk: number;
    breached: number;
    created: number;
    closed: number;
    averageFirstResponseMinutes: number | null;
    firstResponseSlaPercent: number | null;
    firstResponseSamples: number;
  };
  trend: Array<{
    date: string;
    created: number;
    closed: number;
  }>;
  byQueue: Array<{
    id: string | null;
    name: string;
    active: number;
    waiting: number;
    breached: number;
  }>;
  byAssignee: Array<{
    id: string | null;
    name: string;
    active: number;
    waiting: number;
    breached: number;
  }>;
}

function durationLabel(
  minutes: number | null
) {
  if (minutes === null) {
    return "—";
  }

  if (minutes < 60) {
    return `${minutes}m`;
  }

  const hours =
    Math.floor(
      minutes / 60
    );

  const remainder =
    minutes % 60;

  return remainder
    ? `${hours}h ${remainder}m`
    : `${hours}h`;
}

function dayLabel(
  value: string
) {
  const [
    year,
    month,
    day
  ] =
    value.split("-");

  return `${day}/${month}`;
}

export function OperationalDashboard() {
  const {
    request,
    subscribe
  } = useAuth();

  const [days, setDays] =
    useState<PeriodDays>(7);

  const [data, setData] =
    useState<OperationalAnalytics | null>(
      null
    );

  const [loading, setLoading] =
    useState(true);

  const [error, setError] =
    useState("");

  const load =
    useCallback(async () => {
      setLoading(true);

      try {
        const payload =
          await request<OperationalAnalytics>(
            `/api/v1/analytics/operational?days=${days}`
          );

        setData(payload);
        setError("");
      } catch {
        setError(
          "Não foi possível carregar os indicadores operacionais."
        );
      } finally {
        setLoading(false);
      }
    }, [
      days,
      request
    ]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    return subscribe(
      "/api/v1/realtime/events",
      event => {
        if (
          event.type ===
            "ticket.created" ||
          event.type ===
            "ticket.updated" ||
          event.type ===
            "message.created" ||
          event.type ===
            "sla.updated" ||
          event.type ===
            "ticket.event.created"
        ) {
          void load();
        }
      }
    );
  }, [
    load,
    subscribe
  ]);

  const maxTrend =
    useMemo(
      () =>
        Math.max(
          1,
          ...(
            data?.trend.flatMap(
              item => [
                item.created,
                item.closed
              ]
            ) ?? [1]
          )
        ),
      [data]
    );

  const maxQueue =
    useMemo(
      () =>
        Math.max(
          1,
          ...(
            data?.byQueue.map(
              item =>
                item.active
            ) ?? [1]
          )
        ),
      [data]
    );

  const maxAssignee =
    useMemo(
      () =>
        Math.max(
          1,
          ...(
            data?.byAssignee.map(
              item =>
                item.active
            ) ?? [1]
          )
        ),
      [data]
    );

  return (
    <section className="operational-dashboard">
      <div className="operational-dashboard__toolbar">
        <div>
          <span className="eyebrow">
            Operação em números
          </span>
          <h2>
            Visão operacional
          </h2>
        </div>

        <div className="operational-period">
          {(
            [
              7,
              30,
              90
            ] as PeriodDays[]
          ).map(value => (
            <button
              className={
                days === value
                  ? "operational-period__button operational-period__button--active"
                  : "operational-period__button"
              }
              key={value}
              onClick={() =>
                setDays(value)
              }
              type="button"
            >
              {value} dias
            </button>
          ))}
        </div>
      </div>

      {error && (
        <div className="operational-dashboard__error">
          {error}
        </div>
      )}

      {loading &&
      !data ? (
        <div className="operational-dashboard__loading">
          Carregando indicadores…
        </div>
      ) : data ? (
        <>
          <div className="operational-metrics">
            <article className="operational-metric">
              <span>
                Ativos agora
              </span>
              <strong>
                {
                  data.summary
                    .active
                }
              </strong>
              <small>
                OPEN + PENDING
              </small>
            </article>

            <article className="operational-metric">
              <span>
                Cliente aguardando
              </span>
              <strong>
                {
                  data.summary
                    .waiting
                }
              </strong>
              <small>
                {data.summary.risk} em risco
              </small>
            </article>

            <article className="operational-metric operational-metric--danger">
              <span>
                SLA estourado
              </span>
              <strong>
                {
                  data.summary
                    .breached
                }
              </strong>
              <small>
                situação atual
              </small>
            </article>

            <article className="operational-metric">
              <span>
                1ª resposta média
              </span>
              <strong>
                {durationLabel(
                  data.summary
                    .averageFirstResponseMinutes
                )}
              </strong>
              <small>
                {
                  data.summary
                    .firstResponseSamples
                }{" "}
                amostras
              </small>
            </article>

            <article className="operational-metric">
              <span>
                SLA 1ª resposta
              </span>
              <strong>
                {data.summary
                  .firstResponseSlaPercent ===
                null
                  ? "—"
                  : `${data.summary.firstResponseSlaPercent}%`}
              </strong>
              <small>
                limite{" "}
                {
                  data.sla
                    .firstResponseSlaMinutes
                }
                m
              </small>
            </article>

            <article className="operational-metric">
              <span>
                Criados / encerrados
              </span>
              <strong>
                {
                  data.summary
                    .created
                }
                {" / "}
                {
                  data.summary
                    .closed
                }
              </strong>
              <small>
                últimos {days} dias
              </small>
            </article>
          </div>

          <div className="operational-grid">
            <article className="operational-panel operational-panel--trend">
              <div className="operational-panel__heading">
                <div>
                  <span className="eyebrow">
                    Fluxo
                  </span>
                  <h3>
                    Entradas e encerramentos
                  </h3>
                </div>

                <div className="trend-legend">
                  <span>
                    <i className="trend-legend__created" />
                    Criados
                  </span>
                  <span>
                    <i className="trend-legend__closed" />
                    Encerrados
                  </span>
                </div>
              </div>

              <div className="trend-chart">
                {data.trend.map(
                  item => (
                    <div
                      className="trend-column"
                      key={
                        item.date
                      }
                    >
                      <div className="trend-column__bars">
                        <div
                          className="trend-bar trend-bar--created"
                          style={{
                            height:
                              `${Math.max(
                                item.created
                                  ? 6
                                  : 1,
                                (
                                  item.created /
                                  maxTrend
                                ) *
                                  100
                              )}%`
                          }}
                          title={`${item.created} criados`}
                        />

                        <div
                          className="trend-bar trend-bar--closed"
                          style={{
                            height:
                              `${Math.max(
                                item.closed
                                  ? 6
                                  : 1,
                                (
                                  item.closed /
                                  maxTrend
                                ) *
                                  100
                              )}%`
                          }}
                          title={`${item.closed} encerrados`}
                        />
                      </div>

                      <span>
                        {dayLabel(
                          item.date
                        )}
                      </span>
                    </div>
                  )
                )}
              </div>
            </article>

            <article className="operational-panel">
              <div className="operational-panel__heading">
                <div>
                  <span className="eyebrow">
                    Backlog
                  </span>
                  <h3>
                    Por fila
                  </h3>
                </div>
              </div>

              <div className="ranking-list">
                {data.byQueue.length ===
                0 ? (
                  <div className="ranking-list__empty">
                    Sem atendimentos ativos.
                  </div>
                ) : (
                  data.byQueue.map(
                    item => (
                      <div
                        className="ranking-item"
                        key={
                          item.id ??
                          "__none__"
                        }
                      >
                        <div className="ranking-item__heading">
                          <strong>
                            {
                              item.name
                            }
                          </strong>
                          <span>
                            {
                              item.active
                            }
                          </span>
                        </div>

                        <div className="ranking-track">
                          <span
                            style={{
                              width:
                                `${Math.max(
                                  4,
                                  (
                                    item.active /
                                    maxQueue
                                  ) *
                                    100
                                )}%`
                            }}
                          />
                        </div>

                        <small>
                          {item.waiting} aguardando ·{" "}
                          {item.breached} fora do SLA
                        </small>
                      </div>
                    )
                  )
                )}
              </div>
            </article>

            <article className="operational-panel">
              <div className="operational-panel__heading">
                <div>
                  <span className="eyebrow">
                    Distribuição
                  </span>
                  <h3>
                    Por atendente
                  </h3>
                </div>
              </div>

              <div className="ranking-list">
                {data.byAssignee.length ===
                0 ? (
                  <div className="ranking-list__empty">
                    Sem atendimentos ativos.
                  </div>
                ) : (
                  data.byAssignee.map(
                    item => (
                      <div
                        className="ranking-item"
                        key={
                          item.id ??
                          "__none__"
                        }
                      >
                        <div className="ranking-item__heading">
                          <strong>
                            {
                              item.name
                            }
                          </strong>
                          <span>
                            {
                              item.active
                            }
                          </span>
                        </div>

                        <div className="ranking-track">
                          <span
                            style={{
                              width:
                                `${Math.max(
                                  4,
                                  (
                                    item.active /
                                    maxAssignee
                                  ) *
                                    100
                                )}%`
                            }}
                          />
                        </div>

                        <small>
                          {item.waiting} aguardando ·{" "}
                          {item.breached} fora do SLA
                        </small>
                      </div>
                    )
                  )
                )}
              </div>
            </article>
          </div>

          <p className="operational-dashboard__footnote">
            SLA de primeira resposta usa tickets com resposta registrada no período. O Wapp não estima ciclos históricos que não foram persistidos.
          </p>
        </>
      ) : null}
    </section>
  );
}
EOF

# ---------------------------------------------------------------------------
# Replace placeholder dashboard metrics
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/page.tsx";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { OperationalDashboard } from "@/components/dashboard/operational-dashboard";';

if (!content.includes(importLine)) {
  const candidates = [
    'import { WappMark } from "@/components/wapp-mark";',
    'import { useAuth } from "@/components/auth-provider";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Dashboard import anchor not found."
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
    "<OperationalDashboard />"
  )
) {
  const start =
    content.indexOf(
      '          <div className="metric-grid">'
    );

  const endAnchor =
    `          <div
            className={
              canTestAdmin`;

  const end =
    content.indexOf(
      endAnchor,
      start
    );

  if (
    start < 0 ||
    end < 0
  ) {
    throw new Error(
      "Could not find placeholder metric-grid section."
    );
  }

  content =
    content.slice(
      0,
      start
    ) +
    `          <OperationalDashboard />

` +
    content.slice(end);
}

fs.writeFileSync(path, content);
console.log("Dashboard placeholders replaced by operational analytics.");
NODE

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.13 / Operational dashboard" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.13 / Operational dashboard ------------------------------ */

.operational-dashboard {
  display: grid;
  gap: 12px;
}

.operational-dashboard__toolbar {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 18px;
}

.operational-dashboard__toolbar > div:first-child {
  display: grid;
  gap: 3px;
}

.operational-dashboard__toolbar h2 {
  margin: 0;
  font-size: 16px;
  font-weight: 760;
}

.operational-period {
  display: flex;
  gap: 4px;
  border: 1px solid var(--line);
  border-radius: 10px;
  background: #fff;
  padding: 3px;
}

.operational-period__button {
  height: 29px;
  border: 0;
  border-radius: 7px;
  background: transparent;
  color: var(--muted);
  padding: 0 9px;
  font-size: 8px;
  font-weight: 750;
}

.operational-period__button--active {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.operational-dashboard__error {
  border: 1px solid #efd2cf;
  border-radius: 10px;
  background: var(--danger-soft);
  color: var(--danger);
  padding: 9px 11px;
  font-size: 9px;
}

.operational-dashboard__loading {
  display: grid;
  min-height: 160px;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: #fff;
  color: var(--muted);
  font-size: 9px;
}

.operational-metrics {
  display: grid;
  grid-template-columns:
    repeat(6, minmax(0, 1fr));
  gap: 8px;
}

.operational-metric {
  display: grid;
  min-width: 0;
  gap: 5px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: #fff;
  padding: 11px;
}

.operational-metric > span {
  overflow: hidden;
  color: var(--muted);
  font-size: 8px;
  font-weight: 700;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.operational-metric > strong {
  font-size: 20px;
  letter-spacing: -0.03em;
}

.operational-metric > small {
  color: var(--muted);
  font-size: 7px;
}

.operational-metric--danger > strong {
  color: var(--danger);
}

.operational-grid {
  display: grid;
  grid-template-columns:
    minmax(0, 1.45fr)
    minmax(250px, 0.75fr);
  gap: 9px;
}

.operational-panel {
  display: grid;
  align-content: start;
  min-width: 0;
  gap: 10px;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: #fff;
  padding: 12px;
}

.operational-panel--trend {
  grid-row: span 2;
}

.operational-panel__heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 10px;
}

.operational-panel__heading > div {
  display: grid;
  gap: 3px;
}

.operational-panel__heading h3 {
  margin: 0;
  font-size: 11px;
}

.trend-legend {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 8px;
}

.trend-legend > span {
  display: flex;
  align-items: center;
  gap: 4px;
  color: var(--muted);
  font-size: 7px;
}

.trend-legend i {
  display: inline-block;
  width: 7px;
  height: 7px;
  border-radius: 2px;
}

.trend-legend__created {
  background: #6e9d80;
}

.trend-legend__closed {
  background: #aab4ae;
}

.trend-chart {
  display: flex;
  min-height: 215px;
  align-items: stretch;
  gap: 3px;
  overflow-x: auto;
  padding-top: 8px;
}

.trend-column {
  display: grid;
  min-width: 16px;
  flex: 1 0 16px;
  grid-template-rows:
    minmax(0, 1fr)
    auto;
  gap: 5px;
}

.trend-column__bars {
  display: flex;
  height: 185px;
  align-items: flex-end;
  justify-content: center;
  gap: 2px;
  border-bottom: 1px solid var(--line);
}

.trend-bar {
  width: min(6px, 40%);
  min-height: 1px;
  border-radius: 3px 3px 0 0;
}

.trend-bar--created {
  background: #6e9d80;
}

.trend-bar--closed {
  background: #aab4ae;
}

.trend-column > span {
  overflow: hidden;
  color: var(--muted);
  font-size: 6px;
  text-align: center;
  white-space: nowrap;
}

.ranking-list {
  display: grid;
  gap: 9px;
}

.ranking-item {
  display: grid;
  gap: 5px;
}

.ranking-item__heading {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.ranking-item__heading strong {
  overflow: hidden;
  font-size: 8px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ranking-item__heading span {
  color: var(--ink);
  font-size: 9px;
  font-weight: 800;
}

.ranking-track {
  height: 5px;
  overflow: hidden;
  border-radius: 999px;
  background: #edf0ee;
}

.ranking-track > span {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: #779b85;
}

.ranking-item > small {
  color: var(--muted);
  font-size: 7px;
}

.ranking-list__empty {
  display: grid;
  min-height: 90px;
  place-items: center;
  color: var(--muted);
  font-size: 8px;
}

.operational-dashboard__footnote {
  margin: 0;
  color: var(--muted);
  font-size: 7px;
  line-height: 1.5;
}

@media (max-width: 1180px) {
  .operational-metrics {
    grid-template-columns:
      repeat(3, minmax(0, 1fr));
  }
}

@media (max-width: 900px) {
  .operational-grid {
    grid-template-columns: 1fr;
  }

  .operational-panel--trend {
    grid-row: auto;
  }
}

@media (max-width: 680px) {
  .operational-dashboard__toolbar {
    align-items: stretch;
    flex-direction: column;
  }

  .operational-period {
    width: fit-content;
  }

  .operational-metrics {
    grid-template-columns:
      repeat(2, minmax(0, 1fr));
  }

  .trend-chart {
    min-height: 185px;
  }

  .trend-column__bars {
    height: 155px;
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/OPERATIONAL_ANALYTICS.md <<'EOF'
# Operational analytics

P1.13 replaces the Dashboard placeholder metrics with real operational data.

## Periods

The operator can view:

- 7 days
- 30 days
- 90 days

## Current-state metrics

The dashboard shows:

- active OPEN/PENDING tickets;
- customers currently waiting;
- current tickets at SLA risk;
- current SLA breaches.

These use the P1.11 ticket clocks and company SLA settings.

## Period metrics

The selected period shows:

- tickets created;
- tickets closed;
- average first-response time;
- first-response SLA compliance.

First-response compliance only uses tickets that have a persisted first inbound
and first response.

Wapp does not invent historical reply cycles that were not persisted before
P1.11.

## Trend

The daily trend compares:

- ticket creation date;
- ticket close date.

## Backlog distribution

Current active backlog is grouped by:

- queue;
- assigned membership.

Each group includes:

- active count;
- waiting count;
- current SLA breach count.

## API

`GET /api/v1/analytics/operational?days=7`

Allowed periods:

- 7
- 30
- 90

The endpoint requires `sla.read`, which is available to every operational role.

## Migration

P1.13 adds no database schema. No Prisma migration is required.
EOF

echo "[P1.13] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.13] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.13] Operational analytics dashboard installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Test:"
echo "  1. open /dashboard"
echo "  2. switch 7 / 30 / 90 days"
echo "  3. compare Ativos with Conversations"
echo "  4. compare waiting/breached with SLA monitor"
echo "  5. close a test ticket and confirm dashboard refreshes"
