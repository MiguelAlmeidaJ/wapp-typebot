#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEMA="apps/api/prisma/schema.prisma"
APP="apps/api/src/app.ts"
PERMISSIONS="apps/api/src/security/permissions.ts"
PERMISSIONS_TEST="apps/api/src/security/permissions.test.ts"
REALTIME_API="apps/api/src/modules/realtime/realtime.bus.ts"
REALTIME_WEB="apps/web/lib/realtime-types.ts"
UI_PERMISSIONS="apps/web/lib/permissions.ts"
DASHBOARD="apps/web/app/dashboard/page.tsx"
CONTACTS_PAGE="apps/web/app/dashboard/contacts/page.tsx"
CSS="apps/web/app/globals.css"

echo "[P3.2] Installing CRM pipelines..."

# P3.2 intentionally depends on the P3.1 local state. Fail before any write if
# the previous milestone is not present.
for check in \
  "$SCHEMA|model ContactFieldDefinition {" \
  "apps/api/src/modules/contact-crm/contact-crm.service.ts|getContactCrmProfile" \
  "apps/web/components/contacts/contact-crm-panel.tsx|export function ContactCrmPanel" \
  "$PERMISSIONS|contactFields.manage"
do
  file="${check%%|*}"
  marker="${check#*|}"

  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: P3.1 prerequisite missing:"
    echo "  $file -> $marker"
    echo "P3.2 was not applied."
    exit 1
  fi
done

