import type {
  FastifyInstance
} from "fastify";
import {
  Counter,
  Gauge,
  Histogram,
  Registry,
  collectDefaultMetrics
} from "prom-client";

import { prisma } from "../../lib/database.js";
import {
  getMediaCaptureJobCounts
} from "../../jobs/media-capture.queue.js";
import {
  getMaintenanceJobCounts
} from "../../jobs/maintenance.queue.js";

const registry =
  new Registry();

collectDefaultMetrics({
  register:
    registry,
  prefix:
    "wapp_process_"
});

const httpRequests =
  new Counter({
    name:
      "wapp_http_requests_total",
    help:
      "HTTP requests handled by Wapp API.",
    labelNames: [
      "method",
      "route",
      "status"
    ] as const,
    registers: [
      registry
    ]
  });

const httpDuration =
  new Histogram({
    name:
      "wapp_http_request_duration_seconds",
    help:
      "Wapp API request duration.",
    labelNames: [
      "method",
      "route",
      "status"
    ] as const,
    buckets: [
      0.01,
      0.025,
      0.05,
      0.1,
      0.25,
      0.5,
      1,
      2.5,
      5
    ],
    registers: [
      registry
    ]
  });

const tickets =
  new Gauge({
    name:
      "wapp_tickets",
    help:
      "Tickets by status.",
    labelNames: [
      "status"
    ] as const,
    registers: [
      registry
    ]
  });

const whatsappHealth =
  new Gauge({
    name:
      "wapp_whatsapp_connections",
    help:
      "WhatsApp connections by health state.",
    labelNames: [
      "health"
    ] as const,
    registers: [
      registry
    ]
  });

const media =
  new Gauge({
    name:
      "wapp_message_media",
    help:
      "Messages by media processing state.",
    labelNames: [
      "status"
    ] as const,
    registers: [
      registry
    ]
  });

const deliveryFailed =
  new Gauge({
    name:
      "wapp_outbound_delivery_failed_24h",
    help:
      "Outbound messages with failed delivery in the last 24 hours.",
    registers: [
      registry
    ]
  });

const jobs =
  new Gauge({
    name:
      "wapp_jobs",
    help:
      "BullMQ jobs by queue and state.",
    labelNames: [
      "queue",
      "state"
    ] as const,
    registers: [
      registry
    ]
  });

const maintenanceLastSuccess =
  new Gauge({
    name:
      "wapp_maintenance_last_success_timestamp_seconds",
    help:
      "Unix timestamp of the most recent successful maintenance run.",
    registers: [
      registry
    ]
  });

const requestStarted =
  new WeakMap<
    object,
    number
  >();

export function installHttpMetricsHooks(
  app: FastifyInstance
) {
  app.addHook(
    "onRequest",
    async request => {
      requestStarted.set(
        request,
        performance.now()
      );
    }
  );

  app.addHook(
    "onResponse",
    async (
      request,
      reply
    ) => {
      const start =
        requestStarted.get(
          request
        );

      requestStarted.delete(
        request
      );

      const labels = {
        method:
          request.method,
        route:
          request
            .routeOptions
            .url ??
          "unknown",
        status:
          String(
            reply.statusCode
          )
      };

      httpRequests.inc(
        labels
      );

      if (
        start !==
        undefined
      ) {
        httpDuration.observe(
          labels,
          Math.max(
            0,
            performance.now() -
              start
          ) /
            1_000
        );
      }
    }
  );
}

async function refreshOperationalMetrics() {
  tickets.reset();
  whatsappHealth.reset();
  media.reset();
  jobs.reset();

  const [
    ticketGroups,
    healthGroups,
    mediaGroups,
    failed24h,
    mediaJobs,
    maintenanceJobs,
    lastMaintenance
  ] =
    await Promise.all([
      prisma.ticket.groupBy({
        by: [
          "status"
        ],
        _count: {
          _all: true
        }
      }),
      prisma.whatsAppConnection.groupBy({
        by: [
          "healthStatus"
        ],
        _count: {
          _all: true
        }
      }),
      prisma.message.groupBy({
        by: [
          "mediaStatus"
        ],
        _count: {
          _all: true
        }
      }),
      prisma.message.count({
        where: {
          direction:
            "OUTBOUND",
          deliveryStatus:
            "FAILED",
          timestamp: {
            gte:
              new Date(
                Date.now() -
                  24 *
                    60 *
                    60 *
                    1_000
              )
          }
        }
      }),
      getMediaCaptureJobCounts(),
      getMaintenanceJobCounts(),
      prisma.maintenanceRun.findFirst({
        where: {
          status:
            "SUCCESS"
        },
        orderBy: {
          finishedAt:
            "desc"
        },
        select: {
          finishedAt:
            true
        }
      })
    ]);

  for (
    const item
    of ticketGroups
  ) {
    tickets.set(
      {
        status:
          item.status
      },
      item._count._all
    );
  }

  for (
    const item
    of healthGroups
  ) {
    whatsappHealth.set(
      {
        health:
          item.healthStatus
      },
      item._count._all
    );
  }

  for (
    const item
    of mediaGroups
  ) {
    media.set(
      {
        status:
          item.mediaStatus
      },
      item._count._all
    );
  }

  deliveryFailed.set(
    failed24h
  );

  for (
    const [
      state,
      value
    ]
    of Object.entries(
      mediaJobs
    )
  ) {
    if (
      state ===
      "configured" ||
      typeof value !==
        "number"
    ) {
      continue;
    }

    jobs.set(
      {
        queue:
          "media",
        state
      },
      value
    );
  }

  for (
    const [
      state,
      value
    ]
    of Object.entries(
      maintenanceJobs
    )
  ) {
    if (
      state ===
      "configured" ||
      typeof value !==
        "number"
    ) {
      continue;
    }

    jobs.set(
      {
        queue:
          "maintenance",
        state
      },
      value
    );
  }

  maintenanceLastSuccess.set(
    lastMaintenance
      ?.finishedAt
      ?.getTime()
      ? lastMaintenance
          .finishedAt
          .getTime() /
        1_000
      : 0
  );
}

export async function renderMetrics() {
  await refreshOperationalMetrics();

  return registry.metrics();
}

export function metricsContentType() {
  return registry.contentType;
}
