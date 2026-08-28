import { randomUUID } from "node:crypto";

import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";
import { toPrismaJson } from "../../lib/prisma-json.js";
import { recordAudit } from "../audit/audit.service.js";
import { publishRealtime } from "../realtime/realtime.bus.js";
import { recordTicketEvent } from "../tickets/ticket-event.service.js";

export type AutomationTriggerValue =
  | "TICKET_CREATED"
  | "INBOUND_MESSAGE";

export type AutomationConversationTypeValue =
  | "ALL"
  | "DIRECT"
  | "GROUP";

export type AutomationActionTypeValue =
  | "SET_QUEUE"
  | "ASSIGN_MEMBERSHIP"
  | "ADD_TAG"
  | "SEND_TEXT";

export interface AutomationActionInput {
  type:
    AutomationActionTypeValue;
  queueId?: string;
  membershipId?: string;
  tagId?: string;
  text?: string;
}

export interface AutomationRuleInput {
  name: string;
  isActive?: boolean;
  trigger:
    AutomationTriggerValue;
  keywordContains?:
    | string
    | null;
  onlyIfUnassigned?: boolean;
  conversationType?:
    AutomationConversationTypeValue;
  priority?: number;
  actions:
    AutomationActionInput[];
}

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

  return (
    getString(
      key?.id
    ) ??
    `wapp-automation-${randomUUID()}`
  );
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

async function validateActions(
  companyId: string,
  actions:
    AutomationActionInput[]
) {
  for (
    const action
    of actions
  ) {
    switch (
      action.type
    ) {
      case "SET_QUEUE": {
        if (
          !action.queueId
        ) {
          throw new AppError(
            "A ação de fila precisa de uma fila.",
            422,
            "AUTOMATION_QUEUE_REQUIRED"
          );
        }

        const queue =
          await prisma.queue.findFirst({
            where: {
              id:
                action.queueId,
              companyId,
              isActive:
                true
            },
            select: {
              id: true
            }
          });

        if (!queue) {
          throw new AppError(
            "Fila da automação não encontrada.",
            422,
            "AUTOMATION_QUEUE_INVALID"
          );
        }

        break;
      }

      case "ASSIGN_MEMBERSHIP": {
        if (
          !action.membershipId
        ) {
          throw new AppError(
            "A ação de atendente precisa de um atendente.",
            422,
            "AUTOMATION_MEMBERSHIP_REQUIRED"
          );
        }

        const membership =
          await prisma.companyMembership.findFirst({
            where: {
              id:
                action.membershipId,
              companyId,
              isActive:
                true
            },
            select: {
              id: true
            }
          });

        if (!membership) {
          throw new AppError(
            "Atendente da automação não encontrado.",
            422,
            "AUTOMATION_MEMBERSHIP_INVALID"
          );
        }

        break;
      }

      case "ADD_TAG": {
        if (
          !action.tagId
        ) {
          throw new AppError(
            "A ação de etiqueta precisa de uma etiqueta.",
            422,
            "AUTOMATION_TAG_REQUIRED"
          );
        }

        const tag =
          await prisma.tag.findFirst({
            where: {
              id:
                action.tagId,
              companyId,
              isActive:
                true
            },
            select: {
              id: true
            }
          });

        if (!tag) {
          throw new AppError(
            "Etiqueta da automação não encontrada.",
            422,
            "AUTOMATION_TAG_INVALID"
          );
        }

        break;
      }

      case "SEND_TEXT": {
        const text =
          action.text
            ?.trim();

        if (
          !text
        ) {
          throw new AppError(
            "A ação de mensagem precisa de um texto.",
            422,
            "AUTOMATION_TEXT_REQUIRED"
          );
        }

        if (
          text.length >
          4096
        ) {
          throw new AppError(
            "Mensagem automática excede 4096 caracteres.",
            422,
            "AUTOMATION_TEXT_TOO_LONG"
          );
        }

        break;
      }
    }
  }
}

