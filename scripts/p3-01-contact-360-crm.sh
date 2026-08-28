#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEMA="apps/api/prisma/schema.prisma"
APP="apps/api/src/app.ts"
PERMISSIONS="apps/api/src/security/permissions.ts"
PERMISSIONS_TEST="apps/api/src/security/permissions.test.ts"
CONTACTS_PAGE="apps/web/app/dashboard/contacts/page.tsx"
CSS="apps/web/app/globals.css"

echo "[P3.1] Installing Contact 360 CRM..."

for required in \
  "$SCHEMA" \
  "$APP" \
  "$PERMISSIONS" \
  "$PERMISSIONS_TEST" \
  "$CONTACTS_PAGE" \
  "$CSS"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/contact-crm \
  apps/api/prisma/migrations/20260828234500_contact_crm \
  apps/web/components/contacts \
  docs

# ---------------------------------------------------------------------------
# Prisma
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/prisma/schema.prisma";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !content.includes(
    "enum ContactFieldType {"
  )
) {
  const anchor =
    "enum MembershipRole {";

  const index =
    content.indexOf(
      anchor
    );

  if (
    index <
    0
  ) {
    throw new Error(
      "MembershipRole enum anchor not found."
    );
  }

  const addition =
    `enum ContactFieldType {
  TEXT
  NUMBER
  DATE
  BOOLEAN
  SELECT
}

`;

  content =
    content.slice(
      0,
      index
    ) +
    addition +
    content.slice(
      index
    );
}

function addRelation(
  modelName,
  fieldName,
  line
) {
  const start =
    content.indexOf(
      `model ${modelName} {`
    );

  if (
    start <
    0
  ) {
    throw new Error(
      `${modelName} model not found.`
    );
  }

  const end =
    content.indexOf(
      "\n}",
      start
    );

  if (
    end <
    0
  ) {
    throw new Error(
      `${modelName} model end not found.`
    );
  }

  const block =
    content.slice(
      start,
      end
    );

  if (
    block.includes(
      `\n  ${fieldName} `
    )
  ) {
    return;
  }

  content =
    content.slice(
      0,
      end
    ) +
    `\n${line}` +
    content.slice(
      end
    );
}

addRelation(
  "Company",
  "contactFieldDefinitions",
  "  contactFieldDefinitions ContactFieldDefinition[]"
);

addRelation(
  "Contact",
  "customFieldValues",
  "  customFieldValues       ContactFieldValue[]"
);

if (
  !content.includes(
    "model ContactFieldDefinition {"
  )
) {
  content += `

model ContactFieldDefinition {
  id        String           @id @default(uuid()) @db.Char(36)
  companyId String           @db.Char(36)
  key       String           @db.VarChar(50)
  label     String           @db.VarChar(120)
  type      ContactFieldType
  options   Json?
  required  Boolean          @default(false)
  position  Int              @default(0)
  isActive  Boolean          @default(true)
  company   Company          @relation(fields: [companyId], references: [id], onDelete: Cascade)
  values    ContactFieldValue[]
  createdAt DateTime         @default(now())
  updatedAt DateTime         @updatedAt

  @@unique([companyId, key])
  @@index([companyId, isActive, position])
}

model ContactFieldValue {
  id        String                 @id @default(uuid()) @db.Char(36)
  contactId String                 @db.Char(36)
  fieldId   String                 @db.Char(36)
  value     String?                @db.Text
  contact   Contact                @relation(fields: [contactId], references: [id], onDelete: Cascade)
  field     ContactFieldDefinition @relation(fields: [fieldId], references: [id], onDelete: Cascade)
  createdAt DateTime               @default(now())
  updatedAt DateTime               @updatedAt

  @@unique([contactId, fieldId])
  @@index([fieldId, updatedAt])
  @@index([contactId, updatedAt])
}
`;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.1] Prisma CRM models prepared."
);
NODE

cat > apps/api/prisma/migrations/20260828234500_contact_crm/migration.sql <<'EOF'
CREATE TABLE `ContactFieldDefinition` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `key` VARCHAR(50) NOT NULL,
  `label` VARCHAR(120) NOT NULL,
  `type` ENUM(
    'TEXT',
    'NUMBER',
    'DATE',
    'BOOLEAN',
    'SELECT'
  ) NOT NULL,
  `options` JSON NULL,
  `required` BOOLEAN NOT NULL DEFAULT false,
  `position` INTEGER NOT NULL DEFAULT 0,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),

  UNIQUE INDEX `ContactFieldDefinition_companyId_key_key`
    (`companyId`, `key`),

  INDEX `ContactFieldDefinition_companyId_isActive_position_idx`
    (`companyId`, `isActive`, `position`),

  CONSTRAINT `ContactFieldDefinition_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `ContactFieldValue` (
  `id` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `fieldId` CHAR(36) NOT NULL,
  `value` TEXT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),

  UNIQUE INDEX `ContactFieldValue_contactId_fieldId_key`
    (`contactId`, `fieldId`),

  INDEX `ContactFieldValue_fieldId_updatedAt_idx`
    (`fieldId`, `updatedAt`),

  INDEX `ContactFieldValue_contactId_updatedAt_idx`
    (`contactId`, `updatedAt`),

  CONSTRAINT `ContactFieldValue_contactId_fkey`
    FOREIGN KEY (`contactId`)
    REFERENCES `Contact`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactFieldValue_fieldId_fkey`
    FOREIGN KEY (`fieldId`)
    REFERENCES `ContactFieldDefinition`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

