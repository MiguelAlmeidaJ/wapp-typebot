"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";

import {
  useAuth
} from "@/components/auth-provider";
import {
  ApiError
} from "@/lib/api";

interface ScheduledMessage {
  id: string;
  body: string;
  scheduledFor: string;
  status:
    | "PENDING"
    | "PROCESSING"
    | "SENT"
    | "CANCELLED"
    | "FAILED";
  sentAt:
    | string
    | null;
  cancelledAt:
    | string
    | null;
  error:
    | string
    | null;
  createdByMembership: {
    id: string;
    user: {
      id: string;
      name: string;
    };
  };
}

function localDateTimeInput(
  date: Date
) {
  const shifted =
    new Date(
      date.getTime() -
      date
        .getTimezoneOffset() *
      60_000
    );

  return shifted
    .toISOString()
    .slice(
      0,
      16
    );
}

function statusLabel(
  status:
    ScheduledMessage[
      "status"
    ]
) {
  switch (
    status
  ) {
    case "PENDING":
      return "Agendada";
    case "PROCESSING":
      return "Enviando";
    case "SENT":
      return "Enviada";
    case "CANCELLED":
      return "Cancelada";
    case "FAILED":
      return "Falhou";
  }
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

export function ScheduledMessageDrawer({
  ticketId,
  contactName,
  draftText,
  onClose,
  onScheduled
}: {
  ticketId: string;
  contactName: string;
  draftText: string;
  onClose: () => void;
  onScheduled: () => void;
}) {
  const {
    request
  } =
    useAuth();

  const [
    body,
    setBody
  ] =
    useState(
      draftText
    );

  const [
    scheduledFor,
    setScheduledFor
  ] =
    useState(
      localDateTimeInput(
        new Date(
          Date.now() +
          15 *
          60 *
          1_000
        )
      )
    );

  const [
    items,
    setItems
  ] =
    useState<
      ScheduledMessage[]
    >([]);

  const [
    loading,
    setLoading
  ] =
    useState(
      true
    );

  const [
    saving,
    setSaving
  ] =
    useState(
      false
    );

  const [
    cancellingId,
    setCancellingId
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

  const load =
    useCallback(
      async () => {
        const payload =
          await request<{
            scheduledMessages:
              ScheduledMessage[];
          }>(
            `/api/v1/tickets/${ticketId}/scheduled-messages`
          );

        setItems(
          payload
            .scheduledMessages
        );

        setLoading(
          false
        );
      },
      [
        request,
        ticketId
      ]
    );

  useEffect(
    () => {
      void load()
        .catch(
          caught => {
            setError(
              caught instanceof
                ApiError
                ? caught.message
                : "Não foi possível carregar os agendamentos."
            );

            setLoading(
              false
            );
          }
        );
    },
    [
      load
    ]
  );

  async function submit(
    event:
      FormEvent<
        HTMLFormElement
      >
  ) {
    event.preventDefault();

    if (
      !body.trim() ||
      !scheduledFor
    ) {
      return;
    }

    setSaving(
      true
    );

    setError("");
    setNotice("");

    try {
      const payload =
        await request<{
          scheduledMessage:
            ScheduledMessage;
          queued:
            boolean;
        }>(
          `/api/v1/tickets/${ticketId}/scheduled-messages`,
          {
            method:
              "POST",
            body:
              JSON.stringify({
                body:
                  body.trim(),
                scheduledFor:
                  new Date(
                    scheduledFor
                  ).toISOString()
              })
          }
        );

      setNotice(
        payload.queued
          ? "Mensagem agendada."
          : "Agendamento salvo. O worker irá reconciliar o envio quando a fila estiver disponível."
      );

      await load();

      onScheduled();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível agendar a mensagem."
      );
    } finally {
      setSaving(
        false
      );
    }
  }

  async function cancel(
    id: string
  ) {
    setCancellingId(
      id
    );

    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/scheduled-messages/${id}`,
        {
          method:
            "DELETE"
        }
      );

      setNotice(
        "Agendamento cancelado."
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível cancelar o agendamento."
      );
    } finally {
      setCancellingId(
        null
      );
    }
  }

  return (
    <section className="scheduled-message-drawer">
      <header className="scheduled-message-drawer__header">
        <div>
          <span className="eyebrow">
            Envio programado
          </span>

          <strong>
            Agendar mensagem
          </strong>

          <small>
            {contactName}
          </small>
        </div>

        <button
          aria-label="Fechar agendamento"
          onClick={
            onClose
          }
          type="button"
        >
          ×
        </button>
      </header>

      <form
        className="scheduled-message-form"
        onSubmit={
          submit
        }
      >
        <label>
          <span>
            Mensagem
          </span>

          <textarea
            maxLength={
              4096
            }
            onChange={
              event =>
                setBody(
                  event
                    .target
                    .value
                )
            }
            placeholder="Escreva ou aplique uma resposta rápida antes de abrir o agendamento."
            required
            rows={
              3
            }
            value={
              body
            }
          />
        </label>

        <label>
          <span>
            Data e horário
          </span>

          <input
            min={
              localDateTimeInput(
                new Date(
                  Date.now() +
                  30_000
                )
              )
            }
            onChange={
              event =>
                setScheduledFor(
                  event
                    .target
                    .value
                )
            }
            required
            type="datetime-local"
            value={
              scheduledFor
            }
          />
        </label>

        <div className="scheduled-message-form__footer">
          <small>
            Respostas rápidas funcionam como templates: aplique uma no composer e depois abra o agendamento.
          </small>

          <button
            className="primary-button"
            disabled={
              saving ||
              !body.trim()
            }
            type="submit"
          >
            <span>
              {saving
                ? "Agendando…"
                : "Agendar"}
            </span>
          </button>
        </div>
      </form>

      {error && (
        <div className="scheduled-message-feedback scheduled-message-feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="scheduled-message-feedback">
          {notice}
        </div>
      )}

      <div className="scheduled-message-list">
        <div className="scheduled-message-list__heading">
          <strong>
            Histórico de agendamentos
          </strong>

          <span>
            {items.length}
          </span>
        </div>

        {loading ? (
          <div className="scheduled-message-empty">
            Carregando…
          </div>
        ) : items.length ===
          0 ? (
          <div className="scheduled-message-empty">
            Nenhuma mensagem agendada neste atendimento.
          </div>
        ) : (
          items
            .slice(
              0,
              10
            )
            .map(
              item => (
                <article
                  className={
                    `scheduled-message-item scheduled-message-item--${item.status.toLowerCase()}`
                  }
                  key={
                    item.id
                  }
                >
                  <div className="scheduled-message-item__top">
                    <span>
                      {statusLabel(
                        item.status
                      )}
                    </span>

                    <time>
                      {dateTimeLabel(
                        item.scheduledFor
                      )}
                    </time>
                  </div>

                  <p>
                    {item.body}
                  </p>

                  <div className="scheduled-message-item__meta">
                    <span>
                      {item
                        .createdByMembership
                        .user.name}
                    </span>

                    {item.status ===
                      "PENDING" && (
                      <button
                        disabled={
                          cancellingId ===
                          item.id
                        }
                        onClick={() =>
                          void cancel(
                            item.id
                          )
                        }
                        type="button"
                      >
                        {cancellingId ===
                        item.id
                          ? "Cancelando…"
                          : "Cancelar"}
                      </button>
                    )}
                  </div>

                  {item.status ===
                    "FAILED" &&
                    item.error && (
                      <small className="scheduled-message-item__error">
                        {item.error}
                      </small>
                    )}
                </article>
              )
            )
        )}
      </div>
    </section>
  );
}
