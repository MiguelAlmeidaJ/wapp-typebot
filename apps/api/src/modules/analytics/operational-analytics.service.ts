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
