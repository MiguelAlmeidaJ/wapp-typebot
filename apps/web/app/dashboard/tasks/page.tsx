"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";
import { roleCan } from "@/lib/permissions";

type TaskStatus =
  | "OPEN"
  | "DONE"
  | "CANCELLED";

interface Task {
  id: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority:
    | "LOW"
    | "NORMAL"
    | "HIGH"
    | "URGENT";
  dueAt: string;
  reminderAt: string | null;
  reminderSentAt: string | null;
  reminderFailedAt: string | null;
  contact: {
    id: string;
    name: string;
    phoneNumber: string | null;
    email: string | null;
  };
  ticket: {
    id: string;
    status: string;
  } | null;
  assigneeMembership: {
    id: string;
    user: {
      id: string;
      name: string;
    };
  };
}

const priorityLabel = {
  LOW: "Baixa",
  NORMAL: "Normal",
  HIGH: "Alta",
  URGENT: "Urgente"
} as const;

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      dateStyle: "short",
      timeStyle: "short"
    }
  ).format(new Date(value));
}

export default function TasksPage() {
  const router = useRouter();
  const {
    session,
    loading,
    request,
    subscribe
  } = useAuth();

  const [tasks, setTasks] =
    useState<Task[]>([]);
  const [status, setStatus] =
    useState<TaskStatus>("OPEN");
  const [scope, setScope] =
    useState<"ME" | "ALL">("ME");
  const [overdueOnly, setOverdueOnly] =
    useState(false);
  const [busy, setBusy] =
    useState(true);
  const [actionId, setActionId] =
    useState<string | null>(null);
  const [error, setError] = useState("");

  const canAdmin =
    session
      ? roleCan(
          session.role,
          "tasks.admin"
        )
      : false;

  const load = useCallback(async () => {
    setBusy(true);

    try {
      const params =
        new URLSearchParams({
          scope,
          status,
          overdueOnly:
            String(overdueOnly),
          limit: "150"
        });

      const payload =
        await request<{
          tasks: Task[];
        }>(
          `/api/v1/tasks?${params.toString()}`
        );

      setTasks(payload.tasks);
      setError("");
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível carregar as tarefas."
      );
    } finally {
      setBusy(false);
    }
  }, [
    overdueOnly,
    request,
    scope,
    status
  ]);

  useEffect(() => {
    if (
      !loading &&
      !session
    ) {
      router.replace("/login");
      return;
    }

    if (
      session &&
      !roleCan(
        session.role,
        "tasks.view"
      )
    ) {
      router.replace("/dashboard");
      return;
    }

    if (session) {
      void load();
    }
  }, [
    load,
    loading,
    router,
    session
  ]);

  useEffect(() => {
    if (!session) return;

    return subscribe(
      "/api/v1/realtime/events",
      event => {
        if (
          event.type ===
          "task.updated"
        ) {
          void load();
        }
      }
    );
  }, [
    load,
    session,
    subscribe
  ]);

  useEffect(() => {
    if (
      !canAdmin &&
      scope === "ALL"
    ) {
      setScope("ME");
    }
  }, [
    canAdmin,
    scope
  ]);

  const summary = useMemo(() => {
    const now = Date.now();

    return {
      total: tasks.length,
      overdue: tasks.filter(
        task =>
          task.status === "OPEN" &&
          new Date(
            task.dueAt
          ).getTime() <
            now
      ).length,
      today: tasks.filter(task => {
        const date =
          new Date(task.dueAt);
        const today =
          new Date();

        return (
          date.getFullYear() ===
            today.getFullYear() &&
          date.getMonth() ===
            today.getMonth() &&
          date.getDate() ===
            today.getDate()
        );
      }).length
    };
  }, [tasks]);

  async function action(
    taskId: string,
    type: "complete" | "cancel"
  ) {
    setActionId(taskId);

    try {
      await request(
        `/api/v1/tasks/${taskId}/${type}`,
        {
          method: "POST"
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar a tarefa."
      );
    } finally {
      setActionId(null);
    }
  }

  if (
    loading ||
    !session
  ) {
    return (
      <main className="dashboard-loading">
        Carregando tarefas…
      </main>
    );
  }

  return (
    <main className="tasks-screen">
      <header className="tasks-header">
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

          <h1>Tarefas</h1>

          <p>
            Agenda de follow-ups, prazos e lembretes vinculados aos contatos.
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
          Nova tarefa pela ficha do contato
        </button>
      </header>

      {error && (
        <div className="tasks-feedback tasks-feedback--error">
          {error}
        </div>
      )}

      <section className="tasks-summary">
        <article>
          <span>Na visão atual</span>
          <strong>{summary.total}</strong>
        </article>

        <article>
          <span>Para hoje</span>
          <strong>{summary.today}</strong>
        </article>

        <article>
          <span>Atrasadas</span>
          <strong>
            {summary.overdue}
          </strong>
        </article>
      </section>

      <section className="tasks-toolbar">
        <div className="tasks-switch">
          {(
            [
              ["OPEN", "Abertas"],
              ["DONE", "Concluídas"],
              [
                "CANCELLED",
                "Canceladas"
              ]
            ] as const
          ).map(
            ([value, label]) => (
              <button
                className={
                  status === value
                    ? "tasks-switch__item tasks-switch__item--active"
                    : "tasks-switch__item"
                }
                key={value}
                onClick={() =>
                  setStatus(value)
                }
                type="button"
              >
                {label}
              </button>
            )
          )}
        </div>

        {canAdmin && (
          <div className="tasks-switch">
            <button
              className={
                scope === "ME"
                  ? "tasks-switch__item tasks-switch__item--active"
                  : "tasks-switch__item"
              }
              onClick={() =>
                setScope("ME")
              }
              type="button"
            >
              Minhas
            </button>

            <button
              className={
                scope === "ALL"
                  ? "tasks-switch__item tasks-switch__item--active"
                  : "tasks-switch__item"
              }
              onClick={() =>
                setScope("ALL")
              }
              type="button"
            >
              Equipe
            </button>
          </div>
        )}

        {status === "OPEN" && (
          <label className="tasks-overdue-filter">
            <input
              checked={overdueOnly}
              onChange={event =>
                setOverdueOnly(
                  event.target.checked
                )
              }
              type="checkbox"
            />
            Somente atrasadas
          </label>
        )}
      </section>

      {busy ? (
        <div className="tasks-empty">
          Atualizando agenda…
        </div>
      ) : tasks.length === 0 ? (
        <div className="tasks-empty">
          Nenhuma tarefa nesta visão.
        </div>
      ) : (
        <section className="tasks-list">
          {tasks.map(task => {
            const overdue =
              task.status === "OPEN" &&
              new Date(
                task.dueAt
              ).getTime() <
                Date.now();

            return (
              <article
                className={
                  overdue
                    ? "task-row task-row--overdue"
                    : "task-row"
                }
                key={task.id}
              >
                <div className="task-row__when">
                  <strong>
                    {dateTimeLabel(
                      task.dueAt
                    )}
                  </strong>
                  <span>
                    {overdue
                      ? "Atrasada"
                      : task.status}
                  </span>
                </div>

                <button
                  className="task-row__contact"
                  onClick={() =>
                    router.push(
                      `/dashboard/contacts?contact=${task.contact.id}`
                    )
                  }
                  type="button"
                >
                  <span>
                    {task.contact.name
                      .slice(0, 1)
                      .toUpperCase()}
                  </span>

                  <div>
                    <strong>
                      {task.contact.name}
                    </strong>
                    <small>
                      {task
                        .contact
                        .phoneNumber ??
                        task
                          .contact
                          .email ??
                        "Contato"}
                    </small>
                  </div>
                </button>

                <div className="task-row__copy">
                  <div>
                    <span
                      className={
                        `task-priority task-priority--${task.priority.toLowerCase()}`
                      }
                    >
                      {priorityLabel[
                        task.priority
                      ]}
                    </span>

                    <strong>
                      {task.title}
                    </strong>
                  </div>

                  <small>
                    Responsável:{" "}
                    {task
                      .assigneeMembership
                      .user.name}
                  </small>
                </div>

                <div className="task-row__actions">
                  {task.ticket && (
                    <button
                      onClick={() =>
                        router.push(
                          `/dashboard/conversations?ticket=${task.ticket?.id}`
                        )
                      }
                      type="button"
                    >
                      Conversa
                    </button>
                  )}

                  {task.status === "OPEN" && (
                    <>
                      <button
                        disabled={
                          actionId === task.id
                        }
                        onClick={() =>
                          void action(
                            task.id,
                            "complete"
                          )
                        }
                        type="button"
                      >
                        Concluir
                      </button>

                      <button
                        disabled={
                          actionId === task.id
                        }
                        onClick={() =>
                          void action(
                            task.id,
                            "cancel"
                          )
                        }
                        type="button"
                      >
                        Cancelar
                      </button>
                    </>
                  )}
                </div>
              </article>
            );
          })}
        </section>
      )}
    </main>
  );
}
