import {
  randomUUID
} from "node:crypto";

import {
  AppError
} from "../../errors/app-error.js";
import {
  prisma
} from "../../lib/database.js";
import {
  publishRealtime
} from "../realtime/realtime.bus.js";
import {
  inboundNotificationKey,
  notificationPreview,
  uniqueMembershipIds
} from "./notification.policy.js";

export type NotificationType =
  | "NEW_TICKET"
  | "INBOUND_MESSAGE"
  | "ASSIGNED_TO_YOU"
  | "TASK_ASSIGNED"
  | "TASK_REMINDER";

async function createOrRefreshNotification(input: {
  companyId: string;
  membershipId: string;
  ticketId?:
    string;
  contactId?:
    string;
  messageId?:
    string;
  type:
    NotificationType;
  title: string;
  body: string;
  dedupeKey: string;
  incrementOccurrence?:
    boolean;
}) {
  const notification =
    await prisma.notification.upsert({
      where: {
        companyId_membershipId_dedupeKey: {
          companyId:
            input.companyId,
          membershipId:
            input.membershipId,
          dedupeKey:
            input.dedupeKey
        }
      },
      create: {
        companyId:
          input.companyId,
        membershipId:
          input.membershipId,
        ticketId:
          input.ticketId,
        contactId:
          input.contactId,
        messageId:
          input.messageId,
        type:
          input.type,
        title:
          input.title,
        body:
          input.body,
        dedupeKey:
          input.dedupeKey
      },
      update: {
        ticketId:
          input.ticketId,
        contactId:
          input.contactId,
        messageId:
          input.messageId,
        type:
          input.type,
        title:
          input.title,
        body:
          input.body,
        ...(input.incrementOccurrence ===
        false
          ? {}
          : {
              occurrenceCount: {
                increment:
                  1
              }
            }),
        readAt:
          null
      }
    });

  publishRealtime(
    input.companyId,
    {
      type:
        "notification.created",
      notificationId:
        notification.id,
      membershipId:
        input.membershipId,
      ticketId:
        input.ticketId,
      contactId:
        input.contactId,
      messageId:
        input.messageId
    }
  );

  return notification;
}

async function activeRecipient(
  companyId: string,
  membershipId: string
) {
  return prisma.companyMembership.findFirst({
    where: {
      id:
        membershipId,
      companyId,
      isActive:
        true,
      user: {
        isActive:
          true
      }
    },
    select: {
      id:
        true
    }
  });
}

async function recipientIdsForTicket(input: {
  companyId: string;
  ticketId: string;
}) {
  const ticket =
    await prisma.ticket.findFirst({
      where: {
        id:
          input.ticketId,
        companyId:
          input.companyId
      },
      select: {
        assignedMembershipId:
          true,
        queueId:
          true
      }
    });

  if (
    !ticket
  ) {
    return [];
  }

  if (
    ticket
      .assignedMembershipId
  ) {
    const recipient =
      await activeRecipient(
        input.companyId,
        ticket
          .assignedMembershipId
      );

    return recipient
      ? [
          recipient.id
        ]
      : [];
  }

  if (
    ticket.queueId
  ) {
    const queueMembers =
      await prisma.queueMember.findMany({
        where: {
          queueId:
            ticket.queueId,
          membership: {
            companyId:
              input.companyId,
            isActive:
              true,
            user: {
              isActive:
                true
            }
          }
        },
        select: {
          membershipId:
            true
        }
      });

    const queueRecipients =
      uniqueMembershipIds(
        queueMembers.map(
          item =>
            item.membershipId
        )
      );

    if (
      queueRecipients.length >
      0
    ) {
      return queueRecipients;
    }
  }

  const activeMemberships =
    await prisma.companyMembership.findMany({
      where: {
        companyId:
          input.companyId,
        isActive:
          true,
        user: {
          isActive:
            true
        }
      },
      select: {
        id:
          true
      }
    });

  return activeMemberships.map(
    item =>
      item.id
  );
}

export async function notifyInboundTicketActivity(input: {
  companyId: string;
  ticketId: string;
  messageId: string;
  isNewTicket: boolean;
  preview:
    string
    | null;
  fallbackPreview:
    string;
}) {
  const ticket =
    await prisma.ticket.findFirst({
      where: {
        id:
          input.ticketId,
        companyId:
          input.companyId
      },
      select: {
        contact: {
          select: {
            name:
              true
          }
        }
      }
    });

  if (
    !ticket
  ) {
    return [];
  }

  const recipients =
    await recipientIdsForTicket({
      companyId:
        input.companyId,
      ticketId:
        input.ticketId
    });

  const type:
    NotificationType =
    input.isNewTicket
      ? "NEW_TICKET"
      : "INBOUND_MESSAGE";

  const title =
    input.isNewTicket
      ? "Novo atendimento"
      : `Nova mensagem · ${ticket.contact.name}`;

  const body =
    input.isNewTicket
      ? `${ticket.contact.name}: ${notificationPreview(
          input.preview,
          input.fallbackPreview
        )}`
      : notificationPreview(
          input.preview,
          input.fallbackPreview
        );

  const dedupeKey =
    inboundNotificationKey(
      input.ticketId,
      input.isNewTicket
    );

  return Promise.all(
    recipients.map(
      membershipId =>
        createOrRefreshNotification({
          companyId:
            input.companyId,
          membershipId,
          ticketId:
            input.ticketId,
          messageId:
            input.messageId,
          type,
          title,
          body,
          dedupeKey
        })
    )
  );
}