# ---------------------------------------------------------------------------
# Pure CRM policy + tests
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/contact-crm/contact-crm.policy.ts <<'EOF'
export type ContactFieldTypeValue =
  | "TEXT"
  | "NUMBER"
  | "DATE"
  | "BOOLEAN"
  | "SELECT";

export function fieldKeyFromLabel(
  label: string
) {
  const normalized =
    label
      .normalize(
        "NFD"
      )
      .replace(
        /[\u0300-\u036f]/g,
        ""
      )
      .toLowerCase()
      .replace(
        /[^a-z0-9]+/g,
        "_"
      )
      .replace(
        /^_+|_+$/g,
        ""
      )
      .slice(
        0,
        40
      );

  return normalized ||
    "campo";
}

export function normalizeSelectOptions(
  options:
    string[]
    | undefined
) {
  return [
    ...new Set(
      (
        options ??
        []
      )
        .map(
          option =>
            option
              .trim()
              .slice(
                0,
                80
              )
        )
        .filter(
          Boolean
        )
    )
  ].slice(
    0,
    50
  );
}

export function validateContactFieldValue(input: {
  type:
    ContactFieldTypeValue;
  value:
    string;
  options?:
    string[];
}) {
  const value =
    input.value.trim();

  if (
    !value
  ) {
    return null;
  }

  switch (
    input.type
  ) {
    case "TEXT":
      return value.length <=
        2_000
        ? null
        : "TEXT_TOO_LONG";

    case "NUMBER":
      return Number.isFinite(
        Number(
          value
        )
      )
        ? null
        : "INVALID_NUMBER";

    case "DATE": {
      if (
        !/^\d{4}-\d{2}-\d{2}$/.test(
          value
        )
      ) {
        return "INVALID_DATE";
      }

      const date =
        new Date(
          `${value}T00:00:00.000Z`
        );

      return Number.isNaN(
        date.getTime()
      ) ||
        date
          .toISOString()
          .slice(
            0,
            10
          ) !==
          value
        ? "INVALID_DATE"
        : null;
    }

    case "BOOLEAN":
      return [
        "true",
        "false"
      ].includes(
        value
      )
        ? null
        : "INVALID_BOOLEAN";

    case "SELECT":
      return (
        input.options ??
        []
      ).includes(
        value
      )
        ? null
        : "INVALID_OPTION";
  }
}
EOF

cat > apps/api/src/modules/contact-crm/contact-crm.policy.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  fieldKeyFromLabel,
  normalizeSelectOptions,
  validateContactFieldValue
} from "./contact-crm.policy.js";

test(
  "field keys are stable and ASCII-safe",
  () => {
    assert.equal(
      fieldKeyFromLabel(
        "Data da Renovação"
      ),
      "data_da_renovacao"
    );
  }
);

test(
  "select options are trimmed and deduplicated",
  () => {
    assert.deepEqual(
      normalizeSelectOptions([
        " Lead ",
        "Cliente",
        "Lead",
        ""
      ]),
      [
        "Lead",
        "Cliente"
      ]
    );
  }
);

test(
  "typed CRM values reject invalid data",
  () => {
    assert.equal(
      validateContactFieldValue({
        type:
          "NUMBER",
        value:
          "12.50"
      }),
      null
    );

    assert.equal(
      validateContactFieldValue({
        type:
          "NUMBER",
        value:
          "abc"
      }),
      "INVALID_NUMBER"
    );

    assert.equal(
      validateContactFieldValue({
        type:
          "DATE",
        value:
          "2026-02-31"
      }),
      "INVALID_DATE"
    );

    assert.equal(
      validateContactFieldValue({
        type:
          "SELECT",
        value:
          "Cliente",
        options: [
          "Lead",
          "Cliente"
        ]
      }),
      null
    );
  }
);
EOF

# ---------------------------------------------------------------------------
# CRM service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/contact-crm/contact-crm.service.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# CRM routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/contact-crm/contact-crm.routes.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  requirePermission
} from "../auth/auth.guard.js";
import {
  createContactField,
  getContactCrmProfile,
  listContactFields,
  saveContactFieldValues,
  updateContactField
} from "./contact-crm.service.js";

const idSchema =
  z.object({
    id:
      z.string()
        .uuid()
  });

const createFieldSchema =
  z.object({
    label:
      z.string()
        .trim()
        .min(2)
        .max(120),
    type:
      z.enum([
        "TEXT",
        "NUMBER",
        "DATE",
        "BOOLEAN",
        "SELECT"
      ]),
    required:
      z.boolean()
        .default(
          false
        ),
    options:
      z.array(
        z.string()
          .trim()
          .min(1)
          .max(80)
      )
        .max(50)
        .optional()
  });

const updateFieldSchema =
  z.object({
    label:
      z.string()
        .trim()
        .min(2)
        .max(120)
        .optional(),
    required:
      z.boolean()
        .optional(),
    isActive:
      z.boolean()
        .optional(),
    position:
      z.number()
        .int()
        .min(0)
        .max(10_000)
        .optional(),
    options:
      z.array(
        z.string()
          .trim()
          .min(1)
          .max(80)
      )
        .max(50)
        .optional()
  })
    .refine(
      value =>
        Object.keys(
          value
        ).length >
        0,
      {
        message:
          "Informe ao menos uma alteração."
      }
    );

