"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type SlaFilter =
  | "ALL"
  | "WAITING"
  | "RISK"
  | "BREACHED";

interface SlaSettings {
  id: string;
  firstResponseSlaMinutes: number;
  replySlaMinutes: number;
}

interface SlaTicket {
  id: string;
  status:
    | "OPEN"
    | "PENDING";
  lastMessage: string | null;
  lastMessageAt: string;
  firstInboundAt: string | null;
  firstResponseAt: string | null;
  lastInboundAt: string | null;
  lastOutboundAt: string | null;
  waitingSince: string | null;
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
}

interface TicketsResponse {
  tickets: SlaTicket[];
}

interface SettingsResponse {
  settings: SlaSettings;
}

type SlaSeverity =
  | "OK"
  | "WAITING"
  | "RISK"
  | "BREACHED";

function elapsedMinutes(
  from: string | null,
  now: number
) {
  if (!from) {
    return 0;
  }

  return Math.max(
    0,
    Math.floor(
      (
        now -
        new Date(from).getTime()
      ) /
        60_000
    )
  );
}

function durationLabel(
  minutes: number
) {
  if (minutes < 60) {
    return `${minutes}m`;
  }

  const hours =
    Math.floor(
      minutes / 60
    );

  const remainder =
    minutes % 60;

  if (hours < 24) {
    return remainder
      ? `${hours}h ${remainder}m`
      : `${hours}h`;
  }

  const days =
    Math.floor(
      hours / 24
    );

  const remainingHours =
    hours % 24;

  return remainingHours
    ? `${days}d ${remainingHours}h`
    : `${days}d`;
}

function severityFor(
  elapsed: number,
  limit: number
): SlaSeverity {
  if (elapsed >= limit) {
    return "BREACHED";
  }

  if (
    elapsed >=
    Math.ceil(
      limit * 0.7
    )
  ) {
    return "RISK";
  }

  return "WAITING";
}

