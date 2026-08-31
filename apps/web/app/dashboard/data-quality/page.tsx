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
