#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP="apps/api/src/app.ts"
PERMISSIONS="apps/api/src/security/permissions.ts"
PERMISSIONS_TEST="apps/api/src/security/permissions.test.ts"
AUDIT_SERVICE="apps/api/src/modules/audit/audit.service.ts"
UI_PERMISSIONS="apps/web/lib/permissions.ts"
DASHBOARD="apps/web/app/dashboard/page.tsx"
CSS="apps/web/app/globals.css"
PKG="apps/api/package.json"
INTEGRATION_SCRIPT="scripts/test-integration.sh"

echo "[P3.6] Installing import/export and data quality..."

for check in \
  "apps/api/prisma/schema.prisma|model Contact {" \
  "apps/api/prisma/schema.prisma|model ContactCampaignConsent {" \
  "apps/api/src/modules/contact-crm/contact-crm.policy.ts|validateContactFieldValue" \
  "apps/api/src/modules/pipelines/pipeline.service.ts|moveContactStage" \
  "$APP|await app.register(campaignRoutes);" \
  "$PERMISSIONS|campaigns.send" \
  "$AUDIT_SERVICE|export type AuditEntityType =" \
  "$UI_PERMISSIONS|campaigns.send" \
  "$DASHBOARD|href: \"/dashboard/campaigns\"" \
  "$INTEGRATION_SCRIPT|critical.integration.test.ts"
do
  file="${check%%|*}"
  marker="${check#*|}"
  if [[ ! -f "$file" ]] || ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: P3.6 prerequisite missing: $file -> $marker"
    echo "P3.6 made no changes."
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/data-quality \
  apps/web/app/dashboard/data-quality \
  apps/api/src/integration \
  docs

cat > apps/api/src/modules/data-quality/data-quality.policy.ts <<'EOF'
import {
  createHash
} from "node:crypto";

export const MAX_IMPORT_ROWS =
  500;

export const MAX_IMPORT_COLUMNS =
  40;

export const MAX_IMPORT_CSV_CHARS =
  650_000;

export const MAX_EXPORT_ROWS =
  5_000;

export type ImportRowStatus =
  | "CREATE"
  | "UPDATE"
  | "CONFLICT"
  | "INVALID"
  | "SKIP";

export type ImportTarget =
  | "IGNORE"
  | "name"
  | "phone"
  | "email"
  | "notes"
  | `custom:${string}`
  | `pipeline:${string}`;

function firstRecord(
  csv:
    string
) {
  let record =
    "";
  let quoted =
    false;

  for (
    let index =
      0;
    index <
      csv.length;
    index +=
      1
  ) {
    const char =
      csv[index];

    if (
      char ===
      '"'
    ) {
      if (
        quoted &&
        csv[
          index +
            1
        ] ===
          '"'
      ) {
        record +=
          '""';
        index +=
          1;
        continue;
      }

      quoted =
        !quoted;
      record +=
        char;
      continue;
    }

    if (
      (
        char ===
          "\n" ||
        char ===
          "\r"
      ) &&
      !quoted
    ) {
      break;
    }

    record +=
      char;
  }

  return record;
}

function countDelimiter(
  record:
    string,
  delimiter:
    string
) {
  let quoted =
    false;
  let count =
    0;

  for (
    let index =
      0;
    index <
      record.length;
    index +=
      1
  ) {
    const char =
      record[index];

    if (
      char ===
      '"'
    ) {
      if (
        quoted &&
        record[
          index +
            1
        ] ===
          '"'
      ) {
        index +=
          1;
        continue;
      }

      quoted =
        !quoted;
      continue;
    }

    if (
      !quoted &&
      char ===
        delimiter
    ) {
      count +=
        1;
    }
  }

  return count;
}

export function detectCsvDelimiter(
  csv:
    string
) {
  const record =
    firstRecord(
      csv
    );

  const candidates =
    [
      ";",
      ",",
      "\t"
    ];

  let best =
    ";";

  let bestCount =
    -1;

  for (
    const candidate
    of candidates
  ) {
    const count =
      countDelimiter(
        record,
        candidate
      );

    if (
      count >
      bestCount
    ) {
      best =
        candidate;
      bestCount =
        count;
    }
  }

  return best;
}

export function parseCsv(
  raw:
    string
) {
  const csv =
    raw
      .replace(
        /^\uFEFF/,
        ""
      )
      .replace(
        /\r\n/g,
        "\n"
      )
      .replace(
        /\r/g,
        "\n"
      );

  if (
    !csv.trim()
  ) {
    throw new Error(
      "CSV_EMPTY"
    );
  }

  if (
    csv.length >
    MAX_IMPORT_CSV_CHARS
  ) {
    throw new Error(
      "CSV_TOO_LARGE"
    );
  }

  const delimiter =
    detectCsvDelimiter(
      csv
    );

  const records:
    string[][] =
    [];

  let row:
    string[] =
    [];

  let cell =
    "";

  let quoted =
    false;

  function pushCell() {
    if (
      cell.length >
      10_000
    ) {
      throw new Error(
        "CSV_CELL_TOO_LARGE"
      );
    }

    row.push(
      cell
    );

    cell =
      "";
  }

  function pushRow() {
    pushCell();

    const empty =
      row.every(
        value =>
          !value.trim()
      );

    if (
      !empty
    ) {
      if (
        row.length >
        MAX_IMPORT_COLUMNS
      ) {
        throw new Error(
          "CSV_TOO_MANY_COLUMNS"
        );
      }

      records.push(
        row
      );
    }

    row =
      [];
  }

  for (
    let index =
      0;
    index <
      csv.length;
    index +=
      1
  ) {
    const char =
      csv[index];

    if (
      quoted
    ) {
      if (
        char ===
        '"'
      ) {
        if (
          csv[
            index +
              1
          ] ===
          '"'
        ) {
          cell +=
            '"';

          index +=
            1;
        } else {
          quoted =
            false;
        }
      } else {
        cell +=
          char;
      }

      continue;
    }

    if (
      char ===
      '"'
    ) {
      quoted =
        true;
      continue;
    }

    if (
      char ===
      delimiter
    ) {
      pushCell();
      continue;
    }

    if (
      char ===
      "\n"
    ) {
      pushRow();
      continue;
    }

    cell +=
      char;
  }

  if (
    quoted
  ) {
    throw new Error(
      "CSV_UNCLOSED_QUOTE"
    );
  }

  if (
    cell.length >
      0 ||
    row.length >
      0
  ) {
    pushRow();
  }

  if (
    records.length <
    1
  ) {
    throw new Error(
      "CSV_EMPTY"
    );
  }

  const headers =
    records[
      0
    ]!
      .map(
        header =>
          header.trim()
      );

  if (
    headers.some(
      header =>
        !header
    )
  ) {
    throw new Error(
      "CSV_EMPTY_HEADER"
    );
  }

  const normalizedHeaders =
    headers.map(
      header =>
        header
          .trim()
          .toLocaleLowerCase(
            "pt-BR"
          )
    );

  if (
    new Set(
      normalizedHeaders
    ).size !==
    normalizedHeaders.length
  ) {
    throw new Error(
      "CSV_DUPLICATE_HEADER"
    );
  }

  const dataRows =
    records.slice(
      1
    );

  if (
    dataRows.length >
    MAX_IMPORT_ROWS
  ) {
    throw new Error(
      "CSV_TOO_MANY_ROWS"
    );
  }

  const rows =
    dataRows.map(
      (
        values,
        index
      ) => {
        const source:
          Record<
            string,
            string
          > =
          {};

        for (
          let column =
            0;
          column <
            headers.length;
          column +=
            1
        ) {
          source[
            headers[
              column
            ]!
          ] =
            values[
              column
            ] ??
            "";
        }

        return {
          rowNumber:
            index +
            2,
          source
        };
      }
    );

  return {
    delimiter,
    headers,
    rows
  };
}

export function normalizeImportPhone(input: {
  value:
    string;
  defaultCountryCode:
    string;
}) {
  const raw =
    input.value.trim();

  const explicitInternational =
    raw.startsWith(
      "+"
    );

  let digits =
    raw.replace(
      /\D/g,
      ""
    );

  const countryCode =
    input.defaultCountryCode.replace(
      /\D/g,
      ""
    );

  if (
    !/^\d{1,3}$/.test(
      countryCode
    )
  ) {
    return {
      error:
        "INVALID_COUNTRY_CODE" as const
    };
  }

  if (
    !digits
  ) {
    return {
      error:
        "PHONE_REQUIRED" as const
    };
  }

  if (
    !explicitInternational &&
    (
      digits.length ===
        10 ||
      digits.length ===
        11
    )
  ) {
    digits =
      `${countryCode}${digits}`;
  }

  if (
    digits.length <
      11 ||
    digits.length >
      15
  ) {
    return {
      error:
        "INVALID_PHONE_LENGTH" as const
    };
  }

  return {
    phoneNumber:
      digits,
    remoteJid:
      `${digits}@s.whatsapp.net`
  };
}

export function normalizeEmail(
  value:
    string
) {
  const email =
    value
      .trim()
      .toLocaleLowerCase(
        "pt-BR"
      );

  if (
    !email
  ) {
    return {
      value:
        null
    };
  }

  if (
    email.length >
      190 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(
      email
    )
  ) {
    return {
      error:
        "INVALID_EMAIL" as const
    };
  }

  return {
    value:
      email
  };
}

export function parseImportTarget(
  value:
    string
):
  ImportTarget
  | null {
  if (
    [
      "IGNORE",
      "name",
      "phone",
      "email",
      "notes"
    ].includes(
      value
    )
  ) {
    return value as
      ImportTarget;
  }

  if (
    /^custom:[0-9a-fA-F-]{36}$/.test(
      value
    ) ||
    /^pipeline:[0-9a-fA-F-]{36}$/.test(
      value
    )
  ) {
    return value as
      ImportTarget;
  }

  return null;
}

export function safeSpreadsheetCell(
  value:
    string
    | null
    | undefined
) {
  const text =
    value ??
    "";

  if (
    /^[\t\r\n]*[=+\-@]/.test(
      text
    )
  ) {
    return `'${text}`;
  }

  return text;
}

export function csvCell(
  value:
    string
    | null
    | undefined
) {
  const safe =
    safeSpreadsheetCell(
      value
    );

  if (
    /[;"\n\r]/.test(
      safe
    )
  ) {
    return `"${safe.replace(
      /"/g,
      '""'
    )}"`;
  }

  return safe;
}

export function planFingerprint(
  value:
    unknown
) {
  return createHash(
    "sha256"
  )
    .update(
      JSON.stringify(
        value
      )
    )
    .digest(
      "hex"
    );
}
EOF

cat > apps/api/src/modules/data-quality/data-quality.policy.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  csvCell,
  normalizeImportPhone,
  parseCsv,
  parseImportTarget,
  planFingerprint,
  safeSpreadsheetCell
} from "./data-quality.policy.js";

test(
  "CSV parser supports semicolon and escaped quotes",
  () => {
    const parsed =
      parseCsv(
        'nome;telefone;observacao\n"Maria ""M""";11999998888;"Linha 1"\n'
      );

    assert.equal(
      parsed.delimiter,
      ";"
    );

    assert.equal(
      parsed.rows[
        0
      ]?.source.nome,
      'Maria "M"'
    );
  }
);

test(
  "Brazilian local phone becomes canonical WhatsApp jid",
  () => {
    const normalized =
      normalizeImportPhone({
        value:
          "(11) 99999-8888",
        defaultCountryCode:
          "55"
      });

    assert.deepEqual(
      normalized,
      {
        phoneNumber:
          "5511999998888",
        remoteJid:
          "5511999998888@s.whatsapp.net"
      }
    );
  }
);

test(
  "explicit international number is not prefixed again",
  () => {
    const normalized =
      normalizeImportPhone({
        value:
          "+1 415 555 2671",
        defaultCountryCode:
          "55"
      });

    assert.equal(
      "phoneNumber" in
        normalized
        ? normalized.phoneNumber
        : null,
      "14155552671"
    );
  }
);

test(
  "import targets do not expose campaign consent",
  () => {
    assert.equal(
      parseImportTarget(
        "campaignConsent"
      ),
      null
    );

    assert.equal(
      parseImportTarget(
        "custom:00000000-0000-0000-0000-000000000001"
      ),
      "custom:00000000-0000-0000-0000-000000000001"
    );
  }
);

test(
  "spreadsheet formula cells are escaped",
  () => {
    assert.equal(
      safeSpreadsheetCell(
        "=2+2"
      ),
      "'=2+2"
    );

    assert.equal(
      csvCell(
        'Empresa; "A"'
      ),
      '"Empresa; ""A"""'
    );
  }
);

test(
  "preview fingerprint is deterministic",
  () => {
    assert.equal(
      planFingerprint({
        rows: [
          1,
          2
        ]
      }),
      planFingerprint({
        rows: [
          1,
          2
        ]
      })
    );
  }
);
EOF

cat > apps/api/src/modules/data-quality/data-quality.service.ts <<'EOF'
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
  type ContactFieldTypeValue,
  validateContactFieldValue
} from "../contact-crm/contact-crm.policy.js";
import {
  csvCell,
  MAX_EXPORT_ROWS,
  normalizeEmail,
  normalizeImportPhone,
  parseCsv,
  parseImportTarget,
  planFingerprint,
  type ImportRowStatus,
  type ImportTarget
} from "./data-quality.policy.js";

interface ImportMapping {
  [header:
    string]:
    string;
}