const saveValuesSchema =
  z.object({
    values:
      z.array(
        z.object({
          fieldId:
            z.string()
              .uuid(),
          value:
            z.string()
              .max(2_000)
              .nullable()
        })
      )
        .max(100)
  });

export async function contactCrmRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/contact-crm/fields",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contacts.read"
        );

      return {
        fields:
          await listContactFields(
            auth.companyId
          )
      };
    }
  );

  app.get(
    "/api/v1/contact-crm/fields/manage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contactFields.manage"
        );

      return {
        fields:
          await listContactFields(
            auth.companyId,
            true
          )
      };
    }
  );

  app.post(
    "/api/v1/contact-crm/fields",
    async (
      request,
      reply
    ) => {
      const auth =
        await requirePermission(
          request,
          "contactFields.manage"
        );

      const input =
        createFieldSchema.parse(
          request.body
        );

      return reply
        .status(
          201
        )
        .send({
          field:
            await createContactField({
              companyId:
                auth.companyId,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/contact-crm/fields/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contactFields.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        updateFieldSchema.parse(
          request.body
        );

      return {
        field:
          await updateContactField({
            companyId:
              auth.companyId,
            fieldId:
              params.id,
            ...input
          })
      };
    }
  );

  app.get(
    "/api/v1/contacts/:id/crm",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contacts.read"
        );

      const params =
        idSchema.parse(
          request.params
        );

      return getContactCrmProfile(
        auth.companyId,
        params.id
      );
    }
  );

  app.put(
    "/api/v1/contacts/:id/crm-fields",
    async request => {
      const auth =
        await requirePermission(
          request,
          "contacts.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        saveValuesSchema.parse(
          request.body
        );

      return saveContactFieldValues({
        companyId:
          auth.companyId,
        contactId:
          params.id,
        values:
          input.values
      });
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Central RBAC: contactFields.manage only for managerial roles.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/security/permissions.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

if (
  !content.includes(
    '| "contactFields.manage"'
  )
) {
  const anchor =
    '  | "contacts.manage"';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "contacts.manage permission type anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  | "contactFields.manage"`
    );
}

function roleBlock(
  role
) {
  const start =
    content.indexOf(
      `  ${role}: [`
    );

  if (
    start <
    0
  ) {
    throw new Error(
      `${role} permission block not found.`
    );
  }

  const nextRoles =
    [
      "OWNER",
      "ADMIN",
      "SUPERVISOR",
      "AGENT"
    ]
      .filter(
        candidate =>
          candidate !==
          role
      )
      .map(
        candidate =>
          content.indexOf(
            `\n  ${candidate}: [`,
            start +
            1
          )
      )
      .filter(
        index =>
          index >=
          0
      );

  const objectEnd =
    content.indexOf(
      "\n};",
      start
    );

  const end =
    Math.min(
      ...[
        ...nextRoles,
        objectEnd >=
          0
          ? objectEnd
          : content.length
      ]
    );

  return {
    start,
    end,
    block:
      content.slice(
        start,
        end
      )
  };
}

for (
  const role
  of [
    "OWNER",
    "ADMIN",
    "SUPERVISOR"
  ]
) {
  const current =
    roleBlock(
      role
    );

  if (
    current.block.includes(
      '"contactFields.manage"'
    )
  ) {
    continue;
  }

  const anchor =
    `  ${role}: [`;

  content =
    content.replace(
      anchor,
      `${anchor}
    "contactFields.manage",`
    );
}

const agent =
  roleBlock(
    "AGENT"
  );

if (
  agent.block.includes(
    '"contactFields.manage"'
  )
) {
  throw new Error(
    "AGENT must not receive contactFields.manage."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.1] contactFields.manage permission installed."
);
NODE

# Rebuild allPermissions from the actual current WappPermission union.
node <<'NODE'
const fs = require("node:fs");

const permissionPath =
  "apps/api/src/security/permissions.ts";

const testPath =
  "apps/api/src/security/permissions.test.ts";

const permissionSource =
  fs.readFileSync(
    permissionPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

let testSource =
  fs.readFileSync(
    testPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const typeStart =
  permissionSource.indexOf(
    "export type WappPermission ="
  );

const typeEnd =
  permissionSource.indexOf(
    ";",
    typeStart
  );

if (
  typeStart <
    0 ||
  typeEnd <
    0
) {
  throw new Error(
    "WappPermission union not found."
  );
}

const permissions =
  Array.from(
    permissionSource
      .slice(
        typeStart,
        typeEnd
      )
      .matchAll(
        /"([^"]+)"/g
      ),
    match =>
      match[1]
  );

const declarationStart =
  testSource.indexOf(
    "const allPermissions:"
  );

const firstDescribe =
  testSource.indexOf(
    "describe(",
    declarationStart
  );

if (
  declarationStart <
    0 ||
  firstDescribe <
    0
) {
  throw new Error(
    "permissions.test.ts allPermissions boundary not found."
  );
}

const declaration =
  `const allPermissions:
  WappPermission[] = [
${permissions
  .map(
    permission =>
      `    "${permission}"`
  )
  .join(",\n")}
  ];

`;

testSource =
  testSource.slice(
    0,
    declarationStart
  ) +
  declaration +
  testSource.slice(
    firstDescribe
  );

if (
  !testSource.includes(
    '"contact field schema is managerial only"'
  )
) {
  testSource += `

describe(
  "contact CRM field permissions",
  () => {
    it(
      "contact field schema is managerial only",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN",
            "SUPERVISOR"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              role,
              "contactFields.manage"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "contactFields.manage"
          ),
          false
        );
      }
    );
  }
);
`;
}

fs.writeFileSync(
  testPath,
  testSource
);

console.log(
  `[P3.1] permissions test rebuilt from ${permissions.length} current permissions.`
);
NODE

# ---------------------------------------------------------------------------
# Register routes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/app.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const importLine =
  'import { contactCrmRoutes } from "./modules/contact-crm/contact-crm.routes.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { contactRoutes } from "./modules/contacts/contact.routes.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "contactRoutes import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    "await app.register(contactCrmRoutes);"
  )
) {
  const anchor =
    `  await app.register(contactRoutes);`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "contactRoutes registration anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  await app.register(contactCrmRoutes);`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Web Contact 360 component
# ---------------------------------------------------------------------------

cat > apps/web/components/contacts/contact-crm-panel.tsx <<'EOF'
"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";
import {
  useRouter
} from "next/navigation";

import {
  useAuth
} from "@/components/auth-provider";
import {
  ApiError
} from "@/lib/api";

type FieldType =
  | "TEXT"
  | "NUMBER"
  | "DATE"
  | "BOOLEAN"
  | "SELECT";

interface ContactField {
  id: string;
  key: string;
  label: string;
  type:
    FieldType;
  options:
    unknown;
  required:
    boolean;
  position:
    number;
  isActive:
    boolean;
}

interface TimelineItem {
  id: string;
  kind:
    | "MESSAGE"
    | "EVENT"
    | "NOTE";
  ticketId: string;
  occurredAt: string;
  title: string;
  body: string;
  actorName: string;
}

interface CrmProfile {
  fields:
    ContactField[];
  values:
    Record<
      string,
      string
      | null
    >;
  timeline:
    TimelineItem[];
}

function optionsOf(
  field:
    ContactField
) {
  return Array.isArray(
    field.options
  )
    ? field.options.filter(
        (
          option
        ): option is string =>
          typeof option ===
          "string"
      )
    : [];
}

function timelineTitle(
  item:
    TimelineItem
) {
  if (
    item.kind ===
    "MESSAGE"
  ) {
    return item.title;
  }

  if (
    item.kind ===
    "NOTE"
  ) {
    return "Nota interna";
  }

  const labels:
    Record<
      string,
      string
    > = {
      CREATED:
        "Atendimento criado",
      CLAIMED:
        "Atendimento assumido",
      TRANSFERRED:
        "Atendimento transferido",
      CLOSED:
        "Atendimento encerrado",
      REOPENED:
        "Atendimento reaberto",
      TAGS_UPDATED:
        "Etiquetas atualizadas",
      AUTOMATION_APPLIED:
        "Automação executada",
      MESSAGE_SCHEDULED:
        "Mensagem agendada",
      SCHEDULED_MESSAGE_SENT:
        "Agendamento enviado",
      SCHEDULED_MESSAGE_FAILED:
        "Falha no agendamento",
      SCHEDULED_MESSAGE_CANCELLED:
        "Agendamento cancelado"
    };

  return labels[
    item.title
  ] ??
    item.title;
}

function dateTimeLabel(
  value: string
) {
  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      dateStyle:
        "short",
      timeStyle:
        "short"
    }
  ).format(
    new Date(
      value
    )
  );
}

