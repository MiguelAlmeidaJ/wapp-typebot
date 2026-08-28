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

interface QueueItem {
  id: string;
  name: string;
}

interface TeamMembership {
  id: string;
  role:
    | "OWNER"
    | "ADMIN"
    | "SUPERVISOR"
    | "AGENT";
  user: {
    name: string;
  };
}

interface TagItem {
  id: string;
  name: string;
}

interface AutomationAction {
  id: string;
  type:
    | "SET_QUEUE"
    | "ASSIGN_MEMBERSHIP"
    | "ADD_TAG"
    | "SEND_TEXT";
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
}

interface AutomationRule {
  id: string;
  name: string;
  isActive: boolean;
  trigger:
    | "TICKET_CREATED"
    | "INBOUND_MESSAGE";
  keywordContains:
    | string
    | null;
  onlyIfUnassigned:
    boolean;
  conversationType:
    | "ALL"
    | "DIRECT"
    | "GROUP";
  priority: number;
  actions:
    AutomationAction[];
}

interface AutomationRun {
  id: string;
  ruleId: string;
  ticketId: string;
  trigger:
    | "TICKET_CREATED"
    | "INBOUND_MESSAGE";
  status:
    | "RUNNING"
    | "SUCCESS"
    | "FAILED";
  error:
    | string
    | null;
  createdAt: string;
}

function triggerLabel(
  trigger:
    AutomationRule[
      "trigger"
    ]
) {
  return trigger ===
    "TICKET_CREATED"
    ? "Novo atendimento"
    : "Mensagem recebida";
}