interface ImportPlanRow {
  rowNumber:
    number;
  status:
    ImportRowStatus;
  reasons:
    string[];
  source:
    Record<
      string,
      string
    >;
  existingContact:
    | {
        id:
          string;
        name:
          string;
        phoneNumber:
          string
          | null;
        remoteJid:
          string;
        email:
          string
          | null;
      }
    | null;
  contact: {
    createName:
      string;
    phoneNumber:
      string;
    remoteJid:
      string;
    createEmail:
      string
      | null;
    createNotes:
      string
      | null;
    updateName?:
      string;
    updateEmail?:
      string
      | null;
    updateNotes?:
      string
      | null;
  } | null;
  customValues:
    Array<{
      fieldId:
        string;
      label:
        string;
      value:
        string;
    }>;
  pipelineMoves:
    Array<{
      pipelineId:
        string;
      pipelineName:
        string;
      stageId:
        string;
      stageName:
        string;
    }>;
}

interface ImportAnalysis {
  headers:
    string[];
  delimiter:
    string;
  rows:
    ImportPlanRow[];
  summary: {
    total:
      number;
    create:
      number;
    update:
      number;
    conflict:
      number;
    invalid:
      number;
    skip:
      number;
  };
  fingerprint:
    string;
}

function fieldOptions(
  value:
    unknown
) {
  return Array.isArray(
    value
  )
    ? value.filter(
        (
          item
        ): item is string =>
          typeof item ===
          "string"
      )
    : [];
}

function mappedHeaders(
  headers:
    string[],
  mapping:
    ImportMapping
) {
  const targetToHeader =
    new Map<
      ImportTarget,
      string
    >();

  for (
    const [
      header,
      rawTarget
    ]
    of Object.entries(
      mapping
    )
  ) {
    if (
      !headers.includes(
        header
      )
    ) {
      throw new AppError(
        `A coluna “${header}” não existe mais no CSV.`,
        422,
        "IMPORT_MAPPING_HEADER_INVALID"
      );
    }

    const target =
      parseImportTarget(
        rawTarget
      );

    if (
      !target
    ) {
      throw new AppError(
        `Mapeamento inválido para “${header}”.`,
        422,
        "IMPORT_MAPPING_TARGET_INVALID"
      );
    }

    if (
      target ===
      "IGNORE"
    ) {
      continue;
    }

    if (
      targetToHeader.has(
        target
      )
    ) {
      throw new AppError(
        `O destino “${target}” foi mapeado mais de uma vez.`,
        422,
        "IMPORT_MAPPING_DUPLICATE_TARGET"
      );
    }

    targetToHeader.set(
      target,
      header
    );
  }

  if (
    !targetToHeader.has(
      "phone"
    )
  ) {
    throw new AppError(
      "Mapeie uma coluna de telefone/WhatsApp.",
      422,
      "IMPORT_PHONE_MAPPING_REQUIRED"
    );
  }

  return targetToHeader;
}

function rowValue(
  source:
    Record<
      string,
      string
    >,
  targets:
    Map<
      ImportTarget,
      string
    >,
  target:
    ImportTarget
) {
  const header =
    targets.get(
      target
    );

  return header
    ? source[
        header
      ] ??
        ""
    : "";
}

function reasonLabel(
  code:
    string
) {
  const messages:
    Record<
      string,
      string
    > = {
      PHONE_REQUIRED:
        "Telefone ausente.",
      INVALID_PHONE_LENGTH:
        "Telefone fora do tamanho aceito para WhatsApp.",
      INVALID_COUNTRY_CODE:
        "Código de país inválido.",
      INVALID_EMAIL:
        "E-mail inválido.",
      TEXT_TOO_LONG:
        "Texto do campo personalizado excede o limite.",
      INVALID_NUMBER:
        "Campo personalizado exige número.",
      INVALID_DATE:
        "Campo personalizado exige data YYYY-MM-DD.",
      INVALID_BOOLEAN:
        "Campo personalizado exige true ou false.",
      INVALID_OPTION:
        "Valor não existe nas opções do campo personalizado."
    };

  return messages[
    code
  ] ??
    "Valor inválido.";
}

function normalizedName(
  value:
    string
) {
  return value
    .trim()
    .replace(
      /\s+/g,
      " "
    )
    .slice(
      0,
      190
    );
}

function normalizedNotes(
  value:
    string
) {
  const text =
    value.trim();

  return text
    ? text.slice(
        0,
        10_000
      )
    : null;
}

function mapSummary(
  rows:
    ImportPlanRow[]
) {
  const summary = {
    total:
      rows.length,
    create:
      0,
    update:
      0,
    conflict:
      0,
    invalid:
      0,
    skip:
      0
  };

  for (
    const row
    of rows
  ) {
    switch (
      row.status
    ) {
      case "CREATE":
        summary.create +=
          1;
        break;
      case "UPDATE":
        summary.update +=
          1;
        break;
      case "CONFLICT":
        summary.conflict +=
          1;
        break;
      case "INVALID":
        summary.invalid +=
          1;
        break;
      case "SKIP":
        summary.skip +=
          1;
        break;
    }
  }

  return summary;
}

function previewFingerprint(
  analysis:
    Omit<
      ImportAnalysis,
      "fingerprint"
    >
) {
  return planFingerprint({
    headers:
      analysis.headers,
    delimiter:
      analysis.delimiter,
    summary:
      analysis.summary,
    rows:
      analysis.rows.map(
        row => ({
          rowNumber:
            row.rowNumber,
          status:
            row.status,
          contact:
            row.contact,
          existingContactId:
            row.existingContact
              ?.id ??
            null,
          reasons:
            row.reasons,
          customValues:
            row.customValues.map(
              value => [
                value.fieldId,
                value.value
              ]
            ),
          pipelineMoves:
            row.pipelineMoves.map(
              move => [
                move.pipelineId,
                move.stageId
              ]
            )
        })
      )
  });
}