export function ContactCrmPanel({
  contactId,
  contactName
}: {
  contactId:
    string;
  contactName:
    string;
}) {
  const router =
    useRouter();

  const {
    session,
    request
  } =
    useAuth();

  const [
    profile,
    setProfile
  ] =
    useState<
      CrmProfile
      | null
    >(
      null
    );

  const [
    values,
    setValues
  ] =
    useState<
      Record<
        string,
        string
      >
    >({});

  const [
    managedFields,
    setManagedFields
  ] =
    useState<
      ContactField[]
    >([]);

  const [
    managerOpen,
    setManagerOpen
  ] =
    useState(
      false
    );

  const [
    fieldLabel,
    setFieldLabel
  ] =
    useState("");

  const [
    fieldType,
    setFieldType
  ] =
    useState<
      FieldType
    >(
      "TEXT"
    );

  const [
    fieldRequired,
    setFieldRequired
  ] =
    useState(
      false
    );

  const [
    fieldOptions,
    setFieldOptions
  ] =
    useState("");

  const [
    savingValues,
    setSavingValues
  ] =
    useState(
      false
    );

  const [
    savingField,
    setSavingField
  ] =
    useState(
      false
    );

  const [
    loading,
    setLoading
  ] =
    useState(
      true
    );

  const [
    error,
    setError
  ] =
    useState("");

  const [
    notice,
    setNotice
  ] =
    useState("");

  const canManageSchema =
    session
      ? [
          "OWNER",
          "ADMIN",
          "SUPERVISOR"
        ].includes(
          session.role
        )
      : false;

  const load =
    useCallback(
      async () => {
        setLoading(
          true
        );

        try {
          const payload =
            await request<
              CrmProfile
            >(
              `/api/v1/contacts/${contactId}/crm`
            );

          setProfile(
            payload
          );

          setValues(
            Object.fromEntries(
              payload.fields.map(
                field => [
                  field.id,
                  payload.values[
                    field.id
                  ] ??
                    ""
                ]
              )
            )
          );

          setError("");
        } catch {
          setError(
            "Não foi possível carregar a ficha CRM."
          );
        } finally {
          setLoading(
            false
          );
        }
      },
      [
        contactId,
        request
      ]
    );

  const loadManaged =
    useCallback(
      async () => {
        if (
          !canManageSchema
        ) {
          return;
        }

        const payload =
          await request<{
            fields:
              ContactField[];
          }>(
            "/api/v1/contact-crm/fields/manage"
          );

        setManagedFields(
          payload.fields
        );
      },
      [
        canManageSchema,
        request
      ]
    );

  useEffect(
    () => {
      void load();
    },
    [
      load
    ]
  );

  useEffect(
    () => {
      setManagerOpen(
        false
      );
      setNotice("");
      setError("");
    },
    [
      contactId
    ]
  );

  const timeline =
    useMemo(
      () =>
        profile
          ?.timeline
          .slice(
            0,
            30
          ) ??
        [],
      [
        profile
      ]
    );

  async function saveValues(
    event:
      FormEvent<
        HTMLFormElement
      >
  ) {
    event.preventDefault();

    if (
      !profile
    ) {
      return;
    }

    setSavingValues(
      true
    );

    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/contacts/${contactId}/crm-fields`,
        {
          method:
            "PUT",
          body:
            JSON.stringify({
              values:
                profile.fields.map(
                  field => ({
                    fieldId:
                      field.id,
                    value:
                      values[
                        field.id
                      ]?.trim() ||
                      null
                  })
                )
            })
        }
      );

      setNotice(
        "Dados personalizados atualizados."
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível salvar os dados personalizados."
      );
    } finally {
      setSavingValues(
        false
      );
    }
  }

  async function createField(
    event:
      FormEvent<
        HTMLFormElement
      >
  ) {
    event.preventDefault();

    if (
      !canManageSchema ||
      !fieldLabel.trim()
    ) {
      return;
    }

    setSavingField(
      true
    );

    setError("");
    setNotice("");

    try {
      await request(
        "/api/v1/contact-crm/fields",
        {
          method:
            "POST",
          body:
            JSON.stringify({
              label:
                fieldLabel.trim(),
              type:
                fieldType,
              required:
                fieldRequired,
              ...(fieldType ===
                "SELECT"
                ? {
                    options:
                      fieldOptions
                        .split(",")
                        .map(
                          option =>
                            option.trim()
                        )
                        .filter(
                          Boolean
                        )
                  }
                : {})
            })
        }
      );

      setFieldLabel("");
      setFieldType(
        "TEXT"
      );
      setFieldRequired(
        false
      );
      setFieldOptions("");

      setNotice(
        "Campo personalizado criado."
      );

      await Promise.all([
        load(),
        loadManaged()
      ]);
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível criar o campo."
      );
    } finally {
      setSavingField(
        false
      );
    }
  }

  async function toggleField(
    field:
      ContactField
  ) {
    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/contact-crm/fields/${field.id}`,
        {
          method:
            "PATCH",
          body:
            JSON.stringify({
              isActive:
                !field.isActive
            })
        }
      );

      await Promise.all([
        load(),
        loadManaged()
      ]);
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível alterar o campo."
      );
    }
  }

  return (
    <section className="contact-crm">
      <header className="contact-crm__header">
        <div>
          <span className="eyebrow">
            CRM operacional
          </span>

          <h3>
            Perfil 360º
          </h3>

          <p>
            Dados estruturados e atividade de {contactName}.
          </p>
        </div>

        {canManageSchema && (
          <button
            className="ghost-button"
            onClick={() => {
              setManagerOpen(
                current =>
                  !current
              );

              if (
                !managerOpen
              ) {
                void loadManaged()
                  .catch(() => {
                    setError(
                      "Não foi possível carregar a configuração dos campos."
                    );
                  });
              }
            }}
            type="button"
          >
            {managerOpen
              ? "Fechar campos"
              : "Configurar campos"}
          </button>
        )}
      </header>

      {error && (
        <div className="contact-crm__feedback contact-crm__feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="contact-crm__feedback">
          {notice}
        </div>
      )}

      {managerOpen &&
        canManageSchema && (
        <div className="contact-field-manager">
          <form
            className="contact-field-form"
            onSubmit={
              createField
            }
          >
            <label>
              <span>
                Nome do campo
              </span>

              <input
                maxLength={
                  120
                }
                onChange={
                  event =>
                    setFieldLabel(
                      event
                        .target
                        .value
                    )
                }
                placeholder="Ex.: Plano contratado"
                required
                value={
                  fieldLabel
                }
              />
            </label>

            <label>
              <span>
                Tipo
              </span>

              <select
                onChange={
                  event =>
                    setFieldType(
                      event
                        .target
                        .value as
                        FieldType
                    )
                }
                value={
                  fieldType
                }
              >
                <option value="TEXT">
                  Texto
                </option>
                <option value="NUMBER">
                  Número
                </option>
                <option value="DATE">
                  Data
                </option>
                <option value="BOOLEAN">
                  Sim / não
                </option>
                <option value="SELECT">
                  Seleção
                </option>
              </select>
            </label>

            {fieldType ===
              "SELECT" && (
              <label className="contact-field-form__options">
                <span>
                  Opções
                </span>

                <input
                  onChange={
                    event =>
                      setFieldOptions(
                        event
                          .target
                          .value
                      )
                  }
                  placeholder="Lead, Cliente, Inativo"
                  value={
                    fieldOptions
                  }
                />
              </label>
            )}

            <label className="contact-field-form__check">
              <input
                checked={
                  fieldRequired
                }
                onChange={
                  event =>
                    setFieldRequired(
                      event
                        .target
                        .checked
                    )
                }
                type="checkbox"
              />
              Obrigatório
            </label>

            <button
              className="primary-button"
              disabled={
                savingField
              }
              type="submit"
            >
              <span>
                {savingField
                  ? "Criando…"
                  : "Criar campo"}
              </span>
            </button>
          </form>

          <div className="contact-field-admin-list">
            {managedFields.map(
              field => (
                <article
                  className={
                    field.isActive
                      ? "contact-field-admin-item"
                      : "contact-field-admin-item contact-field-admin-item--inactive"
                  }
                  key={
                    field.id
                  }
                >
                  <div>
                    <strong>
                      {field.label}
                    </strong>

                    <span>
                      {field.type}
                      {field.required
                        ? " · obrigatório"
                        : ""}
                    </span>
                  </div>

                  <button
                    onClick={() =>
                      void toggleField(
                        field
                      )
                    }
                    type="button"
                  >
                    {field.isActive
                      ? "Desativar"
                      : "Ativar"}
                  </button>
                </article>
              )
            )}

            {managedFields.length ===
              0 && (
              <div className="contact-crm__empty">
                Nenhum campo personalizado criado.
              </div>
            )}
          </div>
        </div>
      )}

      <div className="contact-crm__grid">
        <form
          className="contact-custom-fields"
          onSubmit={
            saveValues
          }
        >
          <header>
            <strong>
              Dados personalizados
            </strong>

            <span>
              {profile?.fields.length ??
                0} campos
            </span>
          </header>

          {loading ? (
            <div className="contact-crm__empty">
              Carregando…
            </div>
          ) : !profile ||
            profile.fields.length ===
              0 ? (
            <div className="contact-crm__empty">
              Nenhum campo personalizado ativo.
            </div>
          ) : (
            <>
              <div className="contact-custom-fields__list">
                {profile.fields.map(
                  field => (
                    <label
                      className="field"
                      key={
                        field.id
                      }
                    >
                      <span>
                        {field.label}
                        {field.required
                          ? " *"
                          : ""}
                      </span>

                      {field.type ===
                        "SELECT" ? (
                        <select
                          onChange={
                            event =>
                              setValues(
                                current => ({
                                  ...current,
                                  [field.id]:
                                    event
                                      .target
                                      .value
                                })
                              )
                          }
                          value={
                            values[
                              field.id
                            ] ??
                            ""
                          }
                        >
                          <option value="">
                            Selecionar…
                          </option>

                          {optionsOf(
                            field
                          ).map(
                            option => (
                              <option
                                key={
                                  option
                                }
                                value={
                                  option
                                }
                              >
                                {option}
                              </option>
                            )
                          )}
                        </select>
                      ) : field.type ===
                        "BOOLEAN" ? (
                        <select
                          onChange={
                            event =>
                              setValues(
                                current => ({
                                  ...current,
                                  [field.id]:
                                    event
                                      .target
                                      .value
                                })
                              )
                          }
                          value={
                            values[
                              field.id
                            ] ??
                            ""
                          }
                        >
                          <option value="">
                            Não informado
                          </option>
                          <option value="true">
                            Sim
                          </option>
                          <option value="false">
                            Não
                          </option>
                        </select>
                      ) : (
                        <input
                          onChange={
                            event =>
                              setValues(
                                current => ({
                                  ...current,
                                  [field.id]:
                                    event
                                      .target
                                      .value
                                })
                              )
                          }
                          type={
                            field.type ===
                              "NUMBER"
                              ? "number"
                              : field.type ===
                                  "DATE"
                                ? "date"
                                : "text"
                          }
                          value={
                            values[
                              field.id
                            ] ??
                            ""
                          }
                        />
                      )}
                    </label>
                  )
                )}
              </div>

              <button
                className="primary-button"
                disabled={
                  savingValues
                }
                type="submit"
              >
                <span>
                  {savingValues
                    ? "Salvando…"
                    : "Salvar dados CRM"}
                </span>
              </button>
            </>
          )}
        </form>

        <section className="contact-timeline">
          <header>
            <strong>
              Linha do tempo
            </strong>

            <span>
              atividade recente
            </span>
          </header>

          <div className="contact-timeline__list">
            {timeline.map(
              item => (
                <button
                  className={
                    `contact-timeline-item contact-timeline-item--${item.kind.toLowerCase()}`
                  }
                  key={
                    item.id
                  }
                  onClick={() =>
                    router.push(
                      `/dashboard/conversations?ticket=${item.ticketId}`
                    )
                  }
                  type="button"
                >
                  <span className="contact-timeline-item__dot" />

                  <div>
                    <div className="contact-timeline-item__heading">
                      <strong>
                        {timelineTitle(
                          item
                        )}
                      </strong>

                      <time>
                        {dateTimeLabel(
                          item.occurredAt
                        )}
                      </time>
                    </div>

                    <p>
                      {item.body}
                    </p>

                    <small>
                      {item.actorName}
                    </small>
                  </div>
                </button>
              )
            )}

            {!loading &&
              timeline.length ===
                0 && (
                <div className="contact-crm__empty">
                  Nenhuma atividade registrada.
                </div>
              )}
          </div>
        </section>
      </div>
    </section>
  );
}
EOF