export default function AutomationsPage() {
  const router =
    useRouter();

  const {
    session,
    loading,
    request
  } =
    useAuth();

  const [
    automations,
    setAutomations
  ] =
    useState<
      AutomationRule[]
    >([]);

  const [
    runs,
    setRuns
  ] =
    useState<
      AutomationRun[]
    >([]);

  const [
    queues,
    setQueues
  ] =
    useState<
      QueueItem[]
    >([]);

  const [
    team,
    setTeam
  ] =
    useState<
      TeamMembership[]
    >([]);

  const [
    tags,
    setTags
  ] =
    useState<
      TagItem[]
    >([]);

  const [
    name,
    setName
  ] =
    useState("");

  const [
    trigger,
    setTrigger
  ] =
    useState<
      AutomationRule[
        "trigger"
      ]
    >(
      "INBOUND_MESSAGE"
    );

  const [
    keyword,
    setKeyword
  ] =
    useState("");

  const [
    conversationType,
    setConversationType
  ] =
    useState<
      AutomationRule[
        "conversationType"
      ]
    >(
      "ALL"
    );

  const [
    onlyIfUnassigned,
    setOnlyIfUnassigned
  ] =
    useState(
      true
    );

  const [
    queueId,
    setQueueId
  ] =
    useState("");

  const [
    membershipId,
    setMembershipId
  ] =
    useState("");

  const [
    tagId,
    setTagId
  ] =
    useState("");

  const [
    automaticText,
    setAutomaticText
  ] =
    useState("");

  const [
    busy,
    setBusy
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

  const canManage =
    session?.role ===
      "OWNER" ||
    session?.role ===
      "ADMIN" ||
    session?.role ===
      "SUPERVISOR";

  const load =
    useCallback(
      async () => {
        const [
          automationPayload,
          runsPayload,
          queuesPayload,
          teamPayload,
          tagsPayload
        ] =
          await Promise.all([
            request<{
              automations:
                AutomationRule[];
            }>(
              "/api/v1/automations"
            ),
            request<{
              runs:
                AutomationRun[];
            }>(
              "/api/v1/automations/runs?limit=30"
            ),
            request<{
              queues:
                QueueItem[];
            }>(
              "/api/v1/queues"
            ),
            request<{
              memberships:
                TeamMembership[];
            }>(
              "/api/v1/team/memberships"
            ),
            request<{
              tags:
                TagItem[];
            }>(
              "/api/v1/tags"
            )
          ]);

        setAutomations(
          automationPayload
            .automations
        );

        setRuns(
          runsPayload.runs
        );

        setQueues(
          queuesPayload.queues
        );

        setTeam(
          teamPayload
            .memberships
        );

        setTags(
          tagsPayload.tags
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

      if (session) {
        void load()
          .catch(
            caught => {
              setError(
                caught instanceof
                  ApiError
                  ? caught.message
                  : "Não foi possível carregar as automações."
              );
            }
          );
      }
    },
    [
      load,
      loading,
      router,
      session
    ]
  );

  const runByRule =
    useMemo(
      () => {
        const map =
          new Map<
            string,
            AutomationRun
          >();

        for (
          const run
          of runs
        ) {
          if (
            !map.has(
              run.ruleId
            )
          ) {
            map.set(
              run.ruleId,
              run
            );
          }
        }

        return map;
      },
      [
        runs
      ]
    );

  function actionLabel(
    action:
      AutomationAction
  ) {
    switch (
      action.type
    ) {
      case "SET_QUEUE":
        return `Mover para ${
          queues.find(
            queue =>
              queue.id ===
              action.queueId
          )?.name ??
          "fila"
        }`;

      case "ASSIGN_MEMBERSHIP":
        return `Atribuir a ${
          team.find(
            membership =>
              membership.id ===
              action.membershipId
          )?.user.name ??
          "atendente"
        }`;

      case "ADD_TAG":
        return `Adicionar ${
          tags.find(
            tag =>
              tag.id ===
              action.tagId
          )?.name ??
          "etiqueta"
        }`;

      case "SEND_TEXT":
        return "Enviar mensagem automática";
    }
  }

  async function create(
    event:
      FormEvent<
        HTMLFormElement
      >
  ) {
    event.preventDefault();

    if (
      !canManage
    ) {
      return;
    }

    const actions:
      Array<
        Record<
          string,
          string
        >
      > = [];

    if (
      queueId
    ) {
      actions.push({
        type:
          "SET_QUEUE",
        queueId
      });
    }

    if (
      membershipId
    ) {
      actions.push({
        type:
          "ASSIGN_MEMBERSHIP",
        membershipId
      });
    }

    if (
      tagId
    ) {
      actions.push({
        type:
          "ADD_TAG",
        tagId
      });
    }

    if (
      automaticText
        .trim()
    ) {
      actions.push({
        type:
          "SEND_TEXT",
        text:
          automaticText
            .trim()
      });
    }

    if (
      actions.length ===
      0
    ) {
      setError(
        "Escolha ao menos uma ação para a automação."
      );

      return;
    }

    setBusy(
      "create"
    );

    setError("");

    try {
      await request(
        "/api/v1/automations",
        {
          method:
            "POST",
          body:
            JSON.stringify({
              name,
              trigger,
              keywordContains:
                keyword.trim() ||
                null,
              onlyIfUnassigned,
              conversationType,
              priority:
                100,
              actions
            })
        }
      );

      setName("");
      setKeyword("");
      setQueueId("");
      setMembershipId("");
      setTagId("");
      setAutomaticText("");

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível criar a automação."
      );
    } finally {
      setBusy(
        null
      );
    }
  }

  async function toggle(
    rule:
      AutomationRule
  ) {
    if (
      !canManage
    ) {
      return;
    }

    setBusy(
      rule.id
    );

    setError("");

    try {
      await request(
        `/api/v1/automations/${rule.id}`,
        {
          method:
            "PATCH",
          body:
            JSON.stringify({
              isActive:
                !rule.isActive
            })
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível alterar a automação."
      );
    } finally {
      setBusy(
        null
      );
    }
  }

  if (
    loading ||
    !session
  ) {
    return (
      <main className="dashboard-loading">
        Carregando automações…
      </main>
    );
  }

  return (
    <main className="automation-screen">
      <header className="automation-header">
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
            Operação
          </span>

          <h1>
            Automações
          </h1>

          <p>
            Regras objetivas para organizar atendimentos sem esconder o que foi feito automaticamente.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              "/dashboard/conversations"
            )
          }
          type="button"
        >
          Conversas
        </button>
      </header>

      {error && (
        <div className="inbox-error">
          {error}
        </div>
      )}

      {canManage && (
        <form
          className="automation-builder"
          onSubmit={
            create
          }
        >
          <div className="automation-builder__intro">
            <span className="eyebrow">
              Nova regra
            </span>
            <h2>
              Quando isso acontecer…
            </h2>
          </div>

          <div className="automation-builder__grid">
            <label>
              <span>
                Nome
              </span>
              <input
                maxLength={
                  160
                }
                onChange={
                  event =>
                    setName(
                      event
                        .target
                        .value
                    )
                }
                placeholder="Ex.: Financeiro por palavra-chave"
                required
                value={
                  name
                }
              />
            </label>

            <label>
              <span>
                Gatilho
              </span>
              <select
                onChange={
                  event =>
                    setTrigger(
                      event
                        .target
                        .value as
                        AutomationRule[
                          "trigger"
                        ]
                    )
                }
                value={
                  trigger
                }
              >
                <option value="INBOUND_MESSAGE">
                  Mensagem recebida
                </option>
                <option value="TICKET_CREATED">
                  Novo atendimento
                </option>
              </select>
            </label>

            <label>
              <span>
                Contém
              </span>
              <input
                maxLength={
                  190
                }
                onChange={
                  event =>
                    setKeyword(
                      event
                        .target
                        .value
                    )
                }
                placeholder="Opcional: boleto, suporte…"
                value={
                  keyword
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
                    setConversationType(
                      event
                        .target
                        .value as
                        AutomationRule[
                          "conversationType"
                        ]
                    )
                }
                value={
                  conversationType
                }
              >
                <option value="ALL">
                  Todos
                </option>
                <option value="DIRECT">
                  Contatos
                </option>
                <option value="GROUP">
                  Grupos
                </option>
              </select>
            </label>
          </div>

          <label className="automation-check">
            <input
              checked={
                onlyIfUnassigned
              }
              onChange={
                event =>
                  setOnlyIfUnassigned(
                    event
                      .target
                      .checked
                  )
              }
              type="checkbox"
            />
            <span>
              Executar somente se o atendimento ainda estiver sem atendente
            </span>
          </label>

          <div className="automation-builder__divider">
            Então…
          </div>

          <div className="automation-builder__grid">
            <label>
              <span>
                Fila
              </span>
              <select
                onChange={
                  event =>
                    setQueueId(
                      event
                        .target
                        .value
                    )
                }
                value={
                  queueId
                }
              >
                <option value="">
                  Não alterar
                </option>
                {queues.map(
                  queue => (
                    <option
                      key={
                        queue.id
                      }
                      value={
                        queue.id
                      }
                    >
                      {queue.name}
                    </option>
                  )
                )}
              </select>
            </label>

            <label>
              <span>
                Atendente
              </span>
              <select
                onChange={
                  event =>
                    setMembershipId(
                      event
                        .target
                        .value
                    )
                }
                value={
                  membershipId
                }
              >
                <option value="">
                  Não atribuir
                </option>
                {team.map(
                  membership => (
                    <option
                      key={
                        membership.id
                      }
                      value={
                        membership.id
                      }
                    >
                      {membership.user.name}
                    </option>
                  )
                )}
              </select>
            </label>

            <label>
              <span>
                Etiqueta
              </span>
              <select
                onChange={
                  event =>
                    setTagId(
                      event
                        .target
                        .value
                    )
                }
                value={
                  tagId
                }
              >
                <option value="">
                  Não adicionar
                </option>
                {tags.map(
                  tag => (
                    <option
                      key={
                        tag.id
                      }
                      value={
                        tag.id
                      }
                    >
                      {tag.name}
                    </option>
                  )
                )}
              </select>
            </label>
          </div>

          <label className="automation-text-field">
            <span>
              Mensagem automática
            </span>
            <textarea
              maxLength={
                4096
              }
              onChange={
                event =>
                  setAutomaticText(
                    event
                      .target
                      .value
                  )
              }
              placeholder="Opcional. Variáveis: {nome}, {primeiro_nome}, {empresa}"
              rows={
                3
              }
              value={
                automaticText
              }
            />
          </label>

          <div className="automation-builder__footer">
            <small>
              A regra só executa em mensagens recebidas. Mensagens automáticas não disparam outra automação.
            </small>

            <button
              className="primary-button"
              disabled={
                busy ===
                "create"
              }
              type="submit"
            >
              <span>
                {busy ===
                "create"
                  ? "Criando…"
                  : "Criar automação"}
              </span>
              <span>
                +
              </span>
            </button>
          </div>
        </form>
      )}

      <section className="automation-list">
        <div className="automation-list__heading">
          <div>
            <span className="eyebrow">
              Regras
            </span>
            <h2>
              Automações configuradas
            </h2>
          </div>

          <span>
            {automations.length}
          </span>
        </div>

        {automations.length ===
        0 ? (
          <div className="connection-empty">
            <strong>
              Nenhuma automação criada.
            </strong>
            <p>
              As regras ficam visíveis aqui com o último resultado de execução.
            </p>
          </div>
        ) : (
          automations.map(
            rule => {
              const lastRun =
                runByRule.get(
                  rule.id
                );

              return (
                <article
                  className={
                    rule.isActive
                      ? "automation-rule"
                      : "automation-rule automation-rule--inactive"
                  }
                  key={
                    rule.id
                  }
                >
                  <div className="automation-rule__main">
                    <div className="automation-rule__status">
                      <span>
                        {rule.isActive
                          ? "Ativa"
                          : "Pausada"}
                      </span>
                    </div>

                    <div>
                      <h3>
                        {rule.name}
                      </h3>
                      <p>
                        {triggerLabel(
                          rule.trigger
                        )}
                        {rule.keywordContains
                          ? ` · contém “${rule.keywordContains}”`
                          : ""}
                        {rule.onlyIfUnassigned
                          ? " · apenas sem atendente"
                          : ""}
                      </p>
                    </div>
                  </div>

                  <div className="automation-rule__actions">
                    {rule.actions.map(
                      action => (
                        <span
                          key={
                            action.id
                          }
                        >
                          {actionLabel(
                            action
                          )}
                        </span>
                      )
                    )}
                  </div>

                  <div className="automation-rule__last-run">
                    {lastRun ? (
                      <>
                        <span
                          className={
                            `automation-run automation-run--${lastRun.status.toLowerCase()}`
                          }
                        >
                          {lastRun.status ===
                          "SUCCESS"
                            ? "Última execução OK"
                            : lastRun.status ===
                                "FAILED"
                              ? "Última execução falhou"
                              : "Executando"}
                        </span>

                        <time>
                          {new Intl.DateTimeFormat(
                            "pt-BR",
                            {
                              dateStyle:
                                "short",
                              timeStyle:
                                "short"
                            }
                          ).format(
                            new Date(
                              lastRun.createdAt
                            )
                          )}
                        </time>
                      </>
                    ) : (
                      <span>
                        Ainda não executada
                      </span>
                    )}
                  </div>

                  {canManage && (
                    <button
                      className="secondary-button"
                      disabled={
                        busy ===
                        rule.id
                      }
                      onClick={() =>
                        void toggle(
                          rule
                        )
                      }
                      type="button"
                    >
                      {rule.isActive
                        ? "Pausar"
                        : "Ativar"}
                    </button>
                  )}
                </article>
              );
            }
          )
        )}
      </section>
    </main>
  );
}
