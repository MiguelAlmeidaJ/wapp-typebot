"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";

type EventType =
  | "CREATED"
  | "CLAIMED"
  | "TRANSFERRED"
  | "CLOSED"
  | "REOPENED"
  | "TAGS_UPDATED"
  | "AUTOMATION_APPLIED"
  | string;

interface TicketEvent {
  id: string;
  type: EventType;
  metadata:
    | Record<string, unknown>
    | null;
  createdAt: string;
  actorMembership: {
    id: string;
    role: string;
    user: {
      id: string;
      name: string;
      email: string;
    };
  } | null;
}

interface TicketEventsResponse {
  events: TicketEvent[];
}

function dateTimeLabel(
  value: string
) {
  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit"
    }
  ).format(
    new Date(value)
  );
}

function text(
  metadata: Record<string, unknown> | null,
  key: string
) {
  const value =
    metadata?.[key];

  return typeof value ===
    "string" &&
    value.trim()
      ? value
      : null;
}

function stringList(
  metadata: Record<string, unknown> | null,
  key: string
) {
  const value =
    metadata?.[key];

  return Array.isArray(value)
    ? value.filter(
        item =>
          typeof item ===
          "string"
      ) as string[]
    : [];
}

function eventTitle(
  type: EventType
) {
  switch (type) {
    case "CREATED":
      return "Atendimento criado";
    case "CLAIMED":
      return "Atendimento assumido";
    case "TRANSFERRED":
      return "Atendimento transferido";
    case "CLOSED":
      return "Atendimento encerrado";
    case "REOPENED":
      return "Atendimento reaberto";
    case "TAGS_UPDATED":
      return "Etiquetas atualizadas";
    case "MESSAGE_SCHEDULED":
      return "Mensagem agendada";
    case "SCHEDULED_MESSAGE_CANCELLED":
      return "Agendamento cancelado";
    case "SCHEDULED_MESSAGE_SENT":
      return "Mensagem agendada enviada";
    case "SCHEDULED_MESSAGE_FAILED":
      return "Falha no agendamento";
    case "AUTOMATION_APPLIED":
      return "Automação executada";
    default:
      return type;
  }
}

function eventDetail(
  event: TicketEvent
) {
  const metadata =
    event.metadata;

  switch (event.type) {
    case "CREATED": {
      const direction =
        text(
          metadata,
          "initialDirection"
        );

      return direction ===
        "INBOUND"
        ? "Criado a partir de uma nova mensagem recebida."
        : direction ===
            "OUTBOUND"
          ? "Criado a partir de uma mensagem enviada."
          : "Atendimento iniciado.";
    }

    case "CLAIMED": {
      const assignee =
        text(
          metadata,
          "assigneeName"
        );

      return assignee
        ? `Assumido por ${assignee}.`
        : "O atendimento foi assumido.";
    }

    case "TRANSFERRED": {
      const fromQueue =
        text(
          metadata,
          "fromQueueName"
        ) ??
        "sem fila";

      const toQueue =
        text(
          metadata,
          "toQueueName"
        ) ??
        "sem fila";

      const fromAssignee =
        text(
          metadata,
          "fromAssigneeName"
        ) ??
        "sem atendente";

      const toAssignee =
        text(
          metadata,
          "toAssigneeName"
        ) ??
        "sem atendente";

      return `Fila: ${fromQueue} → ${toQueue}. Atendente: ${fromAssignee} → ${toAssignee}.`;
    }

    case "CLOSED":
      return "O atendimento foi encerrado.";

    case "REOPENED": {
      const assignee =
        text(
          metadata,
          "assigneeName"
        );

      return assignee
        ? `Reaberto e atribuído a ${assignee}.`
        : "O atendimento foi reaberto.";
    }

    case "TAGS_UPDATED": {
      const names =
        stringList(
          metadata,
          "tagNames"
        );

      return names.length > 0
        ? `Etiquetas atuais: ${names.join(", ")}.`
        : "Todas as etiquetas foram removidas.";
    }

    case "AUTOMATION_APPLIED": {
      const ruleName =
        text(
          metadata,
          "ruleName"
        );

      const trigger =
        text(
          metadata,
          "trigger"
        );

      const triggerLabel =
        trigger ===
          "TICKET_CREATED"
          ? "novo atendimento"
          : trigger ===
              "INBOUND_MESSAGE"
            ? "mensagem recebida"
            : null;

      if (
        ruleName &&
        triggerLabel
      ) {
        return `A regra “${ruleName}” foi executada por ${triggerLabel}.`;
      }

      if (ruleName) {
        return `A regra “${ruleName}” foi executada.`;
      }

      return "Uma automação operacional foi executada pelo sistema.";
    }

    case "MESSAGE_SCHEDULED": {
      const scheduledFor =
        text(
          metadata,
          "scheduledFor"
        );

      return scheduledFor
        ? `Envio programado para ${dateTimeLabel(scheduledFor)}.`
        : "Uma mensagem foi programada para envio.";
    }

    case "SCHEDULED_MESSAGE_CANCELLED":
      return "O envio programado foi cancelado.";

    case "SCHEDULED_MESSAGE_SENT": {
      const scheduledFor =
        text(
          metadata,
          "scheduledFor"
        );

      return scheduledFor
        ? `Mensagem programada para ${dateTimeLabel(scheduledFor)} enviada pelo sistema.`
        : "A mensagem agendada foi enviada.";
    }

    case "SCHEDULED_MESSAGE_FAILED": {
      const reason =
        text(
          metadata,
          "reason"
        );

      return reason
        ? `Falha no envio agendado: ${reason}`
        : "O envio agendado falhou.";
    }

    default:
      return "Evento operacional registrado.";
  }
}