function actionCreateData(
  ruleId: string,
  actions:
    AutomationActionInput[]
) {
  return actions.map(
    (
      action,
      index
    ) => ({
      ruleId,
      type:
        action.type,
      orderIndex:
        index,
      queueId:
        action.queueId,
      membershipId:
        action.membershipId,
      tagId:
        action.tagId,
      text:
        action.text
          ?.trim()
    })
  );
}

export async function listAutomationRules(
  companyId: string
) {
  const rules =
    await prisma.automationRule.findMany({
      where: {
        companyId
      },
      orderBy: [
        {
          isActive:
            "desc"
        },
        {
          priority:
            "asc"
        },
        {
          createdAt:
            "asc"
        }
      ],
      take: 200
    });

  const actions =
    rules.length >
      0
      ? await prisma.automationAction.findMany({
          where: {
            ruleId: {
              in:
                rules.map(
                  rule =>
                    rule.id
                )
            }
          },
          orderBy: [
            {
              ruleId:
                "asc"
            },
            {
              orderIndex:
                "asc"
            }
          ]
        })
      : [];

  const byRule =
    new Map<
      string,
      typeof actions
    >();

  for (
    const action
    of actions
  ) {
    const current =
      byRule.get(
        action.ruleId
      ) ?? [];

    current.push(
      action
    );

    byRule.set(
      action.ruleId,
      current
    );
  }

  return rules.map(
    rule => ({
      ...rule,
      actions:
        byRule.get(
          rule.id
        ) ?? []
    })
  );
}

export async function listAutomationRuns(
  companyId: string,
  limit = 50
) {
  return prisma.automationRun.findMany({
    where: {
      companyId
    },
    orderBy: {
      createdAt:
        "desc"
    },
    take:
      Math.min(
        Math.max(
          limit,
          1
        ),
        100
      )
  });
}

export async function createAutomationRule(input: {
  companyId: string;
  actorMembershipId: string;
  rule:
    AutomationRuleInput;
}) {
  await validateActions(
    input.companyId,
    input.rule.actions
  );

  const id =
    randomUUID();

  await prisma.$transaction([
    prisma.automationRule.create({
      data: {
        id,
        companyId:
          input.companyId,
        name:
          input.rule.name
            .trim(),
        isActive:
          input.rule
            .isActive ??
          true,
        trigger:
          input.rule.trigger,
        keywordContains:
          input.rule
            .keywordContains
            ?.trim() ||
          null,
        onlyIfUnassigned:
          input.rule
            .onlyIfUnassigned ??
          false,
        conversationType:
          input.rule
            .conversationType ??
          "ALL",
        priority:
          input.rule
            .priority ??
          100,
        createdByMembershipId:
          input.actorMembershipId
      }
    }),
    prisma.automationAction.createMany({
      data:
        actionCreateData(
          id,
          input.rule.actions
        )
    })
  ]);

  const automation =
    (
      await listAutomationRules(
        input.companyId
      )
    ).find(
      rule =>
        rule.id ===
        id
    );

  await recordAudit({
    companyId:
      input.companyId,
    actorMembershipId:
      input.actorMembershipId,
    action:
      "AUTOMATION_CREATED",
    entityType:
      "AUTOMATION_RULE",
    entityId:
      id,
    after:
      automation
  });

  return automation;
}

