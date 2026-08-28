import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import type { WappRole } from "../../lib/tokens.js";
import {
  notifyTaskAssignment,
  notifyTaskReminder
} from "../notifications/notification.service.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import {
  canAssignTaskTo,
  canMutateTask,
  isTaskManager,
  TASK_REMINDER_STALE_MS,
  taskTimeError
} from "./task.policy.js";

type TaskPriority = "LOW" | "NORMAL" | "HIGH" | "URGENT";

const taskInclude = {
  contact: {
    select: {
      id: true,
      name: true,
      phoneNumber: true,
      email: true
    }
  },
  ticket: {
    select: {
      id: true,
      status: true,
      lastMessage: true,
      lastMessageAt: true
    }
  },
  assigneeMembership: {
    select: {
      id: true,
      user: {
        select: {
          id: true,
          name: true
        }
      }
    }
  },
  createdByMembership: {
    select: {
      id: true,
      user: {
        select: {
          id: true,
          name: true
        }
      }
    }
  },
  events: {
    orderBy: {
      createdAt: "desc" as const
    },
    take: 6,
    select: {
      id: true,
      type: true,
      metadata: true,
      createdAt: true,
      actorMembership: {
        select: {
          user: {
            select: {
              name: true
            }
          }
        }
      }
    }
  }
};

function timeErrorMessage(code: string) {
  const messages: Record<string, string> = {
    INVALID_DUE: "Prazo inválido.",
    DUE_TOO_SOON: "Defina o prazo com pelo menos 30 segundos de antecedência.",
    INVALID_REMINDER: "Horário do lembrete inválido.",
    REMINDER_TOO_SOON: "Defina o lembrete com pelo menos 30 segundos de antecedência.",
    REMINDER_AFTER_DUE: "O lembrete não pode acontecer depois do prazo."
  };
  return messages[code] ?? "Datas da tarefa são inválidas.";
}

async function requireContact(companyId: string, contactId: string) {
  const contact = await prisma.contact.findFirst({
    where: {
      id: contactId,
      companyId,
      isGroup: false
    },
    select: {
      id: true,
      name: true
    }
  });

  if (!contact) {
    throw new AppError(
      "Contato não encontrado ou não elegível para tarefa.",
      404,
      "TASK_CONTACT_NOT_FOUND"
    );
  }

  return contact;
}

async function requireAssignee(companyId: string, membershipId: string) {
  const membership = await prisma.companyMembership.findFirst({
    where: {
      id: membershipId,
      companyId,
      isActive: true,
      user: {
        isActive: true
      }
    },
    select: {
      id: true,
      userId: true,
      role: true,
      user: {
        select: {
          id: true,
          name: true
        }
      }
    }
  });

  if (!membership) {
    throw new AppError(
      "Responsável não encontrado ou inativo.",
      422,
      "TASK_ASSIGNEE_INVALID"
    );
  }

  return membership;
}

async function validateTicket(
  companyId: string,
  contactId: string,
  ticketId: string | null | undefined
) {
  if (!ticketId) return null;

  const ticket = await prisma.ticket.findFirst({
    where: {
      id: ticketId,
      companyId,
      contactId
    },
    select: {
      id: true
    }
  });

  if (!ticket) {
    throw new AppError(
      "O atendimento escolhido não pertence a este contato.",
      422,
      "TASK_TICKET_INVALID"
    );
  }

  return ticket;
}

