"use client";

import {
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";

type SearchScope =
  | "ALL"
  | "CURRENT";

interface SearchMessage {
  id: string;
  ticketId: string;
  direction:
    | "INBOUND"
    | "OUTBOUND";
  type: string;
  body: string | null;
  mediaFileName: string | null;
  mediaMimeType: string | null;
  timestamp: string;
  ticket: {
    id: string;
    status:
      | "OPEN"
      | "PENDING"
      | "CLOSED";
    lastMessageAt: string;
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
      };
    } | null;
  };
}

interface SearchResponse {
  messages: SearchMessage[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
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
      minute: "2-digit"
    }
  ).format(
    new Date(value)
  );
}

function messageLabel(
  message: SearchMessage
) {
  if (message.body?.trim()) {
    return message.body.trim();
  }

  if (
    message.mediaFileName?.trim()
  ) {
    return message.mediaFileName;
  }

  switch (
    message.type.toUpperCase()
  ) {
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
    default:
      return `[${message.type}]`;
  }
}

function snippet(
  value: string,
  query: string
) {
  const clean =
    value.replace(
      /\s+/g,
      " "
    );

  const lower =
    clean.toLowerCase();

  const needle =
    query
      .trim()
      .toLowerCase();

  const found =
    lower.indexOf(needle);

  if (
    found < 0 ||
    clean.length <= 150
  ) {
    return clean.slice(
      0,
      150
    );
  }

  const start =
    Math.max(
      0,
      found - 55
    );

  const end =
    Math.min(
      clean.length,
      found +
        needle.length +
        80
    );

  return `${
    start > 0
      ? "…"
      : ""
  }${clean.slice(start, end)}${
    end < clean.length
      ? "…"
      : ""
  }`;
}