# ---------------------------------------------------------------------------
# Mount Contact CRM in current Contacts page
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/contacts/page.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const importLine =
  'import { ContactCrmPanel } from "@/components/contacts/contact-crm-panel";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { useAuth } from "@/components/auth-provider";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Contacts AuthProvider import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    "<ContactCrmPanel"
  )
) {
  const anchor =
    `              <section className="contact-history">`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Contacts history section anchor not found."
    );
  }

  const block =
    `              <ContactCrmPanel
                contactId={
                  detail.id
                }
                contactName={
                  detail.name
                }
              />

`;

  content =
    content.replace(
      anchor,
      `${block}${anchor}`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.1] Contact 360 panel mounted."
);
NODE

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

if ! grep -Fq -- "WAPP P3.1 / CONTACT 360 CRM" "$CSS"; then
cat >> "$CSS" <<'EOF'

/* --- WAPP P3.1 / CONTACT 360 CRM ------------------------------------- */

.contact-crm {
  margin-top: 12px;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: white;
}

.contact-crm__header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  border-bottom: 1px solid var(--line);
  padding: 14px 16px;
}

.contact-crm__header h3 {
  margin: 3px 0 2px;
  font-size: 15px;
  letter-spacing: -0.025em;
}

.contact-crm__header p {
  margin: 0;
  color: var(--muted);
  font-size: 8px;
}

