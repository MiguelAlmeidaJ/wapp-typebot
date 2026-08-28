import {
  AppError
} from "../../errors/app-error.js";
import {
  evolutionWhatsAppClient
} from "../../integrations/whatsapp/evolution.client.js";
import type {
  WappRole
} from "../../lib/tokens.js";
import {
  prisma
} from "../../lib/database.js";
import {
  toPrismaJson
} from "../../lib/prisma-json.js";
import {
  publishRealtime
} from "../realtime/realtime.bus.js";
import {
  recordTicketEvent
} from "../tickets/ticket-event.service.js";
import {
  canManageScheduledMessage,
  scheduleTimeError,
  STALE_PROCESSING_MS
} from "./scheduled-message.policy.js";

function getObject(
  value: unknown
) {
  return value &&
    typeof value ===
      "object"
    ? value as
        Record<
          string,
          unknown
        >
    : undefined;
}

function getString(
  value: unknown
) {
  return typeof value ===
      "string" &&
    value.length >
      0
    ? value
    : undefined;
}

function sentExternalId(
  result: unknown
) {
  const body =
    getObject(
      result
    );

  const key =
    getObject(
      body?.key
    );

  const id =
    getString(
      key?.id
    );

  if (
    !id
  ) {
    throw new Error(
      "WhatsApp provider did not return a message id."
    );
  }

  return id;
}

function sentTimestamp(
  result: unknown
) {
  const body =
    getObject(
      result
    );

  const raw =
    body
      ?.messageTimestamp;

  const seconds =
    typeof raw ===
      "number"
      ? raw
      : typeof raw ===
          "string"
        ? Number(
            raw
          )
        : NaN;

  return Number.isFinite(
    seconds
  )
    ? new Date(
        seconds *
          1000
      )
    : new Date();
}

function canOverrideAssignment(
  role:
    WappRole
) {
  return (
    role ===
      "OWNER" ||
    role ===
      "ADMIN" ||
    role ===
      "SUPERVISOR"
  );
}

async function requireSchedulableTicket(input: {
  companyId: string;
  ticketId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const ticket =
    await prisma.ticket.findFirst({
      where: {
        id:
          input.ticketId,
        companyId:
          input.companyId
      },
      include: {
        contact:
          true,
        whatsappConnection:
          true
      }
    });

  if (
    !ticket
  ) {
    throw new AppError(
      "Atendimento não encontrado.",
      404,
      "TICKET_NOT_FOUND"
    );
  }

  if (
    ticket.status ===
    "CLOSED"
  ) {
    throw new AppError(
      "Não é possível agendar mensagem em atendimento encerrado.",
      409,
      "TICKET_CLOSED"
    );
  }

  if (
    ticket.assignedMembershipId &&
    ticket.assignedMembershipId !==
      input.actorMembershipId &&
    !canOverrideAssignment(
      input.role
    )
  ) {
    throw new AppError(
      "Este atendimento está atribuído a outro atendente.",
      403,
      "TICKET_ASSIGNED_TO_ANOTHER_AGENT"
    );
  }

  const membership =
    await prisma.companyMembership.findFirst({
      where: {
        id:
          input.actorMembershipId,
        companyId:
          input.companyId,
        isActive:
          true,
        user: {
          isActive:
            true
        }
      },
      include: {
        user:
          true
      }
    });

  if (
    !membership
  ) {
    throw new AppError(
      "Atendente não encontrado na empresa ativa.",
      422,
      "INVALID_SCHEDULE_AUTHOR"
    );
  }

  if (
    ticket.queueId &&
    !canOverrideAssignment(
      input.role
    )
  ) {
    const configuredMembers =
      await prisma.queueMember.count({
        where: {
          queueId:
            ticket.queueId
        }
      });

    if (
      configuredMembers >
      0
    ) {
      const queueMembership =
        await prisma.queueMember.findUnique({
          where: {
            queueId_membershipId: {
              queueId:
                ticket.queueId,
              membershipId:
                input.actorMembershipId
            }
          },
          select: {
            id:
              true
          }
        });

      if (
        !queueMembership
      ) {
        throw new AppError(
          "Você não pertence à fila deste atendimento.",
          403,
          "AGENT_NOT_IN_QUEUE"
        );
      }
    }
  }

  return {
    ticket,
    membership
  };
}

export async function listTicketScheduledMessages(input: {
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
        id:
          true
      }
    });

  if (
    !ticket
  ) {
    throw new AppError(
      "Atendimento não encontrado.",
      404,
      "TICKET_NOT_FOUND"
    );
  }

  return prisma.scheduledMessage.findMany({
    where: {
      companyId:
        input.companyId,
      ticketId:
        input.ticketId
    },
    include: {
      createdByMembership: {
        select: {
          id:
            true,
          user: {
            select: {
              id:
                true,
              name:
                true
            }
          }
        }
      }
    },
    orderBy: [
      {
        scheduledFor:
          "asc"
      },
      {
        createdAt:
          "asc"
      }
    ],
    take:
      100
  });
}

