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
