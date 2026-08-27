"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";
import { MessageMedia } from "@/components/messages/message-media";
import { ApiError } from "@/lib/api";

type TicketStatus =
  | "OPEN"
  | "PENDING"
  | "CLOSED";

type MessageType =
  | "TEXT"
  | "IMAGE"
  | "AUDIO"
  | "VIDEO"
  | "DOCUMENT"
  | "STICKER"
  | "LOCATION"
  | "CONTACT"
  | "UNKNOWN";

interface ClosedTicket {
  id: string;
  status: TicketStatus;
  lastMessage: string | null;
  lastMessageAt: string;
  closedAt: string | null;
  contact: {
    id: string;
    name: string;
    phoneNumber: string | null;
    isGroup: boolean;
  };
  queue: {
    id: string;
    name: string;
  } | null;
  assignedMembership: {
    id: string;
    user: {
      id: string;
      name: string;
      email: string;
    };
  } | null;
  tags?: Array<{
    tagId: string;
    tag: {
      id: string;
      name: string;
      colorKey: string;
      isActive: boolean;
    };
  }>;
}

interface ClosedTicketsResponse {
  tickets: ClosedTicket[];
}

interface ArchivedMessage {
  id: string;
  direction:
    | "INBOUND"
    | "OUTBOUND";
  type: MessageType;
  body: string | null;
  mediaMimeType: string | null;
  mediaFileName: string | null;
  mediaStatus:
    | "NONE"
    | "PENDING"
    | "READY"
    | "FAILED";
  mediaSize: number | null;
  timestamp: string;
}

interface MessagesResponse {
  messages: ArchivedMessage[];
}

interface ReopenResponse {
  ticket: ClosedTicket & {
    status:
      | "OPEN"
      | "PENDING";
  };
  reusedExisting: boolean;
}

function dateTimeLabel(
  value: string | null
) {
  if (!value) {
    return "—";
  }

  return new Intl.DateTimeFormat(
    "pt-BR",
    {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit"
    }
  ).format(
    new Date(value)
  );
}

function messageFallback(
  type: MessageType
) {
  switch (type) {
    case "IMAGE":
      return "[Imagem]";
    case "AUDIO":
      return "[Áudio]";
    case "VIDEO":
      return "[Vídeo]";
    case "DOCUMENT":
      return "[Documento]";
    case "STICKER":
      return "[Sticker]";
    case "LOCATION":
      return "[Localização]";
    case "CONTACT":
      return "[Contato]";
    default:
      return "";
  }
}