export async function createScheduledMessage(input: {
  companyId: string;
  ticketId: string;
  actorMembershipId: string;
  role: WappRole;
  body: string;
  scheduledFor: Date;
}) {
  const body =
    input.body.trim();

  if (
    !body
  ) {
    throw new AppError(
      "Digite a mensagem que será agendada.",
      422,
      "SCHEDULE_BODY_REQUIRED"
    );
  }

  if (
    body.length >
    4096
  ) {
    throw new AppError(
      "A mensagem agendada excede 4096 caracteres.",
      422,
      "SCHEDULE_BODY_TOO_LONG"
    );
  }

  const timeError =
    scheduleTimeError(
      new Date(),
      input.scheduledFor
    );

  if (
    timeError ===
    "INVALID"
  ) {
    throw new AppError(
      "Data de agendamento inválida.",
      422,
      "INVALID_SCHEDULE_TIME"
    );
  }

  if (
    timeError ===
    "TOO_SOON"
  ) {
    throw new AppError(
      "Agende a mensagem com pelo menos 30 segundos de antecedência.",
      422,
      "SCHEDULE_TOO_SOON"
    );
  }

  if (
    timeError ===
    "TOO_FAR"
  ) {
    throw new AppError(
      "O agendamento não pode ultrapassar 365 dias.",
      422,
      "SCHEDULE_TOO_FAR"
    );
  }

  await requireSchedulableTicket({
    companyId:
      input.companyId,
    ticketId:
      input.ticketId,
    actorMembershipId:
      input.actorMembershipId,
    role:
      input.role
  });

  const scheduledMessage =
    await prisma.scheduledMessage.create({
      data: {
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        createdByMembershipId:
          input.actorMembershipId,
        body,
        scheduledFor:
          input.scheduledFor
      },
      include: {
        createdByMembership: {
          select: {
            id:
              true,
            user: {
              select: {
                id:
                  true,
                name:
                  true
              }
            }
          }
        }
      }
    });

  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      input.ticketId,
    actorMembershipId:
      input.actorMembershipId,
    type:
      "MESSAGE_SCHEDULED",
    metadata: {
      scheduledMessageId:
        scheduledMessage.id,
      scheduledFor:
        scheduledMessage
          .scheduledFor
          .toISOString()
    }
  });

  return scheduledMessage;
}