export function ConversationSearch({
  selectedTicketId,
  onClose,
  onOpenTicket
}: {
  selectedTicketId: string | null;
  onClose: () => void;
  onOpenTicket: (
    ticketId: string,
    messageId: string
  ) => void;
}) {
  const { request } =
    useAuth();

  const [query, setQuery] =
    useState("");
  const [scope, setScope] =
    useState<SearchScope>(
      selectedTicketId
        ? "CURRENT"
        : "ALL"
    );
  const [page, setPage] =
    useState(1);
  const [results, setResults] =
    useState<SearchMessage[]>([]);
  const [pagination, setPagination] =
    useState<SearchResponse["pagination"]>({
      page: 1,
      limit: 30,
      total: 0,
      pages: 1
    });
  const [loading, setLoading] =
    useState(false);
  const [error, setError] =
    useState("");

  const canSearchCurrent =
    Boolean(selectedTicketId);

  const trimmedQuery =
    query.trim();

  const ready =
    trimmedQuery.length >= 2;

  useEffect(() => {
    if (
      scope === "CURRENT" &&
      !selectedTicketId
    ) {
      setScope("ALL");
    }
  }, [
    scope,
    selectedTicketId
  ]);

  useEffect(() => {
    setPage(1);
  }, [
    query,
    scope,
    selectedTicketId
  ]);

  useEffect(() => {
    if (!ready) {
      setResults([]);
      setPagination({
        page: 1,
        limit: 30,
        total: 0,
        pages: 1
      });
      setError("");
      return;
    }

    let cancelled = false;

    const timer =
      window.setTimeout(
        () => {
          void (async () => {
            setLoading(true);
            setError("");

            try {
              const params =
                new URLSearchParams({
                  q:
                    trimmedQuery,
                  page:
                    String(page),
                  limit:
                    "30"
                });

              if (
                scope ===
                  "CURRENT" &&
                selectedTicketId
              ) {
                params.set(
                  "ticketId",
                  selectedTicketId
                );
              }

              const payload =
                await request<SearchResponse>(
                  `/api/v1/messages/search?${params.toString()}`
                );

              if (cancelled) {
                return;
              }

              setResults(
                payload.messages
              );

              setPagination(
                payload.pagination
              );
            } catch {
              if (!cancelled) {
                setError(
                  "Não foi possível pesquisar o histórico."
                );
              }
            } finally {
              if (!cancelled) {
                setLoading(false);
              }
            }
          })();
        },
        280
      );

    return () => {
      cancelled = true;
      window.clearTimeout(
        timer
      );
    };
  }, [
    page,
    ready,
    request,
    scope,
    selectedTicketId,
    trimmedQuery
  ]);

  const resultLabel =
    useMemo(() => {
      if (!ready) {
        return "Digite pelo menos 2 caracteres.";
      }

      if (loading) {
        return "Pesquisando…";
      }

      if (
        pagination.total === 0
      ) {
        return "Nenhum resultado.";
      }

      return `${pagination.total} resultado${
        pagination.total === 1
          ? ""
          : "s"
      }`;
    }, [
      loading,
      pagination.total,
      ready
    ]);

  return (
    <aside className="conversation-search">
      <header className="conversation-search__header">
        <div>
          <span className="eyebrow">
            Histórico
          </span>
          <strong>
            Buscar mensagens
          </strong>
          <small>
            Pesquisa no banco, não apenas no que está carregado na tela.
          </small>
        </div>

        <button
          aria-label="Fechar busca"
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      <div className="conversation-search__controls">
        <input
          autoFocus
          maxLength={160}
          onChange={event =>
            setQuery(
              event.target.value
            )
          }
          placeholder="Mensagem, arquivo, contato ou telefone…"
          value={query}
        />

        <div className="conversation-search__scope">
          <button
            className={
              scope === "ALL"
                ? "conversation-search__scope-button conversation-search__scope-button--active"
                : "conversation-search__scope-button"
            }
            onClick={() =>
              setScope("ALL")
            }
            type="button"
          >
            Todas
          </button>

          <button
            className={
              scope === "CURRENT"
                ? "conversation-search__scope-button conversation-search__scope-button--active"
                : "conversation-search__scope-button"
            }
            disabled={
              !canSearchCurrent
            }
            onClick={() =>
              setScope(
                "CURRENT"
              )
            }
            type="button"
          >
            Este atendimento
          </button>
        </div>

        <span className="conversation-search__count">
          {resultLabel}
        </span>
      </div>

      <div className="conversation-search__results">
        {error && (
          <div className="conversation-search__empty conversation-search__empty--error">
            {error}
          </div>
        )}

        {!error &&
          ready &&
          !loading &&
          results.length === 0 && (
            <div className="conversation-search__empty">
              Nenhuma mensagem encontrada com esse termo.
            </div>
          )}

        {!error &&
          results.map(
            message => {
              const active =
                message.ticket.status !==
                "CLOSED";

              return (
                <article
                  className="conversation-search-result"
                  key={
                    message.id
                  }
                >
                  <div className="conversation-search-result__top">
                    <div>
                      <strong>
                        {
                          message
                            .ticket
                            .contact
                            .name
                        }
                      </strong>
                      <span>
                        {
                          message
                            .ticket
                            .contact
                            .phoneNumber ??
                          (
                            message
                              .ticket
                              .contact
                              .isGroup
                              ? "Grupo"
                              : "Sem telefone"
                          )
                        }
                      </span>
                    </div>

                    <time>
                      {dateTimeLabel(
                        message.timestamp
                      )}
                    </time>
                  </div>

                  <p>
                    {snippet(
                      messageLabel(
                        message
                      ),
                      trimmedQuery
                    )}
                  </p>

                  <div className="conversation-search-result__meta">
                    <span>
                      {message.direction ===
                      "INBOUND"
                        ? "Cliente"
                        : "Equipe"}
                    </span>

                    <span>
                      {
                        message
                          .ticket
                          .queue
                          ?.name ??
                        "Sem fila"
                      }
                    </span>

                    <span
                      className={
                        active
                          ? "conversation-search-result__status"
                          : "conversation-search-result__status conversation-search-result__status--closed"
                      }
                    >
                      {
                        message
                          .ticket
                          .status
                      }
                    </span>

                    {active ? (
                      <button
                        onClick={() =>
                          onOpenTicket(
                            message.ticketId,
                            message.id
                          )
                        }
                        type="button"
                      >
                        Abrir atendimento
                      </button>
                    ) : (
                      <span>
                        Atendimento encerrado
                      </span>
                    )}
                  </div>
                </article>
              );
            }
          )}
      </div>

      {ready &&
        pagination.pages > 1 && (
          <footer className="conversation-search__pagination">
            <button
              disabled={
                page <= 1 ||
                loading
              }
              onClick={() =>
                setPage(
                  current =>
                    Math.max(
                      1,
                      current - 1
                    )
                )
              }
              type="button"
            >
              Anterior
            </button>

            <span>
              {pagination.page}
              {" / "}
              {pagination.pages}
            </span>

            <button
              disabled={
                page >=
                  pagination.pages ||
                loading
              }
              onClick={() =>
                setPage(
                  current =>
                    Math.min(
                      pagination.pages,
                      current + 1
                    )
                )
              }
              type="button"
            >
              Próxima
            </button>
          </footer>
        )}
    </aside>
  );
}
