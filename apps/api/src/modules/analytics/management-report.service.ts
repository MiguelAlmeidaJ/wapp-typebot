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
