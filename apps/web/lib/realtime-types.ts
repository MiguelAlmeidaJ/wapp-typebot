export type RealtimeEventType =
  | "realtime.ready"
  | "message.created"
  | "message.updated"
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
