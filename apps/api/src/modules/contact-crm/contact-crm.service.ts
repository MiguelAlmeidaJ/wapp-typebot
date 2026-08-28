import {
  AppError
} from "../../errors/app-error.js";
import {
  prisma
} from "../../lib/database.js";
import {
  fieldKeyFromLabel,
  normalizeSelectOptions,
  type ContactFieldTypeValue,
  validateContactFieldValue
} from "./contact-crm.policy.js";

function jsonOptions(
  value: unknown
) {
  if (
    !Array.isArray(
      value
    )
  ) {
    return [];
  }

  return value.filter(
    (
      item
    ): item is string =>
      typeof item ===
      "string"
  );
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
        companyId
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
      "Contato não encontrado.",
      404,
      "CONTACT_NOT_FOUND"
    );
  }

  return contact;
}

async function uniqueFieldKey(
  companyId: string,
  label: string
) {
  const base =
    fieldKeyFromLabel(
      label
    );

  let key =
    base;

  for (
    let suffix =
      2;
    suffix <
      1000;
    suffix +=
      1
  ) {
    const existing =
      await prisma.contactFieldDefinition.findUnique({
        where: {
          companyId_key: {
            companyId,
            key
          }
        },
        select: {
          id:
            true
        }
      });

    if (
      !existing
    ) {
      return key;
    }

    key =
      `${base.slice(
        0,
        35
      )}_${suffix}`;
  }

  throw new AppError(
    "Não foi possível gerar uma chave única para o campo.",
    409,
    "CONTACT_FIELD_KEY_EXHAUSTED"
  );
}

export async function listContactFields(
  companyId: string,
  includeInactive =
    false
) {
  return prisma.contactFieldDefinition.findMany({
    where: {
      companyId,
      ...(includeInactive
        ? {}
        : {
            isActive:
              true
          })
    },
    orderBy: [
      {
        position:
          "asc"
      },
      {
        label:
          "asc"
      }
    ]
  });
}