for required in \
  "$APP" \
  "$PERMISSIONS_TEST" \
  "$REALTIME_API" \
  "$REALTIME_WEB" \
  "$UI_PERMISSIONS" \
  "$DASHBOARD" \
  "$CONTACTS_PAGE" \
  "$CSS"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/pipelines \
  apps/api/prisma/migrations/20260828235500_crm_pipelines \
  apps/web/app/dashboard/pipeline \
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
    "enum CrmStageOutcome {"
  )
) {
  const anchor =
    "enum MembershipRole {";

  const index =
    content.indexOf(
      anchor
    );

  if (
    index < 0
  ) {
    throw new Error(
      "MembershipRole enum anchor not found."
    );
  }

  const addition = `enum CrmStageOutcome {
  OPEN
  WON
  LOST
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
    start < 0
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
    end < 0
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
  "crmPipelines",
  "  crmPipelines             CrmPipeline[]"
);

addRelation(
  "Company",
  "contactStageTransitions",
  "  contactStageTransitions  ContactStageTransition[]"
);

addRelation(
  "Contact",
  "pipelineStates",
  "  pipelineStates           ContactPipelineState[]"
);

addRelation(
  "Contact",
  "stageTransitions",
  "  stageTransitions         ContactStageTransition[]"
);

addRelation(
  "CompanyMembership",
  "pipelineStateUpdates",
  '  pipelineStateUpdates     ContactPipelineState[] @relation("ContactPipelineStateUpdatedBy")'
);

addRelation(
  "CompanyMembership",
  "contactStageTransitions",
  '  contactStageTransitions  ContactStageTransition[] @relation("ContactStageTransitionActor")'
);

if (
  !content.includes(
    "model CrmPipeline {"
  )
) {
  content += `

model CrmPipeline {
  id          String                   @id @default(uuid()) @db.Char(36)
  companyId   String                   @db.Char(36)
  name        String                   @db.VarChar(120)
  description String?                  @db.VarChar(500)
  position    Int                      @default(0)
  isActive    Boolean                  @default(true)
  company     Company                  @relation(fields: [companyId], references: [id], onDelete: Cascade)
  stages      CrmStage[]
  states      ContactPipelineState[]
  transitions ContactStageTransition[]
  createdAt   DateTime                 @default(now())
  updatedAt   DateTime                 @updatedAt

  @@unique([companyId, name])
  @@index([companyId, isActive, position])
}

model CrmStage {
  id              String                   @id @default(uuid()) @db.Char(36)
  pipelineId      String                   @db.Char(36)
  name            String                   @db.VarChar(120)
  colorKey        String                   @default("GRAY") @db.VarChar(20)
  outcome         CrmStageOutcome          @default(OPEN)
  position        Int                      @default(0)
  isActive        Boolean                  @default(true)
  pipeline        CrmPipeline              @relation(fields: [pipelineId], references: [id], onDelete: Cascade)
  states          ContactPipelineState[]
  transitionsFrom ContactStageTransition[] @relation("ContactStageTransitionFrom")
  transitionsTo   ContactStageTransition[] @relation("ContactStageTransitionTo")
  createdAt       DateTime                 @default(now())
  updatedAt       DateTime                 @updatedAt

  @@unique([pipelineId, name])
  @@index([pipelineId, isActive, position])
}

model ContactPipelineState {
  id                    String             @id @default(uuid()) @db.Char(36)
  contactId             String             @db.Char(36)
  pipelineId            String             @db.Char(36)
  stageId               String             @db.Char(36)
  updatedByMembershipId String?            @db.Char(36)
  enteredAt             DateTime           @default(now())
  contact               Contact            @relation(fields: [contactId], references: [id], onDelete: Cascade)
  pipeline              CrmPipeline        @relation(fields: [pipelineId], references: [id], onDelete: Cascade)
  stage                 CrmStage           @relation(fields: [stageId], references: [id], onDelete: Restrict)
  updatedByMembership   CompanyMembership? @relation("ContactPipelineStateUpdatedBy", fields: [updatedByMembershipId], references: [id], onDelete: SetNull)
  createdAt             DateTime           @default(now())
  updatedAt             DateTime           @updatedAt

  @@unique([contactId, pipelineId])
  @@index([pipelineId, stageId, updatedAt])
  @@index([contactId, updatedAt])
}

model ContactStageTransition {
  id                String             @id @default(uuid()) @db.Char(36)
  companyId         String             @db.Char(36)
  contactId         String             @db.Char(36)
  pipelineId        String             @db.Char(36)
  fromStageId       String?            @db.Char(36)
  toStageId         String?            @db.Char(36)
  actorMembershipId String?            @db.Char(36)
  company           Company            @relation(fields: [companyId], references: [id], onDelete: Cascade)
  contact           Contact            @relation(fields: [contactId], references: [id], onDelete: Cascade)
  pipeline          CrmPipeline        @relation(fields: [pipelineId], references: [id], onDelete: Cascade)
  fromStage         CrmStage?          @relation("ContactStageTransitionFrom", fields: [fromStageId], references: [id], onDelete: Restrict)
  toStage           CrmStage?          @relation("ContactStageTransitionTo", fields: [toStageId], references: [id], onDelete: Restrict)
  actorMembership   CompanyMembership? @relation("ContactStageTransitionActor", fields: [actorMembershipId], references: [id], onDelete: SetNull)
  createdAt         DateTime           @default(now())

  @@index([companyId, createdAt])
  @@index([contactId, createdAt])
  @@index([pipelineId, createdAt])
}
`;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.2] Prisma pipeline models prepared."
);
NODE

cat > apps/api/prisma/migrations/20260828235500_crm_pipelines/migration.sql <<'EOF'
CREATE TABLE `CrmPipeline` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `name` VARCHAR(120) NOT NULL,
  `description` VARCHAR(500) NULL,
  `position` INTEGER NOT NULL DEFAULT 0,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `CrmPipeline_companyId_name_key`
    (`companyId`, `name`),
  INDEX `CrmPipeline_companyId_isActive_position_idx`
    (`companyId`, `isActive`, `position`),

  CONSTRAINT `CrmPipeline_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `CrmStage` (
  `id` CHAR(36) NOT NULL,
  `pipelineId` CHAR(36) NOT NULL,
  `name` VARCHAR(120) NOT NULL,
  `colorKey` VARCHAR(20) NOT NULL DEFAULT 'GRAY',
  `outcome` ENUM('OPEN', 'WON', 'LOST') NOT NULL DEFAULT 'OPEN',
  `position` INTEGER NOT NULL DEFAULT 0,
  `isActive` BOOLEAN NOT NULL DEFAULT true,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `CrmStage_pipelineId_name_key`
    (`pipelineId`, `name`),
  INDEX `CrmStage_pipelineId_isActive_position_idx`
    (`pipelineId`, `isActive`, `position`),

  CONSTRAINT `CrmStage_pipelineId_fkey`
    FOREIGN KEY (`pipelineId`)
    REFERENCES `CrmPipeline`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `ContactPipelineState` (
  `id` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `pipelineId` CHAR(36) NOT NULL,
  `stageId` CHAR(36) NOT NULL,
  `updatedByMembershipId` CHAR(36) NULL,
  `enteredAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `ContactPipelineState_contactId_pipelineId_key`
    (`contactId`, `pipelineId`),
  INDEX `ContactPipelineState_pipelineId_stageId_updatedAt_idx`
    (`pipelineId`, `stageId`, `updatedAt`),
  INDEX `ContactPipelineState_contactId_updatedAt_idx`
    (`contactId`, `updatedAt`),

  CONSTRAINT `ContactPipelineState_contactId_fkey`
    FOREIGN KEY (`contactId`)
    REFERENCES `Contact`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactPipelineState_pipelineId_fkey`
    FOREIGN KEY (`pipelineId`)
    REFERENCES `CrmPipeline`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactPipelineState_stageId_fkey`
    FOREIGN KEY (`stageId`)
    REFERENCES `CrmStage`(`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT `ContactPipelineState_updatedByMembershipId_fkey`
    FOREIGN KEY (`updatedByMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `ContactStageTransition` (
  `id` CHAR(36) NOT NULL,
  `companyId` CHAR(36) NOT NULL,
  `contactId` CHAR(36) NOT NULL,
  `pipelineId` CHAR(36) NOT NULL,
  `fromStageId` CHAR(36) NULL,
  `toStageId` CHAR(36) NULL,
  `actorMembershipId` CHAR(36) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`),
  INDEX `ContactStageTransition_companyId_createdAt_idx`
    (`companyId`, `createdAt`),
  INDEX `ContactStageTransition_contactId_createdAt_idx`
    (`contactId`, `createdAt`),
  INDEX `ContactStageTransition_pipelineId_createdAt_idx`
    (`pipelineId`, `createdAt`),

  CONSTRAINT `ContactStageTransition_companyId_fkey`
    FOREIGN KEY (`companyId`)
    REFERENCES `Company`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_contactId_fkey`
    FOREIGN KEY (`contactId`)
    REFERENCES `Contact`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_pipelineId_fkey`
    FOREIGN KEY (`pipelineId`)
    REFERENCES `CrmPipeline`(`id`)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_fromStageId_fkey`
    FOREIGN KEY (`fromStageId`)
    REFERENCES `CrmStage`(`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_toStageId_fkey`
    FOREIGN KEY (`toStageId`)
    REFERENCES `CrmStage`(`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT `ContactStageTransition_actorMembershipId_fkey`
    FOREIGN KEY (`actorMembershipId`)
    REFERENCES `CompanyMembership`(`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

# ---------------------------------------------------------------------------
# Pure policy + tests
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/pipelines/pipeline.policy.ts <<'EOF'
export const PIPELINE_COLOR_KEYS = [
  "GRAY",
  "BLUE",
  "GREEN",
  "ORANGE",
  "PURPLE",
  "RED"
] as const;

export type PipelineColorKey =
  typeof PIPELINE_COLOR_KEYS[number];

export type PipelineStageOutcome =
  | "OPEN"
  | "WON"
  | "LOST";

export function normalizeStageNames(
  names: string[]
) {
  const seen =
    new Set<string>();

  const result:
    string[] =
    [];

  for (
    const raw
    of names
  ) {
    const name =
      raw
        .replace(
          /\s+/g,
          " "
        )
        .trim()
        .slice(
          0,
          120
        );

    if (
      !name
    ) {
      continue;
    }

    const key =
      name.toLocaleLowerCase(
        "pt-BR"
      );

    if (
      seen.has(
        key
      )
    ) {
      continue;
    }

    seen.add(
      key
    );

    result.push(
      name
    );
  }

  return result.slice(
    0,
    20
  );
}

export function stageMoveChanged(
  currentStageId:
    string
    | null
    | undefined,
  nextStageId:
    string
    | null
    | undefined
) {
  return (
    currentStageId ??
    null
  ) !==
    (
      nextStageId ??
      null
    );
}
EOF

cat > apps/api/src/modules/pipelines/pipeline.policy.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  normalizeStageNames,
  stageMoveChanged
} from "./pipeline.policy.js";

test(
  "pipeline stage names are normalized and unique",
  () => {
    assert.deepEqual(
      normalizeStageNames([
        " Novo ",
        "Em   contato",
        "novo",
        "",
        "Cliente"
      ]),
      [
        "Novo",
        "Em contato",
        "Cliente"
      ]
    );
  }
);

test(
  "pipeline movement does not create duplicate history for a no-op",
  () => {
    assert.equal(
      stageMoveChanged(
        "stage-a",
        "stage-a"
      ),
      false
    );

    assert.equal(
      stageMoveChanged(
        null,
        "stage-a"
      ),
      true
    );

    assert.equal(
      stageMoveChanged(
        "stage-a",
        null
      ),
      true
    );
  }
);
EOF

# ---------------------------------------------------------------------------
# Pipeline service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/pipelines/pipeline.service.ts <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/pipelines/pipeline.routes.ts <<'EOF'
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
  createPipeline,
  createPipelineStage,
  getContactPipelineStates,
  getPipelineBoard,
  listPipelines,
  moveContactStage,
  updatePipeline,
  updatePipelineStage
} from "./pipeline.service.js";
import {
  PIPELINE_COLOR_KEYS
} from "./pipeline.policy.js";

const idSchema =
  z.object({
    id:
      z.string()
        .uuid()
  });

const pipelineIdSchema =
  z.object({
    pipelineId:
      z.string()
        .uuid()
  });

const createPipelineSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(2)
        .max(120),
    description:
      z.string()
        .trim()
        .max(500)
        .nullable()
        .optional(),
    stages:
      z.array(
        z.string()
          .trim()
          .min(1)
          .max(120)
      )
        .min(2)
        .max(20)
  });

const updatePipelineSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(2)
        .max(120)
        .optional(),
    description:
      z.string()
        .trim()
        .max(500)
        .nullable()
        .optional(),
    isActive:
      z.boolean()
        .optional(),
    position:
      z.number()
        .int()
        .min(0)
        .max(10_000)
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

const stageSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(1)
        .max(120),
    colorKey:
      z.enum(
        PIPELINE_COLOR_KEYS
      )
        .default(
          "GRAY"
        ),
    outcome:
      z.enum([
        "OPEN",
        "WON",
        "LOST"
      ])
        .default(
          "OPEN"
        )
  });

const updateStageSchema =
  z.object({
    name:
      z.string()
        .trim()
        .min(1)
        .max(120)
        .optional(),
    colorKey:
      z.enum(
        PIPELINE_COLOR_KEYS
      )
        .optional(),
    outcome:
      z.enum([
        "OPEN",
        "WON",
        "LOST"
      ])
        .optional(),
    position:
      z.number()
        .int()
        .min(0)
        .max(10_000)
        .optional(),
    isActive:
      z.boolean()
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

const boardQuerySchema =
  z.object({
    search:
      z.string()
        .trim()
        .max(100)
        .optional()
  });

const moveSchema =
  z.object({
    pipelineId:
      z.string()
        .uuid(),
    stageId:
      z.string()
        .uuid()
        .nullable()
  });

export async function pipelineRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/pipelines",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.read"
        );

      return {
        pipelines:
          await listPipelines(
            auth.companyId
          )
      };
    }
  );

  app.get(
    "/api/v1/pipelines/manage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      return {
        pipelines:
          await listPipelines(
            auth.companyId,
            true
          )
      };
    }
  );

  app.post(
    "/api/v1/pipelines",
    async (
      request,
      reply
    ) => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      const input =
        createPipelineSchema.parse(
          request.body
        );

      return reply
        .status(
          201
        )
        .send({
          pipeline:
            await createPipeline({
              companyId:
                auth.companyId,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/pipelines/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        updatePipelineSchema.parse(
          request.body
        );

      return {
        pipeline:
          await updatePipeline({
            companyId:
              auth.companyId,
            pipelineId:
              params.id,
            ...input
          })
      };
    }
  );

  app.post(
    "/api/v1/pipelines/:id/stages",
    async (
      request,
      reply
    ) => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        stageSchema.parse(
          request.body
        );

      return reply
        .status(
          201
        )
        .send({
          stage:
            await createPipelineStage({
              companyId:
                auth.companyId,
              pipelineId:
                params.id,
              ...input
            })
        });
    }
  );

  app.patch(
    "/api/v1/pipeline-stages/:id",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.manage"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        updateStageSchema.parse(
          request.body
        );

      return {
        stage:
          await updatePipelineStage({
            companyId:
              auth.companyId,
            stageId:
              params.id,
            ...input
          })
      };
    }
  );

  app.get(
    "/api/v1/pipelines/:pipelineId/board",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.read"
        );

      const params =
        pipelineIdSchema.parse(
          request.params
        );

      const query =
        boardQuerySchema.parse(
          request.query
        );

      return getPipelineBoard({
        companyId:
          auth.companyId,
        pipelineId:
          params.pipelineId,
        search:
          query.search
      });
    }
  );

  app.post(
    "/api/v1/contacts/:id/pipeline-stage",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.move"
        );

      const params =
        idSchema.parse(
          request.params
        );

      const input =
        moveSchema.parse(
          request.body
        );

      return moveContactStage({
        companyId:
          auth.companyId,
        contactId:
          params.id,
        pipelineId:
          input.pipelineId,
        stageId:
          input.stageId,
        actorMembershipId:
          auth.membershipId
      });
    }
  );

  app.get(
    "/api/v1/contacts/:id/pipeline-states",
    async request => {
      const auth =
        await requirePermission(
          request,
          "pipelines.read"
        );

      const params =
        idSchema.parse(
          request.params
        );

      return getContactPipelineStates({
        companyId:
          auth.companyId,
        contactId:
          params.id
      });
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Backend permissions, rebuilt safely against the current local matrix.
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

const typeStart =
  content.indexOf(
    "export type WappPermission ="
  );

const typeEnd =
  content.indexOf(
    ";",
    typeStart
  );

if (
  typeStart < 0 ||
  typeEnd < 0
) {
  throw new Error(
    "WappPermission union not found."
  );
}

let union =
  content.slice(
    typeStart,
    typeEnd
  );

for (
  const permission
  of [
    "pipelines.read",
    "pipelines.move",
    "pipelines.manage"
  ]
) {
  if (
    !union.includes(
      `"${permission}"`
    )
  ) {
    union +=
      `\n  | "${permission}"`;
  }
}

content =
  content.slice(
    0,
    typeStart
  ) +
  union +
  content.slice(
    typeEnd
  );

function arrayBounds(
  source,
  role
) {
  const anchor =
    `  ${role}: [`;

  const start =
    source.indexOf(
      anchor
    );

  if (
    start < 0
  ) {
    throw new Error(
      `${role} role block not found.`
    );
  }

  const bracketStart =
    source.indexOf(
      "[",
      start
    );

  let depth =
    0;

  let inString =
    false;

  let quote =
    "";

  let escape =
    false;

  for (
    let index =
      bracketStart;
    index <
      source.length;
    index +=
      1
  ) {
    const char =
      source[index];

    if (
      inString
    ) {
      if (
        escape
      ) {
        escape =
          false;
      } else if (
        char ===
        "\\"
      ) {
        escape =
          true;
      } else if (
        char ===
        quote
      ) {
        inString =
          false;
      }

      continue;
    }

    if (
      char ===
        '"' ||
      char ===
        "'"
    ) {
      inString =
        true;
      quote =
        char;
      continue;
    }

    if (
      char ===
      "["
    ) {
      depth +=
        1;
    } else if (
      char ===
      "]"
    ) {
      depth -=
        1;

      if (
        depth ===
        0
      ) {
        return {
          start:
            bracketStart,
          end:
            index
        };
      }
    }
  }

  throw new Error(
    `${role} array end not found.`
  );
}

const rolePermissions = {
  OWNER: [
    "pipelines.read",
    "pipelines.move",
    "pipelines.manage"
  ],
  ADMIN: [
    "pipelines.read",
    "pipelines.move",
    "pipelines.manage"
  ],
  SUPERVISOR: [
    "pipelines.read",
    "pipelines.move",
    "pipelines.manage"
  ],
  AGENT: [
    "pipelines.read",
    "pipelines.move"
  ]
};

for (
  const role
  of [
    "AGENT",
    "SUPERVISOR",
    "ADMIN",
    "OWNER"
  ]
) {
  const bounds =
    arrayBounds(
      content,
      role
    );

  const block =
    content.slice(
      bounds.start,
      bounds.end +
        1
    );

  const missing =
    rolePermissions[
      role
    ].filter(
      permission =>
        !block.includes(
          `"${permission}"`
        )
    );

  if (
    missing.length ===
    0
  ) {
    continue;
  }

  const beforeClose =
    content.slice(
      0,
      bounds.end
    );

  const afterClose =
    content.slice(
      bounds.end
    );

  const trimmed =
    beforeClose
      .replace(
        /\s+$/,
        ""
      );

  const separator =
    trimmed.endsWith(
      "["
    )
      ? "\n"
      : trimmed.endsWith(
          ","
        )
        ? "\n"
        : ",\n";

  const insertion =
    missing
      .map(
        permission =>
          `    "${permission}"`
      )
      .join(",\n");

  content =
    trimmed +
    separator +
    insertion +
    "\n  " +
    afterClose;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.2] Backend pipeline permissions installed."
);
NODE

# Rebuild permission test inventory from the real local union and add a focused
# managerial/agent test.
node <<'NODE'
const fs = require("node:fs");

const permissionPath =
  "apps/api/src/security/permissions.ts";

const testPath =
  "apps/api/src/security/permissions.test.ts";

const source =
  fs.readFileSync(
    permissionPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

let test =
  fs.readFileSync(
    testPath,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const typeStart =
  source.indexOf(
    "export type WappPermission ="
  );

const typeEnd =
  source.indexOf(
    ";",
    typeStart
  );

const permissions =
  Array.from(
    source
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
  test.indexOf(
    "const allPermissions:"
  );

const firstDescribe =
  test.indexOf(
    "describe(",
    declarationStart
  );

if (
  declarationStart < 0 ||
  firstDescribe < 0
) {
  throw new Error(
    "permissions.test allPermissions boundary not found."
  );
}

const declaration = `const allPermissions:
  WappPermission[] = [
${permissions
  .map(
    permission =>
      `    "${permission}"`
  )
  .join(",\n")}
  ];

`;

test =
  test.slice(
    0,
    declarationStart
  ) +
  declaration +
  test.slice(
    firstDescribe
  );

if (
  !test.includes(
    '"pipeline schema is managerial while movement stays operational"'
  )
) {
  test += `

describe(
  "CRM pipeline permissions",
  () => {
    it(
      "pipeline schema is managerial while movement stays operational",
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
              "pipelines.manage"
            ),
            true
          );

          assert.equal(
            roleHasPermission(
              role,
              "pipelines.move"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "pipelines.read"
          ),
          true
        );

        assert.equal(
          roleHasPermission(
            "AGENT",
            "pipelines.move"
          ),
          true
        );

        assert.equal(
          roleHasPermission(
            "AGENT",
            "pipelines.manage"
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
  test
);

console.log(
  `[P3.2] permissions.test rebuilt with ${permissions.length} permissions.`
);
NODE

# ---------------------------------------------------------------------------
# App route registration
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
  'import { pipelineRoutes } from "./modules/pipelines/pipeline.routes.js";';

if (
  !content.includes(
    importLine
  )
) {
  const preferred =
    'import { contactCrmRoutes } from "./modules/contact-crm/contact-crm.routes.js";';

  const fallback =
    'import { contactRoutes } from "./modules/contacts/contact.routes.js";';

  const anchor =
    content.includes(
      preferred
    )
      ? preferred
      : fallback;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Contact route import anchor not found."
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
    "await app.register(pipelineRoutes);"
  )
) {
  const preferred =
    `  await app.register(contactCrmRoutes);`;

  const fallback =
    `  await app.register(contactRoutes);`;

  const anchor =
    content.includes(
      preferred
    )
      ? preferred
      : fallback;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Contact route registration anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  await app.register(pipelineRoutes);`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Realtime contract
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

function patchRealtime(
  path
) {
  let content =
    fs.readFileSync(
      path,
      "utf8"
    ).replace(
      /\r\n/g,
      "\n"
    );

  const typeStart =
    content.indexOf(
      "export type RealtimeEventType ="
    );

  const typeEnd =
    content.indexOf(
      ";",
      typeStart
    );

  if (
    typeStart < 0 ||
    typeEnd < 0
  ) {
    throw new Error(
      `RealtimeEventType not found in ${path}`
    );
  }

  let union =
    content.slice(
      typeStart,
      typeEnd
    );

  if (
    !union.includes(
      '"contact.pipeline.updated"'
    )
  ) {
    union +=
      '\n  | "contact.pipeline.updated"';
  }

  content =
    content.slice(
      0,
      typeStart
    ) +
    union +
    content.slice(
      typeEnd
    );

  const interfaceStart =
    content.indexOf(
      "export interface RealtimeEvent {"
    );

  const interfaceEnd =
    content.indexOf(
      "\n}",
      interfaceStart
    );

  if (
    interfaceStart < 0 ||
    interfaceEnd < 0
  ) {
    throw new Error(
      `RealtimeEvent interface not found in ${path}`
    );
  }

  let block =
    content.slice(
      interfaceStart,
      interfaceEnd
    );

  if (
    !block.includes(
      "contactId?: string;"
    )
  ) {
    block +=
      "\n  contactId?: string;";
  }

  if (
    !block.includes(
      "pipelineId?: string;"
    )
  ) {
    block +=
      "\n  pipelineId?: string;";
  }

  content =
    content.slice(
      0,
      interfaceStart
    ) +
    block +
    content.slice(
      interfaceEnd
    );

  fs.writeFileSync(
    path,
    content
  );
}

patchRealtime(
  "apps/api/src/modules/realtime/realtime.bus.ts"
);

patchRealtime(
  "apps/web/lib/realtime-types.ts"
);

console.log(
  "[P3.2] Realtime pipeline event installed."
);
NODE

# ---------------------------------------------------------------------------
# Frontend RBAC + dashboard navigation.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/lib/permissions.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const typeStart =
  content.indexOf(
    "export type UiPermission ="
  );

const typeEnd =
  content.indexOf(
    ";",
    typeStart
  );

if (
  typeStart < 0 ||
  typeEnd < 0
) {
  throw new Error(
    "UiPermission union not found."
  );
}

let union =
  content.slice(
    typeStart,
    typeEnd
  );

for (
  const permission
  of [
    "pipeline.view",
    "pipeline.manage"
  ]
) {
  if (
    !union.includes(
      `"${permission}"`
    )
  ) {
    union +=
      `\n  | "${permission}"`;
  }
}

content =
  content.slice(
    0,
    typeStart
  ) +
  union +
  content.slice(
    typeEnd
  );

function arrayBounds(
  source,
  role
) {
  const anchor =
    `  ${role}: [`;

  const start =
    source.indexOf(
      anchor
    );

  if (
    start < 0
  ) {
    throw new Error(
      `${role} UI role block not found.`
    );
  }

  const bracketStart =
    source.indexOf(
      "[",
      start
    );

  let depth =
    0;

  let inString =
    false;

  let quote =
    "";

  let escape =
    false;

  for (
    let index =
      bracketStart;
    index <
      source.length;
    index +=
      1
  ) {
    const char =
      source[index];

    if (
      inString
    ) {
      if (
        escape
      ) {
        escape =
          false;
      } else if (
        char ===
        "\\"
      ) {
        escape =
          true;
      } else if (
        char ===
        quote
      ) {
        inString =
          false;
      }

      continue;
    }

    if (
      char ===
        '"' ||
      char ===
        "'"
    ) {
      inString =
        true;
      quote =
        char;
      continue;
    }

    if (
      char ===
      "["
    ) {
      depth +=
        1;
    } else if (
      char ===
      "]"
    ) {
      depth -=
        1;

      if (
        depth ===
        0
      ) {
        return {
          start:
            bracketStart,
          end:
            index
        };
      }
    }
  }

  throw new Error(
    `${role} UI array end not found.`
  );
}

const desired = {
  OWNER: [
    "pipeline.view",
    "pipeline.manage"
  ],
  ADMIN: [
    "pipeline.view",
    "pipeline.manage"
  ],
  SUPERVISOR: [
    "pipeline.view",
    "pipeline.manage"
  ],
  AGENT: [
    "pipeline.view"
  ]
};

for (
  const role
  of [
    "AGENT",
    "SUPERVISOR",
    "ADMIN",
    "OWNER"
  ]
) {
  const bounds =
    arrayBounds(
      content,
      role
    );

  const block =
    content.slice(
      bounds.start,
      bounds.end +
        1
    );

  const missing =
    desired[
      role
    ].filter(
      permission =>
        !block.includes(
          `"${permission}"`
        )
    );

  if (
    missing.length ===
    0
  ) {
    continue;
  }

  const beforeClose =
    content.slice(
      0,
      bounds.end
    );

  const afterClose =
    content.slice(
      bounds.end
    );

  const trimmed =
    beforeClose.replace(
      /\s+$/,
      ""
    );

  const separator =
    trimmed.endsWith(
      "["
    )
      ? "\n"
      : trimmed.endsWith(
          ","
        )
        ? "\n"
        : ",\n";

  content =
    trimmed +
    separator +
    missing
      .map(
        permission =>
          `    "${permission}"`
      )
      .join(",\n") +
    "\n  " +
    afterClose;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.2] UI pipeline permissions installed."
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/page.tsx";

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
    'href: "/dashboard/pipeline"'
  )
) {
  const anchor = `  {
    label: "Contatos",
    href: "/dashboard/contacts",
    permission: "contacts.view"
  },`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Dashboard Contacts navigation anchor not found."
    );
  }

  const item = `${anchor}
  {
    label: "Pipeline",
    href: "/dashboard/pipeline",
    permission: "pipeline.view"
  },`;

  content =
    content.replace(
      anchor,
      item
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

# ---------------------------------------------------------------------------
# Contact-level pipeline summary
# ---------------------------------------------------------------------------

cat > apps/web/components/contacts/contact-pipeline-summary.tsx <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
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

interface PipelineStage {
  id: string;
  name: string;
  colorKey: string;
  outcome:
    | "OPEN"
    | "WON"
    | "LOST";
  position: number;
}

interface PipelineStatePayload {
  pipelines:
    Array<{
      id: string;
      name: string;
      description:
        | string
        | null;
      stages:
        PipelineStage[];
      currentState: {
        stageId: string;
        enteredAt: string;
      } | null;
    }>;
  transitions:
    Array<{
      id: string;
      pipelineId: string;
      createdAt: string;
      pipeline: {
        name: string;
      };
      fromStage: {
        name: string;
      } | null;
      toStage: {
        name: string;
      } | null;
      actorMembership: {
        user: {
          name: string;
        };
      } | null;
    }>;
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

export function ContactPipelineSummary({
  contactId
}: {
  contactId: string;
}) {
  const router =
    useRouter();

  const {
    request,
    subscribe
  } =
    useAuth();

  const [
    payload,
    setPayload
  ] =
    useState<
      PipelineStatePayload
      | null
    >(
      null
    );

  const [
    moving,
    setMoving
  ] =
    useState<
      string
      | null
    >(
      null
    );

  const [
    error,
    setError
  ] =
    useState("");

  const load =
    useCallback(
      async () => {
        const next =
          await request<
            PipelineStatePayload
          >(
            `/api/v1/contacts/${contactId}/pipeline-states`
          );

        setPayload(
          next
        );
      },
      [
        contactId,
        request
      ]
    );

  useEffect(
    () => {
      void load()
        .catch(() => {
          setError(
            "Não foi possível carregar os pipelines deste contato."
          );
        });
    },
    [
      load
    ]
  );

  useEffect(
    () =>
      subscribe(
        "/api/v1/realtime/events",
        event => {
          if (
            event.type ===
              "contact.pipeline.updated" &&
            event.contactId ===
              contactId
          ) {
            void load()
              .catch(
                () => {}
              );
          }
        }
      ),
    [
      contactId,
      load,
      subscribe
    ]
  );

  async function move(
    pipelineId: string,
    stageId:
      string
      | null
  ) {
    setMoving(
      pipelineId
    );

    setError("");

    try {
      await request(
        `/api/v1/contacts/${contactId}/pipeline-stage`,
        {
          method:
            "POST",
          body:
            JSON.stringify({
              pipelineId,
              stageId
            })
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível mover o contato."
      );
    } finally {
      setMoving(
        null
      );
    }
  }

  return (
    <section className="contact-pipeline-summary">
      <header>
        <div>
          <span className="eyebrow">
            Jornada
          </span>

          <strong>
            Pipeline
          </strong>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              `/dashboard/pipeline?contact=${contactId}`
            )
          }
          type="button"
        >
          Abrir quadro
        </button>
      </header>

      {error && (
        <div className="contact-pipeline-summary__error">
          {error}
        </div>
      )}

      {!payload ? (
        <div className="contact-pipeline-summary__empty">
          Carregando…
        </div>
      ) : payload.pipelines.length ===
        0 ? (
        <div className="contact-pipeline-summary__empty">
          Nenhum pipeline ativo configurado.
        </div>
      ) : (
        <div className="contact-pipeline-summary__body">
          <div className="contact-pipeline-summary__states">
            {payload.pipelines.map(
              pipeline => (
                <label
                  key={
                    pipeline.id
                  }
                >
                  <span>
                    {pipeline.name}
                  </span>

                  <select
                    disabled={
                      moving ===
                      pipeline.id
                    }
                    onChange={
                      event =>
                        void move(
                          pipeline.id,
                          event
                            .target
                            .value ||
                            null
                        )
                    }
                    value={
                      pipeline
                        .currentState
                        ?.stageId ??
                      ""
                    }
                  >
                    <option value="">
                      Sem etapa
                    </option>

                    {pipeline.stages.map(
                      stage => (
                        <option
                          key={
                            stage.id
                          }
                          value={
                            stage.id
                          }
                        >
                          {stage.name}
                        </option>
                      )
                    )}
                  </select>
                </label>
              )
            )}
          </div>

          {payload.transitions.length >
            0 && (
            <div className="contact-stage-history">
              <strong>
                Movimentações recentes
              </strong>

              {payload.transitions
                .slice(
                  0,
                  4
                )
                .map(
                  transition => (
                    <div
                      key={
                        transition.id
                      }
                    >
                      <span>
                        {transition
                          .pipeline
                          .name}
                      </span>

                      <p>
                        {transition
                          .fromStage
                          ?.name ??
                          "Sem etapa"}{" "}
                        →{" "}
                        {transition
                          .toStage
                          ?.name ??
                          "Sem etapa"}
                      </p>

                      <small>
                        {transition
                          .actorMembership
                          ?.user.name ??
                          "Sistema"}{" "}
                        ·{" "}
                        {dateTimeLabel(
                          transition.createdAt
                        )}
                      </small>
                    </div>
                  )
                )}
            </div>
          )}
        </div>
      )}
    </section>
  );
}
EOF

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
  'import { ContactPipelineSummary } from "@/components/contacts/contact-pipeline-summary";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { ContactCrmPanel } from "@/components/contacts/contact-crm-panel";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "P3.1 ContactCrmPanel import not found."
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
    "<ContactPipelineSummary"
  )
) {
  const anchor =
    `              <ContactCrmPanel`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "P3.1 ContactCrmPanel mount not found."
    );
  }

  const block =
    `              <ContactPipelineSummary
                contactId={
                  detail.id
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
  "[P3.2] Contact pipeline summary mounted."
);
NODE

# ---------------------------------------------------------------------------
# Pipeline Kanban page
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/pipeline/page.tsx <<'EOF'
"use client";

import {
  type DragEvent,
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";
import {
  useRouter,
  useSearchParams
} from "next/navigation";

import {
  useAuth
} from "@/components/auth-provider";
import {
  ApiError
} from "@/lib/api";
import {
  roleCan
} from "@/lib/permissions";

interface Stage {
  id: string;
  name: string;
  colorKey: string;
  outcome:
    | "OPEN"
    | "WON"
    | "LOST";
  position: number;
  isActive: boolean;
  _count?: {
    states: number;
  };
}

interface Pipeline {
  id: string;
  name: string;
  description:
    | string
    | null;
  position: number;
  isActive: boolean;
  stages:
    Stage[];
  _count: {
    states: number;
  };
}

interface BoardContact {
  id: string;
  name: string;
  whatsappName:
    | string
    | null;
  phoneNumber:
    | string
    | null;
  email:
    | string
    | null;
  lastSeenAt:
    | string
    | null;
  enteredAt:
    | string
    | null;
  customFieldValues:
    Array<{
      value:
        string
        | null;
      field: {
        id: string;
        label: string;
        type: string;
      };
    }>;
  tickets:
    Array<{
      id: string;
      status:
        | "OPEN"
        | "PENDING"
        | "CLOSED";
      lastMessage:
        | string
        | null;
      lastMessageAt:
        string;
      queue: {
        id: string;
        name: string;
      } | null;
      assignedMembership: {
        id: string;
        user: {
          id: string;
          name: string;
        };
      } | null;
    }>;
}

interface BoardColumn {
  stage:
    | Stage
    | null;
  count: number;
  truncated: boolean;
  contacts:
    BoardContact[];
}

interface BoardPayload {
  pipeline: {
    id: string;
    name: string;
    description:
      | string
      | null;
    stages:
      Stage[];
  };
  columns:
    BoardColumn[];
}

const stageColors = {
  GRAY:
    "Cinza",
  BLUE:
    "Azul",
  GREEN:
    "Verde",
  ORANGE:
    "Laranja",
  PURPLE:
    "Roxo",
  RED:
    "Vermelho"
} as const;

function dateLabel(
  value:
    string
    | null
) {
  if (
    !value
  ) {
    return "—";
  }

  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      day:
        "2-digit",
      month:
        "2-digit"
    }
  ).format(
    new Date(
      value
    )
  );
}

export default function PipelinePage() {
  const router =
    useRouter();

  const searchParams =
    useSearchParams();

  const {
    session,
    loading,
    request,
    subscribe
  } =
    useAuth();

  const [
    pipelines,
    setPipelines
  ] =
    useState<
      Pipeline[]
    >([]);

  const [
    selectedPipelineId,
    setSelectedPipelineId
  ] =
    useState("");

  const [
    board,
    setBoard
  ] =
    useState<
      BoardPayload
      | null
    >(
      null
    );

  const [
    search,
    setSearch
  ] =
    useState(
      searchParams.get(
        "contact"
      )
        ? ""
        : ""
    );

  const [
    draggingContactId,
    setDraggingContactId
  ] =
    useState<
      string
      | null
    >(
      null
    );

  const [
    busy,
    setBusy
  ] =
    useState(
      true
    );

  const [
    movingContactId,
    setMovingContactId
  ] =
    useState<
      string
      | null
    >(
      null
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

  const [
    managerOpen,
    setManagerOpen
  ] =
    useState(
      false
    );

  const [
    pipelineName,
    setPipelineName
  ] =
    useState("");

  const [
    pipelineDescription,
    setPipelineDescription
  ] =
    useState("");

  const [
    initialStages,
    setInitialStages
  ] =
    useState(
      "Novo, Em contato, Qualificado, Cliente"
    );

  const [
    newStageName,
    setNewStageName
  ] =
    useState("");

  const [
    newStageColor,
    setNewStageColor
  ] =
    useState<
      keyof typeof stageColors
    >(
      "GRAY"
    );

  const [
    newStageOutcome,
    setNewStageOutcome
  ] =
    useState<
      "OPEN"
      | "WON"
      | "LOST"
    >(
      "OPEN"
    );

  const canManage =
    session
      ? roleCan(
          session.role,
          "pipeline.manage"
        )
      : false;

  const targetContactId =
    searchParams.get(
      "contact"
    );

  const loadPipelines =
    useCallback(
      async () => {
        const payload =
          await request<{
            pipelines:
              Pipeline[];
          }>(
            "/api/v1/pipelines"
          );

        setPipelines(
          payload.pipelines
        );

        setSelectedPipelineId(
          current =>
            current &&
            payload.pipelines.some(
              item =>
                item.id ===
                current
            )
              ? current
              : payload.pipelines[
                  0
                ]?.id ??
                ""
        );
      },
      [
        request
      ]
    );

  const loadBoard =
    useCallback(
      async () => {
        if (
          !selectedPipelineId
        ) {
          setBoard(
            null
          );
          setBusy(
            false
          );
          return;
        }

        setBusy(
          true
        );

        try {
          const params =
            new URLSearchParams();

          if (
            search.trim()
          ) {
            params.set(
              "search",
              search.trim()
            );
          }

          const payload =
            await request<
              BoardPayload
            >(
              `/api/v1/pipelines/${selectedPipelineId}/board?${params.toString()}`
            );

          setBoard(
            payload
          );

          setError("");
        } catch (caught) {
          setError(
            caught instanceof
              ApiError
              ? caught.message
              : "Não foi possível carregar o pipeline."
          );
        } finally {
          setBusy(
            false
          );
        }
      },
      [
        request,
        search,
        selectedPipelineId
      ]
    );

  useEffect(
    () => {
      if (
        !loading &&
        !session
      ) {
        router.replace(
          "/login"
        );
        return;
      }

      if (
        session &&
        !roleCan(
          session.role,
          "pipeline.view"
        )
      ) {
        router.replace(
          "/dashboard"
        );
        return;
      }

      if (
        session
      ) {
        void loadPipelines()
          .catch(() => {
            setError(
              "Não foi possível carregar os pipelines."
            );
            setBusy(
              false
            );
          });
      }
    },
    [
      loadPipelines,
      loading,
      router,
      session
    ]
  );

  useEffect(
    () => {
      const timer =
        window.setTimeout(
          () => {
            void loadBoard();
          },
          220
        );

      return () =>
        window.clearTimeout(
          timer
        );
    },
    [
      loadBoard
    ]
  );

  useEffect(
    () => {
      if (
        !session
      ) {
        return;
      }

      return subscribe(
        "/api/v1/realtime/events",
        event => {
          if (
            event.type ===
              "contact.pipeline.updated" &&
            (
              !event.pipelineId ||
              event.pipelineId ===
                selectedPipelineId
            )
          ) {
            void loadBoard();
          }
        }
      );
    },
    [
      loadBoard,
      selectedPipelineId,
      session,
      subscribe
    ]
  );

  useEffect(
    () => {
      if (
        !targetContactId ||
        !board
      ) {
        return;
      }

      const exists =
        board.columns.some(
          column =>
            column.contacts.some(
              contact =>
                contact.id ===
                targetContactId
            )
        );

      if (
        exists
      ) {
        window.setTimeout(
          () => {
            document
              .querySelector(
                `[data-pipeline-contact="${targetContactId}"]`
              )
              ?.scrollIntoView({
                behavior:
                  "smooth",
                block:
                  "center",
                inline:
                  "center"
              });
          },
          0
        );
      }
    },
    [
      board,
      targetContactId
    ]
  );

  const allStages =
    useMemo(
      () =>
        board
          ?.pipeline
          .stages ??
        [],
      [
        board
      ]
    );

  async function moveContact(
    contactId: string,
    stageId:
      string
      | null
  ) {
    if (
      !selectedPipelineId ||
      movingContactId
    ) {
      return;
    }

    setMovingContactId(
      contactId
    );

    setError("");

    try {
      await request(
        `/api/v1/contacts/${contactId}/pipeline-stage`,
        {
          method:
            "POST",
          body:
            JSON.stringify({
              pipelineId:
                selectedPipelineId,
              stageId
            })
        }
      );

      await loadBoard();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível mover o contato."
      );
    } finally {
      setMovingContactId(
        null
      );
    }
  }

  function dropOnStage(
    event:
      DragEvent<
        HTMLDivElement
      >,
    stageId:
      string
      | null
  ) {
    event.preventDefault();

    if (
      draggingContactId
    ) {
      void moveContact(
        draggingContactId,
        stageId
      );
    }

    setDraggingContactId(
      null
    );
  }

  async function createNewPipeline(
    event:
      FormEvent<
        HTMLFormElement
      >
  ) {
    event.preventDefault();

    setError("");
    setNotice("");

    try {
      await request(
        "/api/v1/pipelines",
        {
          method:
            "POST",
          body:
            JSON.stringify({
              name:
                pipelineName.trim(),
              description:
                pipelineDescription
                  .trim() ||
                null,
              stages:
                initialStages
                  .split(",")
                  .map(
                    item =>
                      item.trim()
                  )
                  .filter(
                    Boolean
                  )
            })
        }
      );

      setPipelineName("");
      setPipelineDescription("");
      setNotice(
        "Pipeline criado."
      );

      await loadPipelines();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível criar o pipeline."
      );
    }
  }

  async function createStage(
    event:
      FormEvent<
        HTMLFormElement
      >
  ) {
    event.preventDefault();

    if (
      !selectedPipelineId
    ) {
      return;
    }

    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/pipelines/${selectedPipelineId}/stages`,
        {
          method:
            "POST",
          body:
            JSON.stringify({
              name:
                newStageName.trim(),
              colorKey:
                newStageColor,
              outcome:
                newStageOutcome
            })
        }
      );

      setNewStageName("");
      setNotice(
        "Etapa criada."
      );

      await Promise.all([
        loadPipelines(),
        loadBoard()
      ]);
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível criar a etapa."
      );
    }
  }

  async function toggleStage(
    stage:
      Stage
  ) {
    try {
      await request(
        `/api/v1/pipeline-stages/${stage.id}`,
        {
          method:
            "PATCH",
          body:
            JSON.stringify({
              isActive:
                !stage.isActive
            })
        }
      );

      await Promise.all([
        loadPipelines(),
        loadBoard()
      ]);
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível alterar a etapa."
      );
    }
  }

  if (
    loading ||
    !session
  ) {
    return (
      <main className="dashboard-loading">
        Carregando pipeline…
      </main>
    );
  }

  return (
    <main className="pipeline-screen">
      <header className="pipeline-header">
        <div>
          <button
            className="connections-back"
            onClick={() =>
              router.push(
                "/dashboard"
              )
            }
            type="button"
          >
            ← Visão geral
          </button>

          <span className="eyebrow">
            CRM
          </span>

          <h1>
            Pipeline
          </h1>

          <p>
            Etapas de relacionamento independentes do status operacional dos atendimentos.
          </p>
        </div>

        <div className="pipeline-header__actions">
          {pipelines.length >
            0 && (
            <select
              onChange={
                event =>
                  setSelectedPipelineId(
                    event
                      .target
                      .value
                  )
              }
              value={
                selectedPipelineId
              }
            >
              {pipelines.map(
                pipeline => (
                  <option
                    key={
                      pipeline.id
                    }
                    value={
                      pipeline.id
                    }
                  >
                    {pipeline.name}
                  </option>
                )
              )}
            </select>
          )}

          {canManage && (
            <button
              className="ghost-button"
              onClick={() =>
                setManagerOpen(
                  current =>
                    !current
                )
              }
              type="button"
            >
              {managerOpen
                ? "Fechar configuração"
                : "Configurar"}
            </button>
          )}
        </div>
      </header>

      {error && (
        <div className="pipeline-feedback pipeline-feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="pipeline-feedback">
          {notice}
        </div>
      )}

      {canManage &&
        managerOpen && (
        <section className="pipeline-manager">
          <form
            className="pipeline-create-form"
            onSubmit={
              createNewPipeline
            }
          >
            <strong>
              Novo pipeline
            </strong>

            <input
              maxLength={
                120
              }
              onChange={
                event =>
                  setPipelineName(
                    event
                      .target
                      .value
                  )
              }
              placeholder="Ex.: Comercial"
              required
              value={
                pipelineName
              }
            />

            <input
              maxLength={
                500
              }
              onChange={
                event =>
                  setPipelineDescription(
                    event
                      .target
                      .value
                  )
              }
              placeholder="Descrição opcional"
              value={
                pipelineDescription
              }
            />

            <input
              onChange={
                event =>
                  setInitialStages(
                    event
                      .target
                      .value
                  )
              }
              placeholder="Novo, Em contato, Cliente"
              value={
                initialStages
              }
            />

            <button
              className="primary-button"
              type="submit"
            >
              <span>
                Criar pipeline
              </span>
            </button>
          </form>

          {selectedPipelineId && (
            <div className="pipeline-stage-manager">
              <form
                onSubmit={
                  createStage
                }
              >
                <strong>
                  Nova etapa
                </strong>

                <input
                  maxLength={
                    120
                  }
                  onChange={
                    event =>
                      setNewStageName(
                        event
                          .target
                          .value
                      )
                  }
                  placeholder="Nome da etapa"
                  required
                  value={
                    newStageName
                  }
                />

                <select
                  onChange={
                    event =>
                      setNewStageColor(
                        event
                          .target
                          .value as
                          keyof typeof stageColors
                      )
                  }
                  value={
                    newStageColor
                  }
                >
                  {Object.entries(
                    stageColors
                  ).map(
                    ([
                      key,
                      label
                    ]) => (
                      <option
                        key={
                          key
                        }
                        value={
                          key
                        }
                      >
                        {label}
                      </option>
                    )
                  )}
                </select>

                <select
                  onChange={
                    event =>
                      setNewStageOutcome(
                        event
                          .target
                          .value as
                          | "OPEN"
                          | "WON"
                          | "LOST"
                      )
                  }
                  value={
                    newStageOutcome
                  }
                >
                  <option value="OPEN">
                    Em aberto
                  </option>
                  <option value="WON">
                    Ganho
                  </option>
                  <option value="LOST">
                    Perdido
                  </option>
                </select>

                <button
                  className="primary-button"
                  type="submit"
                >
                  <span>
                    Adicionar etapa
                  </span>
                </button>
              </form>

              <div className="pipeline-stage-admin-list">
                {pipelines
                  .find(
                    item =>
                      item.id ===
                      selectedPipelineId
                  )
                  ?.stages.map(
                    stage => (
                      <article
                        className={
                          stage.isActive
                            ? "pipeline-stage-admin-item"
                            : "pipeline-stage-admin-item pipeline-stage-admin-item--inactive"
                        }
                        key={
                          stage.id
                        }
                      >
                        <span
                          className={
                            `pipeline-stage-color pipeline-stage-color--${stage.colorKey.toLowerCase()}`
                          }
                        />

                        <div>
                          <strong>
                            {stage.name}
                          </strong>

                          <small>
                            {stage.outcome}
                            {" · "}
                            {stage
                              ._count
                              ?.states ??
                              0} contatos
                          </small>
                        </div>

                        <button
                          onClick={() =>
                            void toggleStage(
                              stage
                            )
                          }
                          type="button"
                        >
                          {stage.isActive
                            ? "Desativar"
                            : "Ativar"}
                        </button>
                      </article>
                    )
                  )}
              </div>
            </div>
          )}
        </section>
      )}

      <section className="pipeline-toolbar">
        <input
          onChange={
            event =>
              setSearch(
                event
                  .target
                  .value
              )
          }
          placeholder="Buscar contato no quadro…"
          type="search"
          value={
            search
          }
        />

        <span>
          {board
            ? board.columns.reduce(
                (
                  sum,
                  column
                ) =>
                  sum +
                  column.count,
                0
              )
            : 0}{" "}
          contatos
        </span>
      </section>

      {busy ? (
        <div className="pipeline-loading">
          Atualizando quadro…
        </div>
      ) : pipelines.length ===
        0 ? (
        <div className="pipeline-empty-state">
          <strong>
            Nenhum pipeline configurado.
          </strong>

          <p>
            {canManage
              ? "Abra Configurar e crie o primeiro fluxo de relacionamento."
              : "Um administrador precisa configurar o primeiro pipeline."}
          </p>
        </div>
      ) : board ? (
        <section className="pipeline-board">
          {board.columns.map(
            column => (
              <div
                className="pipeline-column"
                key={
                  column.stage
                    ?.id ??
                  "__unassigned__"
                }
                onDragOver={
                  event =>
                    event.preventDefault()
                }
                onDrop={
                  event =>
                    dropOnStage(
                      event,
                      column.stage
                        ?.id ??
                        null
                    )
                }
              >
                <header>
                  <div>
                    <span
                      className={
                        column.stage
                          ? `pipeline-stage-color pipeline-stage-color--${column.stage.colorKey.toLowerCase()}`
                          : "pipeline-stage-color pipeline-stage-color--gray"
                      }
                    />

                    <strong>
                      {column.stage
                        ?.name ??
                        "Sem etapa"}
                    </strong>
                  </div>

                  <span>
                    {column.count}
                  </span>
                </header>

                <div className="pipeline-column__cards">
                  {column.contacts.map(
                    contact => (
                      <article
                        className={
                          targetContactId ===
                          contact.id
                            ? "pipeline-card pipeline-card--target"
                            : "pipeline-card"
                        }
                        data-pipeline-contact={
                          contact.id
                        }
                        draggable
                        key={
                          contact.id
                        }
                        onDragEnd={() =>
                          setDraggingContactId(
                            null
                          )
                        }
                        onDragStart={() =>
                          setDraggingContactId(
                            contact.id
                          )
                        }
                      >
                        <button
                          className="pipeline-card__identity"
                          onClick={() =>
                            router.push(
                              `/dashboard/contacts?contact=${contact.id}`
                            )
                          }
                          type="button"
                        >
                          <span>
                            {contact.name
                              .slice(
                                0,
                                1
                              )
                              .toUpperCase()}
                          </span>

                          <div>
                            <strong>
                              {contact.name}
                            </strong>

                            <small>
                              {contact.phoneNumber ??
                                contact.email ??
                                "Sem telefone"}
                            </small>
                          </div>
                        </button>

                        {contact
                          .customFieldValues
                          .length >
                          0 && (
                          <div className="pipeline-card__fields">
                            {contact
                              .customFieldValues
                              .map(
                                item => (
                                  <span
                                    key={
                                      item
                                        .field
                                        .id
                                    }
                                  >
                                    {item
                                      .field
                                      .label}:{" "}
                                    <strong>
                                      {item.value}
                                    </strong>
                                  </span>
                                )
                              )}
                          </div>
                        )}

                        {contact.tickets[
                          0
                        ] && (
                          <button
                            className="pipeline-card__ticket"
                            onClick={() =>
                              router.push(
                                `/dashboard/conversations?ticket=${contact.tickets[0].id}`
                              )
                            }
                            type="button"
                          >
                            <span>
                              {contact
                                .tickets[0]
                                .queue
                                ?.name ??
                                "Sem fila"}
                            </span>

                            <time>
                              {dateLabel(
                                contact
                                  .tickets[0]
                                  .lastMessageAt
                              )}
                            </time>
                          </button>
                        )}

                        <select
                          aria-label="Mover contato"
                          disabled={
                            movingContactId ===
                            contact.id
                          }
                          onChange={
                            event =>
                              void moveContact(
                                contact.id,
                                event
                                  .target
                                  .value ||
                                  null
                              )
                          }
                          value={
                            column.stage
                              ?.id ??
                              ""
                          }
                        >
                          <option value="">
                            Sem etapa
                          </option>

                          {allStages.map(
                            stage => (
                              <option
                                key={
                                  stage.id
                                }
                                value={
                                  stage.id
                                }
                              >
                                {stage.name}
                              </option>
                            )
                          )}
                        </select>
                      </article>
                    )
                  )}

                  {column.contacts.length ===
                    0 && (
                    <div className="pipeline-column__empty">
                      Arraste um contato para esta etapa.
                    </div>
                  )}

                  {column.truncated && (
                    <small className="pipeline-column__truncated">
                      Exibindo os 80 contatos mais recentes desta coluna.
                    </small>
                  )}
                </div>
              </div>
            )
          )}
        </section>
      ) : null}
    </main>
  );
}
EOF

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

if ! grep -Fq -- "WAPP P3.2 / CRM PIPELINES" "$CSS"; then
cat >> "$CSS" <<'EOF'

/* --- WAPP P3.2 / CRM PIPELINES --------------------------------------- */

.pipeline-screen {
  min-height: 100vh;
  overflow-x: hidden;
  background: var(--surface-subtle);
  padding: 32px clamp(18px, 4vw, 56px) 54px;
}

.pipeline-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 20px;
}

.pipeline-header h1 {
  margin: 6px 0 5px;
  font-size: clamp(32px, 4vw, 48px);
  letter-spacing: -0.05em;
}

.pipeline-header p {
  max-width: 650px;
  margin: 0;
  color: var(--muted);
  font-size: 10px;
  line-height: 1.5;
}

.pipeline-header__actions {
  display: flex;
  align-items: center;
  gap: 7px;
}

.pipeline-header__actions select,
.pipeline-toolbar input,
.pipeline-manager input,
.pipeline-manager select,
.pipeline-card select,
.contact-pipeline-summary select {
  border: 1px solid var(--line);
  border-radius: 8px;
  outline: 0;
  background: white;
  padding: 7px 8px;
  color: var(--ink);
  font: inherit;
  font-size: 9px;
}

.pipeline-feedback {
  margin-top: 12px;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 9px 10px;
  font-size: 8px;
}

.pipeline-feedback--error {
  background: rgba(163, 59, 50, 0.07);
  color: #973a32;
}

.pipeline-manager {
  display: grid;
  grid-template-columns: minmax(260px, 0.7fr) minmax(0, 1.3fr);
  gap: 12px;
  margin-top: 12px;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
  padding: 13px;
}

.pipeline-create-form,
.pipeline-stage-manager > form {
  display: grid;
  align-content: start;
  gap: 7px;
}

.pipeline-create-form > strong,
.pipeline-stage-manager > form > strong {
  font-size: 10px;
}

.pipeline-manager input,
.pipeline-manager select {
  min-height: 36px;
}

.pipeline-manager .primary-button {
  width: fit-content;
}

.pipeline-stage-manager {
  display: grid;
  grid-template-columns: minmax(230px, 0.7fr) minmax(0, 1.3fr);
  gap: 12px;
}

.pipeline-stage-admin-list {
  display: grid;
  align-content: start;
  gap: 5px;
}

.pipeline-stage-admin-item {
  display: grid;
  grid-template-columns: 8px minmax(0, 1fr) auto;
  align-items: center;
  gap: 8px;
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 8px;
}

.pipeline-stage-admin-item--inactive {
  opacity: 0.5;
}

.pipeline-stage-admin-item > div {
  display: grid;
  gap: 2px;
}

.pipeline-stage-admin-item strong {
  font-size: 9px;
}

.pipeline-stage-admin-item small {
  color: var(--muted);
  font-size: 7px;
}

.pipeline-stage-admin-item button {
  border: 0;
  background: transparent;
  color: var(--accent-dark);
  font-size: 7px;
  font-weight: 750;
  cursor: pointer;
}

.pipeline-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: 14px;
}

.pipeline-toolbar input {
  width: min(380px, 100%);
  min-height: 38px;
}

.pipeline-toolbar > span {
  color: var(--muted);
  font-size: 8px;
}

.pipeline-loading,
.pipeline-empty-state {
  margin-top: 12px;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
  padding: 28px;
  color: var(--muted);
  text-align: center;
}

.pipeline-empty-state strong {
  display: block;
  margin-bottom: 5px;
  color: var(--ink);
  font-size: 12px;
}

.pipeline-empty-state p {
  margin: 0;
  font-size: 9px;
}

.pipeline-board {
  display: flex;
  min-height: 520px;
  gap: 10px;
  overflow-x: auto;
  align-items: flex-start;
  margin-top: 11px;
  padding-bottom: 12px;
  overscroll-behavior-x: contain;
  scrollbar-width: thin;
}

.pipeline-column {
  width: 284px;
  min-width: 284px;
  max-height: calc(100dvh - 230px);
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: #f7f9f7;
}

.pipeline-column > header {
  display: flex;
  min-height: 43px;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  border-bottom: 1px solid var(--line);
  background: white;
  padding: 9px 10px;
}

.pipeline-column > header > div {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 7px;
}

.pipeline-column > header strong {
  overflow: hidden;
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pipeline-column > header > span {
  display: grid;
  min-width: 22px;
  height: 20px;
  place-items: center;
  border-radius: 999px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding-inline: 6px;
  font-size: 7px;
  font-weight: 800;
}

.pipeline-stage-color {
  display: block;
  width: 7px;
  height: 7px;
  flex: 0 0 7px;
  border-radius: 999px;
  background: #9aa29d;
}

.pipeline-stage-color--blue {
  background: #4f79a7;
}

.pipeline-stage-color--green {
  background: var(--accent-dark);
}

.pipeline-stage-color--orange {
  background: #c1803f;
}

.pipeline-stage-color--purple {
  background: #8068a1;
}

.pipeline-stage-color--red {
  background: #a84e49;
}

.pipeline-stage-color--gray {
  background: #9aa29d;
}

.pipeline-column__cards {
  max-height: calc(100dvh - 274px);
  overflow-y: auto;
  padding: 7px;
  scrollbar-width: thin;
}

.pipeline-card {
  display: grid;
  gap: 7px;
  margin-bottom: 7px;
  border: 1px solid #e3e8e4;
  border-radius: 10px;
  background: white;
  padding: 9px;
  box-shadow: 0 3px 10px rgba(28, 43, 34, 0.035);
}

.pipeline-card[draggable="true"] {
  cursor: grab;
}

.pipeline-card--target {
  border-color: rgba(31, 122, 80, 0.42);
  box-shadow: 0 0 0 3px rgba(31, 122, 80, 0.08);
}

.pipeline-card__identity {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 8px;
  border: 0;
  background: transparent;
  padding: 0;
  text-align: left;
  cursor: pointer;
}

.pipeline-card__identity > span {
  display: grid;
  width: 30px;
  height: 30px;
  flex: 0 0 30px;
  place-items: center;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 9px;
  font-weight: 850;
}

.pipeline-card__identity > div {
  display: grid;
  min-width: 0;
  gap: 2px;
}

.pipeline-card__identity strong {
  overflow: hidden;
  color: var(--ink);
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pipeline-card__identity small {
  overflow: hidden;
  color: var(--muted);
  font-size: 7px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pipeline-card__fields {
  display: grid;
  gap: 2px;
  border-top: 1px solid #edf0ed;
  padding-top: 6px;
}

.pipeline-card__fields > span {
  overflow: hidden;
  color: var(--muted);
  font-size: 7px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pipeline-card__fields strong {
  color: #465149;
}

.pipeline-card__ticket {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  border: 0;
  border-radius: 7px;
  background: #f7f9f7;
  padding: 6px 7px;
  color: var(--muted);
  font-size: 7px;
  cursor: pointer;
}

.pipeline-card select {
  width: 100%;
  min-height: 32px;
}

.pipeline-column__empty {
  padding: 24px 10px;
  color: var(--muted);
  font-size: 8px;
  line-height: 1.45;
  text-align: center;
}

.pipeline-column__truncated {
  display: block;
  padding: 8px;
  color: var(--muted);
  font-size: 7px;
  text-align: center;
}

.contact-pipeline-summary {
  margin-top: 12px;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
}

.contact-pipeline-summary > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  border-bottom: 1px solid var(--line);
  padding: 11px 13px;
}

.contact-pipeline-summary > header > div {
  display: grid;
  gap: 2px;
}

.contact-pipeline-summary > header strong {
  font-size: 10px;
}

.contact-pipeline-summary__body {
  display: grid;
  grid-template-columns: minmax(220px, 0.8fr) minmax(0, 1.2fr);
}

.contact-pipeline-summary__states {
  display: grid;
  align-content: start;
  gap: 8px;
  border-right: 1px solid var(--line);
  padding: 11px 13px;
}

.contact-pipeline-summary__states label {
  display: grid;
  gap: 4px;
}

.contact-pipeline-summary__states label > span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 720;
}

.contact-stage-history {
  display: grid;
  align-content: start;
  gap: 0;
  padding: 11px 13px;
}

.contact-stage-history > strong {
  margin-bottom: 4px;
  font-size: 9px;
}

.contact-stage-history > div {
  display: grid;
  grid-template-columns: 90px minmax(0, 1fr);
  gap: 2px 8px;
  border-bottom: 1px solid #edf0ed;
  padding: 7px 0;
}

.contact-stage-history > div:last-child {
  border-bottom: 0;
}

.contact-stage-history span {
  color: var(--muted);
  font-size: 7px;
}

.contact-stage-history p {
  margin: 0;
  color: #465149;
  font-size: 8px;
}

.contact-stage-history small {
  grid-column: 2;
  color: var(--muted);
  font-size: 7px;
}

.contact-pipeline-summary__error {
  background: rgba(163, 59, 50, 0.07);
  color: #973a32;
  padding: 8px 13px;
  font-size: 8px;
}

.contact-pipeline-summary__empty {
  padding: 18px 13px;
  color: var(--muted);
  font-size: 8px;
}

@media (max-width: 900px) {
  .pipeline-manager,
  .pipeline-stage-manager,
  .contact-pipeline-summary__body {
    grid-template-columns: 1fr;
  }

  .contact-pipeline-summary__states {
    border-right: 0;
    border-bottom: 1px solid var(--line);
  }
}

@media (max-width: 760px) {
  .pipeline-screen {
    min-height: 100dvh;
    padding: 20px 12px
      calc(82px + env(safe-area-inset-bottom, 0px));
  }

  .pipeline-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .pipeline-header__actions,
  .pipeline-toolbar {
    width: 100%;
  }

  .pipeline-header__actions select,
  .pipeline-toolbar input {
    min-height: 42px;
    flex: 1 1 auto;
    font-size: 16px;
  }

  .pipeline-board {
    min-height: 58dvh;
    margin-right: -12px;
    padding-right: 12px;
    scroll-snap-type: x proximity;
  }

  .pipeline-column {
    width: min(86vw, 330px);
    min-width: min(86vw, 330px);
    max-height: 62dvh;
    scroll-snap-align: start;
  }

  .pipeline-column__cards {
    max-height: calc(62dvh - 44px);
  }

  .pipeline-card {
    min-height: 120px;
  }

  .pipeline-card select,
  .pipeline-manager input,
  .pipeline-manager select,
  .contact-pipeline-summary select {
    min-height: 42px;
    font-size: 16px;
  }

  .contact-stage-history > div {
    grid-template-columns: 1fr;
  }

  .contact-stage-history small {
    grid-column: auto;
  }
}

/* --- /WAPP P3.2 ------------------------------------------------------ */
EOF
fi

# ---------------------------------------------------------------------------
# Tests + docs
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
  "src/modules/pipelines/pipeline.policy.test.ts";

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

cat > docs/P3_02_CRM_PIPELINES.md <<'EOF'
# P3.2 CRM pipelines

P3.2 introduces company-defined relationship pipelines without changing the
operational ticket lifecycle.

`Ticket.status` remains:

- PENDING
- OPEN
- CLOSED

A CRM pipeline answers a different question: where is this contact in a
commercial, onboarding, renewal or other relationship journey?

## Multiple pipelines

A company may maintain multiple active pipelines.

Each pipeline owns its stages.

A contact may have one current stage per pipeline.

Removing a contact from a pipeline is represented as `stageId = null` at the
API level and deletes only the current state row. Transition history remains.

## Stage outcomes

Stages support:

- OPEN
- WON
- LOST

Outcome is metadata for later P3 reporting and segmentation. It does not close
a Wapp ticket.

## History

Every real movement creates an immutable `ContactStageTransition`.

No-op updates to the same stage do not create duplicate transition history.

Transitions preserve:

- contact;
- pipeline;
- previous stage;
- next stage;
- acting membership;
- timestamp.

## RBAC

All operational roles can:

- read pipelines;
- move contacts between stages.

OWNER / ADMIN / SUPERVISOR can also:

- create pipelines;
- create stages;
- activate/deactivate configuration.

AGENT cannot change the shared pipeline schema.

A stage with current contacts cannot be deactivated until those contacts are
moved elsewhere.

## Board

`/dashboard/pipeline`

The board:

- has one column per stage plus "Sem etapa";
- supports drag/drop on desktop;
- always exposes a stage select, including for touch/mobile;
- shows up to 80 recent contacts per column and tells the user when a column is
  truncated;
- links cards back to the contact and the latest ticket;
- listens to `contact.pipeline.updated` through Wapp realtime.

## Contact profile

The Contacts screen gets a Pipeline section with:

- current stage in every active pipeline;
- direct stage movement;
- recent stage-transition history;
- link to the full board.

## API

- GET `/api/v1/pipelines`
- GET `/api/v1/pipelines/manage`
- POST `/api/v1/pipelines`
- PATCH `/api/v1/pipelines/:id`
- POST `/api/v1/pipelines/:id/stages`
- PATCH `/api/v1/pipeline-stages/:id`
- GET `/api/v1/pipelines/:pipelineId/board`
- POST `/api/v1/contacts/:id/pipeline-stage`
- GET `/api/v1/contacts/:id/pipeline-states`

## Migration

P3.2 introduces:

- `CrmPipeline`
- `CrmStage`
- `ContactPipelineState`
- `ContactStageTransition`
- `CrmStageOutcome`
EOF

echo "[P3.2] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P3.2] Unit tests..."
pnpm test

echo "[P3.2] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.2] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.2] CODE VALIDATION PASS."
echo
echo "Migration required:"
echo "  pnpm --filter @wapp/api db:migrate"
echo
echo "Then:"
echo "  pnpm test:integration"
echo "  pnpm dev"