export async function cancelScheduledMessage(input: {
  companyId: string;
  scheduledMessageId: string;
  actorMembershipId: string;
  role: WappRole;
}) {
  const existing =
    await prisma.scheduledMessage.findFirst({
      where: {
        id:
          input.scheduledMessageId,
        companyId:
          input.companyId
      }
    });

  if (
    !existing
  ) {
    throw new AppError(
      "Agendamento não encontrado.",
      404,
      "SCHEDULE_NOT_FOUND"
    );
  }

  if (
    !canManageScheduledMessage({
      role:
        input.role,
      actorMembershipId:
        input.actorMembershipId,
      createdByMembershipId:
        existing
          .createdByMembershipId
    })
  ) {
    throw new AppError(
      "Você não pode cancelar o agendamento de outro atendente.",
      403,
      "SCHEDULE_FORBIDDEN"
    );
  }

  if (
    existing.status !==
    "PENDING"
  ) {
    throw new AppError(
      "Somente agendamentos pendentes podem ser cancelados.",
      409,
      "SCHEDULE_NOT_PENDING"
    );
  }

  const result =
    await prisma.scheduledMessage.updateMany({
      where: {
        id:
          existing.id,
        status:
          "PENDING"
      },
      data: {
        status:
          "CANCELLED",
        cancelledAt:
          new Date()
      }
    });

  if (
    result.count !==
    1
  ) {
    throw new AppError(
      "O agendamento já começou a ser processado.",
      409,
      "SCHEDULE_ALREADY_PROCESSING"
    );
  }

  const cancelled =
    await prisma.scheduledMessage.findUniqueOrThrow({
      where: {
        id:
          existing.id
      },
      include: {
        createdByMembership: {
          select: {
            id:
              true,
            user: {
              select: {
                id:
                  true,
                name:
                  true
              }
            }
          }
        }
      }
    });

  await recordTicketEvent({
    companyId:
      input.companyId,
    ticketId:
      existing.ticketId,
    actorMembershipId:
      input.actorMembershipId,
    type:
      "SCHEDULED_MESSAGE_CANCELLED",
    metadata: {
      scheduledMessageId:
        existing.id,
      scheduledFor:
        existing
          .scheduledFor
          .toISOString()
    }
  });

  return cancelled;
}

async function markFailed(
  scheduledMessageId: string,
  error: string
) {
  const failed =
    await prisma.scheduledMessage.update({
      where: {
        id:
          scheduledMessageId
      },
      data: {
        status:
          "FAILED",
        error:
          error.slice(
            0,
            4000
          )
      }
    });

  await recordTicketEvent({
    companyId:
      failed.companyId,
    ticketId:
      failed.ticketId,
    actorMembershipId:
      failed.createdByMembershipId,
    type:
      "SCHEDULED_MESSAGE_FAILED",
    metadata: {
      scheduledMessageId:
        failed.id,
      reason:
        failed.error
    }
  });

  return failed;
}