export function ClosedTicketsDrawer({
  onClose,
  onReopened
}: {
  onClose: () => void;
  onReopened: (
    ticketId: string,
    reusedExisting: boolean
  ) => void;
}) {
  const { request } =
    useAuth();

  const [tickets, setTickets] =
    useState<ClosedTicket[]>([]);
  const [selectedId, setSelectedId] =
    useState<string | null>(null);
  const [messages, setMessages] =
    useState<ArchivedMessage[]>([]);
  const [loadingTickets, setLoadingTickets] =
    useState(true);
  const [loadingMessages, setLoadingMessages] =
    useState(false);
  const [reopening, setReopening] =
    useState(false);
  const [search, setSearch] =
    useState("");
  const [error, setError] =
    useState("");

  const selectedTicket =
    useMemo(
      () =>
        tickets.find(
          ticket =>
            ticket.id ===
            selectedId
        ) ?? null,
      [
        selectedId,
        tickets
      ]
    );

  const visibleTickets =
    useMemo(() => {
      const query =
        search
          .trim()
          .toLowerCase();

      if (!query) {
        return tickets;
      }

      return tickets.filter(
        ticket =>
          ticket.contact.name
            .toLowerCase()
            .includes(query) ||
          (
            ticket.contact
              .phoneNumber ??
            ""
          )
            .toLowerCase()
            .includes(query) ||
          (
            ticket.lastMessage ??
            ""
          )
            .toLowerCase()
            .includes(query)
      );
    }, [
      search,
      tickets
    ]);

  const loadTickets =
    useCallback(async () => {
      setLoadingTickets(true);
      setError("");

      try {
        const payload =
          await request<ClosedTicketsResponse>(
            "/api/v1/tickets?status=CLOSED"
          );

        setTickets(
          payload.tickets
        );

        setSelectedId(
          current =>
            current &&
            payload.tickets.some(
              ticket =>
                ticket.id ===
                current
            )
              ? current
              : payload.tickets[0]
                  ?.id ??
                null
        );
      } catch {
        setError(
          "Não foi possível carregar os atendimentos encerrados."
        );
      } finally {
        setLoadingTickets(false);
      }
    }, [request]);

  useEffect(() => {
    void loadTickets();
  }, [loadTickets]);

  useEffect(() => {
    if (!selectedId) {
      setMessages([]);
      return;
    }

    let cancelled = false;

    void (async () => {
      setLoadingMessages(true);
      setError("");

      try {
        const payload =
          await request<MessagesResponse>(
            `/api/v1/tickets/${selectedId}/messages`
          );

        if (!cancelled) {
          setMessages(
            payload.messages
          );
        }
      } catch {
        if (!cancelled) {
          setError(
            "Não foi possível carregar o histórico deste atendimento."
          );
        }
      } finally {
        if (!cancelled) {
          setLoadingMessages(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [
    request,
    selectedId
  ]);

  async function reopen() {
    if (
      !selectedId ||
      reopening
    ) {
      return;
    }

    setReopening(true);
    setError("");

    try {
      const payload =
        await request<ReopenResponse>(
          `/api/v1/tickets/${selectedId}/reopen`,
          {
            method: "POST"
          }
        );

      onReopened(
        payload.ticket.id,
        payload.reusedExisting
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível reabrir o atendimento."
      );
    } finally {
      setReopening(false);
    }
  }

  return (
    <aside className="closed-tickets-drawer">
      <header className="closed-tickets-drawer__header">
        <div>
          <span className="eyebrow">
            Histórico
          </span>
          <strong>
            Atendimentos encerrados
          </strong>
          <small>
            Consulte o histórico e reabra somente quando necessário.
          </small>
        </div>

        <button
          aria-label="Fechar atendimentos encerrados"
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      {error && (
        <div className="closed-tickets-drawer__error">
          {error}
        </div>
      )}

      <div className="closed-tickets-layout">
        <section className="closed-tickets-list">
          <div className="closed-tickets-list__search">
            <input
              onChange={event =>
                setSearch(
                  event.target.value
                )
              }
              placeholder="Buscar encerrado…"
              value={search}
            />
            <span>
              {visibleTickets.length}
            </span>
          </div>

          <div className="closed-tickets-list__items">
            {loadingTickets ? (
              <div className="closed-tickets-empty">
                Carregando…
              </div>
            ) : visibleTickets.length === 0 ? (
              <div className="closed-tickets-empty">
                Nenhum atendimento encerrado.
              </div>
            ) : (
              visibleTickets.map(
                ticket => (
                  <button
                    className={
                      ticket.id ===
                      selectedId
                        ? "closed-ticket-row closed-ticket-row--active"
                        : "closed-ticket-row"
                    }
                    key={ticket.id}
                    onClick={() =>
                      setSelectedId(
                        ticket.id
                      )
                    }
                    type="button"
                  >
                    <div className="closed-ticket-row__top">
                      <strong>
                        {
                          ticket
                            .contact
                            .name
                        }
                      </strong>
                      <time>
                        {dateTimeLabel(
                          ticket.closedAt
                        )}
                      </time>
                    </div>

                    <p>
                      {ticket.lastMessage ??
                        "Sem mensagem"}
                    </p>

                    <div className="closed-ticket-row__meta">
                      <span>
                        {
                          ticket.queue
                            ?.name ??
                          "Sem fila"
                        }
                      </span>

                      <span>
                        {
                          ticket
                            .assignedMembership
                            ?.user
                            .name ??
                          "Sem atendente"
                        }
                      </span>
                    </div>
                  </button>
                )
              )
            )}
          </div>
        </section>

        <section className="closed-ticket-history">
          {!selectedTicket ? (
            <div className="closed-tickets-empty">
              Selecione um atendimento.
            </div>
          ) : (
            <>
              <header className="closed-ticket-history__header">
                <div>
                  <strong>
                    {
                      selectedTicket
                        .contact
                        .name
                    }
                  </strong>
                  <span>
                    {
                      selectedTicket
                        .contact
                        .phoneNumber ??
                      (
                        selectedTicket
                          .contact
                          .isGroup
                          ? "Grupo"
                          : "Sem telefone"
                      )
                    }
                  </span>
                  <small>
                    Encerrado em{" "}
                    {dateTimeLabel(
                      selectedTicket.closedAt
                    )}
                  </small>
                </div>

                <button
                  disabled={reopening}
                  onClick={() =>
                    void reopen()
                  }
                  type="button"
                >
                  {reopening
                    ? "Reabrindo…"
                    : "Reabrir atendimento"}
                </button>
              </header>

              <div className="closed-ticket-history__messages">
                {loadingMessages ? (
                  <div className="closed-tickets-empty">
                    Carregando histórico…
                  </div>
                ) : messages.length === 0 ? (
                  <div className="closed-tickets-empty">
                    Nenhuma mensagem neste atendimento.
                  </div>
                ) : (
                  messages.map(
                    message => (
                      <article
                        className={
                          message.direction ===
                          "OUTBOUND"
                            ? "archived-message archived-message--outbound"
                            : "archived-message"
                        }
                        key={message.id}
                      >
                        <MessageMedia
                          fileName={
                            message.mediaFileName
                          }
                          messageId={
                            message.id
                          }
                          mimeType={
                            message.mediaMimeType
                          }
                          status={
                            message.mediaStatus
                          }
                          type={
                            message.type
                          }
                        />

                        {(message.body ??
                          messageFallback(
                            message.type
                          )) && (
                          <p>
                            {message.body ??
                              messageFallback(
                                message.type
                              )}
                          </p>
                        )}

                        <time>
                          {dateTimeLabel(
                            message.timestamp
                          )}
                        </time>
                      </article>
                    )
                  )
                )}
              </div>

              <footer className="closed-ticket-history__footer">
                Histórico em modo leitura.
              </footer>
            </>
          )}
        </section>
      </div>
    </aside>
  );
}