export function TicketHistoryDrawer({
  ticketId,
  contactName,
  onClose
}: {
  ticketId: string;
  contactName: string;
  onClose: () => void;
}) {
  const {
    request,
    subscribe
  } = useAuth();

  const [events, setEvents] =
    useState<TicketEvent[]>([]);
  const [loading, setLoading] =
    useState(true);
  const [error, setError] =
    useState("");

  const load =
    useCallback(async () => {
      try {
        const payload =
          await request<TicketEventsResponse>(
            `/api/v1/tickets/${ticketId}/events`
          );

        setEvents(
          payload.events
        );
        setError("");
      } catch {
        setError(
          "Não foi possível carregar o histórico operacional."
        );
      } finally {
        setLoading(false);
      }
    }, [
      request,
      ticketId
    ]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    return subscribe(
      "/api/v1/realtime/events",
      event => {
        if (
          event.type ===
            "ticket.event.created" &&
          event.ticketId ===
            ticketId
        ) {
          void load();
        }
      }
    );
  }, [
    load,
    subscribe,
    ticketId
  ]);

  const grouped =
    useMemo(
      () => events,
      [events]
    );

  return (
    <aside className="ticket-history-drawer">
      <header className="ticket-history-drawer__header">
        <div>
          <span className="eyebrow">
            Auditoria
          </span>
          <strong>
            Histórico operacional
          </strong>
          <small>
            {contactName}
          </small>
        </div>

        <button
          aria-label="Fechar histórico operacional"
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      <div className="ticket-history-drawer__intro">
        Mensagens e notas continuam em seus próprios históricos. Aqui ficam apenas movimentações do atendimento.
      </div>

      <div className="ticket-history-drawer__events">
        {error && (
          <div className="ticket-history-empty ticket-history-empty--error">
            {error}
          </div>
        )}

        {!error &&
          loading && (
            <div className="ticket-history-empty">
              Carregando histórico…
            </div>
          )}

        {!error &&
          !loading &&
          grouped.length ===
            0 && (
            <div className="ticket-history-empty">
              Nenhuma movimentação registrada ainda. A auditoria passa a registrar novos eventos a partir do P1.12.
            </div>
          )}

        {!error &&
          grouped.map(event => (
            <article
              className={`ticket-history-event ticket-history-event--${event.type.toLowerCase()}`}
              key={event.id}
            >
              <div className="ticket-history-event__rail">
                <span />
              </div>

              <div className="ticket-history-event__content">
                <div className="ticket-history-event__heading">
                  <strong>
                    {eventTitle(
                      event.type
                    )}
                  </strong>

                  <time>
                    {dateTimeLabel(
                      event.createdAt
                    )}
                  </time>
                </div>

                <p>
                  {eventDetail(
                    event
                  )}
                </p>

                <span className="ticket-history-event__actor">
                  {event
                    .actorMembership
                    ?.user.name ??
                    "Sistema"}
                  {event
                    .actorMembership
                    ?.role
                    ? ` · ${event.actorMembership.role}`
                    : ""}
                </span>
              </div>
            </article>
          ))}
      </div>
    </aside>
  );
}