export async function updateAutomationRule(input: {
  companyId: string;
  actorMembershipId: string;
  ruleId: string;
  patch: Partial<
    Omit<
      AutomationRuleInput,
      "actions"
    >
  > & {
    actions?:
      AutomationActionInput[];
  };
}) {
  const existing =
    (
      await listAutomationRules(
        input.companyId
      )
    ).find(
      rule =>
        rule.id ===
        input.ruleId
    );

  if (!existing) {
    throw new AppError(
      "Automação não encontrada.",
      404,
      "AUTOMATION_NOT_FOUND"
    );
  }

  if (
    input.patch.actions
  ) {
    await validateActions(
      input.companyId,
      input.patch.actions
    );
  }

  await prisma.$transaction(
    async tx => {
      await tx.automationRule.update({
        where: {
          id:
            existing.id
        },
        data: {
          ...(input.patch
            .name !==
          undefined
            ? {
                name:
                  input.patch
                    .name.trim()
              }
            : {}),
          ...(input.patch
            .isActive !==
          undefined
            ? {
                isActive:
                  input.patch
                    .isActive
              }
            : {}),
          ...(input.patch
            .trigger !==
          undefined
            ? {
                trigger:
                  input.patch
                    .trigger
              }
            : {}),
          ...(input.patch
            .keywordContains !==
          undefined
            ? {
                keywordContains:
                  input.patch
                    .keywordContains
                    ?.trim() ||
                  null
              }
            : {}),
          ...(input.patch
            .onlyIfUnassigned !==
          undefined
            ? {
                onlyIfUnassigned:
                  input.patch
                    .onlyIfUnassigned
              }
            : {}),
          ...(input.patch
            .conversationType !==
          undefined
            ? {
                conversationType:
                  input.patch
                    .conversationType
              }
            : {}),
          ...(input.patch
            .priority !==
          undefined
            ? {
                priority:
                  input.patch
                    .priority
              }
            : {})
        }
      });

      if (
        input.patch.actions
      ) {
        await tx.automationAction.deleteMany({
          where: {
            ruleId:
              existing.id
          }
        });

        await tx.automationAction.createMany({
          data:
            actionCreateData(
              existing.id,
              input.patch
                .actions
            )
        });
      }
    }
  );

  const updated =
    (
      await listAutomationRules(
        input.companyId
      )
    ).find(
      rule =>
        rule.id ===
        existing.id
    );

  await recordAudit({
    companyId:
      input.companyId,
    actorMembershipId:
      input.actorMembershipId,
    action:
      "AUTOMATION_UPDATED",
    entityType:
      "AUTOMATION_RULE",
    entityId:
      existing.id,
    before:
      existing,
    after:
      updated
  });

  return updated;
}

function matchesRule(input: {
  rule: {
    keywordContains:
      | string
      | null;
    onlyIfUnassigned:
      boolean;
    conversationType:
      "ALL"
      | "DIRECT"
      | "GROUP";
  };
  ticket: {
    assignedMembershipId:
      | string
      | null;
    contact: {
      isGroup:
        boolean;
    };
  };
  messageBody:
    | string
    | null;
}) {
  if (
    input.rule
      .onlyIfUnassigned &&
    input.ticket
      .assignedMembershipId
  ) {
    return false;
  }

  if (
    input.rule
      .conversationType ===
      "DIRECT" &&
    input.ticket
      .contact.isGroup
  ) {
    return false;
  }

  if (
    input.rule
      .conversationType ===
      "GROUP" &&
    !input.ticket
      .contact.isGroup
  ) {
    return false;
  }

  const keyword =
    input.rule
      .keywordContains
      ?.trim()
      .toLocaleLowerCase(
        "pt-BR"
      );

  if (
    keyword &&
    !input.messageBody
      ?.toLocaleLowerCase(
        "pt-BR"
      )
      .includes(
        keyword
      )
  ) {
    return false;
  }

  return true;
}

function expandText(
  text: string,
  context: {
    contactName: string;
    companyName: string;
  }
) {
  const firstName =
    context.contactName
      .trim()
      .split(
        /\s+/
      )[0] ??
    context.contactName;

  return text
    .replaceAll(
      "{nome}",
      context.contactName
    )
    .replaceAll(
      "{primeiro_nome}",
      firstName
    )
    .replaceAll(
      "{empresa}",
      context.companyName
    );
}