export async function createContactField(input: {
  companyId: string;
  label: string;
  type:
    ContactFieldTypeValue;
  required:
    boolean;
  options?:
    string[];
}) {
  const label =
    input.label.trim();

  const options =
    input.type ===
      "SELECT"
      ? normalizeSelectOptions(
          input.options
        )
      : [];

  if (
    input.type ===
      "SELECT" &&
    options.length <
      2
  ) {
    throw new AppError(
      "Campos de seleção precisam de pelo menos duas opções.",
      422,
      "CONTACT_FIELD_OPTIONS_REQUIRED"
    );
  }

  const key =
    await uniqueFieldKey(
      input.companyId,
      label
    );

  const last =
    await prisma.contactFieldDefinition.findFirst({
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

  return prisma.contactFieldDefinition.create({
    data: {
      companyId:
        input.companyId,
      key,
      label,
      type:
        input.type,
      required:
        input.required,
      position:
        (
          last?.position ??
          -1
        ) +
        1,
      options:
        input.type ===
          "SELECT"
          ? options
          : undefined
    }
  });
}

export async function updateContactField(input: {
  companyId: string;
  fieldId: string;
  label?:
    string;
  required?:
    boolean;
  isActive?:
    boolean;
  position?:
    number;
  options?:
    string[];
}) {
  const field =
    await prisma.contactFieldDefinition.findFirst({
      where: {
        id:
          input.fieldId,
        companyId:
          input.companyId
      }
    });

  if (
    !field
  ) {
    throw new AppError(
      "Campo personalizado não encontrado.",
      404,
      "CONTACT_FIELD_NOT_FOUND"
    );
  }

  const options =
    field.type ===
      "SELECT" &&
    input.options !==
      undefined
      ? normalizeSelectOptions(
          input.options
        )
      : undefined;

  if (
    field.type ===
      "SELECT" &&
    options &&
    options.length <
      2
  ) {
    throw new AppError(
      "Campos de seleção precisam de pelo menos duas opções.",
      422,
      "CONTACT_FIELD_OPTIONS_REQUIRED"
    );
  }

  return prisma.contactFieldDefinition.update({
    where: {
      id:
        field.id
    },
    data: {
      ...(input.label !==
      undefined
        ? {
            label:
              input.label.trim()
          }
        : {}),
      ...(input.required !==
      undefined
        ? {
            required:
              input.required
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
        : {}),
      ...(options !==
      undefined
        ? {
            options
          }
        : {})
    }
  });
}

function fieldValueErrorMessage(
  code: string
) {
  switch (
    code
  ) {
    case "TEXT_TOO_LONG":
      return "O texto excede 2000 caracteres.";
    case "INVALID_NUMBER":
      return "Informe um número válido.";
    case "INVALID_DATE":
      return "Informe uma data válida.";
    case "INVALID_BOOLEAN":
      return "Informe verdadeiro ou falso.";
    case "INVALID_OPTION":
      return "A opção escolhida não existe mais.";
    default:
      return "Valor inválido.";
  }
}

export async function saveContactFieldValues(input: {
  companyId: string;
  contactId: string;
  values:
    Array<{
      fieldId:
        string;
      value:
        string
        | null;
    }>;
}) {
  await requireContact(
    input.companyId,
    input.contactId
  );

  const fields =
    await prisma.contactFieldDefinition.findMany({
      where: {
        companyId:
          input.companyId,
        isActive:
          true
      }
    });

  const byId =
    new Map(
      fields.map(
        field => [
          field.id,
          field
        ]
      )
    );

  for (
    const entry
    of input.values
  ) {
    const field =
      byId.get(
        entry.fieldId
      );

    if (
      !field
    ) {
      throw new AppError(
        "Um dos campos personalizados não existe ou está inativo.",
        422,
        "CONTACT_FIELD_INVALID"
      );
    }

    const value =
      entry.value
        ?.trim() ??
      "";

    const error =
      validateContactFieldValue({
        type:
          field.type as
            ContactFieldTypeValue,
        value,
        options:
          jsonOptions(
            field.options
          )
      });

    if (
      error
    ) {
      throw new AppError(
        `${field.label}: ${fieldValueErrorMessage(
          error
        )}`,
        422,
        "CONTACT_FIELD_VALUE_INVALID"
      );
    }
  }

  const existing =
    await prisma.contactFieldValue.findMany({
      where: {
        contactId:
          input.contactId,
        field: {
          companyId:
            input.companyId
        }
      }
    });

  const finalValues =
    new Map(
      existing.map(
        item => [
          item.fieldId,
          item.value ??
            ""
        ]
      )
    );

  for (
    const entry
    of input.values
  ) {
    finalValues.set(
      entry.fieldId,
      entry.value
        ?.trim() ??
        ""
    );
  }

  for (
    const field
    of fields
  ) {
    if (
      field.required &&
      !finalValues
        .get(
          field.id
        )
        ?.trim()
    ) {
      throw new AppError(
        `O campo “${field.label}” é obrigatório.`,
        422,
        "CONTACT_FIELD_REQUIRED"
      );
    }
  }

  await prisma.$transaction(
    input.values.map(
      entry => {
        const value =
          entry.value
            ?.trim() ??
          "";

        return value
          ? prisma.contactFieldValue.upsert({
              where: {
                contactId_fieldId: {
                  contactId:
                    input.contactId,
                  fieldId:
                    entry.fieldId
                }
              },
              create: {
                contactId:
                  input.contactId,
                fieldId:
                  entry.fieldId,
                value
              },
              update: {
                value
              }
            })
          : prisma.contactFieldValue.deleteMany({
              where: {
                contactId:
                  input.contactId,
                fieldId:
                  entry.fieldId
              }
            });
      }
    )
  );

  return getContactCrmProfile(
    input.companyId,
    input.contactId
  );
}

export async function getContactCrmProfile(
  companyId: string,
  contactId: string
) {
  const contact =
    await requireContact(
      companyId,
      contactId
    );

  const [
    fields,
    values,
    messages,
    events,
    notes
  ] =
    await Promise.all([
      listContactFields(
        companyId
      ),
      prisma.contactFieldValue.findMany({
        where: {
          contactId,
          field: {
            companyId
          }
        },
        select: {
          fieldId:
            true,
          value:
            true
        }
      }),
      prisma.message.findMany({
        where: {
          companyId,
          ticket: {
            contactId
          }
        },
        orderBy: {
          timestamp:
            "desc"
        },
        take:
          40,
        select: {
          id:
            true,
          ticketId:
            true,
          direction:
            true,
          type:
            true,
          body:
            true,
          timestamp:
            true,
          sentByUser: {
            select: {
              name:
                true
            }
          }
        }
      }),
      prisma.ticketEvent.findMany({
        where: {
          companyId,
          ticket: {
            contactId
          }
        },
        orderBy: {
          createdAt:
            "desc"
        },
        take:
          30,
        select: {
          id:
            true,
          ticketId:
            true,
          type:
            true,
          createdAt:
            true,
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
      }),
      prisma.ticketNote.findMany({
        where: {
          companyId,
          ticket: {
            contactId
          }
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
          ticketId:
            true,
          body:
            true,
          createdAt:
            true,
          authorMembership: {
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

  const timeline =
    [
      ...messages.map(
        message => ({
          id:
            `message:${message.id}`,
          kind:
            "MESSAGE" as const,
          ticketId:
            message.ticketId,
          occurredAt:
            message.timestamp,
          title:
            message.direction ===
              "INBOUND"
              ? "Mensagem recebida"
              : "Mensagem enviada",
          body:
            message.body ??
            `[${message.type.toLowerCase()}]`,
          actorName:
            message.sentByUser
              ?.name ??
            (
              message.direction ===
                "INBOUND"
                ? contact.name
                : "Sistema"
            )
        })
      ),
      ...events.map(
        event => ({
          id:
            `event:${event.id}`,
          kind:
            "EVENT" as const,
          ticketId:
            event.ticketId,
          occurredAt:
            event.createdAt,
          title:
            event.type,
          body:
            "Movimentação do atendimento.",
          actorName:
            event.actorMembership
              ?.user.name ??
            "Sistema"
        })
      ),
      ...notes.map(
        note => ({
          id:
            `note:${note.id}`,
          kind:
            "NOTE" as const,
          ticketId:
            note.ticketId,
          occurredAt:
            note.createdAt,
          title:
            "Nota interna",
          body:
            note.body,
          actorName:
            note.authorMembership
              .user.name
        })
      )
    ]
      .sort(
        (
          left,
          right
        ) =>
          right
            .occurredAt
            .getTime() -
          left
            .occurredAt
            .getTime()
      )
      .slice(
        0,
        60
      );

  return {
    contact: {
      id:
        contact.id,
      name:
        contact.name
    },
    fields,
    values:
      Object.fromEntries(
        values.map(
          entry => [
            entry.fieldId,
            entry.value
          ]
        )
      ),
    timeline
  };
}