async function loadImportContext(
  companyId:
    string
) {
  const [
    fields,
    pipelines
  ] =
    await Promise.all([
      prisma.contactFieldDefinition.findMany({
        where: {
          companyId,
          isActive:
            true
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
      }),
      prisma.crmPipeline.findMany({
        where: {
          companyId,
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
      })
    ]);

  return {
    fields,
    pipelines
  };
}

export async function inspectContactImportCsv(
  csv:
    string
) {
  try {
    const parsed =
      parseCsv(
        csv
      );

    return {
      delimiter:
        parsed.delimiter,
      headers:
        parsed.headers,
      sample:
        parsed.rows
          .slice(
            0,
            5
          )
          .map(
            row =>
              row.source
          ),
      rowCount:
        parsed.rows.length
    };
  } catch (error) {
    throw csvError(
      error
    );
  }
}

function csvError(
  error:
    unknown
) {
  const code =
    error instanceof
      Error
      ? error.message
      : "CSV_INVALID";

  const messages:
    Record<
      string,
      string
    > = {
      CSV_EMPTY:
        "O CSV está vazio.",
      CSV_TOO_LARGE:
        "O CSV excede o limite seguro desta importação.",
      CSV_CELL_TOO_LARGE:
        "Uma célula excede 10.000 caracteres.",
      CSV_TOO_MANY_COLUMNS:
        "O CSV possui colunas demais.",
      CSV_TOO_MANY_ROWS:
        "O CSV excede 500 linhas. Divida o arquivo em lotes.",
      CSV_UNCLOSED_QUOTE:
        "O CSV possui aspas não fechadas.",
      CSV_EMPTY_HEADER:
        "Todas as colunas precisam de cabeçalho.",
      CSV_DUPLICATE_HEADER:
        "O CSV possui cabeçalhos duplicados."
    };

  return new AppError(
    messages[
      code
    ] ??
      "Não foi possível interpretar o CSV.",
    422,
    code
  );
}

async function analyzeContactImport(input: {
  companyId:
    string;
  csv:
    string;
  mapping:
    ImportMapping;
  defaultCountryCode:
    string;
}):
  Promise<
    ImportAnalysis
  > {
  let parsed:
    ReturnType<
      typeof parseCsv
    >;

  try {
    parsed =
      parseCsv(
        input.csv
      );
  } catch (error) {
    throw csvError(
      error
    );
  }

  const targetToHeader =
    mappedHeaders(
      parsed.headers,
      input.mapping
    );

  const context =
    await loadImportContext(
      input.companyId
    );

  const fieldById =
    new Map(
      context.fields.map(
        field => [
          field.id,
          field
        ]
      )
    );

  const pipelineById =
    new Map(
      context.pipelines.map(
        pipeline => [
          pipeline.id,
          pipeline
        ]
      )
    );

  for (
    const target
    of targetToHeader.keys()
  ) {
    if (
      target.startsWith(
        "custom:"
      )
    ) {
      const id =
        target.slice(
          "custom:".length
        );

      if (
        !fieldById.has(
          id
        )
      ) {
        throw new AppError(
          "Um campo personalizado mapeado não existe ou está inativo.",
          422,
          "IMPORT_CUSTOM_FIELD_INVALID"
        );
      }
    }

    if (
      target.startsWith(
        "pipeline:"
      )
    ) {
      const id =
        target.slice(
          "pipeline:".length
        );

      if (
        !pipelineById.has(
          id
        )
      ) {
        throw new AppError(
          "Um pipeline mapeado não existe ou está inativo.",
          422,
          "IMPORT_PIPELINE_INVALID"
        );
      }
    }
  }

  const drafts =
    parsed.rows.map(
      row => {
        const reasons:
          string[] =
          [];

        const normalizedPhone =
          normalizeImportPhone({
            value:
              rowValue(
                row.source,
                targetToHeader,
                "phone"
              ),
            defaultCountryCode:
              input.defaultCountryCode
          });

        if (
          "error" in
          normalizedPhone
        ) {
          reasons.push(
            reasonLabel(
              normalizedPhone.error
            )
          );
        }

        const rawEmail =
          rowValue(
            row.source,
            targetToHeader,
            "email"
          );

        const email =
          normalizeEmail(
            rawEmail
          );

        if (
          "error" in
          email
        ) {
          reasons.push(
            reasonLabel(
              email.error
            )
          );
        }

        const rawName =
          rowValue(
            row.source,
            targetToHeader,
            "name"
          );

        const mappedName =
          targetToHeader.has(
            "name"
          )
            ? normalizedName(
                rawName
              )
            : "";

        const customValues:
          ImportPlanRow[
            "customValues"
          ] =
          [];

        for (
          const [
            target,
            header
          ]
          of targetToHeader.entries()
        ) {
          if (
            !target.startsWith(
              "custom:"
            )
          ) {
            continue;
          }

          const fieldId =
            target.slice(
              "custom:".length
            );

          const field =
            fieldById.get(
              fieldId
            )!;

          const value =
            (
              row.source[
                header
              ] ??
              ""
            ).trim();

          const validation =
            validateContactFieldValue({
              type:
                field.type as
                  ContactFieldTypeValue,
              value,
              options:
                fieldOptions(
                  field.options
                )
            });

          if (
            validation
          ) {
            reasons.push(
              `${field.label}: ${reasonLabel(
                validation
              )}`
            );
          }

          customValues.push({
            fieldId,
            label:
              field.label,
            value
          });
        }

        const pipelineMoves:
          ImportPlanRow[
            "pipelineMoves"
          ] =
          [];

        for (
          const [
            target,
            header
          ]
          of targetToHeader.entries()
        ) {
          if (
            !target.startsWith(
              "pipeline:"
            )
          ) {
            continue;
          }

          const pipelineId =
            target.slice(
              "pipeline:".length
            );

          const pipeline =
            pipelineById.get(
              pipelineId
            )!;

          const requested =
            (
              row.source[
                header
              ] ??
              ""
            )
              .trim()
              .toLocaleLowerCase(
                "pt-BR"
              );

          if (
            !requested
          ) {
            continue;
          }

          const stage =
            pipeline.stages.find(
              item =>
                item.name
                  .trim()
                  .toLocaleLowerCase(
                    "pt-BR"
                  ) ===
                requested
            );

          if (
            !stage
          ) {
            reasons.push(
              `${pipeline.name}: etapa “${row.source[
                header
              ]}” não encontrada.`
            );

            continue;
          }

          pipelineMoves.push({
            pipelineId:
              pipeline.id,
            pipelineName:
              pipeline.name,
            stageId:
              stage.id,
            stageName:
              stage.name
          });
        }

        const phone =
          "phoneNumber" in
          normalizedPhone
            ? normalizedPhone
            : null;

        const normalizedEmail =
          "value" in
          email
            ? email.value
            : null;

        const createName =
          mappedName ||
          phone
            ?.phoneNumber ||
          "Contato";

        return {
          rowNumber:
            row.rowNumber,
          source:
            row.source,
          reasons,
          phone,
          normalizedEmail,
          mappedName,
          notes:
            normalizedNotes(
              rowValue(
                row.source,
                targetToHeader,
                "notes"
              )
            ),
          hasNameMapping:
            targetToHeader.has(
              "name"
            ),
          hasEmailMapping:
            targetToHeader.has(
              "email"
            ),
          hasNotesMapping:
            targetToHeader.has(
              "notes"
            ),
          createName,
          customValues,
          pipelineMoves
        };
      }
    );

  const remoteJids =
    drafts
      .map(
        draft =>
          draft.phone
            ?.remoteJid
      )
      .filter(
        (
          value
        ): value is string =>
          Boolean(
            value
          )
      );

  const phones =
    drafts
      .map(
        draft =>
          draft.phone
            ?.phoneNumber
      )
      .filter(
        (
          value
        ): value is string =>
          Boolean(
            value
          )
      );

  const emails =
    drafts
      .map(
        draft =>
          draft.normalizedEmail
      )
      .filter(
        (
          value
        ): value is string =>
          Boolean(
            value
          )
      );

  const OR:
    Prisma.ContactWhereInput[] =
    [];

  if (
    remoteJids.length >
    0
  ) {
    OR.push({
      remoteJid: {
        in:
          remoteJids
      }
    });
  }

  if (
    phones.length >
    0
  ) {
    OR.push({
      phoneNumber: {
        in:
          phones
      }
    });
  }

  if (
    emails.length >
    0
  ) {
    OR.push({
      email: {
        in:
          emails
      }
    });
  }

  const existing =
    OR.length >
      0
      ? await prisma.contact.findMany({
          where: {
            companyId:
              input.companyId,
            isGroup:
              false,
            OR
          },
          select: {
            id:
              true,
            name:
              true,
            phoneNumber:
              true,
            remoteJid:
              true,
            email:
              true,
            customFieldValues: {
              select: {
                fieldId:
                  true,
                value:
                  true
              }
            }
          }
        })
      : [];

  const byRemoteJid =
    new Map(
      existing.map(
        contact => [
          contact.remoteJid,
          contact
        ]
      )
    );

  const byPhone =
    new Map<
      string,
      typeof existing
    >();

  const byEmail =
    new Map<
      string,
      typeof existing
    >();

  for (
    const contact
    of existing
  ) {
    if (
      contact.phoneNumber
    ) {
      const list =
        byPhone.get(
          contact.phoneNumber
        ) ??
        [];

      list.push(
        contact
      );

      byPhone.set(
        contact.phoneNumber,
        list
      );
    }

    if (
      contact.email
    ) {
      const key =
        contact.email
          .trim()
          .toLocaleLowerCase(
            "pt-BR"
          );

      const list =
        byEmail.get(
          key
        ) ??
        [];

      list.push(
        contact
      );

      byEmail.set(
        key,
        list
      );
    }
  }

  const seenFileRemoteJids =
    new Map<
      string,
      number
    >();

  const rows:
    ImportPlanRow[] =
    [];

  for (
    const draft
    of drafts
  ) {
    if (
      !draft.phone
    ) {
      rows.push({
        rowNumber:
          draft.rowNumber,
        status:
          "INVALID",
        reasons:
          draft.reasons,
        source:
          draft.source,
        existingContact:
          null,
        contact:
          null,
        customValues:
          draft.customValues,
        pipelineMoves:
          draft.pipelineMoves
      });

      continue;
    }

    const previousRow =
      seenFileRemoteJids.get(
        draft.phone.remoteJid
      );

    if (
      previousRow
    ) {
      rows.push({
        rowNumber:
          draft.rowNumber,
        status:
          "SKIP",
        reasons: [
          `Telefone repetido no próprio CSV; primeira ocorrência na linha ${previousRow}.`
        ],
        source:
          draft.source,
        existingContact:
          null,
        contact: {
          createName:
            draft.createName,
          phoneNumber:
            draft.phone.phoneNumber,
          remoteJid:
            draft.phone.remoteJid,
          createEmail:
            draft.normalizedEmail,
          createNotes:
            draft.notes
        },
        customValues:
          draft.customValues,
        pipelineMoves:
          draft.pipelineMoves
      });

      continue;
    }

    seenFileRemoteJids.set(
      draft.phone.remoteJid,
      draft.rowNumber
    );

    const exact =
      byRemoteJid.get(
        draft.phone.remoteJid
      ) ??
      null;

    const phoneConflicts =
      (
        byPhone.get(
          draft.phone.phoneNumber
        ) ??
        []
      ).filter(
        contact =>
          contact.id !==
          exact?.id
      );

    const emailConflicts =
      draft.normalizedEmail
        ? (
            byEmail.get(
              draft.normalizedEmail
            ) ??
            []
          ).filter(
            contact =>
              contact.id !==
              exact?.id
          )
        : [];

    const reasons =
      [
        ...draft.reasons
      ];

    if (
      phoneConflicts.length >
      0
    ) {
      reasons.push(
        `O telefone já aparece em outro contato (${phoneConflicts[
          0
        ]?.name ?? "registro existente"}) com identidade WhatsApp diferente.`
      );
    }

    if (
      emailConflicts.length >
      0
    ) {
      reasons.push(
        `O e-mail já aparece em outro contato (${emailConflicts[
          0
        ]?.name ?? "registro existente"}).`
      );
    }

    const existingCustom =
      new Map(
        exact
          ?.customFieldValues
          .map(
            item => [
              item.fieldId,
              item.value ??
                ""
            ]
          ) ??
        []
      );

    const importedCustom =
      new Map(
        draft.customValues.map(
          item => [
            item.fieldId,
            item.value
          ]
        )
      );

    for (
      const field
      of context.fields
    ) {
      if (
        !field.required
      ) {
        continue;
      }

      const finalValue =
        importedCustom.has(
          field.id
        )
          ? importedCustom.get(
              field.id
            ) ??
            ""
          : existingCustom.get(
              field.id
            ) ??
            "";

      if (
        !finalValue.trim()
      ) {
        reasons.push(
          `O campo obrigatório “${field.label}” ficará vazio.`
        );
      }
    }

    let status:
      ImportRowStatus;

    if (
      phoneConflicts.length >
        0 ||
      emailConflicts.length >
        0
    ) {
      status =
        "CONFLICT";
    } else if (
      reasons.length >
      0
    ) {
      status =
        "INVALID";
    } else {
      status =
        exact
          ? "UPDATE"
          : "CREATE";
    }

    rows.push({
      rowNumber:
        draft.rowNumber,
      status,
      reasons,
      source:
        draft.source,
      existingContact:
        exact
          ? {
              id:
                exact.id,
              name:
                exact.name,
              phoneNumber:
                exact.phoneNumber,
              remoteJid:
                exact.remoteJid,
              email:
                exact.email
            }
          : null,
      contact: {
        createName:
          draft.createName,
        phoneNumber:
          draft.phone.phoneNumber,
        remoteJid:
          draft.phone.remoteJid,
        createEmail:
          draft.normalizedEmail,
        createNotes:
          draft.notes,
        ...(draft.hasNameMapping &&
        draft.mappedName
          ? {
              updateName:
                draft.mappedName
            }
          : {}),
        ...(draft.hasEmailMapping
          ? {
              updateEmail:
                draft.normalizedEmail
            }
          : {}),
        ...(draft.hasNotesMapping
          ? {
              updateNotes:
                draft.notes
            }
          : {})
      },
      customValues:
        draft.customValues,
      pipelineMoves:
        draft.pipelineMoves
    });
  }

  const withoutFingerprint = {
    headers:
      parsed.headers,
    delimiter:
      parsed.delimiter,
    rows,
    summary:
      mapSummary(
        rows
      )
  };

  return {
    ...withoutFingerprint,
    fingerprint:
      previewFingerprint(
        withoutFingerprint
      )
  };
}

export async function previewContactImport(input: {
  companyId:
    string;
  csv:
    string;
  mapping:
    ImportMapping;
  defaultCountryCode:
    string;
}) {
  return analyzeContactImport(
    input
  );
}

async function applyImportRow(input: {
  companyId:
    string;
  actorMembershipId:
    string;
  row:
    ImportPlanRow;
}) {
  if (
    !input.row.contact ||
    ![
      "CREATE",
      "UPDATE"
    ].includes(
      input.row.status
    )
  ) {
    throw new AppError(
      "Linha não elegível para importação.",
      422,
      "IMPORT_ROW_NOT_ELIGIBLE"
    );
  }

  const movedPipelines:
    string[] =
    [];

  const contact =
    await prisma.$transaction(
      async tx => {
        let current:
          {
            id:
              string;
          };

        if (
          input.row.status ===
          "CREATE"
        ) {
          current =
            await tx.contact.create({
              data: {
                companyId:
                  input.companyId,
                remoteJid:
                  input.row.contact!
                    .remoteJid,
                phoneNumber:
                  input.row.contact!
                    .phoneNumber,
                name:
                  input.row.contact!
                    .createName,
                email:
                  input.row.contact!
                    .createEmail,
                notes:
                  input.row.contact!
                    .createNotes,
                isGroup:
                  false
              },
              select: {
                id:
                  true
              }
            });
        } else {
          const existingId =
            input.row
              .existingContact
              ?.id;

          if (
            !existingId
          ) {
            throw new AppError(
              "Contato existente não foi resolvido.",
              409,
              "IMPORT_EXISTING_CONTACT_MISSING"
            );
          }

          const updateData:
            Prisma.ContactUpdateInput = {
              phoneNumber:
                input.row.contact!
                  .phoneNumber,
              ...(input.row.contact!
                .updateName !==
              undefined
                ? {
                    name:
                      input.row.contact!
                        .updateName
                  }
                : {}),
              ...(input.row.contact!
                .updateEmail !==
              undefined
                ? {
                    email:
                      input.row.contact!
                        .updateEmail
                  }
                : {}),
              ...(input.row.contact!
                .updateNotes !==
              undefined
                ? {
                    notes:
                      input.row.contact!
                        .updateNotes
                  }
                : {})
            };

          current =
            await tx.contact.update({
              where: {
                id:
                  existingId
              },
              data:
                updateData,
              select: {
                id:
                  true
              }
            });
        }

        for (
          const value
          of input.row.customValues
        ) {
          if (
            value.value.trim()
          ) {
            await tx.contactFieldValue.upsert({
              where: {
                contactId_fieldId: {
                  contactId:
                    current.id,
                  fieldId:
                    value.fieldId
                }
              },
              create: {
                contactId:
                  current.id,
                fieldId:
                  value.fieldId,
                value:
                  value.value.trim()
              },
              update: {
                value:
                  value.value.trim()
              }
            });
          } else {
            await tx.contactFieldValue.deleteMany({
              where: {
                contactId:
                  current.id,
                fieldId:
                  value.fieldId
              }
            });
          }
        }

        for (
          const move
          of input.row.pipelineMoves
        ) {
          const stage =
            await tx.crmStage.findFirst({
              where: {
                id:
                  move.stageId,
                pipelineId:
                  move.pipelineId,
                isActive:
                  true,
                pipeline: {
                  companyId:
                    input.companyId,
                  isActive:
                    true
                }
              },
              select: {
                id:
                  true
              }
            });

          if (
            !stage
          ) {
            throw new AppError(
              `${move.pipelineName}: a etapa mudou desde a prévia.`,
              409,
              "IMPORT_PIPELINE_CHANGED"
            );
          }

          const state =
            await tx.contactPipelineState.findUnique({
              where: {
                contactId_pipelineId: {
                  contactId:
                    current.id,
                  pipelineId:
                    move.pipelineId
                }
              }
            });

          if (
            state?.stageId ===
            move.stageId
          ) {
            continue;
          }

          const now =
            new Date();

          await tx.contactPipelineState.upsert({
            where: {
              contactId_pipelineId: {
                contactId:
                  current.id,
                pipelineId:
                  move.pipelineId
              }
            },
            create: {
              contactId:
                current.id,
              pipelineId:
                move.pipelineId,
              stageId:
                move.stageId,
              enteredAt:
                now,
              updatedByMembershipId:
                input.actorMembershipId
            },
            update: {
              stageId:
                move.stageId,
              enteredAt:
                now,
              updatedByMembershipId:
                input.actorMembershipId
            }
          });

          await tx.contactStageTransition.create({
            data: {
              companyId:
                input.companyId,
              contactId:
                current.id,
              pipelineId:
                move.pipelineId,
              fromStageId:
                state?.stageId ??
                null,
              toStageId:
                move.stageId,
              actorMembershipId:
                input.actorMembershipId
            }
          });

          movedPipelines.push(
            move.pipelineId
          );
        }

        return current;
      }
    );

  for (
    const pipelineId
    of movedPipelines
  ) {
    publishRealtime(
      input.companyId,
      {
        type:
          "contact.pipeline.updated",
        contactId:
          contact.id,
        pipelineId,
        membershipId:
          input.actorMembershipId
      }
    );
  }

  return contact;
}

export async function commitContactImport(input: {
  companyId:
    string;
  actorMembershipId:
    string;
  csv:
    string;
  mapping:
    ImportMapping;
  defaultCountryCode:
    string;
  fingerprint:
    string;
  mode:
    "CREATE_ONLY"
    | "CREATE_AND_UPDATE";
  includedRowNumbers:
    number[];
}) {
  const analysis =
    await analyzeContactImport({
      companyId:
        input.companyId,
      csv:
        input.csv,
      mapping:
        input.mapping,
      defaultCountryCode:
        input.defaultCountryCode
    });

  if (
    analysis.fingerprint !==
    input.fingerprint
  ) {
    throw new AppError(
      "A prévia mudou desde a confirmação. Revise o CSV novamente.",
      409,
      "IMPORT_PREVIEW_CHANGED"
    );
  }

  const included =
    new Set(
      input.includedRowNumbers
    );

  const candidates =
    analysis.rows.filter(
      row =>
        included.has(
          row.rowNumber
        )
    );

  if (
    candidates.length ===
    0
  ) {
    throw new AppError(
      "Selecione ao menos uma linha elegível.",
      422,
      "IMPORT_NO_ROWS_SELECTED"
    );
  }

  for (
    const row
    of candidates
  ) {
    const allowed =
      row.status ===
        "CREATE" ||
      (
        row.status ===
          "UPDATE" &&
        input.mode ===
          "CREATE_AND_UPDATE"
      );

    if (
      !allowed
    ) {
      throw new AppError(
        `A linha ${row.rowNumber} não está elegível no modo selecionado.`,
        422,
        "IMPORT_SELECTED_ROW_INVALID"
      );
    }
  }

  let created =
    0;
  let updated =
    0;
  let failed =
    0;

  const failures:
    Array<{
      rowNumber:
        number;
      message:
        string;
    }> =
    [];

  for (
    const row
    of candidates
  ) {
    try {
      await applyImportRow({
        companyId:
          input.companyId,
        actorMembershipId:
          input.actorMembershipId,
        row
      });

      if (
        row.status ===
        "CREATE"
      ) {
        created +=
          1;
      } else {
        updated +=
          1;
      }
    } catch (error) {
      failed +=
        1;

      failures.push({
        rowNumber:
          row.rowNumber,
        message:
          error instanceof
            Error
            ? error.message
            : "Falha inesperada."
      });
    }
  }

  return {
    fingerprint:
      analysis.fingerprint,
    requested:
      candidates.length,
    created,
    updated,
    failed,
    failures
  };
}

function duplicateKey(
  value:
    string
    | null
    | undefined
) {
  return value
    ?.trim()
    .toLocaleLowerCase(
      "pt-BR"
    ) ??
    "";
}

function duplicateGroups(
  contacts:
    Array<{
      id:
        string;
      name:
        string;
      phoneNumber:
        string
        | null;
      email:
        string
        | null;
      remoteJid:
        string;
    }>
) {
  const groups:
    Array<{
      kind:
        "PHONE"
        | "EMAIL";
      value:
        string;
      contacts:
        Array<{
          id:
            string;
          name:
            string;
          remoteJid:
            string;
        }>;
    }> =
    [];

  for (
    const kind
    of [
      "PHONE",
      "EMAIL"
    ] as const
  ) {
    const map =
      new Map<
        string,
        typeof contacts
      >();

    for (
      const contact
      of contacts
    ) {
      const raw =
        kind ===
          "PHONE"
          ? contact.phoneNumber
          : contact.email;

      const key =
        kind ===
          "PHONE"
          ? raw
              ?.replace(
                /\D/g,
                ""
              ) ??
            ""
          : duplicateKey(
              raw
            );

      if (
        !key
      ) {
        continue;
      }

      const list =
        map.get(
          key
        ) ??
        [];

      list.push(
        contact
      );

      map.set(
        key,
        list
      );
    }

    for (
      const [
        value,
        list
      ]
      of map.entries()
    ) {
      if (
        list.length <
        2
      ) {
        continue;
      }

      groups.push({
        kind,
        value,
        contacts:
          list.map(
            contact => ({
              id:
                contact.id,
              name:
                contact.name,
              remoteJid:
                contact.remoteJid
            })
          )
      });

      if (
        groups.length >=
        50
      ) {
        return groups;
      }
    }
  }

  return groups;
}

export async function getDataQualityContext(
  companyId:
    string
) {
  const [
    fields,
    pipelines,
    totalPeople,
    missingPhone,
    missingEmail,
    consentCount,
    scanContacts
  ] =
    await Promise.all([
      prisma.contactFieldDefinition.findMany({
        where: {
          companyId,
          isActive:
            true
        },
        select: {
          id:
            true,
          key:
            true,
          label:
            true,
          type:
            true,
          required:
            true,
          options:
            true,
          position:
            true
        },
        orderBy: {
          position:
            "asc"
        }
      }),
      prisma.crmPipeline.findMany({
        where: {
          companyId,
          isActive:
            true
        },
        select: {
          id:
            true,
          name:
            true,
          stages: {
            where: {
              isActive:
                true
            },
            select: {
              id:
                true,
              name:
                true,
              position:
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
      prisma.contact.count({
        where: {
          companyId,
          isGroup:
            false
        }
      }),
      prisma.contact.count({
        where: {
          companyId,
          isGroup:
            false,
          phoneNumber:
            null
        }
      }),
      prisma.contact.count({
        where: {
          companyId,
          isGroup:
            false,
          email:
            null
        }
      }),
      prisma.contactCampaignConsent.count({
        where: {
          companyId
        }
      }),
      prisma.contact.findMany({
        where: {
          companyId,
          isGroup:
            false
        },
        select: {
          id:
            true,
          name:
            true,
          phoneNumber:
            true,
          email:
            true,
          remoteJid:
            true
        },
        orderBy: {
          updatedAt:
            "desc"
        },
        take:
          MAX_EXPORT_ROWS
      })
    ]);

  return {
    fields,
    pipelines,
    summary: {
      totalPeople,
      missingPhone,
      missingEmail,
      unknownCampaignConsent:
        Math.max(
          0,
          totalPeople -
          consentCount
        ),
      scannedForDuplicates:
        scanContacts.length,
      duplicateGroups:
        duplicateGroups(
          scanContacts
        ).length
    },
    duplicates:
      duplicateGroups(
        scanContacts
      )
  };
}

export async function exportContactsCsv(input: {
  companyId:
    string;
  search?:
    string;
}) {
  const search =
    input.search
      ?.trim()
      .slice(
        0,
        100
      );

  const [
    fields,
    pipelines,
    contacts,
    total
  ] =
    await Promise.all([
      prisma.contactFieldDefinition.findMany({
        where: {
          companyId:
            input.companyId,
          isActive:
            true
        },
        select: {
          id:
            true,
          key:
            true,
          label:
            true
        },
        orderBy: {
          position:
            "asc"
        }
      }),
      prisma.crmPipeline.findMany({
        where: {
          companyId:
            input.companyId,
          isActive:
            true
        },
        select: {
          id:
            true,
          name:
            true
        },
        orderBy: {
          position:
            "asc"
        }
      }),
      prisma.contact.findMany({
        where: {
          companyId:
            input.companyId,
          isGroup:
            false,
          ...(search
            ? {
                OR: [
                  {
                    name: {
                      contains:
                        search
                    }
                  },
                  {
                    phoneNumber: {
                      contains:
                        search
                    }
                  },
                  {
                    email: {
                      contains:
                        search
                    }
                  }
                ]
              }
            : {})
        },
        select: {
          id:
            true,
          name:
            true,
          phoneNumber:
            true,
          remoteJid:
            true,
          email:
            true,
          notes:
            true,
          lastSeenAt:
            true,
          campaignConsent: {
            select: {
              status:
                true
            }
          },
          customFieldValues: {
            select: {
              fieldId:
                true,
              value:
                true
            }
          },
          pipelineStates: {
            select: {
              pipelineId:
                true,
              stage: {
                select: {
                  name:
                    true
                }
              }
            }
          }
        },
        orderBy: {
          name:
            "asc"
        },
        take:
          MAX_EXPORT_ROWS
      }),
      prisma.contact.count({
        where: {
          companyId:
            input.companyId,
          isGroup:
            false,
          ...(search
            ? {
                OR: [
                  {
                    name: {
                      contains:
                        search
                    }
                  },
                  {
                    phoneNumber: {
                      contains:
                        search
                    }
                  },
                  {
                    email: {
                      contains:
                        search
                    }
                  }
                ]
              }
            : {})
        }
      })
    ]);

  const headers =
    [
      "nome",
      "telefone",
      "email",
      "observacoes",
      "remote_jid",
      "ultima_interacao",
      "consentimento_campanhas",
      ...fields.map(
        field =>
          `custom:${field.key}`
      ),
      ...pipelines.map(
        pipeline =>
          `pipeline:${pipeline.name}`
      )
    ];

  const lines =
    [
      headers.map(
        csvCell
      ).join(
        ";"
      )
    ];

  for (
    const contact
    of contacts
  ) {
    const custom =
      new Map(
        contact.customFieldValues.map(
          value => [
            value.fieldId,
            value.value ??
              ""
          ]
        )
      );

    const states =
      new Map(
        contact.pipelineStates.map(
          state => [
            state.pipelineId,
            state.stage.name
          ]
        )
      );

    const values =
      [
        contact.name,
        contact.phoneNumber ??
          "",
        contact.email ??
          "",
        contact.notes ??
          "",
        contact.remoteJid,
        contact.lastSeenAt
          ?.toISOString() ??
          "",
        contact
          .campaignConsent
          ?.status ??
          "UNKNOWN",
        ...fields.map(
          field =>
            custom.get(
              field.id
            ) ??
            ""
        ),
        ...pipelines.map(
          pipeline =>
            states.get(
              pipeline.id
            ) ??
            ""
        )
      ];

    lines.push(
      values.map(
        csvCell
      ).join(
        ";"
      )
    );
  }

  const date =
    new Date()
      .toISOString()
      .slice(
        0,
        10
      );

  return {
    filename:
      `wapp-contatos-${date}.csv`,
    csv:
      lines.join(
        "\r\n"
      ),
    count:
      contacts.length,
    truncated:
      total >
      contacts.length
  };
}
EOF

cat > apps/api/src/modules/data-quality/data-quality.routes.ts <<'EOF'
import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  recordAudit
} from "../audit/audit.service.js";
import {
  requirePermission
} from "../auth/auth.guard.js";
import {
  commitContactImport,
  exportContactsCsv,
  getDataQualityContext,
  inspectContactImportCsv,
  previewContactImport
} from "./data-quality.service.js";
import {
  MAX_IMPORT_CSV_CHARS
} from "./data-quality.policy.js";

const csvSchema =
  z.string()
    .min(1)
    .max(
      MAX_IMPORT_CSV_CHARS
    );

const mappingSchema =
  z.record(
    z.string()
      .min(1)
      .max(190),
    z.string()
      .min(1)
      .max(100)
  );

const countryCodeSchema =
  z.string()
    .regex(
      /^\d{1,3}$/
    )
    .default(
      "55"
    );

const previewSchema =
  z.object({
    csv:
      csvSchema,
    mapping:
      mappingSchema,
    defaultCountryCode:
      countryCodeSchema
  });

const commitSchema =
  previewSchema.extend({
    fingerprint:
      z.string()
        .regex(
          /^[a-f0-9]{64}$/
        ),
    mode:
      z.enum([
        "CREATE_ONLY",
        "CREATE_AND_UPDATE"
      ]),
    includedRowNumbers:
      z.array(
        z.number()
          .int()
          .min(2)
          .max(502)
      )
        .min(1)
        .max(500)
        .refine(
          rows =>
            new Set(
              rows
            ).size ===
            rows.length,
          {
            message:
              "Linhas selecionadas não podem se repetir."
          }
        ),
    confirmation:
      z.literal(
        "IMPORTAR CONTATOS"
      )
  });

const inspectSchema =
  z.object({
    csv:
      csvSchema
  });

const exportSchema =
  z.object({
    search:
      z.string()
        .trim()
        .max(100)
        .optional()
  });

function requestMetadata(
  request: {
    id:
      string;
    ip:
      string;
    headers:
      Record<
        string,
        string
        | string[]
        | undefined
      >;
  }
) {
  const rawUserAgent =
    request.headers[
      "user-agent"
    ];

  return {
    requestId:
      request.id,
    ipAddress:
      request.ip,
    userAgent:
      Array.isArray(
        rawUserAgent
      )
        ? rawUserAgent[
            0
          ]
        : rawUserAgent
  };
}

export async function dataQualityRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/data-quality/context",
    async request => {
      const auth =
        await requirePermission(
          request,
          "dataQuality.read"
        );

      return getDataQualityContext(
        auth.companyId
      );
    }
  );

  app.post(
    "/api/v1/data-quality/import/inspect",
    async request => {
      await requirePermission(
        request,
        "dataQuality.manage"
      );

      const input =
        inspectSchema.parse(
          request.body
        );

      return inspectContactImportCsv(
        input.csv
      );
    }
  );

  app.post(
    "/api/v1/data-quality/import/preview",
    async request => {
      const auth =
        await requirePermission(
          request,
          "dataQuality.manage"
        );

      const input =
        previewSchema.parse(
          request.body
        );

      return previewContactImport({
        companyId:
          auth.companyId,
        ...input
      });
    }
  );

  app.post(
    "/api/v1/data-quality/import/commit",
    async request => {
      const auth =
        await requirePermission(
          request,
          "dataQuality.manage"
        );

      const input =
        commitSchema.parse(
          request.body
        );

      const {
        confirmation:
          _confirmation,
        ...commitInput
      } =
        input;

      const result =
        await commitContactImport({
          companyId:
            auth.companyId,
          actorMembershipId:
            auth.membershipId,
          ...commitInput
        });

      await recordAudit({
        companyId:
          auth.companyId,
        actorMembershipId:
          auth.membershipId,
        action:
          "CONTACT_IMPORT",
        entityType:
          "CONTACT_DATA",
        metadata: {
          fingerprint:
            result.fingerprint,
          mode:
            input.mode,
          requested:
            result.requested,
          created:
            result.created,
          updated:
            result.updated,
          failed:
            result.failed
        },
        ...requestMetadata(
          request
        )
      });

      return result;
    }
  );

  app.post(
    "/api/v1/data-quality/export",
    async request => {
      const auth =
        await requirePermission(
          request,
          "dataQuality.manage"
        );

      const input =
        exportSchema.parse(
          request.body ??
          {}
        );

      const result =
        await exportContactsCsv({
          companyId:
            auth.companyId,
          search:
            input.search
        });

      await recordAudit({
        companyId:
          auth.companyId,
        actorMembershipId:
          auth.membershipId,
        action:
          "CONTACT_EXPORT",
        entityType:
          "CONTACT_DATA",
        metadata: {
          count:
            result.count,
          truncated:
            result.truncated,
          search:
            input.search ??
            null
        },
        ...requestMetadata(
          request
        )
      });

      return result;
    }
  );
}
EOF

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
  'import { dataQualityRoutes } from "./modules/data-quality/data-quality.routes.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { campaignRoutes } from "./modules/campaigns/campaign.routes.js";';

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "campaignRoutes import anchor not found."
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
    "await app.register(dataQualityRoutes);"
  )
) {
  const anchor =
    "  await app.register(campaignRoutes);";

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "campaignRoutes registration anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  await app.register(dataQualityRoutes);`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/audit/audit.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const unionStart =
  content.indexOf(
    "export type AuditEntityType ="
  );

const unionEnd =
  content.indexOf(
    ";",
    unionStart
  );

if (
  unionStart <
    0 ||
  unionEnd <
    0
) {
  throw new Error(
    "AuditEntityType union not found."
  );
}

let union =
  content.slice(
    unionStart,
    unionEnd
  );

if (
  !union.includes(
    '"CONTACT_DATA"'
  )
) {
  union +=
    '\n  | "CONTACT_DATA"';
}

content =
  content.slice(
    0,
    unionStart
  ) +
  union +
  content.slice(
    unionEnd
  );

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.6] CONTACT_DATA audit entity installed."
);
NODE

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
  typeStart <
    0 ||
  typeEnd <
    0
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
    "dataQuality.read",
    "dataQuality.manage"
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
  const start =
    source.indexOf(
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

  const open =
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
      open;
    index <
      source.length;
    index +=
      1
  ) {
    const char =
      source[
        index
      ];

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
          end:
            index
        };
      }
    }
  }

  throw new Error(
    `${role} permission array end not found.`
  );
}