export async function createTask(input: {
  companyId: string;
  actorMembershipId: string;
  role: WappRole;
  contactId: string;
  ticketId?: string | null;
  assigneeMembershipId: string;
  title: string;
  description?: string | null;
  priority: TaskPriority;
  dueAt: Date;
  reminderAt: Date | null;
}) {
  const [contact, assignee] = await Promise.all([
    requireContact(input.companyId, input.contactId),
    requireAssignee(input.companyId, input.assigneeMembershipId),
    validateTicket(input.companyId, input.contactId, input.ticketId)
  ]);

  if (!canAssignTaskTo({
    role: input.role,
    actorMembershipId: input.actorMembershipId,
    assigneeMembershipId: assignee.id
  })) {
    throw new AppError(
      "Atendentes só podem criar tarefas para si mesmos.",
      403,
      "TASK_ASSIGNMENT_FORBIDDEN"
    );
  }

  const timeError = taskTimeError({
    now: new Date(),
    dueAt: input.dueAt,
    reminderAt: input.reminderAt
  });

  if (timeError) {
    throw new AppError(
      timeErrorMessage(timeError),
      422,
      "TASK_TIME_INVALID"
    );
  }

  const task = await prisma.$transaction(async tx => {
    const created = await tx.crmTask.create({
      data: {
        companyId: input.companyId,
        contactId: input.contactId,
        ticketId: input.ticketId ?? null,
        assigneeMembershipId: assignee.id,
        createdByMembershipId: input.actorMembershipId,
        title: input.title.trim(),
        description: input.description?.trim() || null,
        priority: input.priority,
        dueAt: input.dueAt,
        reminderAt: input.reminderAt
      }
    });

    await tx.crmTaskEvent.create({
      data: {
        companyId: input.companyId,
        taskId: created.id,
        actorMembershipId: input.actorMembershipId,
        type: "CREATED",
        metadata: toPrismaJson({
          assigneeMembershipId: assignee.id,
          dueAt: input.dueAt.toISOString(),
          reminderAt: input.reminderAt?.toISOString() ?? null,
          priority: input.priority
        })
      }
    });

    return created;
  });

  await notifyTaskAssignment({
    companyId: input.companyId,
    membershipId: assignee.id,
    actorMembershipId: input.actorMembershipId,
    taskId: task.id,
    contactId: input.contactId,
    ticketId: input.ticketId,
    taskTitle: task.title,
    contactName: contact.name
  });

  publishRealtime(input.companyId, {
    type: "task.updated",
    taskId: task.id,
    contactId: input.contactId,
    membershipId: assignee.id
  });

  return prisma.crmTask.findUniqueOrThrow({
    where: {
      id: task.id
    },
    include: taskInclude
  });
}

export async function listTasks(input: {
  companyId: string;
  actorMembershipId: string;
  role: WappRole;
  scope: "ME" | "ALL";
  status: "OPEN" | "DONE" | "CANCELLED";
  contactId?: string;
  overdueOnly: boolean;
  limit: number;
}) {
  if (input.scope === "ALL" && !isTaskManager(input.role)) {
    throw new AppError(
      "Somente gestores podem consultar tarefas de toda a equipe.",
      403,
      "TASK_SCOPE_FORBIDDEN"
    );
  }

  return prisma.crmTask.findMany({
    where: {
      companyId: input.companyId,
      status: input.status,
      ...(input.scope === "ME"
        ? {
            assigneeMembershipId: input.actorMembershipId
          }
        : {}),
      ...(input.contactId
        ? {
            contactId: input.contactId
          }
        : {}),
      ...(input.overdueOnly && input.status === "OPEN"
        ? {
            dueAt: {
              lt: new Date()
            }
          }
        : {})
    },
    include: taskInclude,
    orderBy: input.status === "OPEN"
      ? [
          {
            dueAt: "asc"
          },
          {
            createdAt: "desc"
          }
        ]
      : [
          {
            updatedAt: "desc"
          }
        ],
    take: Math.min(Math.max(input.limit, 1), 200)
  });
}

export async function getContactTaskContext(input: {
  companyId: string;
  actorMembershipId: string;
  role: WappRole;
  contactId: string;
}) {
  await requireContact(input.companyId, input.contactId);

  const [tasks, assignees, tickets] = await Promise.all([
    prisma.crmTask.findMany({
      where: {
        companyId: input.companyId,
        contactId: input.contactId
      },
      include: taskInclude,
      orderBy: [
        {
          dueAt: "asc"
        },
        {
          updatedAt: "desc"
        }
      ],
      take: 100
    }),
    prisma.companyMembership.findMany({
      where: {
        companyId: input.companyId,
        isActive: true,
        user: {
          isActive: true
        },
        ...(isTaskManager(input.role)
          ? {}
          : {
              id: input.actorMembershipId
            })
      },
      select: {
        id: true,
        role: true,
        user: {
          select: {
            id: true,
            name: true
          }
        }
      },
      orderBy: {
        user: {
          name: "asc"
        }
      }
    }),
    prisma.ticket.findMany({
      where: {
        companyId: input.companyId,
        contactId: input.contactId
      },
      select: {
        id: true,
        status: true,
        lastMessage: true,
        lastMessageAt: true
      },
      orderBy: {
        lastMessageAt: "desc"
      },
      take: 20
    })
  ]);

  return {
    tasks,
    assignees,
    tickets,
    actorMembershipId:
      input.actorMembershipId
  };
}

