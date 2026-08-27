"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";

type PeriodDays =
  | 7
  | 30
  | 90;

interface OperationalAnalytics {
  period: {
    days: PeriodDays;
    from: string;
    to: string;
  };
  sla: {
    firstResponseSlaMinutes: number;
    replySlaMinutes: number;
  };
  summary: {
    active: number;
    waiting: number;
    risk: number;
    breached: number;
    created: number;
    closed: number;
    averageFirstResponseMinutes: number | null;
    firstResponseSlaPercent: number | null;
    firstResponseSamples: number;
  };
  trend: Array<{
    date: string;
    created: number;
    closed: number;
  }>;
  byQueue: Array<{
    id: string | null;
    name: string;
    active: number;
    waiting: number;
    breached: number;
  }>;
  byAssignee: Array<{
    id: string | null;
    name: string;
    active: number;
    waiting: number;
    breached: number;
  }>;
}

function durationLabel(
  minutes: number | null
) {
  if (minutes === null) {
    return "—";
  }

  if (minutes < 60) {
    return `${minutes}m`;
  }

  const hours =
    Math.floor(
      minutes / 60
    );

  const remainder =
    minutes % 60;

  return remainder
    ? `${hours}h ${remainder}m`
    : `${hours}h`;
}

function dayLabel(
  value: string
) {
  const [
    year,
    month,
    day
  ] =
    value.split("-");

  return `${day}/${month}`;
}

