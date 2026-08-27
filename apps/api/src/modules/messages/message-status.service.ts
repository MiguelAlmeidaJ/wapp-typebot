import type {
  MessageDeliveryStatus,
  WhatsAppConnection
} from "../../generated/prisma/client.js";

import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

type UnknownRecord = Record<string, unknown>;

const statusRank: Record<
  MessageDeliveryStatus,
  number
> = {
  NONE: 0,
  PENDING: 1,
  SENT: 2,
  DELIVERED: 3,
  READ: 4,
  PLAYED: 5,
  FAILED: 99
};

function record(
  value: unknown
): UnknownRecord | undefined {
  return value &&
    typeof value === "object" &&
    !Array.isArray(value)
    ? (value as UnknownRecord)
    : undefined;
}

function stringValue(
  value: unknown
) {
  if (
    typeof value === "string" &&
    value.trim()
  ) {
    return value.trim();
  }

  return undefined;
}

function normalizeStatus(
  value: unknown
): MessageDeliveryStatus | undefined {
  if (typeof value === "number") {
    switch (value) {
      case 0:
        return "FAILED";
      case 1:
        return "PENDING";
      case 2:
        return "SENT";
      case 3:
        return "DELIVERED";
      case 4:
        return "READ";
      case 5:
        return "PLAYED";
      default:
        return undefined;
    }
  }

  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value
    .trim()
    .toUpperCase()
    .replace(/[\s.-]+/g, "_");

  switch (normalized) {
    case "ERROR":
    case "FAILED":
    case "FAILURE":
      return "FAILED";

    case "PENDING":
      return "PENDING";

    case "SERVER_ACK":
    case "SENT":
      return "SENT";

    case "DELIVERY_ACK":
    case "DELIVERED":
      return "DELIVERED";

    case "READ":
      return "READ";

    case "PLAYED":
      return "PLAYED";

    default:
      return undefined;
  }
}

function updateItems(
  body: UnknownRecord
): UnknownRecord[] {
  const data = body.data;

  if (Array.isArray(data)) {
    return data
      .map(item => record(item))
      .filter(
        (item): item is UnknownRecord =>
          Boolean(item)
      );
  }

  const dataRecord = record(data);

  return dataRecord
    ? [dataRecord]
    : [];
}

function externalId(
  item: UnknownRecord
) {
  const key = record(item.key);

  return (
    stringValue(key?.id) ??
    stringValue(item.id) ??
    stringValue(
      record(item.message)?.id
    )
  );
}

function itemStatus(
  item: UnknownRecord
) {
  const update = record(item.update);

  return normalizeStatus(
    update?.status ??
    item.status
  );
}

function failureReason(
  item: UnknownRecord
) {
  const update = record(item.update);

  const candidates = [
    update?.message,
    update?.error,
    item.message,
    item.error
  ];

  for (const candidate of candidates) {
    const value = stringValue(candidate);

    if (value) {
      return value.slice(0, 2_000);
    }
  }

  return null;
}

function shouldAdvance(
  current: MessageDeliveryStatus,
  next: MessageDeliveryStatus
) {
  if (next === "FAILED") {
    return (
      current !== "READ" &&
      current !== "PLAYED"
    );
  }

  if (current === "FAILED") {
    return false;
  }

  return (
    statusRank[next] >
    statusRank[current]
  );
}

export async function ingestEvolutionMessageUpdate(
  body: UnknownRecord,
  connection: WhatsAppConnection
) {
  const results: Array<{
    externalId: string;
    status: MessageDeliveryStatus;
    updated: boolean;
  }> = [];

  for (const item of updateItems(body)) {
    const id = externalId(item);
    const status = itemStatus(item);

    if (!id || !status) {
      continue;
    }

    const current =
      await prisma.message.findUnique({
        where: {
          whatsappConnectionId_externalId: {
            whatsappConnectionId:
              connection.id,
            externalId: id
          }
        },
        select: {
          id: true,
          ticketId: true,
          companyId: true,
          direction: true,
          deliveryStatus: true
        }
      });

    if (
      !current ||
      current.direction !== "OUTBOUND"
    ) {
      results.push({
        externalId: id,
        status,
        updated: false
      });
      continue;
    }

    if (
      current.deliveryStatus === status ||
      !shouldAdvance(
        current.deliveryStatus,
        status
      )
    ) {
      results.push({
        externalId: id,
        status,
        updated: false
      });
      continue;
    }

    const now = new Date();

    await prisma.message.update({
      where: {
        id: current.id
      },
      data: {
        deliveryStatus: status,
        ...(status === "DELIVERED"
          ? {
              deliveredAt: now
            }
          : {}),
        ...(status === "READ"
          ? {
              deliveredAt:
                now,
              readAt: now
            }
          : {}),
        ...(status === "PLAYED"
          ? {
              deliveredAt:
                now,
              readAt: now,
              playedAt: now
            }
          : {}),
        ...(status === "FAILED"
          ? {
              deliveryError:
                failureReason(item) ??
                "A Evolution informou falha na entrega."
            }
          : {
              deliveryError: null
            })
      }
    });

    publishRealtime(
      current.companyId,
      {
        type: "message.updated",
        ticketId: current.ticketId,
        messageId: current.id
      }
    );

    results.push({
      externalId: id,
      status,
      updated: true
    });
  }

  return results;
}