export async function deliverScheduledMessage(
  scheduledMessageId: string
) {
  const now =
    new Date();

  const claimed =
    await prisma.scheduledMessage.updateMany({
      where: {
        id:
          scheduledMessageId,
        status:
          "PENDING",
        scheduledFor: {
          lte:
            new Date(
              now.getTime() +
              2_000
            )
        }
      },
      data: {
        status:
          "PROCESSING",
        claimedAt:
          now,
        error:
          null
      }
    });

  if (
    claimed.count !==
    1
  ) {
    return {
      delivered:
        false,
      reason:
        "not_due_or_not_pending"
    };
  }

  const scheduled =
    await prisma.scheduledMessage.findUnique({
      where: {
        id:
          scheduledMessageId
      },
      include: {
        ticket: {
          include: {
            contact:
              true,
            whatsappConnection:
              true
          }
        },
        createdByMembership: {
          include: {
            user:
              true
          }
        }
      }
    });

  if (
    !scheduled
  ) {
    return {
      delivered:
        false,
      reason:
        "missing_after_claim"
    };
  }

  if (
    !scheduled
      .createdByMembership
      .isActive ||
    !scheduled
      .createdByMembership
      .user.isActive
  ) {
    await markFailed(
      scheduled.id,
      "O usuário que criou o agendamento não está mais ativo."
    );

    return {
      delivered:
        false,
      reason:
        "author_inactive"
    };
  }

  if (
    scheduled.ticket.status ===
    "CLOSED"
  ) {
    await markFailed(
      scheduled.id,
      "O atendimento foi encerrado antes do horário agendado."
    );

    return {
      delivered:
        false,
      reason:
        "ticket_closed"
    };
  }

  if (
    scheduled
      .ticket
      .whatsappConnection
      .status !==
    "CONNECTED"
  ) {
    await markFailed(
      scheduled.id,
      "A conexão WhatsApp estava offline no horário do envio."
    );

    return {
      delivered:
        false,
      reason:
        "connection_offline"
    };
  }

  try {
    const result =
      await evolutionWhatsAppClient.sendText({
        instanceName:
          scheduled
            .ticket
            .whatsappConnection
            .instanceName,
        number:
          scheduled
            .ticket
            .contact
            .remoteJid,
        text:
          scheduled.body
      });

    const timestamp =
      sentTimestamp(
        result
      );

    const externalId =
      sentExternalId(
        result
      );

    const message =
      await prisma.message.upsert({
        where: {
          whatsappConnectionId_externalId: {
            whatsappConnectionId:
              scheduled
                .ticket
                .whatsappConnectionId,
            externalId
          }
        },
        update: {},
        create: {
          companyId:
            scheduled.companyId,
          ticketId:
            scheduled.ticketId,
          whatsappConnectionId:
            scheduled
              .ticket
              .whatsappConnectionId,
          sentByUserId:
            scheduled
              .createdByMembership
              .userId,
          externalId,
          direction:
            "OUTBOUND",
          type:
            "TEXT",
          deliveryStatus:
            "PENDING",
          body:
            scheduled.body,
          timestamp,
          rawPayload:
            toPrismaJson(
              result
            )
        }
      });

    await prisma.$transaction([
      prisma.ticket.update({
        where: {
          id:
            scheduled.ticketId
        },
        data: {
          lastMessage:
            scheduled.body,
          lastMessageAt:
            timestamp,
          lastOutboundAt:
            timestamp,
          waitingSince:
            null,
          ...(scheduled
            .ticket
            .firstInboundAt &&
          !scheduled
            .ticket
            .firstResponseAt
            ? {
                firstResponseAt:
                  timestamp
              }
            : {})
        }
      }),
      prisma.scheduledMessage.update({
        where: {
          id:
            scheduled.id
        },
        data: {
          status:
            "SENT",
          sentAt:
            timestamp,
          sentMessageId:
            message.id,
          error:
            null
        }
      })
    ]);

    await recordTicketEvent({
      companyId:
        scheduled.companyId,
      ticketId:
        scheduled.ticketId,
      actorMembershipId:
        scheduled
          .createdByMembershipId,
      type:
        "SCHEDULED_MESSAGE_SENT",
      metadata: {
        scheduledMessageId:
          scheduled.id,
        messageId:
          message.id,
        scheduledFor:
          scheduled
            .scheduledFor
            .toISOString()
      }
    });

    publishRealtime(
      scheduled.companyId,
      {
        type:
          "message.created",
        ticketId:
          scheduled.ticketId,
        messageId:
          message.id
      }
    );

    publishRealtime(
      scheduled.companyId,
      {
        type:
          "ticket.updated",
        ticketId:
          scheduled.ticketId
      }
    );

    return {
      delivered:
        true,
      messageId:
        message.id
    };
  } catch (error) {
    const message =
      error instanceof
        Error
        ? error.message
        : "Falha desconhecida ao enviar a mensagem agendada.";

    await markFailed(
      scheduled.id,
      message
    );

    return {
      delivered:
        false,
      reason:
        "send_failed"
    };
  }
}

export async function reconcileScheduledMessages() {
  const now =
    new Date();

  await prisma.scheduledMessage.updateMany({
    where: {
      status:
        "PROCESSING",
      claimedAt: {
        lt:
          new Date(
            now.getTime() -
            STALE_PROCESSING_MS
          )
      }
    },
    data: {
      status:
        "FAILED",
      error:
        "Execução interrompida. A entrega pode ser incerta; confira o WhatsApp antes de reagendar."
    }
  });

  return prisma.scheduledMessage.findMany({
    where: {
      status:
        "PENDING",
      scheduledFor: {
        lte:
          now
      }
    },
    select: {
      id:
        true,
      scheduledFor:
        true
    },
    orderBy: {
      scheduledFor:
        "asc"
    },
    take:
      100
  });
}
