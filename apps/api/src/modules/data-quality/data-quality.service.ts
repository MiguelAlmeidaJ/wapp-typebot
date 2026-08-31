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
