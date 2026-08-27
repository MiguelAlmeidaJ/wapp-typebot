export type RealtimeEventType =
  | "realtime.ready"
  | "message.created"
  | "message.updated"
  | "note.created"
  | "quick-reply.updated"
  | "tag.updated"
  | "sla.updated"
  | "ticket.event.created"
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
  noteId?: string;
  quickReplyId?: string;
  tagId?: string;
  eventId?: string;
  queueId?: string;
  connectionId?: string;
  membershipId?: string;
  online?: boolean;
}
