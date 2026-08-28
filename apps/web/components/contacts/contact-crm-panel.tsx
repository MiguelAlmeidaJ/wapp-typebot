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