export async function notifyTicketAssignment(input: {
  companyId: string;
  ticketId: string;
  membershipId: string;
  actorMembershipId?:
    string
    | null;
}) {
  if (
    input.actorMembershipId &&
    input.actorMembershipId ===
      input.membershipId
  ) {
    return null;
  }

  const [
    recipient,
    ticket
  ] =
    await Promise.all([
      activeRecipient(
        input.companyId,
        input.membershipId
      ),
      prisma.ticket.findFirst({
        where: {
          id:
            input.ticketId,
          companyId:
            input.companyId
        },
        select: {
          contact: {
            select: {
              name:
                true
            }
          },
          queue: {
            select: {
              name:
                true
            }
          }
        }
      })
    ]);

  if (
    !recipient ||
    !ticket
  ) {
    return null;
  }

  return createOrRefreshNotification({
    companyId:
      input.companyId,
    membershipId:
      input.membershipId,
    ticketId:
      input.ticketId,
    type:
      "ASSIGNED_TO_YOU",
    title:
      "Atendimento atribuído a você",
    body:
      ticket.queue
        ? `${ticket.contact.name} · ${ticket.queue.name}`
        : ticket
            .contact
            .name,
    dedupeKey:
      `assignment:${input.ticketId}:${randomUUID()}`
  });
}

export async function notifyTaskAssignment(input: {
  companyId: string;
  membershipId: string;
  actorMembershipId: string;
  taskId: string;
  contactId: string;
  ticketId?: string | null;
  taskTitle: string;
  contactName: string;
}) {
  if (input.membershipId === input.actorMembershipId) return null;

  const recipient = await activeRecipient(
    input.companyId,
    input.membershipId
  );

  if (!recipient) return null;

  return createOrRefreshNotification({
    companyId: input.companyId,
    membershipId: input.membershipId,
    ticketId: input.ticketId ?? undefined,
    contactId: input.contactId,
    type: "TASK_ASSIGNED",
    title: "Nova tarefa atribuída",
    body: `${input.taskTitle} · ${input.contactName}`,
    dedupeKey: `task-assignment:${input.taskId}:${input.membershipId}`,
    incrementOccurrence: false
  });
}

export async function notifyTaskReminder(input: {
  companyId: string;
  membershipId: string;
  taskId: string;
  contactId: string;
  ticketId?: string | null;
  taskTitle: string;
  contactName: string;
  remindAt: Date;
}) {
  const recipient = await activeRecipient(
    input.companyId,
    input.membershipId
  );

  if (!recipient) return null;

  return createOrRefreshNotification({
    companyId: input.companyId,
    membershipId: input.membershipId,
    ticketId: input.ticketId ?? undefined,
    contactId: input.contactId,
    type: "TASK_REMINDER",
    title: "Lembrete de tarefa",
    body: `${input.taskTitle} · ${input.contactName}`,
    dedupeKey: `task-reminder:${input.taskId}:${input.remindAt.toISOString()}`,
    incrementOccurrence: false
  });
}

export async function listNotifications(input: {
  companyId: string;
  membershipId: string;
  limit: number;
  unreadOnly:
    boolean;
}) {
  const where = {
    companyId:
      input.companyId,
    membershipId:
      input.membershipId,
    ...(input.unreadOnly
      ? {
          readAt:
            null
        }
      : {})
  };

  const [
    notifications,
    unreadCount
  ] =
    await Promise.all([
      prisma.notification.findMany({
        where,
        orderBy: {
          updatedAt:
            "desc"
        },
        take:
          Math.min(
            Math.max(
              input.limit,
              1
            ),
            100
          )
      }),
      prisma.notification.count({
        where: {
          companyId:
            input.companyId,
          membershipId:
            input.membershipId,
          readAt:
            null
        }
      })
    ]);

  return {
    notifications,
    unreadCount
  };
}

export async function markNotificationRead(input: {
  companyId: string;
  membershipId: string;
  notificationId: string;
}) {
  const result =
    await prisma.notification.updateMany({
      where: {
        id:
          input.notificationId,
        companyId:
          input.companyId,
        membershipId:
          input.membershipId
      },
      data: {
        readAt:
          new Date()
      }
    });

  if (
    result.count !==
    1
  ) {
    throw new AppError(
      "Notificação não encontrada.",
      404,
      "NOTIFICATION_NOT_FOUND"
    );
  }

  return prisma.notification.findUniqueOrThrow({
    where: {
      id:
        input.notificationId
    }
  });
}

export async function markAllNotificationsRead(input: {
  companyId: string;
  membershipId: string;
}) {
  const result =
    await prisma.notification.updateMany({
      where: {
        companyId:
          input.companyId,
        membershipId:
          input.membershipId,
        readAt:
          null
      },
      data: {
        readAt:
          new Date()
      }
    });

  return {
    updated:
      result.count
  };
}
