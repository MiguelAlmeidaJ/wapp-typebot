"use client";

import {
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
import {
  roleCan
} from "@/lib/permissions";

interface QueueItem {
  id: string;
  name: string;
}

interface ComparisonMetric {
  current:
    number
    | null;
  previous:
    number
    | null;
  changePercent:
    number
    | null;
}

interface ManagementReport {
  period: {
    days:
      7
      | 30
      | 90;
    from:
      string;
    to:
      string;
    queueId:
      string
      | null;
  };
  sla: {
    firstResponseMinutes:
      number;
    replyMinutes:
      number;
  };
  currentState: {
    active:
      number;
    waiting:
      number;
    breached:
      number;
    unassigned:
      number;
  };
  comparison: {
    created:
      ComparisonMetric;
    closed:
      ComparisonMetric;
    reopened:
      ComparisonMetric;
    outboundMessages:
      ComparisonMetric;
    averageFirstResponseMinutes:
      ComparisonMetric;
    firstResponseSlaPercent:
      ComparisonMetric;
    averageResolutionMinutes:
      ComparisonMetric;
    throughputPercent:
      ComparisonMetric;
  };
  samples: {
    firstResponse:
      number;
    resolution:
      number;
  };
  trend:
    Array<{
      date:
        string;
      created:
        number;
      closed:
        number;
    }>;
  byQueue:
    Array<{
      id:
        string
        | null;
      name:
        string;
      active:
        number;
      created:
        number;
      closed:
        number;
      throughputPercent:
        number
        | null;
      averageFirstResponseMinutes:
        number
        | null;
      firstResponseSlaPercent:
        number
        | null;
      averageResolutionMinutes:
        number
        | null;
    }>;
  byAssignee:
    Array<{
      id:
        string;
      name:
        string;
      role:
        string;
      isActive:
        boolean;
      active:
        number;
      closed:
        number;
      closedChangePercent:
        number
        | null;
      outboundMessages:
        number;
      outboundChangePercent:
        number
        | null;
    }>;
}

function minutesLabel(
  value:
    number
    | null
) {
  if (
    value ===
    null
  ) {
    return "—";
  }

  if (
    value <
    60
  ) {
    return `${value} min`;
  }

  const hours =
    Math.floor(
      value /
      60
    );

  const minutes =
    value %
    60;

  if (
    hours <
    24
  ) {
    return minutes
      ? `${hours}h ${minutes}min`
      : `${hours}h`;
  }

  const days =
    Math.floor(
      hours /
      24
    );

  const remainingHours =
    hours %
    24;

  return remainingHours
    ? `${days}d ${remainingHours}h`
    : `${days}d`;
}

function percentLabel(
  value:
    number
    | null
) {
  return value ===
    null
    ? "—"
    : `${value}%`;
}

function changeLabel(
  value:
    number
    | null,
  inverse =
    false
) {
  if (
    value ===
    null
  ) {
    return {
      text:
        "sem base anterior",
      className:
        "report-change report-change--neutral"
    };
  }

  if (
    value ===
    0
  ) {
    return {
      text:
        "sem variação",
      className:
        "report-change report-change--neutral"
    };
  }

  const positive =
    inverse
      ? value <
        0
      : value >
        0;

  return {
    text:
      `${value > 0 ? "+" : ""}${value}%`,
    className:
      positive
        ? "report-change report-change--good"
        : "report-change report-change--bad"
  };
}

function SummaryCard({
  label,
  value,
  helper,
  change,
  inverse
}: {
  label:
    string;
  value:
    string;
  helper:
    string;
  change:
    number
    | null;
  inverse?:
    boolean;
}) {
  const presentation =
    changeLabel(
      change,
      inverse
    );

  return (
    <article className="management-summary-card">
      <span>
        {label}
      </span>

      <strong>
        {value}
      </strong>

      <div>
        <small>
          {helper}
        </small>

        <span
          className={
            presentation.className
          }
        >
          {presentation.text}
        </span>
      </div>
    </article>
  );
}

export default function ReportsPage() {
  const router =
    useRouter();

  const {
    session,
    loading,
    request
  } =
    useAuth();

  const [
    days,
    setDays
  ] =
    useState<
      7
      | 30
      | 90
    >(
      30
    );

  const [
    queueId,
    setQueueId
  ] =
    useState("");

  const [
    queues,
    setQueues
  ] =
    useState<
      QueueItem[]
    >([]);

  const [
    report,
    setReport
  ] =
    useState<
      ManagementReport
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
    error,
    setError
  ] =
    useState("");

  const canView =
    session
      ? roleCan(
          session.role,
          "reports.view"
        )
      : false;

  const load =
    useCallback(
      async () => {
        if (
          !canView
        ) {
          return;
        }

        setBusy(
          true
        );

        setError("");

        try {
          const params =
            new URLSearchParams({
              days:
                String(
                  days
                )
            });

          if (
            queueId
          ) {
            params.set(
              "queueId",
              queueId
            );
          }

          const [
            reportPayload,
            queuePayload
          ] =
            await Promise.all([
              request<
                ManagementReport
              >(
                `/api/v1/reports/management?${params.toString()}`
              ),
              request<{
                queues:
                  QueueItem[];
              }>(
                "/api/v1/queues"
              )
            ]);

          setReport(
            reportPayload
          );

          setQueues(
            queuePayload
              .queues
          );
        } catch (caught) {
          setError(
            caught instanceof
              ApiError
              ? caught.message
              : "Não foi possível carregar os relatórios."
          );
        } finally {
          setBusy(
            false
          );
        }
      },
      [
        canView,
        days,
        queueId,
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

      if (
        session &&
        !roleCan(
          session.role,
          "reports.view"
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
        void load();
      }
    },
    [
      load,
      loading,
      router,
      session
    ]
  );

  const chartMax =
    useMemo(
      () =>
        Math.max(
          1,
          ...(
            report?.trend.flatMap(
              item => [
                item.created,
                item.closed
              ]
            ) ??
            [
              1
            ]
          )
        ),
      [
        report
      ]
    );

  if (
    loading ||
    !session ||
    !canView
  ) {
    return (
      <main className="dashboard-loading">
        Carregando relatórios…
      </main>
    );
  }

  return (
    <main className="management-reports">
      <header className="management-reports__header">
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
            Gestão
          </span>

          <h1>
            Relatórios
          </h1>

          <p>
            Leia capacidade, produtividade e qualidade sem confundir fotografia atual com autoria histórica.
          </p>
        </div>

        <div className="management-report-filters">
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
                Todas as filas
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

          <div className="management-period-switch">
            {(
              [
                7,
                30,
                90
              ] as const
            ).map(
              value => (
                <button
                  className={
                    days ===
                    value
                      ? "management-period-switch__item management-period-switch__item--active"
                      : "management-period-switch__item"
                  }
                  key={
                    value
                  }
                  onClick={() =>
                    setDays(
                      value
                    )
                  }
                  type="button"
                >
                  {value}d
                </button>
              )
            )}
          </div>
        </div>
      </header>

      {error && (
        <div className="inbox-error">
          {error}
        </div>
      )}

      {busy && (
        <div className="management-report-loading">
          Atualizando indicadores…
        </div>
      )}

      {!busy &&
        report && (
        <>
          <section className="management-state-strip">
            <div>
              <span>
                Ativos agora
              </span>
              <strong>
                {report
                  .currentState
                  .active}
              </strong>
            </div>

            <div>
              <span>
                Aguardando resposta
              </span>
              <strong>
                {report
                  .currentState
                  .waiting}
              </strong>
            </div>

            <div>
              <span>
                SLA estourado
              </span>
              <strong>
                {report
                  .currentState
                  .breached}
              </strong>
            </div>

            <div>
              <span>
                Sem atendente
              </span>
              <strong>
                {report
                  .currentState
                  .unassigned}
              </strong>
            </div>
          </section>

          <section className="management-summary-grid">
            <SummaryCard
              change={
                report
                  .comparison
                  .created
                  .changePercent
              }
              helper={`vs. ${report.comparison.created.previous} no período anterior`}
              label="Novos atendimentos"
              value={
                String(
                  report
                    .comparison
                    .created
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .closed
                  .changePercent
              }
              helper={`vs. ${report.comparison.closed.previous} no período anterior`}
              label="Encerrados"
              value={
                String(
                  report
                    .comparison
                    .closed
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .firstResponseSlaPercent
                  .changePercent
              }
              helper={`${report.samples.firstResponse} respostas medidas`}
              label="SLA 1ª resposta"
              value={
                percentLabel(
                  report
                    .comparison
                    .firstResponseSlaPercent
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .averageFirstResponseMinutes
                  .changePercent
              }
              helper={`meta: ${report.sla.firstResponseMinutes} min`}
              inverse
              label="Tempo 1ª resposta"
              value={
                minutesLabel(
                  report
                    .comparison
                    .averageFirstResponseMinutes
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .averageResolutionMinutes
                  .changePercent
              }
              helper={`${report.samples.resolution} encerramentos medidos`}
              inverse
              label="Tempo de resolução"
              value={
                minutesLabel(
                  report
                    .comparison
                    .averageResolutionMinutes
                    .current
                )
              }
            />

            <SummaryCard
              change={
                report
                  .comparison
                  .outboundMessages
                  .changePercent
              }
              helper={`vs. ${report.comparison.outboundMessages.previous} no período anterior`}
              label="Mensagens enviadas"
              value={
                String(
                  report
                    .comparison
                    .outboundMessages
                    .current
                )
              }
            />
          </section>

          <section className="management-report-layout">
            <article className="management-report-panel management-report-panel--trend">
              <header>
                <div>
                  <span className="eyebrow">
                    Fluxo
                  </span>
                  <h2>
                    Entrada x encerramento
                  </h2>
                </div>

                <div className="management-chart-legend">
                  <span>
                    <i />
                    Criados
                  </span>

                  <span>
                    <i />
                    Encerrados
                  </span>
                </div>
              </header>

              <div className="management-trend-chart">
                {report
                  .trend
                  .map(
                    (
                      item,
                      index
                    ) => (
                      <div
                        className="management-trend-day"
                        key={
                          item.date
                        }
                        title={`${item.date}: ${item.created} criados, ${item.closed} encerrados`}
                      >
                        <div className="management-trend-day__bars">
                          <span
                            style={{
                              height:
                                `${Math.max(
                                  item.created >
                                    0
                                    ? 6
                                    : 0,
                                  (
                                    item.created /
                                    chartMax
                                  ) *
                                    100
                                )}%`
                            }}
                          />

                          <span
                            style={{
                              height:
                                `${Math.max(
                                  item.closed >
                                    0
                                    ? 6
                                    : 0,
                                  (
                                    item.closed /
                                    chartMax
                                  ) *
                                    100
                                )}%`
                            }}
                          />
                        </div>

                        {(report.period.days ===
                          7 ||
                          index %
                            Math.ceil(
                              report.period.days /
                              7
                            ) ===
                            0) && (
                          <small>
                            {new Intl.DateTimeFormat(
                              "pt-BR",
                              {
                                day:
                                  "2-digit",
                                month:
                                  "2-digit"
                              }
                            ).format(
                              new Date(
                                `${item.date}T12:00:00`
                              )
                            )}
                          </small>
                        )}
                      </div>
                    )
                  )}
              </div>
            </article>

            <article className="management-report-panel management-report-panel--health">
              <header>
                <div>
                  <span className="eyebrow">
                    Leitura
                  </span>
                  <h2>
                    Saúde da operação
                  </h2>
                </div>
              </header>

              <div className="management-health-list">
                <div>
                  <span>
                    Encerrados / criados
                  </span>
                  <strong>
                    {percentLabel(
                      report
                        .comparison
                        .throughputPercent
                        .current
                    )}
                  </strong>
                </div>

                <div>
                  <span>
                    Reaberturas
                  </span>
                  <strong>
                    {report
                      .comparison
                      .reopened
                      .current}
                  </strong>
                </div>

                <div>
                  <span>
                    Meta de resposta
                  </span>
                  <strong>
                    {report
                      .sla
                      .firstResponseMinutes} min
                  </strong>
                </div>

                <div>
                  <span>
                    Meta entre respostas
                  </span>
                  <strong>
                    {report
                      .sla
                      .replyMinutes} min
                  </strong>
                </div>
              </div>

              <p>
                “Encerrados / criados” é throughput do período, não taxa de conversão. Pode superar 100% quando a equipe reduz backlog antigo.
              </p>
            </article>
          </section>

          <section className="management-report-panel">
            <header>
              <div>
                <span className="eyebrow">
                  Filas
                </span>
                <h2>
                  Desempenho operacional
                </h2>
              </div>
            </header>

            <div className="management-report-table">
              <div className="management-report-table__row management-report-table__row--head">
                <span>
                  Fila
                </span>
                <span>
                  Ativos
                </span>
                <span>
                  Criados
                </span>
                <span>
                  Encerrados
                </span>
                <span>
                  SLA 1ª resp.
                </span>
                <span>
                  T. 1ª resp.
                </span>
                <span>
                  T. resolução
                </span>
              </div>

              {report
                .byQueue
                .map(
                  queue => (
                    <div
                      className="management-report-table__row"
                      key={
                        queue.id ??
                        "__none__"
                      }
                    >
                      <strong>
                        {queue.name}
                      </strong>
                      <span>
                        {queue.active}
                      </span>
                      <span>
                        {queue.created}
                      </span>
                      <span>
                        {queue.closed}
                      </span>
                      <span>
                        {percentLabel(
                          queue
                            .firstResponseSlaPercent
                        )}
                      </span>
                      <span>
                        {minutesLabel(
                          queue
                            .averageFirstResponseMinutes
                        )}
                      </span>
                      <span>
                        {minutesLabel(
                          queue
                            .averageResolutionMinutes
                        )}
                      </span>
                    </div>
                  )
                )}

              {report
                .byQueue
                .length ===
                0 && (
                <div className="management-report-empty">
                  Nenhum dado de fila neste período.
                </div>
              )}
            </div>
          </section>

          <section className="management-report-panel">
            <header>
              <div>
                <span className="eyebrow">
                  Equipe
                </span>
                <h2>
                  Produção atribuível
                </h2>
              </div>

              <small className="management-report-panel__note">
                Encerramentos usam o ator real do histórico; mensagens usam o remetente real.
              </small>
            </header>

            <div className="management-agent-list">
              {report
                .byAssignee
                .map(
                  member => {
                    const closedChange =
                      changeLabel(
                        member
                          .closedChangePercent
                      );

                    const outboundChange =
                      changeLabel(
                        member
                          .outboundChangePercent
                      );

                    return (
                      <article
                        className="management-agent-row"
                        key={
                          member.id
                        }
                      >
                        <div className="management-agent-row__identity">
                          <span>
                            {member.name
                              .slice(
                                0,
                                1
                              )
                              .toUpperCase()}
                          </span>

                          <div>
                            <strong>
                              {member.name}
                            </strong>
                            <small>
                              {member.role}
                              {!member.isActive
                                ? " · inativo"
                                : ""}
                            </small>
                          </div>
                        </div>

                        <div>
                          <span>
                            Ativos
                          </span>
                          <strong>
                            {member.active}
                          </strong>
                        </div>

                        <div>
                          <span>
                            Encerrados
                          </span>
                          <strong>
                            {member.closed}
                          </strong>
                          <small
                            className={
                              closedChange.className
                            }
                          >
                            {closedChange.text}
                          </small>
                        </div>

                        <div>
                          <span>
                            Mensagens
                          </span>
                          <strong>
                            {member.outboundMessages}
                          </strong>
                          <small
                            className={
                              outboundChange.className
                            }
                          >
                            {outboundChange.text}
                          </small>
                        </div>
                      </article>
                    );
                  }
                )}

              {report
                .byAssignee
                .length ===
                0 && (
                <div className="management-report-empty">
                  Nenhuma produção atribuível neste período.
                </div>
              )}
            </div>
          </section>
        </>
      )}
    </main>
  );
}