.contact-crm__feedback {
  margin: 10px 14px 0;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 8px 9px;
  font-size: 8px;
}

.contact-crm__feedback--error {
  background: rgba(163, 59, 50, 0.07);
  color: #973a32;
}

.contact-field-manager {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(220px, 0.8fr);
  gap: 12px;
  border-bottom: 1px solid var(--line);
  background: #fafbfa;
  padding: 13px 14px;
}

.contact-field-form {
  display: grid;
  grid-template-columns: minmax(0, 1.5fr) minmax(130px, 0.7fr);
  gap: 9px;
}

.contact-field-form label {
  display: grid;
  gap: 4px;
}

.contact-field-form label > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 740;
}

.contact-field-form input,
.contact-field-form select,
.contact-custom-fields input,
.contact-custom-fields select {
  width: 100%;
  min-height: 36px;
  border: 1px solid var(--line);
  border-radius: 8px;
  outline: 0;
  background: white;
  padding: 7px 8px;
  color: var(--ink);
  font: inherit;
  font-size: 9px;
}

.contact-field-form__options {
  grid-column: 1 / -1;
}

.contact-field-form__check {
  display: flex !important;
  align-items: center;
  gap: 6px;
}

.contact-field-form__check input {
  width: 15px;
  min-height: 15px;
}