async function executeAutomaticText(input: {
  companyId: string;
  ticket: {
    id: string;
    firstInboundAt:
      | Date
      | null;
    firstResponseAt:
      | Date
      | null;
    contact: {
      name: string;
      remoteJid: string;
    };
    whatsappConnection: {
      id: string;
      instanceName: string;
      status: string;
    };
  };
  text: string;
  companyName: string;
}) {
  if (
    input.ticket
      .whatsappConnection
      .status !==
    "CONNECTED"
  ) {
    throw new Error(
      "WhatsApp connection is not CONNECTED."
    );
  }

  const text =
    expandText(
      input.text,
      {
        contactName:
          input.ticket
            .contact.name,
        companyName:
          input.companyName
      }
    );

  const result =
    await evolutionWhatsAppClient.sendText({
      instanceName:
        input.ticket
          .whatsappConnection
          .instanceName,
      number:
        input.ticket
          .contact.remoteJid,
      text
    });

  const externalId =
    sentExternalId(
      result
    );

  const timestamp =
    sentTimestamp(
      result
    );

  const message =
    await prisma.message.upsert({
      where: {
        whatsappConnectionId_externalId: {
          whatsappConnectionId:
            input.ticket
              .whatsappConnection.id,
          externalId
        }
      },
      create: {
        companyId:
          input.companyId,
        ticketId:
          input.ticket.id,
        whatsappConnectionId:
          input.ticket
            .whatsappConnection.id,
        externalId,
        direction:
          "OUTBOUND",
        type:
          "TEXT",
        deliveryStatus:
          "PENDING",
        body:
          text,
        timestamp
      },
      update: {}
    });

  await prisma.ticket.update({
    where: {
      id:
        input.ticket.id
    },
    data: {
      lastMessage:
        text,
      lastMessageAt:
        timestamp,
      lastOutboundAt:
        timestamp,
      waitingSince:
        null,
      ...(input.ticket
        .firstInboundAt &&
      !input.ticket
        .firstResponseAt
        ? {
            firstResponseAt:
              timestamp
          }
        : {})
    }
  });

  publishRealtime(
    input.companyId,
    {
      type:
        "message.created",
      ticketId:
        input.ticket.id,
      messageId:
        message.id
    }
  );

  return {
    type:
      "SEND_TEXT" as const,
    messageId:
      message.id
  };
}

async function executeAction(input: {
  companyId: string;
  ticketId: string;
  action: {
    type:
      AutomationActionTypeValue;
    queueId:
      | string
      | null;
    membershipId:
      | string
      | null;
    tagId:
      | string
      | null;
    text:
      | string
      | null;
  };
  companyName: string;
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
        contact: true,
        whatsappConnection:
          true
      }
    });

  if (!ticket) {
    throw new Error(
      "Automation ticket no longer exists."
    );
  }

  switch (
    input.action.type
  ) {
    case "SET_QUEUE": {
      const queue =
        input.action
          .queueId
          ? await prisma.queue.findFirst({
              where: {
                id:
                  input.action
                    .queueId,
                companyId:
                  input.companyId,
                isActive:
                  true
              },
              select: {
                id: true
              }
            })
          : null;

      if (!queue) {
        throw new Error(
          "Automation queue is unavailable."
        );
      }

      await prisma.ticket.update({
        where: {
          id:
            ticket.id
        },
        data: {
          queueId:
            queue.id
        }
      });

      return {
        type:
          "SET_QUEUE" as const,
        queueId:
          queue.id
      };
    }

    case "ASSIGN_MEMBERSHIP": {
      const membership =
        input.action
          .membershipId
          ? await prisma.companyMembership.findFirst({
              where: {
                id:
                  input.action
                    .membershipId,
                companyId:
                  input.companyId,
                isActive:
                  true
              },
              select: {
                id: true
              }
            })
          : null;

      if (!membership) {
        throw new Error(
          "Automation membership is unavailable."
        );
      }

      await prisma.ticket.update({
        where: {
          id:
            ticket.id
        },
        data: {
          assignedMembershipId:
            membership.id,
          status:
            "OPEN"
        }
      });

      return {
        type:
          "ASSIGN_MEMBERSHIP" as const,
        membershipId:
          membership.id
      };
    }

    case "ADD_TAG": {
      const tag =
        input.action
          .tagId
          ? await prisma.tag.findFirst({
              where: {
                id:
                  input.action
                    .tagId,
                companyId:
                  input.companyId,
                isActive:
                  true
              },
              select: {
                id: true
              }
            })
          : null;

      if (!tag) {
        throw new Error(
          "Automation tag is unavailable."
        );
      }

      await prisma.ticketTag.upsert({
        where: {
          ticketId_tagId: {
            ticketId:
              ticket.id,
            tagId:
              tag.id
          }
        },
        create: {
          ticketId:
            ticket.id,
          tagId:
            tag.id
        },
        update: {}
      });

      return {
        type:
          "ADD_TAG" as const,
        tagId:
          tag.id
      };
    }

    case "SEND_TEXT": {
      if (
        !input.action
          .text
      ) {
        throw new Error(
          "Automation text is empty."
        );
      }

      return executeAutomaticText({
        companyId:
          input.companyId,
        ticket,
        text:
          input.action.text,
        companyName:
          input.companyName
      });
    }
  }
}

