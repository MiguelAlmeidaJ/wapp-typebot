import type {
  Prisma
} from "../../generated/prisma/client.js";

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
  normalizeStageNames,
  PIPELINE_COLOR_KEYS,
  stageMoveChanged,
  type PipelineColorKey,
  type PipelineStageOutcome
} from "./pipeline.policy.js";

const boardContactSelect = {
  id:
    true,
  name:
    true,
  whatsappName:
    true,
  phoneNumber:
    true,
  email:
    true,
  lastSeenAt:
    true,
  customFieldValues: {
    where: {
      field: {
        isActive:
          true
      }
    },
    orderBy: {
      field: {
        position:
          "asc"
      }
    },
    take:
      2,
    select: {
      value:
        true,
      field: {
        select: {
          id:
            true,
          label:
            true,
          type:
            true
        }
      }
    }
  },
  tickets: {
    orderBy: {
      lastMessageAt:
        "desc"
    },
    take:
      1,
    select: {
      id:
        true,
      status:
        true,
      lastMessage:
        true,
      lastMessageAt:
        true,
      queue: {
        select: {
          id:
            true,
          name:
            true
        }
      },
      assignedMembership: {
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
  }
} satisfies Prisma.ContactSelect;

async function requirePipeline(
  companyId: string,
  pipelineId: string,
  activeOnly =
    false
) {
  const pipeline =
    await prisma.crmPipeline.findFirst({
      where: {
        id:
          pipelineId,
        companyId,
        ...(activeOnly
          ? {
              isActive:
                true
            }
          : {})
      }
    });

  if (
    !pipeline
  ) {
    throw new AppError(
      "Pipeline não encontrado.",
      404,
      "PIPELINE_NOT_FOUND"
    );
  }

  return pipeline;
}

async function requireContact(
  companyId: string,
  contactId: string
) {
  const contact =
    await prisma.contact.findFirst({
      where: {
        id:
          contactId,
        companyId,
        isGroup:
          false
      },
      select: {
        id:
          true,
        name:
          true
      }
    });

  if (
    !contact
  ) {
    throw new AppError(
      "Contato não encontrado ou não elegível para pipeline.",
      404,
      "PIPELINE_CONTACT_NOT_FOUND"
    );
  }

  return contact;
}

export async function listPipelines(
  companyId: string,
  includeInactive =
    false
) {
  return prisma.crmPipeline.findMany({
    where: {
      companyId,
      ...(includeInactive
        ? {}
        : {
            isActive:
              true
          })
    },
    include: {
      stages: {
        orderBy: [
          {
            position:
              "asc"
          },
          {
            createdAt:
              "asc"
          }
        ],
        include: {
          _count: {
            select: {
              states:
                true
            }
          }
        }
      },
      _count: {
        select: {
          states:
            true
        }
      }
    },
    orderBy: [
      {
        position:
          "asc"
      },
      {
        createdAt:
          "asc"
      }
    ]
  });
}

export async function createPipeline(input: {
  companyId: string;
  name: string;
  description?:
    string
    | null;
  stages:
    string[];
}) {
  const stages =
    normalizeStageNames(
      input.stages
    );

  if (
    stages.length <
    2
  ) {
    throw new AppError(
      "Crie pelo menos duas etapas no pipeline.",
      422,
      "PIPELINE_STAGES_REQUIRED"
    );
  }

  const last =
    await prisma.crmPipeline.findFirst({
      where: {
        companyId:
          input.companyId
      },
      orderBy: {
        position:
          "desc"
      },
      select: {
        position:
          true
      }
    });

  try {
    return await prisma.crmPipeline.create({
      data: {
        companyId:
          input.companyId,
        name:
          input.name.trim(),
        description:
          input.description
            ?.trim() ||
          null,
        position:
          (
            last?.position ??
            -1
          ) +
          1,
        stages: {
          create:
            stages.map(
              (
                name,
                index
              ) => ({
                name,
                position:
                  index,
                colorKey:
                  PIPELINE_COLOR_KEYS[
                    index %
                    PIPELINE_COLOR_KEYS.length
                  ],
                outcome:
                  "OPEN"
              })
            )
        }
      },
      include: {
        stages: {
          orderBy: {
            position:
              "asc"
          }
        }
      }
    });
  } catch (error) {
    if (
      error instanceof
        Error &&
      error.message.includes(
        "Unique constraint"
      )
    ) {
      throw new AppError(
        "Já existe um pipeline com esse nome.",
        409,
        "PIPELINE_NAME_EXISTS"
      );
    }

    throw error;
  }
}

export async function updatePipeline(input: {
  companyId: string;
  pipelineId: string;
  name?:
    string;
  description?:
    string
    | null;
  isActive?:
    boolean;
  position?:
    number;
}) {
  const pipeline =
    await requirePipeline(
      input.companyId,
      input.pipelineId
    );

  return prisma.crmPipeline.update({
    where: {
      id:
        pipeline.id
    },
    data: {
      ...(input.name !==
      undefined
        ? {
            name:
              input.name.trim()
          }
        : {}),
      ...(input.description !==
      undefined
        ? {
            description:
              input.description
                ?.trim() ||
              null
          }
        : {}),
      ...(input.isActive !==
      undefined
        ? {
            isActive:
              input.isActive
          }
        : {}),
      ...(input.position !==
      undefined
        ? {
            position:
              input.position
          }
        : {})
    }
  });
}

export async function createPipelineStage(input: {
  companyId: string;
  pipelineId: string;
  name: string;
  colorKey:
    PipelineColorKey;
  outcome:
    PipelineStageOutcome;
}) {
  await requirePipeline(
    input.companyId,
    input.pipelineId
  );

  const last =
    await prisma.crmStage.findFirst({
      where: {
        pipelineId:
          input.pipelineId
      },
      orderBy: {
        position:
          "desc"
      },
      select: {
        position:
          true
      }
    });

  try {
    return await prisma.crmStage.create({
      data: {
        pipelineId:
          input.pipelineId,
        name:
          input.name.trim(),
        colorKey:
          input.colorKey,
        outcome:
          input.outcome,
        position:
          (
            last?.position ??
            -1
          ) +
          1
      }
    });
  } catch (error) {
    if (
      error instanceof
        Error &&
      error.message.includes(
        "Unique constraint"
      )
    ) {
      throw new AppError(
        "Já existe uma etapa com esse nome neste pipeline.",
        409,
        "PIPELINE_STAGE_NAME_EXISTS"
      );
    }

    throw error;
  }
}

export async function updatePipelineStage(input: {
  companyId: string;
  stageId: string;
  name?:
    string;
  colorKey?:
    PipelineColorKey;
  outcome?:
    PipelineStageOutcome;
  position?:
    number;
  isActive?:
    boolean;
}) {
  const stage =
    await prisma.crmStage.findFirst({
      where: {
        id:
          input.stageId,
        pipeline: {
          companyId:
            input.companyId
        }
      },
      include: {
        _count: {
          select: {
            states:
              true
          }
        }
      }
    });

  if (
    !stage
  ) {
    throw new AppError(
      "Etapa não encontrada.",
      404,
      "PIPELINE_STAGE_NOT_FOUND"
    );
  }

  if (
    input.isActive ===
      false &&
    stage._count.states >
      0
  ) {
    throw new AppError(
      "Mova os contatos desta etapa antes de desativá-la.",
      409,
      "PIPELINE_STAGE_IN_USE"
    );
  }

  return prisma.crmStage.update({
    where: {
      id:
        stage.id
    },
    data: {
      ...(input.name !==
      undefined
        ? {
            name:
              input.name.trim()
          }
        : {}),
      ...(input.colorKey !==
      undefined
        ? {
            colorKey:
              input.colorKey
          }
        : {}),
      ...(input.outcome !==
      undefined
        ? {
            outcome:
              input.outcome
          }
        : {}),
      ...(input.position !==
      undefined
        ? {
            position:
              input.position
          }
        : {}),
      ...(input.isActive !==
      undefined
        ? {
            isActive:
              input.isActive
          }
        : {})
    }
  });
}

function contactSearchWhere(
  companyId: string,
  search?:
    string
) {
  const q =
    search
      ?.trim()
      .slice(
        0,
        100
      );

  return {
    companyId,
    isGroup:
      false,
    ...(q
      ? {
          OR: [
            {
              name: {
                contains:
                  q
              }
            },
            {
              whatsappName: {
                contains:
                  q
              }
            },
            {
              phoneNumber: {
                contains:
                  q
              }
            },
            {
              email: {
                contains:
                  q
              }
            }
          ]
        }
      : {})
  } satisfies Prisma.ContactWhereInput;
}

export async function getPipelineBoard(input: {
  companyId: string;
  pipelineId: string;
  search?:
    string;
}) {
  const pipeline =
    await prisma.crmPipeline.findFirst({
      where: {
        id:
          input.pipelineId,
        companyId:
          input.companyId,
        isActive:
          true
      },
      include: {
        stages: {
          where: {
            isActive:
              true
          },
          orderBy: [
            {
              position:
                "asc"
            },
            {
              createdAt:
                "asc"
            }
          ]
        }
      }
    });

  if (
    !pipeline
  ) {
    throw new AppError(
      "Pipeline não encontrado ou inativo.",
      404,
      "PIPELINE_NOT_FOUND"
    );
  }

  const contactWhere =
    contactSearchWhere(
      input.companyId,
      input.search
    );

  const [
    stageResults,
    unassignedContacts,
    unassignedCount
  ] =
    await Promise.all([
      Promise.all(
        pipeline.stages.map(
          async stage => {
            const [
              states,
              count
            ] =
              await Promise.all([
                prisma.contactPipelineState.findMany({
                  where: {
                    pipelineId:
                      pipeline.id,
                    stageId:
                      stage.id,
                    contact:
                      contactWhere
                  },
                  orderBy: {
                    updatedAt:
                      "desc"
                  },
                  take:
                    80,
                  select: {
                    id:
                      true,
                    enteredAt:
                      true,
                    updatedAt:
                      true,
                    contact: {
                      select:
                        boardContactSelect
                    }
                  }
                }),
                prisma.contactPipelineState.count({
                  where: {
                    pipelineId:
                      pipeline.id,
                    stageId:
                      stage.id,
                    contact:
                      contactWhere
                  }
                })
              ]);

            return {
              stage,
              count,
              truncated:
                count >
                states.length,
              contacts:
                states.map(
                  state => ({
                    ...state.contact,
                    stateId:
                      state.id,
                    enteredAt:
                      state.enteredAt,
                    pipelineUpdatedAt:
                      state.updatedAt
                  })
                )
            };
          }
        )
      ),
      prisma.contact.findMany({
        where: {
          ...contactWhere,
          pipelineStates: {
            none: {
              pipelineId:
                pipeline.id
            }
          }
        },
        orderBy: {
          updatedAt:
            "desc"
        },
        take:
          80,
        select:
          boardContactSelect
      }),
      prisma.contact.count({
        where: {
          ...contactWhere,
          pipelineStates: {
            none: {
              pipelineId:
                pipeline.id
            }
          }
        }
      })
    ]);

  return {
    pipeline: {
      id:
        pipeline.id,
      name:
        pipeline.name,
      description:
        pipeline.description,
      stages:
        pipeline.stages
    },
    columns: [
      {
        stage:
          null,
        count:
          unassignedCount,
        truncated:
          unassignedCount >
          unassignedContacts.length,
        contacts:
          unassignedContacts.map(
            contact => ({
              ...contact,
              stateId:
                null,
              enteredAt:
                null,
              pipelineUpdatedAt:
                null
            })
          )
      },
      ...stageResults
    ]
  };
}

export async function moveContactStage(input: {
  companyId: string;
  contactId: string;
  pipelineId: string;
  stageId:
    string
    | null;
  actorMembershipId: string;
}) {
  await Promise.all([
    requireContact(
      input.companyId,
      input.contactId
    ),
    requirePipeline(
      input.companyId,
      input.pipelineId,
      true
    )
  ]);

  const stage =
    input.stageId
      ? await prisma.crmStage.findFirst({
          where: {
            id:
              input.stageId,
            pipelineId:
              input.pipelineId,
            isActive:
              true
          }
        })
      : null;

  if (
    input.stageId &&
    !stage
  ) {
    throw new AppError(
      "A etapa escolhida não pertence ao pipeline ou está inativa.",
      422,
      "PIPELINE_STAGE_INVALID"
    );
  }

  const current =
    await prisma.contactPipelineState.findUnique({
      where: {
        contactId_pipelineId: {
          contactId:
            input.contactId,
          pipelineId:
            input.pipelineId
        }
      }
    });

  if (
    !stageMoveChanged(
      current?.stageId,
      stage?.id
    )
  ) {
    return {
      changed:
        false,
      state:
        current
    };
  }

  const now =
    new Date();

  const [
    nextState
  ] =
    await prisma.$transaction(
      async tx => {
        const state =
          stage
            ? await tx.contactPipelineState.upsert({
                where: {
                  contactId_pipelineId: {
                    contactId:
                      input.contactId,
                    pipelineId:
                      input.pipelineId
                  }
                },
                create: {
                  contactId:
                    input.contactId,
                  pipelineId:
                    input.pipelineId,
                  stageId:
                    stage.id,
                  enteredAt:
                    now,
                  updatedByMembershipId:
                    input.actorMembershipId
                },
                update: {
                  stageId:
                    stage.id,
                  enteredAt:
                    now,
                  updatedByMembershipId:
                    input.actorMembershipId
                }
              })
            : (
                current
                  ? (
                      await tx.contactPipelineState.delete({
                        where: {
                          id:
                            current.id
                        }
                      }),
                      null
                    )
                  : null
              );

        await tx.contactStageTransition.create({
          data: {
            companyId:
              input.companyId,
            contactId:
              input.contactId,
            pipelineId:
              input.pipelineId,
            fromStageId:
              current?.stageId ??
              null,
            toStageId:
              stage?.id ??
              null,
            actorMembershipId:
              input.actorMembershipId
          }
        });

        return [
          state
        ];
      }
    );

  publishRealtime(
    input.companyId,
    {
      type:
        "contact.pipeline.updated",
      contactId:
        input.contactId,
      pipelineId:
        input.pipelineId,
      membershipId:
        input.actorMembershipId
    }
  );

  return {
    changed:
      true,
    state:
      nextState
  };
}

export async function getContactPipelineStates(input: {
  companyId: string;
  contactId: string;
}) {
  await requireContact(
    input.companyId,
    input.contactId
  );

  const [
    pipelines,
    states,
    transitions
  ] =
    await Promise.all([
      prisma.crmPipeline.findMany({
        where: {
          companyId:
            input.companyId,
          isActive:
            true
        },
        include: {
          stages: {
            where: {
              isActive:
                true
            },
            orderBy: {
              position:
                "asc"
            }
          }
        },
        orderBy: {
          position:
            "asc"
        }
      }),
      prisma.contactPipelineState.findMany({
        where: {
          contactId:
            input.contactId,
          pipeline: {
            companyId:
              input.companyId
          }
        },
        select: {
          id:
            true,
          pipelineId:
            true,
          stageId:
            true,
          enteredAt:
            true,
          updatedAt:
            true
        }
      }),
      prisma.contactStageTransition.findMany({
        where: {
          companyId:
            input.companyId,
          contactId:
            input.contactId
        },
        orderBy: {
          createdAt:
            "desc"
        },
        take:
          20,
        select: {
          id:
            true,
          pipelineId:
            true,
          createdAt:
            true,
          pipeline: {
            select: {
              name:
                true
            }
          },
          fromStage: {
            select: {
              name:
                true
            }
          },
          toStage: {
            select: {
              name:
                true
            }
          },
          actorMembership: {
            select: {
              user: {
                select: {
                  name:
                    true
                }
              }
            }
          }
        }
      })
    ]);

  const stateByPipeline =
    new Map(
      states.map(
        state => [
          state.pipelineId,
          state
        ]
      )
    );

  return {
    pipelines:
      pipelines.map(
        pipeline => ({
          ...pipeline,
          currentState:
            stateByPipeline.get(
              pipeline.id
            ) ??
            null
        })
      ),
    transitions
  };
}
