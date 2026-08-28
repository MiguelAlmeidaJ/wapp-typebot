import type {
  Prisma
} from "../generated/prisma/client.js";

import { env } from "../config/env.js";
import { prisma } from "../lib/database.js";
import { toPrismaJson } from "../lib/prisma-json.js";
import {
  retentionCutoff,
  staleMediaCutoff
} from "./maintenance.policy.js";

export type MaintenanceSource =
  | "SCHEDULED"
  | "CLI";

export async function runMaintenance(
  source: MaintenanceSource
) {
  const startedAt =
    new Date();

  const run =
    await prisma.maintenanceRun.create({
      data: {
        source,
        status:
          "RUNNING",
        startedAt
      }
    });

  try {
    const sessionCutoff =
      retentionCutoff(
        startedAt,
        env
          .SESSION_RETENTION_DAYS
      );

    const mediaCutoff =
      staleMediaCutoff(
        startedAt,
        env
          .MAINTENANCE_STALE_MEDIA_MINUTES
      );

    const [
      deletedSessions,
      stalePendingMedia,
      failedMedia,
      failedDelivery,
      evolutionDown
    ] =
      await prisma.$transaction([
        prisma.session.deleteMany({
          where: {
            OR: [
              {
                expiresAt: {
                  lt:
                    sessionCutoff
                }
              },
              {
                revokedAt: {
                  not: null,
                  lt:
                    sessionCutoff
                }
              }
            ]
          }
        }),
        prisma.message.count({
          where: {
            mediaStatus:
              "PENDING",
            createdAt: {
              lt:
                mediaCutoff
            }
          }
        }),
        prisma.message.count({
          where: {
            mediaStatus:
              "FAILED"
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
                retentionCutoff(
                  startedAt,
                  1
                )
            }
          }
        }),
        prisma.whatsAppConnection.count({
          where: {
            healthStatus:
              "DOWN"
          }
        })
      ]);

    const result = {
      deletedSessions:
        deletedSessions.count,
      diagnostics: {
        stalePendingMedia,
        failedMedia,
        failedDeliveryLast24h:
          failedDelivery,
        evolutionDown
      },
      policy: {
        sessionRetentionDays:
          env
            .SESSION_RETENTION_DAYS,
        staleMediaMinutes:
          env
            .MAINTENANCE_STALE_MEDIA_MINUTES
      }
    };

    const finishedAt =
      new Date();

    await prisma.maintenanceRun.update({
      where: {
        id:
          run.id
      },
      data: {
        status:
          "SUCCESS",
        result:
          toPrismaJson(
            result
          ) as Prisma.InputJsonValue,
        finishedAt
      }
    });

    console.info(
      "[maintenance] completed",
      result
    );

    return result;
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : "Unknown maintenance error.";

    await prisma.maintenanceRun.update({
      where: {
        id:
          run.id
      },
      data: {
        status:
          "FAILED",
        error:
          message.slice(
            0,
            4_000
          ),
        finishedAt:
          new Date()
      }
    });

    throw error;
  }
}

export async function getMaintenanceStatus() {
  return prisma.maintenanceRun.findMany({
    orderBy: [
      {
        createdAt:
          "desc"
      },
      {
        id:
          "desc"
      }
    ],
    take: 20
  });
}