export async function evaluateAutomationEvent(input: {
  companyId: string;
  ticketId: string;
  sourceMessageId: string;
  trigger:
    AutomationTriggerValue;
}) {
  const company =
    await prisma.company.findUnique({
      where: {
        id:
          input.companyId
      },
      select: {
        name: true
      }
    });

  const sourceMessage =
    await prisma.message.findFirst({
      where: {
        id:
          input.sourceMessageId,
        companyId:
          input.companyId,
        ticketId:
          input.ticketId
      },
      select: {
        body: true
      }
    });

  if (
    !company ||
    !sourceMessage
  ) {
    return {
      evaluated: 0,
      matched: 0
    };
  }

  const rules =
    await prisma.automationRule.findMany({
      where: {
        companyId:
          input.companyId,
        isActive:
          true,
        trigger:
          input.trigger
      },
      orderBy: [
        {
          priority:
            "asc"
        },
        {
          createdAt:
            "asc"
        }
      ]
    });

  let matched = 0;

  for (
    const rule
    of rules
  ) {
    const ticket =
      await prisma.ticket.findFirst({
        where: {
          id:
            input.ticketId,
          companyId:
            input.companyId
        },
        include: {
          contact: {
            select: {
              isGroup:
                true
            }
          }
        }
      });

    if (!ticket) {
      break;
    }

    const doesMatch =
      matchesRule({
        rule,
        ticket,
        messageBody:
          sourceMessage.body
      });

    if (!doesMatch) {
      continue;
    }

    matched +=
      1;

    const dedupeKey =
      `${rule.id}-${input.trigger}-${input.sourceMessageId}`;

    const existingRun =
      await prisma.automationRun.findUnique({
        where: {
          dedupeKey
        },
        select: {
          id: true
        }
      });

    if (existingRun) {
      continue;
    }

    const run =
      await prisma.automationRun.create({
        data: {
          companyId:
            input.companyId,
          ruleId:
            rule.id,
          ticketId:
            input.ticketId,
          sourceMessageId:
            input.sourceMessageId,
          trigger:
            input.trigger,
          status:
            "RUNNING",
          matched:
            true,
          dedupeKey
        }
      });

    try {
      const actions =
        await prisma.automationAction.findMany({
          where: {
            ruleId:
              rule.id
          },
          orderBy: {
            orderIndex:
              "asc"
          }
        });

      const results:
        unknown[] = [];

      for (
        const action
        of actions
      ) {
        results.push(
          await executeAction({
            companyId:
              input.companyId,
            ticketId:
              input.ticketId,
            action,
            companyName:
              company.name
          })
        );
      }

      await prisma.automationRun.update({
        where: {
          id:
            run.id
        },
        data: {
          status:
            "SUCCESS",
          details:
            toPrismaJson({
              rule:
                rule.name,
              actions:
                results
            }),
          finishedAt:
            new Date()
        }
      });

      await recordTicketEvent({
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        type:
          "AUTOMATION_APPLIED",
        metadata: {
          ruleId:
            rule.id,
          ruleName:
            rule.name,
          trigger:
            input.trigger
        }
      });

      publishRealtime(
        input.companyId,
        {
          type:
            "ticket.updated",
          ticketId:
            input.ticketId
        }
      );
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : "Unknown automation error.";

      await prisma.automationRun.update({
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
              4000
            ),
          finishedAt:
            new Date()
        }
      });

      console.error(
        "[automations] rule execution failed",
        {
          ruleId:
            rule.id,
          ticketId:
            input.ticketId,
          error:
            message
        }
      );
    }
  }

  return {
    evaluated:
      rules.length,
    matched
  };
}