.contact-field-form .primary-button {
  width: fit-content;
}

.contact-field-admin-list {
  display: grid;
  align-content: start;
  gap: 5px;
}

.contact-field-admin-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  border: 1px solid var(--line);
  border-radius: 9px;
  background: white;
  padding: 8px 9px;
}

.contact-field-admin-item--inactive {
  opacity: 0.55;
}

.contact-field-admin-item > div {
  display: grid;
  gap: 2px;
}

.contact-field-admin-item strong {
  font-size: 9px;
}

.contact-field-admin-item span {
  color: var(--muted);
  font-size: 7px;
}

.contact-field-admin-item button {
  border: 0;
  background: transparent;
  color: var(--accent-dark);
  font-size: 7px;
  font-weight: 760;
  cursor: pointer;
}

.contact-crm__grid {
  display: grid;
  grid-template-columns: minmax(260px, 0.85fr) minmax(0, 1.15fr);
  min-height: 340px;
}

.contact-custom-fields {
  display: grid;
  align-content: start;
  gap: 11px;
  border-right: 1px solid var(--line);
  padding: 14px;
}

.contact-custom-fields > header,
.contact-timeline > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.contact-custom-fields > header strong,
.contact-timeline > header strong {
  font-size: 10px;
}

.contact-custom-fields > header span,
.contact-timeline > header span {
  color: var(--muted);
  font-size: 7px;
}

.contact-custom-fields__list {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 9px;
}

.contact-custom-fields .field {
  display: grid;
  gap: 4px;
}

.contact-custom-fields .field > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 720;
}

.contact-custom-fields .primary-button {
  width: fit-content;
}

.contact-timeline {
  display: flex;
  min-width: 0;
  flex-direction: column;
  padding: 14px 0 0;
}

.contact-timeline > header {
  flex: 0 0 auto;
  padding: 0 14px 10px;
}

.contact-timeline__list {
  max-height: 420px;
  overflow-y: auto;
  border-top: 1px solid var(--line);
  scrollbar-width: thin;
}

.contact-timeline-item {
  display: grid;
  width: 100%;
  grid-template-columns: 8px minmax(0, 1fr);
  gap: 8px;
  border: 0;
  border-bottom: 1px solid #edf0ed;
  background: white;
  padding: 10px 14px;
  text-align: left;
  cursor: pointer;
}