const wanted = {
  OWNER: [
    "dataQuality.read",
    "dataQuality.manage"
  ],
  ADMIN: [
    "dataQuality.read",
    "dataQuality.manage"
  ],
  SUPERVISOR: [
    "dataQuality.read",
    "dataQuality.manage"
  ],
  AGENT: []
};

for (
  const role
  of [
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

  const blockStart =
    content.lastIndexOf(
      `  ${role}: [`,
      bounds.end
    );

  const block =
    content.slice(
      blockStart,
      bounds.end +
        1
    );

  const missing =
    wanted[
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

  const before =
    content.slice(
      0,
      bounds.end
    ).replace(
      /\s+$/,
      ""
    );

  const after =
    content.slice(
      bounds.end
    );

  const separator =
    before.endsWith(
      ","
    )
      ? "\n"
      : ",\n";

  content =
    before +
    separator +
    missing
      .map(
        permission =>
          `    "${permission}"`
      )
      .join(
        ",\n"
      ) +
    "\n  " +
    after;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.6] Backend data-quality permissions installed."
);
NODE

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

const start =
  source.indexOf(
    "export type WappPermission ="
  );

const end =
  source.indexOf(
    ";",
    start
  );

const permissions =
  Array.from(
    source
      .slice(
        start,
        end
      )
      .matchAll(
        /"([^"]+)"/g
      ),
    match =>
      match[
        1
      ]
  );

