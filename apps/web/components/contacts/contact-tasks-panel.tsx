"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type TaskStatus = "OPEN" | "DONE" | "CANCELLED";
type TaskPriority = "LOW" | "NORMAL" | "HIGH" | "URGENT";

interface Task {
  id: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: TaskPriority;
  dueAt: string;
  reminderAt: string | null;
  reminderSentAt: string | null;
  reminderFailedAt: string | null;
  reminderError: string | null;
  ticket: {
    id: string;
    status: string;
    lastMessage: string | null;
    lastMessageAt: string;
  } | null;
  assigneeMembership: {
    id: string;
    user: {
      id: string;
      name: string;
    };
  };
}

interface ContextPayload {
  actorMembershipId: string;
  tasks: Task[];
  assignees: Array<{
    id: string;
    role: string;
    user: {
      id: string;
      name: string;
    };
  }>;
  tickets: Array<{
    id: string;
    status: string;
    lastMessage: string | null;
    lastMessageAt: string;
  }>;
}

const priorityLabel = {
  LOW: "Baixa",
  NORMAL: "Normal",
  HIGH: "Alta",
  URGENT: "Urgente"
} as const;

function localDateTime(date: Date) {
  return new Date(
    date.getTime() -
    date.getTimezoneOffset() * 60_000
  ).toISOString().slice(0, 16);
}

function newDefaultDue() {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  date.setHours(10, 0, 0, 0);
  return date;
}

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short"
  }).format(new Date(value));
}