.contact-timeline-item:hover {
  background: #fafbfa;
}

.contact-timeline-item__dot {
  width: 7px;
  height: 7px;
  margin-top: 4px;
  border-radius: 999px;
  background: #b8c0bb;
}

.contact-timeline-item--message
  .contact-timeline-item__dot {
  background: var(--accent-dark);
}

.contact-timeline-item--note
  .contact-timeline-item__dot {
  background: #b78a3d;
}

.contact-timeline-item > div {
  display: grid;
  min-width: 0;
  gap: 4px;
}

.contact-timeline-item__heading {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 10px;
}

.contact-timeline-item__heading strong {
  overflow: hidden;
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.contact-timeline-item__heading time,
.contact-timeline-item small {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 7px;
}

.contact-timeline-item p {
  display: -webkit-box;
  overflow: hidden;
  margin: 0;
  color: #59635d;
  font-size: 8px;
  line-height: 1.45;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.contact-crm__empty {
  padding: 16px 4px;
  color: var(--muted);
  font-size: 8px;
}

@media (max-width: 900px) {
  .contact-field-manager,
  .contact-crm__grid {
    grid-template-columns: 1fr;
  }

  .contact-custom-fields {
    border-right: 0;
    border-bottom: 1px solid var(--line);
  }
}

@media (max-width: 760px) {
  .contact-crm__header {
    align-items: flex-start;
    flex-direction: column;
  }

  .contact-field-form,
  .contact-custom-fields__list {
    grid-template-columns: 1fr;
  }

  .contact-field-form__options {
    grid-column: auto;
  }

  .contact-field-form input,
  .contact-field-form select,
  .contact-custom-fields input,
  .contact-custom-fields select {
    min-height: 42px;
    font-size: 16px;
  }

  .contact-timeline__list {
    max-height: 52dvh;
  }

  .contact-timeline-item {
    min-height: 62px;
  }
}

/* --- /WAPP P3.1 ------------------------------------------------------ */
EOF
fi

# ---------------------------------------------------------------------------
# Test registration + documentation
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

const current =
  pkg.scripts?.test;

if (
  typeof current !==
    "string"
) {
  throw new Error(
    "API test script missing."
  );
}

const file =
  "src/modules/contact-crm/contact-crm.policy.test.ts";

if (
  !current.includes(
    file
  )
) {
  pkg.scripts.test =
    `${current} ${file}`;
}

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);
NODE

cat > docs/P3_ROADMAP.md <<'EOF'
# Wapp P3 — CRM and customer workflow

P3 moves Wapp from a complete conversation operation into a customer-workflow
platform.

Planned sequence:

- P3.1 Contact 360 CRM: custom fields + consolidated customer timeline.
- P3.2 Pipeline / stages: company-defined stages for commercial or service
  journeys without replacing ticket status.
- P3.3 Follow-ups and tasks: assigned tasks, due dates, reminders and
  completion history.
- P3.4 Segments: saved contact filters built from standard and custom fields.
- P3.5 Controlled outbound campaigns: explicit segmentation, rate controls,
  opt-out / suppression and auditable execution. This must not be implemented
  as an unrestricted bulk-send loop.
- P3.6 Import/export and data quality: safe CSV workflows, duplicate review and
  field mapping.

Production deployment remains a separate decision and is not part of this P3
roadmap automatically.
EOF

cat > docs/P3_01_CONTACT_360_CRM.md <<'EOF'
# P3.1 Contact 360 CRM

P3.1 extends the existing Contacts module instead of replacing it.

Existing Wapp identity rules remain unchanged:

- `Contact.name` is the manual Wapp display name;
- `Contact.whatsappName` remains provider identity;
- incoming provider names must not overwrite a deliberate manual Wapp name.

## Custom fields

Company-level definitions support:

- TEXT
- NUMBER
- DATE
- BOOLEAN
- SELECT

Definitions have:

- generated stable key;
- label;
- type;
- SELECT options;
- required flag;
- position;
- active/inactive state.

Only OWNER / ADMIN / SUPERVISOR have `contactFields.manage`.

Existing `contacts.manage` continues to control editing values on a contact.

Field type is immutable after creation. This avoids silently invalidating
existing stored values.

## Values

Values are stored per contact + field with one unique row.

Blank optional values remove the row.

Required fields are validated against the final contact state, not only the
fields submitted in the current request.

## Contact timeline

The CRM profile consolidates recent:

- messages;
- immutable ticket operational events;
- internal notes.

The API does not expose raw WhatsApp payloads.

Timeline items deep-link back to the corresponding Wapp ticket.

## API

- GET `/api/v1/contact-crm/fields`
- GET `/api/v1/contact-crm/fields/manage`
- POST `/api/v1/contact-crm/fields`
- PATCH `/api/v1/contact-crm/fields/:id`
- GET `/api/v1/contacts/:id/crm`
- PUT `/api/v1/contacts/:id/crm-fields`

## Migration

P3.1 introduces:

- `ContactFieldDefinition`
- `ContactFieldValue`
- `ContactFieldType`
EOF

echo "[P3.1] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P3.1] Unit tests..."
pnpm test

echo "[P3.1] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.1] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.1] CODE VALIDATION PASS."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