export function SlaMonitorDrawer({
  onClose,
  onOpenTicket
}: {
  onClose: () => void;
  onOpenTicket: (
    ticketId: string
  ) => void;
}) {
  const {
    request,
    session,
    subscribe
  } = useAuth();

  const [tickets, setTickets] =
    useState<SlaTicket[]>([]);
  const [settings, setSettings] =
    useState<SlaSettings | null>(null);
  const [filter, setFilter] =
    useState<SlaFilter>("ALL");
  const [now, setNow] =
    useState(
      () => Date.now()
    );
  const [loading, setLoading] =
    useState(true);
  const [saving, setSaving] =
    useState(false);
  const [error, setError] =
    useState("");
  const [firstResponseMinutes, setFirstResponseMinutes] =
    useState("15");
  const [replyMinutes, setReplyMinutes] =
    useState("30");

  const canManage =
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
    useCallback(async () => {
      try {
        const [
          ticketPayload,
          settingsPayload
        ] =
          await Promise.all([
            request<TicketsResponse>(
              "/api/v1/tickets?status=ACTIVE"
            ),
            request<SettingsResponse>(
              "/api/v1/sla/settings"
            )
          ]);

        setTickets(
          ticketPayload.tickets
        );
        setSettings(
          settingsPayload.settings
        );
        setFirstResponseMinutes(
          String(
            settingsPayload
              .settings
              .firstResponseSlaMinutes
          )
        );
        setReplyMinutes(
          String(
            settingsPayload
              .settings
              .replySlaMinutes
          )
        );
        setError("");
      } catch {
        setError(
          "Não foi possível carregar os indicadores de SLA."
        );
      } finally {
        setLoading(false);
      }
    }, [request]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const interval =
      window.setInterval(
        () => {
          setNow(
            Date.now()
          );
        },
        30_000
      );

    return () => {
      window.clearInterval(
        interval
      );
    };
  }, []);

  useEffect(() => {
    return subscribe(
      "/api/v1/realtime/events",
      event => {
        if (
          event.type ===
            "ticket.created" ||
          event.type ===
            "ticket.updated" ||
          event.type ===
            "message.created" ||
          event.type ===
            "sla.updated"
        ) {
          void load();
        }
      }
    );
  }, [
    load,
    subscribe
  ]);

  const rows =
    useMemo(() => {
      if (!settings) {
        return [];
      }

      return tickets
        .map(ticket => {
          const waitingMinutes =
            elapsedMinutes(
              ticket.waitingSince,
              now
            );

          const firstResponseWaiting =
            Boolean(
              ticket.firstInboundAt &&
              !ticket.firstResponseAt
            );

          const firstResponseElapsed =
            firstResponseWaiting
              ? elapsedMinutes(
                  ticket.firstInboundAt,
                  now
                )
              : ticket.firstInboundAt &&
                  ticket.firstResponseAt
                ? Math.max(
                    0,
                    Math.floor(
                      (
                        new Date(
                          ticket.firstResponseAt
                        ).getTime() -
                        new Date(
                          ticket.firstInboundAt
                        ).getTime()
                      ) /
                        60_000
                    )
                  )
                : 0;

          const responseSeverity =
            ticket.waitingSince
              ? severityFor(
                  waitingMinutes,
                  settings.replySlaMinutes
                )
              : "OK";

          const firstSeverity =
            firstResponseWaiting
              ? severityFor(
                  firstResponseElapsed,
                  settings
                    .firstResponseSlaMinutes
                )
              : "OK";

          const severity: SlaSeverity =
            responseSeverity ===
              "BREACHED" ||
            firstSeverity ===
              "BREACHED"
              ? "BREACHED"
              : responseSeverity ===
                    "RISK" ||
                  firstSeverity ===
                    "RISK"
                ? "RISK"
                : ticket.waitingSince ||
                    firstResponseWaiting
                  ? "WAITING"
                  : "OK";

          const score =
            severity ===
            "BREACHED"
              ? 4
              : severity ===
                  "RISK"
                ? 3
                : severity ===
                    "WAITING"
                  ? 2
                  : 1;

          return {
            ticket,
            waitingMinutes,
            firstResponseElapsed,
            firstResponseWaiting,
            severity,
            score
          };
        })
        .filter(row => {
          if (
            filter === "ALL"
          ) {
            return true;
          }

          if (
            filter === "WAITING"
          ) {
            return (
              row.ticket
                .waitingSince !==
                null ||
              row.firstResponseWaiting
            );
          }

          return (
            row.severity ===
            filter
          );
        })
        .sort(
          (a, b) =>
            b.score -
              a.score ||
            b.waitingMinutes -
              a.waitingMinutes ||
            new Date(
              a.ticket
                .lastMessageAt
            ).getTime() -
              new Date(
                b.ticket
                  .lastMessageAt
              ).getTime()
        );
    }, [
      filter,
      now,
      settings,
      tickets
    ]);

  const counts =
    useMemo(() => {
      if (!settings) {
        return {
          waiting: 0,
          risk: 0,
          breached: 0
        };
      }

      let waiting = 0;
      let risk = 0;
      let breached = 0;

      for (const ticket of tickets) {
        const currentWaiting =
          ticket.waitingSince
            ? severityFor(
                elapsedMinutes(
                  ticket.waitingSince,
                  now
                ),
                settings
                  .replySlaMinutes
              )
            : "OK";

        const firstWaiting =
          ticket.firstInboundAt &&
          !ticket.firstResponseAt
            ? severityFor(
                elapsedMinutes(
                  ticket.firstInboundAt,
                  now
                ),
                settings
                  .firstResponseSlaMinutes
              )
            : "OK";

        if (
          currentWaiting ===
            "BREACHED" ||
          firstWaiting ===
            "BREACHED"
        ) {
          breached += 1;
        } else if (
          currentWaiting ===
            "RISK" ||
          firstWaiting ===
            "RISK"
        ) {
          risk += 1;
        }

        if (
          ticket.waitingSince ||
          (
            ticket.firstInboundAt &&
            !ticket.firstResponseAt
          )
        ) {
          waiting += 1;
        }
      }

      return {
        waiting,
        risk,
        breached
      };
    }, [
      now,
      settings,
      tickets
    ]);

  async function saveSettings() {
    const first =
      Number(
        firstResponseMinutes
      );

    const reply =
      Number(
        replyMinutes
      );

    if (
      !Number.isInteger(first) ||
      !Number.isInteger(reply) ||
      first < 1 ||
      reply < 1 ||
      first > 1440 ||
      reply > 1440
    ) {
      setError(
        "Informe tempos entre 1 e 1440 minutos."
      );
      return;
    }

    setSaving(true);
    setError("");

    try {
      const payload =
        await request<SettingsResponse>(
          "/api/v1/sla/settings",
          {
            method: "PUT",
            body: JSON.stringify({
              firstResponseSlaMinutes:
                first,
              replySlaMinutes:
                reply
            })
          }
        );

      setSettings(
        payload.settings
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar o SLA."
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <aside className="sla-monitor">
      <header className="sla-monitor__header">
        <div>
          <span className="eyebrow">
            Operação
          </span>
          <strong>
            Monitor de SLA
          </strong>
          <small>
            Relógio baseado em mensagens reais de entrada e resposta.
          </small>
        </div>

        <button
          aria-label="Fechar monitor de SLA"
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      {error && (
        <div className="sla-monitor__error">
          {error}
        </div>
      )}

      <section className="sla-summary">
        <button
          className={
            filter === "WAITING"
              ? "sla-summary-card sla-summary-card--active"
              : "sla-summary-card"
          }
          onClick={() =>
            setFilter("WAITING")
          }
          type="button"
        >
          <span>Aguardando</span>
          <strong>
            {counts.waiting}
          </strong>
        </button>

        <button
          className={
            filter === "RISK"
              ? "sla-summary-card sla-summary-card--risk sla-summary-card--active"
              : "sla-summary-card sla-summary-card--risk"
          }
          onClick={() =>
            setFilter("RISK")
          }
          type="button"
        >
          <span>Em risco</span>
          <strong>
            {counts.risk}
          </strong>
        </button>

        <button
          className={
            filter === "BREACHED"
              ? "sla-summary-card sla-summary-card--breached sla-summary-card--active"
              : "sla-summary-card sla-summary-card--breached"
          }
          onClick={() =>
            setFilter("BREACHED")
          }
          type="button"
        >
          <span>Estourados</span>
          <strong>
            {counts.breached}
          </strong>
        </button>

        <button
          className={
            filter === "ALL"
              ? "sla-summary-card sla-summary-card--active"
              : "sla-summary-card"
          }
          onClick={() =>
            setFilter("ALL")
          }
          type="button"
        >
          <span>Ativos</span>
          <strong>
            {tickets.length}
          </strong>
        </button>
      </section>

      {canManage &&
        settings && (
          <section className="sla-settings">
            <label>
              <span>
                Primeira resposta
              </span>
              <div>
                <input
                  inputMode="numeric"
                  max={1440}
                  min={1}
                  onChange={event =>
                    setFirstResponseMinutes(
                      event.target.value
                    )
                  }
                  type="number"
                  value={
                    firstResponseMinutes
                  }
                />
                <small>min</small>
              </div>
            </label>

            <label>
              <span>
                Próxima resposta
              </span>
              <div>
                <input
                  inputMode="numeric"
                  max={1440}
                  min={1}
                  onChange={event =>
                    setReplyMinutes(
                      event.target.value
                    )
                  }
                  type="number"
                  value={
                    replyMinutes
                  }
                />
                <small>min</small>
              </div>
            </label>

            <button
              disabled={saving}
              onClick={() =>
                void saveSettings()
              }
              type="button"
            >
              {saving
                ? "Salvando…"
                : "Salvar SLA"}
            </button>
          </section>
        )}

      <div className="sla-monitor__list">
        {loading ? (
          <div className="sla-monitor__empty">
            Carregando indicadores…
          </div>
        ) : rows.length === 0 ? (
          <div className="sla-monitor__empty">
            Nenhum atendimento neste filtro.
          </div>
        ) : (
          rows.map(row => (
            <article
              className={`sla-ticket sla-ticket--${row.severity.toLowerCase()}`}
              key={
                row.ticket.id
              }
            >
              <div className="sla-ticket__heading">
                <div>
                  <strong>
                    {
                      row.ticket
                        .contact
                        .name
                    }
                  </strong>
                  <span>
                    {
                      row.ticket
                        .queue
                        ?.name ??
                      "Sem fila"
                    }
                    {" · "}
                    {
                      row.ticket
                        .assignedMembership
                        ?.user
                        .name ??
                      "Sem atendente"
                    }
                  </span>
                </div>

                <span className="sla-ticket__severity">
                  {row.severity ===
                  "BREACHED"
                    ? "SLA estourado"
                    : row.severity ===
                        "RISK"
                      ? "Em risco"
                      : row.severity ===
                          "WAITING"
                        ? "Aguardando"
                        : "Em dia"}
                </span>
              </div>

              <div className="sla-ticket__metrics">
                {row.ticket
                  .waitingSince ? (
                  <div>
                    <span>
                      Cliente aguardando
                    </span>
                    <strong>
                      {durationLabel(
                        row.waitingMinutes
                      )}
                    </strong>
                    <small>
                      limite{" "}
                      {
                        settings
                          ?.replySlaMinutes
                      }
                      m
                    </small>
                  </div>
                ) : (
                  <div>
                    <span>
                      Resposta atual
                    </span>
                    <strong>
                      Em dia
                    </strong>
                    <small>
                      sem espera do cliente
                    </small>
                  </div>
                )}

                <div>
                  <span>
                    1ª resposta
                  </span>

                  {!row.ticket
                    .firstInboundAt ? (
                    <>
                      <strong>
                        —
                      </strong>
                      <small>
                        sem entrada
                      </small>
                    </>
                  ) : row.firstResponseWaiting ? (
                    <>
                      <strong>
                        {durationLabel(
                          row
                            .firstResponseElapsed
                        )}
                      </strong>
                      <small>
                        aguardando resposta
                      </small>
                    </>
                  ) : (
                    <>
                      <strong>
                        {durationLabel(
                          row
                            .firstResponseElapsed
                        )}
                      </strong>
                      <small>
                        {row.firstResponseElapsed <=
                        (
                          settings
                            ?.firstResponseSlaMinutes ??
                          0
                        )
                          ? "dentro do SLA"
                          : "fora do SLA"}
                      </small>
                    </>
                  )}
                </div>
              </div>

              <p>
                {row.ticket
                  .lastMessage ??
                  "Sem mensagem"}
              </p>

              <button
                onClick={() =>
                  onOpenTicket(
                    row.ticket.id
                  )
                }
                type="button"
              >
                Abrir atendimento
              </button>
            </article>
          ))
        )}
      </div>
    </aside>
  );
}