const declarationStart =
  test.indexOf(
    "const allPermissions:"
  );

const describeStart =
  test.indexOf(
    "describe(",
    declarationStart
  );

if (
  declarationStart <
    0 ||
  describeStart <
    0
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
  .join(
    ",\n"
  )}
  ];

`;

test =
  test.slice(
    0,
    declarationStart
  ) +
  declaration +
  test.slice(
    describeStart
  );

if (
  !test.includes(
    '"contact data import/export is managerial only"'
  )
) {
  test += `

describe(
  "contact data quality permissions",
  () => {
    it(
      "contact data import/export is managerial only",
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
              "dataQuality.read"
            ),
            true
          );

          assert.equal(
            roleHasPermission(
              role,
              "dataQuality.manage"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "dataQuality.read"
          ),
          false
        );

        assert.equal(
          roleHasPermission(
            "AGENT",
            "dataQuality.manage"
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
  `[P3.6] permissions.test rebuilt with ${permissions.length} permissions.`
);
NODE

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
  typeStart <
    0 ||
  typeEnd <
    0
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
    "dataQuality.view",
    "dataQuality.manage"
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
  const start =
    source.indexOf(
      `  ${role}: [`
    );

  if (
    start <
    0
  ) {
    throw new Error(
      `${role} UI permission block not found.`
    );
  }

  const open =
    source.indexOf(
      "[",
      start
    );

  let depth =
    0;

  let quoted =
    false;

  let quote =
    "";

  let escape =
    false;

  for (
    let index =
      open;
    index <
      source.length;
    index +=
      1
  ) {
    const char =
      source[
        index
      ];

    if (
      quoted
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
        quoted =
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
      quoted =
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
          end:
            index
        };
      }
    }
  }

  throw new Error(
    `${role} UI permission array end not found.`
  );
}

const wanted = {
  OWNER: [
    "dataQuality.view",
    "dataQuality.manage"
  ],
  ADMIN: [
    "dataQuality.view",
    "dataQuality.manage"
  ],
  SUPERVISOR: [
    "dataQuality.view",
    "dataQuality.manage"
  ]
};