export function OperationalDashboard() {
  const {
    request,
    subscribe
  } = useAuth();

  const [days, setDays] =
    useState<PeriodDays>(7);

  const [data, setData] =
    useState<OperationalAnalytics | null>(
      null
    );

  const [loading, setLoading] =
    useState(true);

  const [error, setError] =
    useState("");

  const load =
    useCallback(async () => {
      setLoading(true);

      try {
        const payload =
          await request<OperationalAnalytics>(
            `/api/v1/analytics/operational?days=${days}`
          );

        setData(payload);
        setError("");
      } catch {
        setError(
          "Não foi possível carregar os indicadores operacionais."
        );
      } finally {
        setLoading(false);
      }
    }, [
      days,
      request
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
            "ticket.created" ||
          event.type ===
            "ticket.updated" ||
          event.type ===
            "message.created" ||
          event.type ===
            "sla.updated" ||
          event.type ===
            "ticket.event.created"
        ) {
          void load();
        }
      }
    );
  }, [
    load,
    subscribe
  ]);

  const maxTrend =
    useMemo(
      () =>
        Math.max(
          1,
          ...(
            data?.trend.flatMap(
              item => [
                item.created,
                item.closed
              ]
            ) ?? [1]
          )
        ),
      [data]
    );

  const maxQueue =
    useMemo(
      () =>
        Math.max(
          1,
          ...(
            data?.byQueue.map(
              item =>
                item.active
            ) ?? [1]
          )
        ),
      [data]
    );

  const maxAssignee =
    useMemo(
      () =>
        Math.max(
          1,
          ...(
            data?.byAssignee.map(
              item =>
                item.active
            ) ?? [1]
          )
        ),
      [data]
    );

  return (
    <section className="operational-dashboard">
      <div className="operational-dashboard__toolbar">
        <div>
          <span className="eyebrow">
            Operação em números
          </span>
          <h2>
            Visão operacional
          </h2>
        </div>

        <div className="operational-period">
          {(
            [
              7,
              30,
              90
            ] as PeriodDays[]
          ).map(value => (
            <button
              className={
                days === value
                  ? "operational-period__button operational-period__button--active"
                  : "operational-period__button"
              }
              key={value}
              onClick={() =>
                setDays(value)
              }
              type="button"
            >
              {value} dias
            </button>
          ))}
        </div>
      </div>

      {error && (
        <div className="operational-dashboard__error">
          {error}
        </div>
      )}

      {loading &&
      !data ? (
        <div className="operational-dashboard__loading">
          Carregando indicadores…
        </div>
      ) : data ? (
        <>
          <div className="operational-metrics">
            <article className="operational-metric">
              <span>
                Ativos agora
              </span>
              <strong>
                {
                  data.summary
                    .active
                }
              </strong>
              <small>
                OPEN + PENDING
              </small>
            </article>

            <article className="operational-metric">
              <span>
                Cliente aguardando
              </span>
              <strong>
                {
                  data.summary
                    .waiting
                }
              </strong>
              <small>
                {data.summary.risk} em risco
              </small>
            </article>

            <article className="operational-metric operational-metric--danger">
              <span>
                SLA estourado
              </span>
              <strong>
                {
                  data.summary
                    .breached
                }
              </strong>
              <small>
                situação atual
              </small>
            </article>

            <article className="operational-metric">
              <span>
                1ª resposta média
              </span>
              <strong>
                {durationLabel(
                  data.summary
                    .averageFirstResponseMinutes
                )}
              </strong>
              <small>
                {
                  data.summary
                    .firstResponseSamples
                }{" "}
                amostras
              </small>
            </article>

            <article className="operational-metric">
              <span>
                SLA 1ª resposta
              </span>
              <strong>
                {data.summary
                  .firstResponseSlaPercent ===
                null
                  ? "—"
                  : `${data.summary.firstResponseSlaPercent}%`}
              </strong>
              <small>
                limite{" "}
                {
                  data.sla
                    .firstResponseSlaMinutes
                }
                m
              </small>
            </article>

            <article className="operational-metric">
              <span>
                Criados / encerrados
              </span>
              <strong>
                {
                  data.summary
                    .created
                }
                {" / "}
                {
                  data.summary
                    .closed
                }
              </strong>
              <small>
                últimos {days} dias
              </small>
            </article>
          </div>

          <div className="operational-grid">
            <article className="operational-panel operational-panel--trend">
              <div className="operational-panel__heading">
                <div>
                  <span className="eyebrow">
                    Fluxo
                  </span>
                  <h3>
                    Entradas e encerramentos
                  </h3>
                </div>

                <div className="trend-legend">
                  <span>
                    <i className="trend-legend__created" />
                    Criados
                  </span>
                  <span>
                    <i className="trend-legend__closed" />
                    Encerrados
                  </span>
                </div>
              </div>

              <div className="trend-chart">
                {data.trend.map(
                  item => (
                    <div
                      className="trend-column"
                      key={
                        item.date
                      }
                    >
                      <div className="trend-column__bars">
                        <div
                          className="trend-bar trend-bar--created"
                          style={{
                            height:
                              `${Math.max(
                                item.created
                                  ? 6
                                  : 1,
                                (
                                  item.created /
                                  maxTrend
                                ) *
                                  100
                              )}%`
                          }}
                          title={`${item.created} criados`}
                        />

                        <div
                          className="trend-bar trend-bar--closed"
                          style={{
                            height:
                              `${Math.max(
                                item.closed
                                  ? 6
                                  : 1,
                                (
                                  item.closed /
                                  maxTrend
                                ) *
                                  100
                              )}%`
                          }}
                          title={`${item.closed} encerrados`}
                        />
                      </div>

                      <span>
                        {dayLabel(
                          item.date
                        )}
                      </span>
                    </div>
                  )
                )}
              </div>
            </article>

            <article className="operational-panel">
              <div className="operational-panel__heading">
                <div>
                  <span className="eyebrow">
                    Backlog
                  </span>
                  <h3>
                    Por fila
                  </h3>
                </div>
              </div>

              <div className="ranking-list">
                {data.byQueue.length ===
                0 ? (
                  <div className="ranking-list__empty">
                    Sem atendimentos ativos.
                  </div>
                ) : (
                  data.byQueue.map(
                    item => (
                      <div
                        className="ranking-item"
                        key={
                          item.id ??
                          "__none__"
                        }
                      >
                        <div className="ranking-item__heading">
                          <strong>
                            {
                              item.name
                            }
                          </strong>
                          <span>
                            {
                              item.active
                            }
                          </span>
                        </div>

                        <div className="ranking-track">
                          <span
                            style={{
                              width:
                                `${Math.max(
                                  4,
                                  (
                                    item.active /
                                    maxQueue
                                  ) *
                                    100
                                )}%`
                            }}
                          />
                        </div>

                        <small>
                          {item.waiting} aguardando ·{" "}
                          {item.breached} fora do SLA
                        </small>
                      </div>
                    )
                  )
                )}
              </div>
            </article>

            <article className="operational-panel">
              <div className="operational-panel__heading">
                <div>
                  <span className="eyebrow">
                    Distribuição
                  </span>
                  <h3>
                    Por atendente
                  </h3>
                </div>
              </div>

              <div className="ranking-list">
                {data.byAssignee.length ===
                0 ? (
                  <div className="ranking-list__empty">
                    Sem atendimentos ativos.
                  </div>
                ) : (
                  data.byAssignee.map(
                    item => (
                      <div
                        className="ranking-item"
                        key={
                          item.id ??
                          "__none__"
                        }
                      >
                        <div className="ranking-item__heading">
                          <strong>
                            {
                              item.name
                            }
                          </strong>
                          <span>
                            {
                              item.active
                            }
                          </span>
                        </div>

                        <div className="ranking-track">
                          <span
                            style={{
                              width:
                                `${Math.max(
                                  4,
                                  (
                                    item.active /
                                    maxAssignee
                                  ) *
                                    100
                                )}%`
                            }}
                          />
                        </div>

                        <small>
                          {item.waiting} aguardando ·{" "}
                          {item.breached} fora do SLA
                        </small>
                      </div>
                    )
                  )
                )}
              </div>
            </article>
          </div>

          <p className="operational-dashboard__footnote">
            SLA de primeira resposta usa tickets com resposta registrada no período. O Wapp não estima ciclos históricos que não foram persistidos.
          </p>
        </>
      ) : null}
    </section>
  );
}