export function ContactTasksPanel({
  contactId,
  contactName
}: {
  contactId: string;
  contactName: string;
}) {
  const router = useRouter();
  const {
    request,
    subscribe
  } = useAuth();

  const [context, setContext] =
    useState<ContextPayload | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] =
    useState("");
  const [priority, setPriority] =
    useState<TaskPriority>("NORMAL");
  const [assigneeId, setAssigneeId] =
    useState("");
  const [ticketId, setTicketId] =
    useState("");

  const initialDue = useMemo(
    () => newDefaultDue(),
    [contactId]
  );

  const [dueAt, setDueAt] = useState(
    localDateTime(initialDue)
  );
  const [reminderAt, setReminderAt] =
    useState(
      localDateTime(
        new Date(
          initialDue.getTime() -
          60 * 60 * 1_000
        )
      )
    );

  const [creating, setCreating] =
    useState(false);
  const [actionId, setActionId] =
    useState<string | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const load = useCallback(async () => {
    const payload =
      await request<ContextPayload>(
        `/api/v1/contacts/${contactId}/tasks/context`
      );

    setContext(payload);
    setAssigneeId(current =>
      current &&
      payload.assignees.some(
        item => item.id === current
      )
        ? current
        : payload.assignees.find(
            item =>
              item.id ===
              payload.actorMembershipId
          )?.id ??
          payload.assignees[0]?.id ??
          ""
    );
  }, [
    contactId,
    request
  ]);

  useEffect(() => {
    void load().catch(() => {
      setError(
        "Não foi possível carregar as tarefas do contato."
      );
    });
  }, [load]);

  useEffect(
    () =>
      subscribe(
        "/api/v1/realtime/events",
        event => {
          if (
            event.type === "task.updated" &&
            event.contactId === contactId
          ) {
            void load().catch(() => {});
          }
        }
      ),
    [contactId, load, subscribe]
  );

  const sortedTasks = useMemo(
    () =>
      [...(context?.tasks ?? [])].sort(
        (left, right) => {
          if (
            left.status === "OPEN" &&
            right.status !== "OPEN"
          ) {
            return -1;
          }

          if (
            left.status !== "OPEN" &&
            right.status === "OPEN"
          ) {
            return 1;
          }

          return (
            new Date(left.dueAt).getTime() -
            new Date(right.dueAt).getTime()
          );
        }
      ),
    [context?.tasks]
  );

  async function createTask(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!assigneeId) return;

    setCreating(true);
    setError("");
    setNotice("");

    try {
      const result = await request<{
        reminderQueued: boolean;
      }>("/api/v1/tasks", {
        method: "POST",
        body: JSON.stringify({
          contactId,
          ticketId: ticketId || null,
          assigneeMembershipId: assigneeId,
          title: title.trim(),
          description:
            description.trim() || null,
          priority,
          dueAt: new Date(
            dueAt
          ).toISOString(),
          reminderAt: reminderAt
            ? new Date(
                reminderAt
              ).toISOString()
            : null
        })
      });

      const nextDue = newDefaultDue();

      setTitle("");
      setDescription("");
      setPriority("NORMAL");
      setTicketId("");
      setDueAt(
        localDateTime(
          nextDue
        )
      );
      setReminderAt(
        localDateTime(
          new Date(
            nextDue.getTime() -
            60 * 60 * 1_000
          )
        )
      );
      setNotice(
        result.reminderQueued ||
        !reminderAt
          ? "Tarefa criada."
          : "Tarefa criada. O reconciliador cuidará do lembrete quando a fila estiver disponível."
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível criar a tarefa."
      );
    } finally {
      setCreating(false);
    }
  }

  async function runAction(
    taskId: string,
    action: "complete" | "cancel"
  ) {
    setActionId(taskId);
    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/tasks/${taskId}/${action}`,
        {
          method: "POST"
        }
      );

      setNotice(
        action === "complete"
          ? "Tarefa concluída."
          : "Tarefa cancelada."
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

  return (
    <section className="contact-tasks">
      <header>
        <div>
          <span className="eyebrow">
            Follow-up
          </span>
          <strong>Tarefas</strong>
          <small>
            Próximas ações com {contactName}.
          </small>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              "/dashboard/tasks"
            )
          }
          type="button"
        >
          Abrir agenda
        </button>
      </header>

      {error && (
        <div className="contact-tasks__feedback contact-tasks__feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="contact-tasks__feedback">
          {notice}
        </div>
      )}

      <div className="contact-tasks__layout">
        <form
          className="contact-task-form"
          onSubmit={createTask}
        >
          <strong>Nova tarefa</strong>

          <label>
            <span>Título</span>
            <input
              maxLength={190}
              onChange={event =>
                setTitle(
                  event.target.value
                )
              }
              placeholder="Ex.: Retornar proposta"
              required
              value={title}
            />
          </label>

          <label>
            <span>Responsável</span>
            <select
              onChange={event =>
                setAssigneeId(
                  event.target.value
                )
              }
              required
              value={assigneeId}
            >
              {context?.assignees.map(
                item => (
                  <option
                    key={item.id}
                    value={item.id}
                  >
                    {item.user.name}
                  </option>
                )
              )}
            </select>
          </label>

          <div className="contact-task-form__row">
            <label>
              <span>Prazo</span>
              <input
                onChange={event =>
                  setDueAt(
                    event.target.value
                  )
                }
                required
                type="datetime-local"
                value={dueAt}
              />
            </label>

            <label>
              <span>Lembrete</span>
              <input
                onChange={event =>
                  setReminderAt(
                    event.target.value
                  )
                }
                type="datetime-local"
                value={reminderAt}
              />
            </label>
          </div>

          <div className="contact-task-form__row">
            <label>
              <span>Prioridade</span>
              <select
                onChange={event =>
                  setPriority(
                    event.target
                      .value as
                      TaskPriority
                  )
                }
                value={priority}
              >
                {Object.entries(
                  priorityLabel
                ).map(
                  ([key, label]) => (
                    <option
                      key={key}
                      value={key}
                    >
                      {label}
                    </option>
                  )
                )}
              </select>
            </label>

            <label>
              <span>Atendimento</span>
              <select
                onChange={event =>
                  setTicketId(
                    event.target.value
                  )
                }
                value={ticketId}
              >
                <option value="">
                  Sem vínculo
                </option>

                {context?.tickets.map(
                  ticket => (
                    <option
                      key={ticket.id}
                      value={ticket.id}
                    >
                      {ticket.status} ·{" "}
                      {dateTimeLabel(
                        ticket.lastMessageAt
                      )}
                    </option>
                  )
                )}
              </select>
            </label>
          </div>

          <label>
            <span>Detalhes</span>
            <textarea
              maxLength={10_000}
              onChange={event =>
                setDescription(
                  event.target.value
                )
              }
              placeholder="Contexto opcional para o follow-up."
              rows={3}
              value={description}
            />
          </label>

          <button
            className="primary-button"
            disabled={
              creating ||
              !title.trim() ||
              !assigneeId
            }
            type="submit"
          >
            <span>
              {creating
                ? "Criando…"
                : "Criar tarefa"}
            </span>
          </button>
        </form>

        <div className="contact-task-list">
          <header>
            <strong>Acompanhamento</strong>
            <span>
              {sortedTasks.filter(
                task =>
                  task.status === "OPEN"
              ).length} abertas
            </span>
          </header>

          {sortedTasks.map(task => {
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
                    ? "contact-task-item contact-task-item--overdue"
                    : `contact-task-item contact-task-item--${task.status.toLowerCase()}`
                }
                key={task.id}
              >
                <div className="contact-task-item__top">
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

                    {overdue && (
                      <span className="task-overdue">
                        Atrasada
                      </span>
                    )}
                  </div>

                  <time>
                    {dateTimeLabel(
                      task.dueAt
                    )}
                  </time>
                </div>

                <strong>{task.title}</strong>

                {task.description && (
                  <p>
                    {task.description}
                  </p>
                )}

                <div className="contact-task-item__meta">
                  <span>
                    {task
                      .assigneeMembership
                      .user.name}
                  </span>

                  {task.ticket && (
                    <button
                      onClick={() =>
                        router.push(
                          `/dashboard/conversations?ticket=${task.ticket?.id}`
                        )
                      }
                      type="button"
                    >
                      Abrir atendimento
                    </button>
                  )}
                </div>

                {task.reminderFailedAt &&
                  task.reminderError && (
                  <small className="contact-task-item__reminder-error">
                    Lembrete:{" "}
                    {task.reminderError}
                  </small>
                )}

                {task.status === "OPEN" && (
                  <div className="contact-task-item__actions">
                    <button
                      disabled={
                        actionId ===
                        task.id
                      }
                      onClick={() =>
                        void runAction(
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
                        actionId ===
                        task.id
                      }
                      onClick={() =>
                        void runAction(
                          task.id,
                          "cancel"
                        )
                      }
                      type="button"
                    >
                      Cancelar
                    </button>
                  </div>
                )}
              </article>
            );
          })}

          {sortedTasks.length === 0 && (
            <div className="contact-tasks__empty">
              Nenhuma tarefa registrada para este contato.
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