async function requireTaskForMutation(input: {
  companyId: string;
  taskId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const task = await prisma.crmTask.findFirst({
    where: {
      id: input.taskId,
      companyId: input.companyId
    },
    include: {
      contact: {
        select: {
          id: true,
          name: true
        }
      }
    }
  });

  if (!task) {
    throw new AppError(
      "Tarefa não encontrada.",
      404,
      "TASK_NOT_FOUND"
    );
  }

  if (!canMutateTask({
    role: input.role,
    actorMembershipId: input.actorMembershipId,
    assigneeMembershipId: task.assigneeMembershipId,
    createdByMembershipId: task.createdByMembershipId
  })) {
    throw new AppError(
      "Você não pode alterar esta tarefa.",
      403,
      "TASK_FORBIDDEN"
    );
  }

  return task;
}

export async function updateTask(input: {
  companyId: string;
  taskId: string;
  actorMembershipId: string;
  role: WappRole;
  title?: string;
  description?: string | null;
  priority?: TaskPriority;
  dueAt?: Date;
  reminderAt?: Date | null;
  ticketId?: string | null;
  assigneeMembershipId?: string;
}) {
  const task = await requireTaskForMutation(input);

  if (task.status !== "OPEN") {
    throw new AppError(
      "Somente tarefas abertas podem ser alteradas.",
      409,
      "TASK_NOT_OPEN"
    );
  }

  const nextAssigneeId =
    input.assigneeMembershipId ?? task.assigneeMembershipId;

  if (
    input.assigneeMembershipId &&
    input.assigneeMembershipId !== task.assigneeMembershipId &&
    !isTaskManager(input.role)
  ) {
    throw new AppError(
      "Somente gestores podem transferir tarefas.",
      403,
      "TASK_REASSIGN_FORBIDDEN"
    );
  }

  const assignee = await requireAssignee(
    input.companyId,
    nextAssigneeId
  );

  if (input.ticketId !== undefined) {
    await validateTicket(
      input.companyId,
      task.contactId,
      input.ticketId
    );
  }

  const nextDueAt = input.dueAt ?? task.dueAt;
  const nextReminderAt =
    input.reminderAt !== undefined ? input.reminderAt : task.reminderAt;

  const timeError = taskTimeError({
    now: new Date(),
    dueAt: nextDueAt,
    reminderAt: nextReminderAt
  });

  if (timeError) {
    throw new AppError(
      timeErrorMessage(timeError),
      422,
      "TASK_TIME_INVALID"
    );
  }

  const reminderChanged =
    input.reminderAt !== undefined &&
    (input.reminderAt?.getTime() ?? null) !==
      (task.reminderAt?.getTime() ?? null);

  const assigneeChanged =
    assignee.id !== task.assigneeMembershipId;

  const changedFields = [
    input.title !== undefined ? "title" : null,
    input.description !== undefined ? "description" : null,
    input.priority !== undefined ? "priority" : null,
    input.dueAt !== undefined ? "dueAt" : null,
    input.reminderAt !== undefined ? "reminderAt" : null,
    input.ticketId !== undefined ? "ticketId" : null,
    assigneeChanged ? "assignee" : null
  ].filter((value): value is string => Boolean(value));

  const updated = await prisma.$transaction(async tx => {
    const next = await tx.crmTask.update({
      where: {
        id: task.id
      },
      data: {
        ...(input.title !== undefined
          ? {
              title: input.title.trim()
            }
          : {}),
        ...(input.description !== undefined
          ? {
              description: input.description?.trim() || null
            }
          : {}),
        ...(input.priority !== undefined
          ? {
              priority: input.priority
            }
          : {}),
        ...(input.dueAt !== undefined
          ? {
              dueAt: input.dueAt
            }
          : {}),
        ...(input.reminderAt !== undefined
          ? {
              reminderAt: input.reminderAt
            }
          : {}),
        ...(input.ticketId !== undefined
          ? {
              ticketId: input.ticketId
            }
          : {}),
        ...(assigneeChanged
          ? {
              assigneeMembershipId: assignee.id
            }
          : {}),
        ...(reminderChanged
          ? {
              reminderClaimedAt: null,
              reminderSentAt: null,
              reminderFailedAt: null,
              reminderError: null
            }
          : {})
      }
    });

    await tx.crmTaskEvent.create({
      data: {
        companyId: input.companyId,
        taskId: task.id,
        actorMembershipId: input.actorMembershipId,
        type: "UPDATED",
        metadata: toPrismaJson({
          changedFields
        })
      }
    });

    if (assigneeChanged) {
      await tx.crmTaskEvent.create({
        data: {
          companyId: input.companyId,
          taskId: task.id,
          actorMembershipId: input.actorMembershipId,
          type: "REASSIGNED",
          metadata: toPrismaJson({
            fromMembershipId: task.assigneeMembershipId,
            toMembershipId: assignee.id
          })
        }
      });
    }

    return next;
  });

  if (assigneeChanged) {
    await notifyTaskAssignment({
      companyId: input.companyId,
      membershipId: assignee.id,
      actorMembershipId: input.actorMembershipId,
      taskId: task.id,
      contactId: task.contactId,
      ticketId: updated.ticketId,
      taskTitle: updated.title,
      contactName: task.contact.name
    });
  }

  publishRealtime(input.companyId, {
    type: "task.updated",
    taskId: task.id,
    contactId: task.contactId,
    membershipId: assignee.id
  });

  return prisma.crmTask.findUniqueOrThrow({
    where: {
      id: task.id
    },
    include: taskInclude
  });
}

export async function completeTask(input: {
  companyId: string;
  taskId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const task = await requireTaskForMutation(input);
  if (task.status !== "OPEN") {
    throw new AppError("A tarefa já foi finalizada.", 409, "TASK_NOT_OPEN");
  }

  const now = new Date();
  await prisma.$transaction([
    prisma.crmTask.update({
      where: {
        id: task.id
      },
      data: {
        status: "DONE",
        completedAt: now,
        reminderClaimedAt: null
      }
    }),
    prisma.crmTaskEvent.create({
      data: {
        companyId: input.companyId,
        taskId: task.id,
        actorMembershipId: input.actorMembershipId,
        type: "COMPLETED"
      }
    })
  ]);

  publishRealtime(input.companyId, {
    type: "task.updated",
    taskId: task.id,
    contactId: task.contactId,
    membershipId: task.assigneeMembershipId
  });

  return prisma.crmTask.findUniqueOrThrow({
    where: {
      id: task.id
    },
    include: taskInclude
  });
}

export async function cancelTask(input: {
  companyId: string;
  taskId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const task = await requireTaskForMutation(input);
  if (task.status !== "OPEN") {
    throw new AppError("A tarefa já foi finalizada.", 409, "TASK_NOT_OPEN");
  }

  const now = new Date();
  await prisma.$transaction([
    prisma.crmTask.update({
      where: {
        id: task.id
      },
      data: {
        status: "CANCELLED",
        cancelledAt: now,
        reminderClaimedAt: null
      }
    }),
    prisma.crmTaskEvent.create({
      data: {
        companyId: input.companyId,
        taskId: task.id,
        actorMembershipId: input.actorMembershipId,
        type: "CANCELLED"
      }
    })
  ]);

  publishRealtime(input.companyId, {
    type: "task.updated",
    taskId: task.id,
    contactId: task.contactId,
    membershipId: task.assigneeMembershipId
  });

  return prisma.crmTask.findUniqueOrThrow({
    where: {
      id: task.id
    },
    include: taskInclude
  });
}

export async function deliverTaskReminder(
  taskId: string,
  expectedRemindAt: string
) {
  const task = await prisma.crmTask.findUnique({
    where: {
      id: taskId
    },
    include: {
      contact: {
        select: {
          id: true,
          name: true
        }
      },
      assigneeMembership: {
        include: {
          user: true
        }
      }
    }
  });

  if (
    !task ||
    task.status !== "OPEN" ||
    !task.reminderAt ||
    task.reminderSentAt ||
    task.reminderFailedAt
  ) {
    return {
      delivered: false,
      reason: "inactive_or_already_handled"
    };
  }

  if (task.reminderAt.toISOString() !== expectedRemindAt) {
    return {
      delivered: false,
      reason: "stale_job"
    };
  }

  const now = new Date();
  if (task.reminderAt.getTime() > now.getTime() + 2_000) {
    return {
      delivered: false,
      reason: "not_due"
    };
  }

  const claimed = await prisma.crmTask.updateMany({
    where: {
      id: task.id,
      status: "OPEN",
      reminderSentAt: null,
      reminderFailedAt: null,
      OR: [
        {
          reminderClaimedAt: null
        },
        {
          reminderClaimedAt: {
            lt: new Date(now.getTime() - TASK_REMINDER_STALE_MS)
          }
        }
      ]
    },
    data: {
      reminderClaimedAt: now
    }
  });

  if (claimed.count !== 1) {
    return {
      delivered: false,
      reason: "already_claimed"
    };
  }

  if (!task.assigneeMembership.isActive || !task.assigneeMembership.user.isActive) {
    await prisma.$transaction([
      prisma.crmTask.update({
        where: {
          id: task.id
        },
        data: {
          reminderClaimedAt: null,
          reminderFailedAt: now,
          reminderError: "O responsável pela tarefa está inativo."
        }
      }),
      prisma.crmTaskEvent.create({
        data: {
          companyId: task.companyId,
          taskId: task.id,
          actorMembershipId: null,
          type: "REMINDER_FAILED",
          metadata: toPrismaJson({
            reason: "assignee_inactive"
          })
        }
      })
    ]);

    return {
      delivered: false,
      reason: "assignee_inactive"
    };
  }

  try {
    const notification = await notifyTaskReminder({
      companyId: task.companyId,
      membershipId: task.assigneeMembershipId,
      taskId: task.id,
      contactId: task.contactId,
      ticketId: task.ticketId,
      taskTitle: task.title,
      contactName: task.contact.name,
      remindAt: task.reminderAt
    });

    if (!notification) {
      await prisma.$transaction([
        prisma.crmTask.update({
          where: {
            id: task.id
          },
          data: {
            reminderClaimedAt: null,
            reminderFailedAt: now,
            reminderError: "Não foi possível localizar um responsável ativo."
          }
        }),
        prisma.crmTaskEvent.create({
          data: {
            companyId: task.companyId,
            taskId: task.id,
            actorMembershipId: null,
            type: "REMINDER_FAILED",
            metadata: toPrismaJson({
              reason: "recipient_unavailable"
            })
          }
        })
      ]);

      return {
        delivered: false,
        reason: "recipient_unavailable"
      };
    }

    await prisma.$transaction(async tx => {
      const updated = await tx.crmTask.updateMany({
        where: {
          id: task.id,
          status: "OPEN",
          reminderSentAt: null,
          reminderFailedAt: null
        },
        data: {
          reminderClaimedAt: null,
          reminderSentAt: new Date(),
          reminderError: null
        }
      });

      if (updated.count === 1) {
        await tx.crmTaskEvent.create({
          data: {
            companyId: task.companyId,
            taskId: task.id,
            actorMembershipId: null,
            type: "REMINDER_SENT",
            metadata: toPrismaJson({
              notificationId: notification.id
            })
          }
        });
      }
    });

    publishRealtime(task.companyId, {
      type: "task.updated",
      taskId: task.id,
      contactId: task.contactId,
      membershipId: task.assigneeMembershipId
    });

    return {
      delivered: true
    };
  } catch (error) {
    await prisma.crmTask.updateMany({
      where: {
        id: task.id,
        reminderSentAt: null,
        reminderFailedAt: null
      },
      data: {
        reminderClaimedAt: null
      }
    });
    throw error;
  }
}

export async function reconcileTaskReminders() {
  return prisma.crmTask.findMany({
    where: {
      status: "OPEN",
      reminderAt: {
        lte: new Date()
      },
      reminderSentAt: null,
      reminderFailedAt: null
    },
    select: {
      id: true,
      reminderAt: true
    },
    orderBy: {
      reminderAt: "asc"
    },
    take: 100
  });
}
