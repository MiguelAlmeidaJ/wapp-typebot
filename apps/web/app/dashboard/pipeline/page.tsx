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
