import { env } from "../../config/env.js";
import { prisma } from "../../lib/database.js";

export interface OperationalAlert {
  code: string;
  severity:
    | "INFO"
    | "WARNING"
    | "CRITICAL";
  count: number;
  message: string;
}

export async function getOperationalAlerts(
  companyId: string
) {
  const staleCutoff =
    new Date(
      Date.now() -
        env
          .MAINTENANCE_STALE_MEDIA_MINUTES *
          60 *
          1_000
    );

  const last24h =
    new Date(
      Date.now() -
        24 *
          60 *
          60 *
          1_000
    );

  const [
    down,
    degraded,
    staleMedia,
    failedMedia,
    failedDelivery,
    maintenanceFailure
  ] =
    await Promise.all([
      prisma.whatsAppConnection.count({
        where: {
          companyId,
          healthStatus:
            "DOWN"
        }
      }),
      prisma.whatsAppConnection.count({
        where: {
          companyId,
          healthStatus:
            "DEGRADED"
        }
      }),
      prisma.message.count({
        where: {
          companyId,
          mediaStatus:
            "PENDING",
          createdAt: {
            lt:
              staleCutoff
          }
        }
      }),
      prisma.message.count({
        where: {
          companyId,
          mediaStatus:
            "FAILED"
        }
      }),
      prisma.message.count({
        where: {
          companyId,
          direction:
            "OUTBOUND",
          deliveryStatus:
            "FAILED",
          timestamp: {
            gte:
              last24h
          }
        }
      }),
      prisma.maintenanceRun.findFirst({
        where: {
          status:
            "FAILED",
          createdAt: {
            gte:
              last24h
          }
        },
        select: {
          id: true
        }
      })
    ]);

  const alerts:
    OperationalAlert[] =
    [];

  if (down > 0) {
    alerts.push({
      code:
        "EVOLUTION_DOWN",
      severity:
        "CRITICAL",
      count:
        down,
      message:
        `${down} conexão(ões) sem resposta da Evolution.`
    });
  }

  if (degraded > 0) {
    alerts.push({
      code:
        "WHATSAPP_DEGRADED",
      severity:
        "WARNING",
      count:
        degraded,
      message:
        `${degraded} conexão(ões) acessíveis, mas não conectadas.`
    });
  }

  if (
    staleMedia >
    0
  ) {
    alerts.push({
      code:
        "MEDIA_STALE_PENDING",
      severity:
        "WARNING",
      count:
        staleMedia,
      message:
        `${staleMedia} mídia(s) permanecem pendentes além da janela operacional.`
    });
  }

  if (
    failedMedia >
    0
  ) {
    alerts.push({
      code:
        "MEDIA_FAILED",
      severity:
        "WARNING",
      count:
        failedMedia,
      message:
        `${failedMedia} mídia(s) falharam no processamento.`
    });
  }

  if (
    failedDelivery >
    0
  ) {
    alerts.push({
      code:
        "DELIVERY_FAILED",
      severity:
        "WARNING",
      count:
        failedDelivery,
      message:
        `${failedDelivery} mensagem(ns) de saída falharam nas últimas 24h.`
    });
  }

  if (
    maintenanceFailure
  ) {
    alerts.push({
      code:
        "MAINTENANCE_FAILED",
      severity:
        "CRITICAL",
      count: 1,
      message:
        "O housekeeping automático registrou falha nas últimas 24h."
    });
  }

  return {
    status:
      alerts.some(
        alert =>
          alert.severity ===
          "CRITICAL"
      )
        ? "CRITICAL"
        : alerts.length >
            0
          ? "ATTENTION"
          : "OK",
    alerts,
    checkedAt:
      new Date()
        .toISOString()
  };
}