for (
  const role
  of [
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

  const blockStart =
    content.lastIndexOf(
      `  ${role}: [`,
      bounds.end
    );

  const block =
    content.slice(
      blockStart,
      bounds.end +
        1
    );

  const missing =
    wanted[
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

  const before =
    content.slice(
      0,
      bounds.end
    ).replace(
      /\s+$/,
      ""
    );

  const after =
    content.slice(
      bounds.end
    );

  content =
    before +
    (
      before.endsWith(
        ","
      )
        ? "\n"
        : ",\n"
    ) +
    missing
      .map(
        permission =>
          `    "${permission}"`
      )
      .join(
        ",\n"
      ) +
    "\n  " +
    after;
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "[P3.6] UI data-quality permissions installed."
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
    'href: "/dashboard/data-quality"'
  )
) {
  const anchor = `  {
    label: "Campanhas",
    href: "/dashboard/campaigns",
    permission: "campaigns.view"
  },`;

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Campaign navigation anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  {
    label: "Dados",
    href: "/dashboard/data-quality",
    permission: "dataQuality.view"
  },`
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > apps/web/app/dashboard/data-quality/page.tsx <<'EOF'
"use client";

import {
  type ChangeEvent,
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
import {
  roleCan
} from "@/lib/permissions";

type ImportStatus =
  | "CREATE"
  | "UPDATE"
  | "CONFLICT"
  | "INVALID"
  | "SKIP";

interface FieldDefinition {
  id: string;
  key: string;
  label: string;
  type: string;
  required: boolean;
  options: unknown;
}

interface Pipeline {
  id: string;
  name: string;
  stages:
    Array<{
      id: string;
      name: string;
      position: number;
    }>;
}

interface DuplicateGroup {
  kind:
    | "PHONE"
    | "EMAIL";
  value:
    string;
  contacts:
    Array<{
      id: string;
      name: string;
      remoteJid: string;
    }>;
}

interface ContextPayload {
  fields:
    FieldDefinition[];
  pipelines:
    Pipeline[];
  summary: {
    totalPeople: number;
    missingPhone: number;
    missingEmail: number;
    unknownCampaignConsent: number;
    scannedForDuplicates: number;
    duplicateGroups: number;
  };
  duplicates:
    DuplicateGroup[];
}

interface InspectPayload {
  delimiter: string;
  headers: string[];
  sample:
    Array<
      Record<
        string,
        string
      >
    >;
  rowCount: number;
}

interface PreviewRow {
  rowNumber: number;
  status:
    ImportStatus;
  reasons:
    string[];
  source:
    Record<
      string,
      string
    >;
  existingContact: {
    id: string;
    name: string;
    phoneNumber:
      | string
      | null;
    remoteJid: string;
    email:
      | string
      | null;
  } | null;
  contact: {
    createName: string;
    phoneNumber: string;
    remoteJid: string;
    createEmail:
      | string
      | null;
  } | null;
  customValues:
    Array<{
      fieldId: string;
      label: string;
      value: string;
    }>;
  pipelineMoves:
    Array<{
      pipelineId: string;
      pipelineName: string;
      stageId: string;
      stageName: string;
    }>;
}

interface PreviewPayload {
  headers: string[];
  delimiter: string;
  rows:
    PreviewRow[];
  summary: {
    total: number;
    create: number;
    update: number;
    conflict: number;
    invalid: number;
    skip: number;
  };
  fingerprint: string;
}

interface CommitPayload {
  requested: number;
  created: number;
  updated: number;
  failed: number;
  failures:
    Array<{
      rowNumber: number;
      message: string;
    }>;
}

function normalizedHeader(
  value:
    string
) {
  return value
    .normalize(
      "NFD"
    )
    .replace(
      /[\u0300-\u036f]/g,
      ""
    )
    .trim()
    .toLowerCase()
    .replace(
      /[^a-z0-9]+/g,
      "_"
    )
    .replace(
      /^_+|_+$/g,
      ""
    );
}

function autoTarget(
  header:
    string
) {
  const key =
    normalizedHeader(
      header
    );

  if (
    [
      "nome",
      "name",
      "cliente",
      "contato"
    ].includes(
      key
    )
  ) {
    return "name";
  }

  if (
    [
      "telefone",
      "phone",
      "celular",
      "whatsapp",
      "numero",
      "numero_whatsapp"
    ].includes(
      key
    )
  ) {
    return "phone";
  }

  if (
    [
      "email",
      "e_mail"
    ].includes(
      key
    )
  ) {
    return "email";
  }

  if (
    [
      "observacoes",
      "observacao",
      "notes",
      "nota",
      "anotacoes"
    ].includes(
      key
    )
  ) {
    return "notes";
  }

  return "IGNORE";
}

function statusLabel(
  status:
    ImportStatus
) {
  const labels:
    Record<
      ImportStatus,
      string
    > = {
      CREATE:
        "Criar",
      UPDATE:
        "Atualizar",
      CONFLICT:
        "Conflito",
      INVALID:
        "Inválido",
      SKIP:
        "Ignorar"
    };

  return labels[
    status
  ];
}

export default function DataQualityPage() {
  const router =
    useRouter();

  const {
    session,
    loading,
    request
  } =
    useAuth();

  const [
    context,
    setContext
  ] =
    useState<
      ContextPayload
      | null
    >(
      null
    );

  const [
    csv,
    setCsv
  ] =
    useState("");

  const [
    filename,
    setFilename
  ] =
    useState("");

  const [
    inspect,
    setInspect
  ] =
    useState<
      InspectPayload
      | null
    >(
      null
    );

  const [
    mapping,
    setMapping
  ] =
    useState<
      Record<
        string,
        string
      >
    >({});

  const [
    countryCode,
    setCountryCode
  ] =
    useState(
      "55"
    );

  const [
    preview,
    setPreview
  ] =
    useState<
      PreviewPayload
      | null
    >(
      null
    );

  const [
    selectedRows,
    setSelectedRows
  ] =
    useState<
      Set<
        number
      >
    >(
      new Set()
    );

  const [
    includeUpdates,
    setIncludeUpdates
  ] =
    useState(
      true
    );

  const [
    confirmation,
    setConfirmation
  ] =
    useState("");

  const [
    exportSearch,
    setExportSearch
  ] =
    useState("");

  const [
    busy,
    setBusy
  ] =
    useState(
      true
    );

  const [
    actionBusy,
    setActionBusy
  ] =
    useState(
      false
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

  const canManage =
    session
      ? roleCan(
          session.role,
          "dataQuality.manage"
        )
      : false;

  const loadContext =
    useCallback(
      async () => {
        const payload =
          await request<
            ContextPayload
          >(
            "/api/v1/data-quality/context"
          );

        setContext(
          payload
        );
      },
      [
        request
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
          "dataQuality.view"
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
        setBusy(
          true
        );

        void loadContext()
          .catch(() => {
            setError(
              "Não foi possível carregar a qualidade dos dados."
            );
          })
          .finally(() => {
            setBusy(
              false
            );
          });
      }
    },
    [
      loadContext,
      loading,
      router,
      session
    ]
  );

  const targetOptions =
    useMemo(
      () => {
        const options:
          Array<{
            value:
              string;
            label:
              string;
          }> = [
            {
              value:
                "IGNORE",
              label:
                "Ignorar coluna"
            },
            {
              value:
                "name",
              label:
                "Contato · Nome"
            },
            {
              value:
                "phone",
              label:
                "Contato · Telefone/WhatsApp"
            },
            {
              value:
                "email",
              label:
                "Contato · E-mail"
            },
            {
              value:
                "notes",
              label:
                "Contato · Observações"
            }
          ];

        for (
          const field
          of context
            ?.fields ??
          []
        ) {
          options.push({
            value:
              `custom:${field.id}`,
            label:
              `CRM · ${field.label}${field.required ? " *" : ""}`
          });
        }

        for (
          const pipeline
          of context
            ?.pipelines ??
          []
        ) {
          options.push({
            value:
              `pipeline:${pipeline.id}`,
            label:
              `Pipeline · ${pipeline.name}`
          });
        }

        return options;
      },
      [
        context
      ]
    );

  async function handleFile(
    event:
      ChangeEvent<
        HTMLInputElement
      >
  ) {
    const file =
      event.target
        .files?.[
          0
        ];

    if (
      !file
    ) {
      return;
    }

    setActionBusy(
      true
    );

    setError("");
    setNotice("");
    setPreview(
      null
    );
    setConfirmation("");

    try {
      const text =
        await file.text();

      const inspected =
        await request<
          InspectPayload
        >(
          "/api/v1/data-quality/import/inspect",
          {
            method:
              "POST",
            body:
              JSON.stringify({
                csv:
                  text
              })
          }
        );

      const auto:
        Record<
          string,
          string
        > =
        {};

      for (
        const header
        of inspected.headers
      ) {
        auto[
          header
        ] =
          autoTarget(
            header
          );
      }

      setCsv(
        text
      );

      setFilename(
        file.name
      );

      setInspect(
        inspected
      );

      setMapping(
        auto
      );

      setNotice(
        `${inspected.rowCount} linha(s) encontradas. Revise o mapeamento antes da prévia.`
      );
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível ler o CSV."
      );
    } finally {
      setActionBusy(
        false
      );

      event.target.value =
        "";
    }
  }

  async function runPreview() {
    if (
      !csv
    ) {
      return;
    }

    setActionBusy(
      true
    );
    setError("");
    setNotice("");
    setConfirmation("");

    try {
      const payload =
        await request<
          PreviewPayload
        >(
          "/api/v1/data-quality/import/preview",
          {
            method:
              "POST",
            body:
              JSON.stringify({
                csv,
                mapping,
                defaultCountryCode:
                  countryCode
              })
          }
        );

      setPreview(
        payload
      );

      setSelectedRows(
        new Set(
          payload.rows
            .filter(
              row =>
                row.status ===
                  "CREATE" ||
                (
                  includeUpdates &&
                  row.status ===
                    "UPDATE"
                )
            )
            .map(
              row =>
                row.rowNumber
            )
        )
      );
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível gerar a prévia."
      );
    } finally {
      setActionBusy(
        false
      );
    }
  }

  function toggleRow(
    row:
      PreviewRow
  ) {
    const eligible =
      row.status ===
        "CREATE" ||
      (
        includeUpdates &&
        row.status ===
          "UPDATE"
      );

    if (
      !eligible
    ) {
      return;
    }

    setSelectedRows(
      current => {
        const next =
          new Set(
            current
          );

        if (
          next.has(
            row.rowNumber
          )
        ) {
          next.delete(
            row.rowNumber
          );
        } else {
          next.add(
            row.rowNumber
          );
        }

        return next;
      }
    );
  }

  useEffect(
    () => {
      if (
        !preview
      ) {
        return;
      }

      setSelectedRows(
        current => {
          const next =
            new Set<
              number
            >();

          for (
            const row
            of preview.rows
          ) {
            if (
              row.status ===
              "CREATE"
            ) {
              if (
                current.has(
                  row.rowNumber
                ) ||
                current.size ===
                  0
              ) {
                next.add(
                  row.rowNumber
                );
              }
            }

            if (
              includeUpdates &&
              row.status ===
                "UPDATE"
            ) {
              if (
                current.has(
                  row.rowNumber
                ) ||
                current.size ===
                  0
              ) {
                next.add(
                  row.rowNumber
                );
              }
            }
          }

          return next;
        }
      );
    },
    [
      includeUpdates,
      preview
    ]
  );

  async function commitImport() {
    if (
      !preview ||
      confirmation !==
        "IMPORTAR CONTATOS"
    ) {
      return;
    }

    setActionBusy(
      true
    );
    setError("");
    setNotice("");

    try {
      const result =
        await request<
          CommitPayload
        >(
          "/api/v1/data-quality/import/commit",
          {
            method:
              "POST",
            body:
              JSON.stringify({
                csv,
                mapping,
                defaultCountryCode:
                  countryCode,
                fingerprint:
                  preview.fingerprint,
                mode:
                  includeUpdates
                    ? "CREATE_AND_UPDATE"
                    : "CREATE_ONLY",
                includedRowNumbers:
                  Array.from(
                    selectedRows
                  ).sort(
                    (
                      left,
                      right
                    ) =>
                      left -
                      right
                  ),
                confirmation:
                  "IMPORTAR CONTATOS"
              })
          }
        );

      const completionNotice =
        `Importação concluída: ${result.created} criado(s), ${result.updated} atualizado(s), ${result.failed} falha(s).`;

      setConfirmation("");

      await loadContext();

      await runPreview();

      setNotice(
        completionNotice
      );
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível concluir a importação."
      );
    } finally {
      setActionBusy(
        false
      );
    }
  }

  async function exportContacts() {
    setActionBusy(
      true
    );

    setError("");
    setNotice("");

    try {
      const result =
        await request<{
          filename:
            string;
          csv:
            string;
          count:
            number;
          truncated:
            boolean;
        }>(
          "/api/v1/data-quality/export",
          {
            method:
              "POST",
            body:
              JSON.stringify({
                search:
                  exportSearch
                    .trim() ||
                  undefined
              })
          }
        );

      const blob =
        new Blob(
          [
            "\uFEFF",
            result.csv
          ],
          {
            type:
              "text/csv;charset=utf-8"
          }
        );

      const url =
        URL.createObjectURL(
          blob
        );

      const anchor =
        document.createElement(
          "a"
        );

      anchor.href =
        url;

      anchor.download =
        result.filename;

      document.body.appendChild(
        anchor
      );

      anchor.click();
      anchor.remove();

      URL.revokeObjectURL(
        url
      );

      setNotice(
        result.truncated
          ? `Exportados ${result.count} contatos. O resultado foi limitado a 5.000 registros.`
          : `Exportados ${result.count} contatos.`
      );
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível exportar os contatos."
      );
    } finally {
      setActionBusy(
        false
      );
    }
  }

  if (
    loading ||
    !session ||
    busy
  ) {
    return (
      <main className="dashboard-loading">
        Carregando dados…
      </main>
    );
  }

  return (
    <main className="data-quality-screen">
      <header className="data-quality-header">
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
            Qualidade de dados
          </h1>

          <p>
            Importe, revise duplicidades e exporte contatos sem contornar as regras do CRM.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              "/dashboard/contacts"
            )
          }
          type="button"
        >
          Ver contatos
        </button>
      </header>

      {error && (
        <div className="data-quality-feedback data-quality-feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="data-quality-feedback">
          {notice}
        </div>
      )}

      <section className="data-quality-summary">
        <article>
          <span>
            Contatos
          </span>
          <strong>
            {context?.summary.totalPeople ??
              0}
          </strong>
        </article>

        <article>
          <span>
            Sem telefone
          </span>
          <strong>
            {context?.summary.missingPhone ??
              0}
          </strong>
        </article>

        <article>
          <span>
            Sem e-mail
          </span>
          <strong>
            {context?.summary.missingEmail ??
              0}
          </strong>
        </article>

        <article>
          <span>
            Consentimento não informado
          </span>
          <strong>
            {context?.summary.unknownCampaignConsent ??
              0}
          </strong>
        </article>

        <article>
          <span>
            Grupos de duplicidade
          </span>
          <strong>
            {context?.summary.duplicateGroups ??
              0}
          </strong>
        </article>
      </section>

      <section className="data-quality-layout">
        <section className="data-quality-panel">
          <header>
            <div>
              <span className="eyebrow">
                Importação
              </span>

              <h2>
                CSV com prévia obrigatória
              </h2>

              <p>
                Até 500 linhas por lote. Telefone é obrigatório e vira a identidade WhatsApp canônica.
              </p>
            </div>
          </header>

          <div className="data-quality-import-controls">
            <label className="data-quality-file">
              <span>
                Arquivo CSV
              </span>

              <input
                accept=".csv,text/csv"
                disabled={
                  !canManage ||
                  actionBusy
                }
                onChange={
                  handleFile
                }
                type="file"
              />

              <small>
                {filename ||
                  "Nenhum arquivo selecionado"}
              </small>
            </label>

            <label>
              <span>
                Código do país
              </span>

              <input
                inputMode="numeric"
                maxLength={
                  3
                }
                onChange={
                  event =>
                    setCountryCode(
                      event.target.value.replace(
                        /\D/g,
                        ""
                      )
                    )
                }
                value={
                  countryCode
                }
              />

              <small>
                Números locais de 10/11 dígitos usam este DDI. Brasil: 55.
              </small>
            </label>
          </div>

          {inspect && (
            <section className="data-quality-mapping">
              <header>
                <strong>
                  Mapeamento
                </strong>

                <span>
                  {inspect.rowCount} linha(s) · delimitador {inspect.delimiter === "\t" ? "TAB" : inspect.delimiter}
                </span>
              </header>

              <div className="data-quality-mapping__rows">
                {inspect.headers.map(
                  header => (
                    <label
                      key={
                        header
                      }
                    >
                      <span>
                        {header}
                      </span>

                      <select
                        onChange={
                          event => {
                            setMapping(
                              current => ({
                                ...current,
                                [header]:
                                  event.target.value
                              })
                            );

                            setPreview(
                              null
                            );
                          }
                        }
                        value={
                          mapping[
                            header
                          ] ??
                          "IGNORE"
                        }
                      >
                        {targetOptions.map(
                          option => (
                            <option
                              key={
                                option.value
                              }
                              value={
                                option.value
                              }
                            >
                              {option.label}
                            </option>
                          )
                        )}
                      </select>
                    </label>
                  )
                )}
              </div>

              <div className="data-quality-mapping__note">
                Consentimento de campanhas não é um destino de importação. O CSV nunca cria autorização de disparo.
              </div>

              <button
                className="primary-button"
                disabled={
                  actionBusy
                }
                onClick={() =>
                  void runPreview()
                }
                type="button"
              >
                <span>
                  Gerar prévia
                </span>
              </button>
            </section>
          )}

          {preview && (
            <section className="data-quality-preview">
              <div className="data-quality-preview__summary">
                <article>
                  <span>
                    Criar
                  </span>
                  <strong>
                    {preview.summary.create}
                  </strong>
                </article>

                <article>
                  <span>
                    Atualizar
                  </span>
                  <strong>
                    {preview.summary.update}
                  </strong>
                </article>

                <article>
                  <span>
                    Conflitos
                  </span>
                  <strong>
                    {preview.summary.conflict}
                  </strong>
                </article>

                <article>
                  <span>
                    Inválidos
                  </span>
                  <strong>
                    {preview.summary.invalid}
                  </strong>
                </article>

                <article>
                  <span>
                    Ignorar
                  </span>
                  <strong>
                    {preview.summary.skip}
                  </strong>
                </article>
              </div>

              <label className="data-quality-update-toggle">
                <input
                  checked={
                    includeUpdates
                  }
                  onChange={
                    event =>
                      setIncludeUpdates(
                        event.target.checked
                      )
                  }
                  type="checkbox"
                />

                Permitir atualização dos contatos que já existem
              </label>

              <div className="data-quality-preview__table">
                <table>
                  <thead>
                    <tr>
                      <th>
                        Usar
                      </th>
                      <th>
                        Linha
                      </th>
                      <th>
                        Resultado
                      </th>
                      <th>
                        Nome
                      </th>
                      <th>
                        Telefone
                      </th>
                      <th>
                        Revisão
                      </th>
                    </tr>
                  </thead>

                  <tbody>
                    {preview.rows
                      .slice(
                        0,
                        150
                      )
                      .map(
                        row => {
                          const eligible =
                            row.status ===
                              "CREATE" ||
                            (
                              includeUpdates &&
                              row.status ===
                                "UPDATE"
                            );

                          return (
                            <tr
                              key={
                                row.rowNumber
                              }
                            >
                              <td>
                                <input
                                  checked={
                                    selectedRows.has(
                                      row.rowNumber
                                    )
                                  }
                                  disabled={
                                    !eligible
                                  }
                                  onChange={() =>
                                    toggleRow(
                                      row
                                    )
                                  }
                                  type="checkbox"
                                />
                              </td>

                              <td>
                                {row.rowNumber}
                              </td>

                              <td>
                                <span
                                  className={`data-quality-status data-quality-status--${row.status.toLowerCase()}`}
                                >
                                  {statusLabel(
                                    row.status
                                  )}
                                </span>
                              </td>

                              <td>
                                {row.contact
                                  ?.createName ??
                                  "—"}
                              </td>

                              <td>
                                {row.contact
                                  ?.phoneNumber ??
                                  "—"}
                              </td>

                              <td>
                                {row.reasons.length >
                                0
                                  ? row.reasons.join(
                                      " "
                                    )
                                  : row.existingContact
                                    ? `Existe: ${row.existingContact.name}`
                                    : "Pronto para criar"}
                              </td>
                            </tr>
                          );
                        }
                      )}
                  </tbody>
                </table>
              </div>

              {preview.rows.length >
                150 && (
                <small className="data-quality-preview__limit">
                  A tabela mostra as primeiras 150 linhas; todas as linhas elegíveis continuam no lote.
                </small>
              )}

              <div className="data-quality-confirm">
                <label>
                  <span>
                    Confirmação
                  </span>

                  <input
                    onChange={
                      event =>
                        setConfirmation(
                          event.target.value
                        )
                    }
                    placeholder="IMPORTAR CONTATOS"
                    value={
                      confirmation
                    }
                  />
                </label>

                <button
                  className="primary-button"
                  disabled={
                    actionBusy ||
                    selectedRows.size ===
                      0 ||
                    confirmation !==
                      "IMPORTAR CONTATOS"
                  }
                  onClick={() =>
                    void commitImport()
                  }
                  type="button"
                >
                  <span>
                    Importar {selectedRows.size} linha(s)
                  </span>
                </button>
              </div>
            </section>
          )}
        </section>

        <aside className="data-quality-side">
          <section className="data-quality-panel">
            <header>
              <span className="eyebrow">
                Exportação
              </span>

              <h2>
                CSV seguro
              </h2>

              <p>
                Inclui campos CRM, pipeline e situação de consentimento. Fórmulas de planilha são neutralizadas.
              </p>
            </header>

            <label className="data-quality-export-search">
              <span>
                Filtrar antes de exportar
              </span>

              <input
                onChange={
                  event =>
                    setExportSearch(
                      event.target.value
                    )
                }
                placeholder="Nome, telefone ou e-mail"
                value={
                  exportSearch
                }
              />
            </label>

            <button
              className="ghost-button"
              disabled={
                !canManage ||
                actionBusy
              }
              onClick={() =>
                void exportContacts()
              }
              type="button"
            >
              Exportar contatos
            </button>

            <small>
              Limite inicial: 5.000 contatos por exportação.
            </small>
          </section>

          <section className="data-quality-panel">
            <header>
              <span className="eyebrow">
                Duplicidades
              </span>

              <h2>
                Revisão manual
              </h2>

              <p>
                O Wapp apenas sinaliza possíveis duplicidades. Nenhum contato é mesclado automaticamente.
              </p>
            </header>

            <div className="data-quality-duplicates">
              {(context
                ?.duplicates ??
                []).map(
                (
                  group,
                  index
                ) => (
                  <article
                    key={`${group.kind}:${group.value}:${index}`}
                  >
                    <div>
                      <span>
                        {group.kind ===
                          "PHONE"
                          ? "Telefone"
                          : "E-mail"}
                      </span>

                      <strong>
                        {group.value}
                      </strong>
                    </div>

                    <ul>
                      {group.contacts.map(
                        contact => (
                          <li
                            key={
                              contact.id
                            }
                          >
                            <button
                              onClick={() =>
                                router.push(
                                  `/dashboard/contacts?contact=${contact.id}`
                                )
                              }
                              type="button"
                            >
                              {contact.name}
                            </button>
                          </li>
                        )
                      )}
                    </ul>
                  </article>
                )
              )}

              {(context
                ?.duplicates
                .length ??
                0) ===
                0 && (
                <p className="data-quality-empty">
                  Nenhuma duplicidade potencial encontrada na varredura atual.
                </p>
              )}
            </div>

            <small>
              Varredura atual: até {context?.summary.scannedForDuplicates ?? 0} contatos.
            </small>
          </section>
        </aside>
      </section>
    </main>
  );
}
EOF

if ! grep -Fq -- "WAPP P3.6 / DATA QUALITY" "$CSS"; then
cat >> "$CSS" <<'EOF'

/* --- WAPP P3.6 / DATA QUALITY --------------------------------------- */

.data-quality-screen {
  min-height: 100vh;
  overflow-x: hidden;
  background: var(--surface-subtle);
  padding: 32px clamp(18px, 4vw, 56px) 56px;
}

.data-quality-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 20px;
}

.data-quality-header h1 {
  margin: 6px 0 5px;
  font-size: clamp(32px, 4vw, 48px);
  letter-spacing: -0.05em;
}

.data-quality-header p {
  max-width: 720px;
  margin: 0;
  color: var(--muted);
  font-size: 10px;
  line-height: 1.5;
}

.data-quality-feedback {
  margin-top: 12px;
  border-radius: 9px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 9px 10px;
  font-size: 8px;
}

.data-quality-feedback--error {
  background: rgba(163, 59, 50, 0.07);
  color: #973a32;
}

.data-quality-summary {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 8px;
  margin-top: 14px;
}

.data-quality-summary article {
  display: grid;
  gap: 5px;
  min-height: 78px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: white;
  padding: 11px 12px;
}

.data-quality-summary span {
  color: var(--muted);
  font-size: 7px;
}

.data-quality-summary strong {
  font-size: 21px;
  letter-spacing: -0.04em;
}

.data-quality-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(280px, .6fr);
  gap: 10px;
  align-items: start;
  margin-top: 10px;
}

.data-quality-side {
  display: grid;
  gap: 10px;
}

.data-quality-panel {
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
}

.data-quality-panel > header {
  border-bottom: 1px solid var(--line);
  padding: 12px 13px;
}

.data-quality-panel > header h2 {
  margin: 3px 0 4px;
  font-size: 15px;
  letter-spacing: -0.025em;
}

.data-quality-panel > header p {
  max-width: 650px;
  margin: 0;
  color: var(--muted);
  font-size: 7px;
  line-height: 1.5;
}

.data-quality-import-controls {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 150px;
  gap: 8px;
  border-bottom: 1px solid var(--line);
  padding: 11px 12px;
}

.data-quality-import-controls label,
.data-quality-export-search,
.data-quality-confirm label {
  display: grid;
  gap: 4px;
}

.data-quality-import-controls label > span,
.data-quality-export-search > span,
.data-quality-confirm label > span {
  color: var(--muted);
  font-size: 7px;
  font-weight: 760;
}

.data-quality-import-controls input,
.data-quality-export-search input,
.data-quality-confirm input,
.data-quality-mapping select {
  width: 100%;
  min-height: 37px;
  border: 1px solid var(--line);
  border-radius: 8px;
  outline: 0;
  background: white;
  padding: 7px 8px;
  color: var(--ink);
  font: inherit;
  font-size: 8px;
}

.data-quality-import-controls small,
.data-quality-panel > small {
  color: var(--muted);
  font-size: 6px;
  line-height: 1.45;
}

.data-quality-file input {
  padding: 5px 7px;
}

.data-quality-mapping {
  border-bottom: 1px solid var(--line);
  padding: 11px 12px;
}

.data-quality-mapping > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 8px;
}

.data-quality-mapping > header strong {
  font-size: 9px;
}

.data-quality-mapping > header span {
  color: var(--muted);
  font-size: 7px;
}

.data-quality-mapping__rows {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 6px;
}

.data-quality-mapping__rows label {
  display: grid;
  grid-template-columns: minmax(100px, .7fr) minmax(0, 1.3fr);
  align-items: center;
  gap: 8px;
  border: 1px solid #edf0ed;
  border-radius: 8px;
  padding: 6px;
}

.data-quality-mapping__rows label > span {
  overflow: hidden;
  color: #505b55;
  font-size: 7px;
  font-weight: 740;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.data-quality-mapping__note {
  margin: 9px 0;
  border-radius: 8px;
  background: #f7faf8;
  color: #59635d;
  padding: 8px 9px;
  font-size: 7px;
  line-height: 1.45;
}

.data-quality-preview {
  padding: 11px 12px;
}

.data-quality-preview__summary {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 9px;
}

.data-quality-preview__summary article {
  display: grid;
  gap: 2px;
  border-right: 1px solid var(--line);
  background: #fafbfa;
  padding: 8px;
}

.data-quality-preview__summary article:last-child {
  border-right: 0;
}

.data-quality-preview__summary span {
  color: var(--muted);
  font-size: 6px;
}

.data-quality-preview__summary strong {
  font-size: 14px;
}

.data-quality-update-toggle {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 10px 0;
  color: #59635d;
  font-size: 7px;
}

.data-quality-preview__table {
  overflow: auto;
  max-height: 480px;
  border: 1px solid var(--line);
  border-radius: 9px;
}

.data-quality-preview__table table {
  width: 100%;
  min-width: 760px;
  border-collapse: collapse;
}

.data-quality-preview__table th,
.data-quality-preview__table td {
  border-bottom: 1px solid #edf0ed;
  padding: 7px 8px;
  font-size: 7px;
  text-align: left;
  vertical-align: top;
}

.data-quality-preview__table th {
  position: sticky;
  top: 0;
  z-index: 1;
  background: #f8faf8;
  color: var(--muted);
  font-size: 6px;
  text-transform: uppercase;
  letter-spacing: .04em;
}

.data-quality-preview__table td:last-child {
  max-width: 300px;
  color: var(--muted);
  line-height: 1.4;
}

.data-quality-status {
  display: inline-flex;
  border-radius: 999px;
  background: #eff2f0;
  padding: 4px 6px;
  color: #616b65;
  font-size: 6px;
  font-weight: 800;
}

.data-quality-status--create {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.data-quality-status--update {
  background: #eef3f8;
  color: #3b6482;
}

.data-quality-status--conflict,
.data-quality-status--invalid {
  background: rgba(163, 59, 50, .08);
  color: #973a32;
}

.data-quality-preview__limit {
  display: block;
  margin-top: 6px;
  color: var(--muted);
  font-size: 6px;
}

.data-quality-confirm {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: end;
  gap: 8px;
  margin-top: 10px;
  border-top: 1px solid var(--line);
  padding-top: 10px;
}

.data-quality-side .data-quality-panel {
  padding-bottom: 12px;
}

.data-quality-side .data-quality-panel > .ghost-button,
.data-quality-side .data-quality-panel > small,
.data-quality-export-search {
  margin-right: 12px;
  margin-left: 12px;
}

.data-quality-export-search {
  margin-top: 11px;
  margin-bottom: 8px;
}

.data-quality-duplicates {
  display: grid;
  gap: 6px;
  max-height: 460px;
  overflow-y: auto;
  padding: 10px 12px;
}

.data-quality-duplicates article {
  border: 1px solid #edf0ed;
  border-radius: 9px;
  padding: 8px;
}

.data-quality-duplicates article > div {
  display: grid;
  gap: 2px;
}

.data-quality-duplicates article span {
  color: var(--muted);
  font-size: 6px;
  text-transform: uppercase;
}

.data-quality-duplicates article strong {
  overflow-wrap: anywhere;
  font-size: 8px;
}

.data-quality-duplicates ul {
  display: grid;
  gap: 3px;
  margin: 7px 0 0;
  padding: 0;
  list-style: none;
}

.data-quality-duplicates button {
  border: 0;
  background: transparent;
  color: var(--accent-dark);
  padding: 0;
  font-size: 7px;
  text-align: left;
  cursor: pointer;
}

.data-quality-empty {
  margin: 0;
  color: var(--muted);
  font-size: 7px;
  line-height: 1.45;
}

@media (max-width: 1100px) {
  .data-quality-summary {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  .data-quality-layout {
    grid-template-columns: 1fr;
  }

  .data-quality-side {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 760px) {
  .data-quality-screen {
    min-height: 100dvh;
    padding: 20px 12px
      calc(82px + env(safe-area-inset-bottom, 0px));
  }

  .data-quality-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .data-quality-summary {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .data-quality-import-controls,
  .data-quality-mapping__rows,
  .data-quality-confirm,
  .data-quality-side {
    grid-template-columns: 1fr;
  }

  .data-quality-mapping__rows label {
    grid-template-columns: 1fr;
  }

  .data-quality-preview__summary {
    grid-template-columns: repeat(2, 1fr);
  }

  .data-quality-import-controls input,
  .data-quality-export-search input,
  .data-quality-confirm input,
  .data-quality-mapping select {
    min-height: 42px;
    font-size: 16px;
  }

  .data-quality-confirm .primary-button {
    width: 100%;
  }
}

/* --- /WAPP P3.6 ----------------------------------------------------- */
EOF
fi

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
  "src/modules/data-quality/data-quality.policy.test.ts";

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

cat > apps/api/src/integration/data-quality.integration.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  randomUUID
} from "node:crypto";
import {
  after,
  before,
  test
} from "node:test";

import type {
  FastifyInstance
} from "fastify";

import {
  buildApp
} from "../app.js";
import {
  prisma
} from "../lib/database.js";
import {
  hashPassword
} from "../lib/password.js";

const EMAIL =
  "data-quality.integration@wapp.test";

const PASSWORD =
  "IntegrationPassword!123";

const COMPANY_SLUG =
  "data-quality-integration";

let app:
  FastifyInstance;

let companyId =
  "";

async function login() {
  const response =
    await app.inject({
      method:
        "POST",
      url:
        "/api/v1/auth/login",
      payload: {
        email:
          EMAIL,
        password:
          PASSWORD,
        companySlug:
          COMPANY_SLUG
      }
    });

  assert.equal(
    response.statusCode,
    200,
    response.body
  );

  return response.json<{
    accessToken:
      string;
  }>();
}

before(async () => {
  const passwordHash =
    await hashPassword(
      PASSWORD
    );

  const company =
    await prisma.company.create({
      data: {
        name:
          "Data Quality Integration",
        slug:
          COMPANY_SLUG
      }
    });

  companyId =
    company.id;

  const user =
    await prisma.user.create({
      data: {
        name:
          "Data Quality Owner",
        email:
          EMAIL,
        passwordHash
      }
    });

  await prisma.companyMembership.create({
    data: {
      companyId:
        company.id,
      userId:
        user.id,
      role:
        "OWNER"
    }
  });

  await prisma.whatsAppConnection.create({
    data: {
      companyId:
        company.id,
      name:
        "Data Quality fixture",
      instanceName:
        `dq-${randomUUID()}`,
      provider:
        "META_CLOUD",
      status:
        "CONNECTED"
    }
  });

  app =
    await buildApp();

  await app.ready();
});

after(async () => {
  if (
    app
  ) {
    await app.close();
  }
});

test(
  "P3.6 CSV preview/commit maps CRM and pipeline without campaign opt-in",
  async () => {
    const {
      accessToken
    } =
      await login();

    const headers = {
      authorization:
        `Bearer ${accessToken}`
    };

    const fieldResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/contact-crm/fields",
        headers,
        payload: {
          label:
            "Origem importação",
          type:
            "TEXT",
          required:
            false
        }
      });

    assert.equal(
      fieldResponse.statusCode,
      201,
      fieldResponse.body
    );

    const field =
      fieldResponse.json<{
        field: {
          id:
            string;
        };
      }>().field;

    const pipelineResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/pipelines",
        headers,
        payload: {
          name:
            "Pipeline importação",
          stages: [
            "Novo",
            "Qualificado"
          ]
        }
      });

    assert.equal(
      pipelineResponse.statusCode,
      201,
      pipelineResponse.body
    );

    const pipeline =
      pipelineResponse.json<{
        pipeline: {
          id:
            string;
          stages:
            Array<{
              id:
                string;
            }>;
        };
      }>().pipeline;

    const csv =
      "nome;telefone;email;origem;etapa\n" +
      "Contato Importado;11988887777;importado@example.com;CSV;Qualificado\n";

    const mapping = {
      nome:
        "name",
      telefone:
        "phone",
      email:
        "email",
      origem:
        `custom:${field.id}`,
      etapa:
        `pipeline:${pipeline.id}`
    };

    const previewResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/data-quality/import/preview",
        headers,
        payload: {
          csv,
          mapping,
          defaultCountryCode:
            "55"
        }
      });

    assert.equal(
      previewResponse.statusCode,
      200,
      previewResponse.body
    );

    const preview =
      previewResponse.json<{
        fingerprint:
          string;
        summary: {
          create:
            number;
          update:
            number;
          conflict:
            number;
          invalid:
            number;
        };
        rows:
          Array<{
            rowNumber:
              number;
            status:
              string;
          }>;
      }>();

    assert.equal(
      preview.summary.create,
      1
    );

    assert.equal(
      preview.summary.update,
      0
    );

    assert.equal(
      preview.summary.conflict,
      0
    );

    assert.equal(
      preview.summary.invalid,
      0
    );

    const rowNumber =
      preview.rows[
        0
      ]!.rowNumber;

    const commitResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/data-quality/import/commit",
        headers,
        payload: {
          csv,
          mapping,
          defaultCountryCode:
            "55",
          fingerprint:
            preview.fingerprint,
          mode:
            "CREATE_AND_UPDATE",
          includedRowNumbers: [
            rowNumber
          ],
          confirmation:
            "IMPORTAR CONTATOS"
        }
      });

    assert.equal(
      commitResponse.statusCode,
      200,
      commitResponse.body
    );

    const commit =
      commitResponse.json<{
        created:
          number;
        updated:
          number;
        failed:
          number;
      }>();

    assert.equal(
      commit.created,
      1
    );

    assert.equal(
      commit.updated,
      0
    );

    assert.equal(
      commit.failed,
      0
    );

    const contact =
      await prisma.contact.findUniqueOrThrow({
        where: {
          companyId_remoteJid: {
            companyId,
            remoteJid:
              "5511988887777@s.whatsapp.net"
          }
        },
        include: {
          campaignConsent:
            true,
          customFieldValues:
            true,
          pipelineStates:
            true
        }
      });

    assert.equal(
      contact.name,
      "Contato Importado"
    );

    assert.equal(
      contact.campaignConsent,
      null,
      "CSV import must never create campaign consent."
    );

    assert.equal(
      contact.customFieldValues[
        0
      ]?.value,
      "CSV"
    );

    assert.equal(
      contact.pipelineStates[
        0
      ]?.stageId,
      pipeline.stages[
        1
      ]?.id
    );

    const previewAgain =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/data-quality/import/preview",
        headers,
        payload: {
          csv,
          mapping,
          defaultCountryCode:
            "55"
        }
      });

    assert.equal(
      previewAgain.statusCode,
      200,
      previewAgain.body
    );

    assert.equal(
      previewAgain.json<{
        summary: {
          update:
            number;
        };
      }>().summary.update,
      1
    );

    await prisma.contact.create({
      data: {
        companyId,
        remoteJid:
          "5511977776666@s.whatsapp.net",
        phoneNumber:
          "5511977776666",
        name:
          "=SUM(1,1)"
      }
    });

    const exportResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/data-quality/export",
        headers,
        payload: {}
      });

    assert.equal(
      exportResponse.statusCode,
      200,
      exportResponse.body
    );

    const exported =
      exportResponse.json<{
        csv:
          string;
      }>().csv;

    assert.match(
      exported,
      /custom:origem_importacao/
    );

    assert.match(
      exported,
      /pipeline:Pipeline importação/
    );

    assert.match(
      exported,
      /'=SUM\(1,1\)/
    );
  }
);
EOF

node <<'NODE'
const fs = require("node:fs");

const path =
  "scripts/test-integration.sh";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const oldBlock = `pnpm --filter @wapp/api exec \\
  tsx --test \\
  src/integration/critical.integration.test.ts`;

const newBlock = `pnpm --filter @wapp/api exec \\
  tsx --test \\
  --test-concurrency=1 \\
  src/integration/critical.integration.test.ts \\
  src/integration/data-quality.integration.test.ts`;

if (
  content.includes(
    oldBlock
  )
) {
  content =
    content.replace(
      oldBlock,
      newBlock
    );
} else if (
  !content.includes(
    "src/integration/data-quality.integration.test.ts"
  )
) {
  throw new Error(
    "Integration test command anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);
NODE

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/audit/audit.service.ts";

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
    'case "CONTACT_DATA":'
  )
) {
  const anchor = `    case "AUTOMATION_RULE":
      return prisma.automationRule.findFirst({`;

  const index =
    content.indexOf(
      anchor
    );

  if (
    index <
    0
  ) {
    throw new Error(
      "AUTOMATION_RULE audit switch anchor not found."
    );
  }

  const caseBlock = `    case "CONTACT_DATA":
      return null;

`;

  content =
    content.slice(
      0,
      index
    ) +
    caseBlock +
    content.slice(
      index
    );
}

fs.writeFileSync(
  path,
  content
);
NODE

cat > docs/P3_06_DATA_QUALITY.md <<'EOF'
# P3.6 Import/export and data quality

P3.6 closes the functional P3 roadmap with safe CSV workflows.

No database migration is introduced by this milestone.

## Import safety model

Import is a two-step process:

1. preview;
2. explicit commit.

The preview classifies every CSV row as:

- `CREATE`;
- `UPDATE`;
- `CONFLICT`;
- `INVALID`;
- `SKIP`.

The server returns a SHA-256 fingerprint derived from the resolved plan,
including row status and the currently matched contact IDs.

Commit recomputes the plan from the same CSV and mapping. If contact data
changed enough to alter the plan, the fingerprint changes and commit is
rejected with `IMPORT_PREVIEW_CHANGED`.

This prevents a previously reviewed preview from silently committing against a
different duplicate state.

## Limits

Initial import limits:

- 500 data rows per CSV;
- 40 columns;
- 650,000 CSV characters so the request stays below the API's 1 MiB body
  limit with JSON overhead;
- 10,000 characters per individual cell.

Large imports must be split into explicit batches.

## Contact identity

One column must map to phone / WhatsApp.

The importer normalizes the number and creates the canonical phone JID:

`<digits>@s.whatsapp.net`

A configurable default country code is used only for local numbers containing
10 or 11 digits without a leading `+`.

For the Brazilian default:

`(11) 99999-8888` -> `5511999998888@s.whatsapp.net`

Numbers already supplied with `+` are treated as international numbers and are
not prefixed again.

The existing database invariant remains authoritative:

`@@unique([companyId, remoteJid])`

## Duplicate review

The importer never automatically merges ambiguous contacts.

Exact `companyId + remoteJid` matches become `UPDATE`.

The following become `CONFLICT`:

- the normalized phone is already attached to a different remote JID;
- the normalized e-mail is already attached to another contact.

Repeated phone identities inside the same CSV become `SKIP` after the first
occurrence.

The Data Quality screen also scans up to 5,000 existing direct contacts and
surfaces possible phone/e-mail duplicate groups for manual review.

No automatic merge endpoint exists in P3.6.

## Field mapping

Supported standard targets:

- name;
- phone / WhatsApp;
- e-mail;
- notes.

P3.1 custom fields can be mapped individually.

The same existing value rules are used for TEXT, NUMBER, DATE, BOOLEAN and
SELECT fields.

Required custom fields are checked against the final value. Existing values
may satisfy a required field during an update.

P3.2 pipelines can be mapped one column per pipeline. The CSV cell contains
the stage name. Only active stages are eligible.

Pipeline changes created by import also create the normal
`ContactStageTransition` history with the importing membership as actor.

Each committed row executes in its own database transaction so a row cannot
finish half-applied across Contact, custom fields and pipeline state.

## Campaign consent boundary

Campaign consent is intentionally not an import target.

CSV import never creates or changes `ContactCampaignConsent`.

A contact imported from an external list therefore remains `UNKNOWN` for
campaign purposes until explicit authorization is recorded through the normal
P3.5 consent workflow.

This prevents CSV upload from bypassing the controlled-campaign safety model.

## Export

Managerial users can export up to 5,000 direct contacts per request.

The export includes:

- name;
- phone;
- e-mail;
- notes;
- remote JID;
- last interaction;
- campaign consent state;
- active custom-field values;
- current stage in active pipelines.

Spreadsheet formula injection is neutralized. Cells beginning with `=`, `+`,
`-` or `@` are prefixed with an apostrophe before CSV encoding.

Import and export operations write summarized `CONTACT_DATA` audit events. Raw
CSV content is never written into the audit log.

## RBAC

OWNER / ADMIN / SUPERVISOR:

- read Data Quality;
- preview imports;
- commit imports;
- export contact data;
- review duplicate candidates.

AGENT has no P3.6 access.

## API

- GET `/api/v1/data-quality/context`
- POST `/api/v1/data-quality/import/inspect`
- POST `/api/v1/data-quality/import/preview`
- POST `/api/v1/data-quality/import/commit`
- POST `/api/v1/data-quality/export`

## UI

`/dashboard/data-quality`

The page contains:

- data quality counters;
- CSV selection and column mapping;
- import preview and row selection;
- explicit `IMPORTAR CONTATOS` confirmation;
- safe CSV export;
- existing duplicate review links.
EOF

cat > scripts/p3-06-data-quality-smoke.mjs <<'EOF'
import fs from "node:fs";

const app =
  fs.readFileSync(
    "apps/api/src/app.ts",
    "utf8"
  );

const policy =
  fs.readFileSync(
    "apps/api/src/modules/data-quality/data-quality.policy.ts",
    "utf8"
  );

const service =
  fs.readFileSync(
    "apps/api/src/modules/data-quality/data-quality.service.ts",
    "utf8"
  );

const routes =
  fs.readFileSync(
    "apps/api/src/modules/data-quality/data-quality.routes.ts",
    "utf8"
  );

const web =
  fs.readFileSync(
    "apps/web/app/dashboard/data-quality/page.tsx",
    "utf8"
  );

const permissions =
  fs.readFileSync(
    "apps/api/src/security/permissions.ts",
    "utf8"
  );

for (
  const marker
  of [
    "await app.register(dataQualityRoutes);",
    "normalizeImportPhone",
    "IMPORT_PREVIEW_CHANGED",
    "contactCampaignConsent",
    "safeSpreadsheetCell",
    "/api/v1/data-quality/import/preview",
    "IMPORTAR CONTATOS",
    '"dataQuality.manage"'
  ]
) {
  const source =
    marker.includes(
      "app.register"
    )
      ? app
      : marker ===
          "normalizeImportPhone" ||
        marker ===
          "safeSpreadsheetCell"
        ? policy
        : marker ===
            "IMPORT_PREVIEW_CHANGED" ||
          marker ===
            "contactCampaignConsent"
          ? service
          : marker.startsWith(
              "/api/"
            )
            ? routes
            : marker ===
                "IMPORTAR CONTATOS"
              ? web
              : permissions;

  if (
    !source.includes(
      marker
    )
  ) {
    throw new Error(
      `P3.6 marker missing: ${marker}`
    );
  }
}

if (
  /contactCampaignConsent\.(create|update|upsert)/.test(
    service
  ) ||
  service.includes(
    '"OPTED_IN"'
  )
) {
  throw new Error(
    "P3.6 service appears to mutate campaign consent."
  );
}

console.log(
  "[P3.6] data-quality smoke PASS"
);
EOF

echo "[P3.6] Data-quality smoke..."
node scripts/p3-06-data-quality-smoke.mjs

echo "[P3.6] Security scan..."
pnpm security:scan

echo "[P3.6] Unit tests..."
pnpm test

echo "[P3.6] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.6] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo "[P3.6] Isolated integration tests..."
pnpm test:integration

echo "[P3.6] Production build..."
pnpm build

echo
echo "[P3.6] CODE + INTEGRATION VALIDATION PASS."
echo
echo "No Prisma migration is required for P3.6."
echo "Next:"
echo "  pnpm dev"
echo
echo "Runtime checklist:"
echo "  - open /dashboard/data-quality"
echo "  - import a 2-row test CSV"
echo "  - verify CREATE / UPDATE / CONFLICT classifications"
echo "  - verify imported contact remains campaign consent UNKNOWN"
echo "  - verify custom field and pipeline mapping"
echo "  - export CSV and open it in a spreadsheet"
echo "  - review duplicate groups without automatic merge"
