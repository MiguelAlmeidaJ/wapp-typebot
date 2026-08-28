"use client";

import {
  useCallback,
  useEffect,
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

interface PipelineStage {
  id: string;
  name: string;
  colorKey: string;
  outcome:
    | "OPEN"
    | "WON"
    | "LOST";
  position: number;
}

interface PipelineStatePayload {
  pipelines:
    Array<{
      id: string;
      name: string;
      description:
        | string
        | null;
      stages:
        PipelineStage[];
      currentState: {
        stageId: string;
        enteredAt: string;
      } | null;
    }>;
  transitions:
    Array<{
      id: string;
      pipelineId: string;
      createdAt: string;
      pipeline: {
        name: string;
      };
      fromStage: {
        name: string;
      } | null;
      toStage: {
        name: string;
      } | null;
      actorMembership: {
        user: {
          name: string;
        };
      } | null;
    }>;
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

export function ContactPipelineSummary({
  contactId
}: {
  contactId: string;
}) {
  const router =
    useRouter();

  const {
    request,
    subscribe
  } =
    useAuth();

  const [
    payload,
    setPayload
  ] =
    useState<
      PipelineStatePayload
      | null
    >(
      null
    );

  const [
    moving,
    setMoving
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

  const load =
    useCallback(
      async () => {
        const next =
          await request<
            PipelineStatePayload
          >(
            `/api/v1/contacts/${contactId}/pipeline-states`
          );

        setPayload(
          next
        );
      },
      [
        contactId,
        request
      ]
    );

  useEffect(
    () => {
      void load()
        .catch(() => {
          setError(
            "Não foi possível carregar os pipelines deste contato."
          );
        });
    },
    [
      load
    ]
  );

  useEffect(
    () =>
      subscribe(
        "/api/v1/realtime/events",
        event => {
          if (
            event.type ===
              "contact.pipeline.updated" &&
            event.contactId ===
              contactId
          ) {
            void load()
              .catch(
                () => {}
              );
          }
        }
      ),
    [
      contactId,
      load,
      subscribe
    ]
  );

  async function move(
    pipelineId: string,
    stageId:
      string
      | null
  ) {
    setMoving(
      pipelineId
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
              pipelineId,
              stageId
            })
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível mover o contato."
      );
    } finally {
      setMoving(
        null
      );
    }
  }

  return (
    <section className="contact-pipeline-summary">
      <header>
        <div>
          <span className="eyebrow">
            Jornada
          </span>

          <strong>
            Pipeline
          </strong>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              `/dashboard/pipeline?contact=${contactId}`
            )
          }
          type="button"
        >
          Abrir quadro
        </button>
      </header>

      {error && (
        <div className="contact-pipeline-summary__error">
          {error}
        </div>
      )}

      {!payload ? (
        <div className="contact-pipeline-summary__empty">
          Carregando…
        </div>
      ) : payload.pipelines.length ===
        0 ? (
        <div className="contact-pipeline-summary__empty">
          Nenhum pipeline ativo configurado.
        </div>
      ) : (
        <div className="contact-pipeline-summary__body">
          <div className="contact-pipeline-summary__states">
            {payload.pipelines.map(
              pipeline => (
                <label
                  key={
                    pipeline.id
                  }
                >
                  <span>
                    {pipeline.name}
                  </span>

                  <select
                    disabled={
                      moving ===
                      pipeline.id
                    }
                    onChange={
                      event =>
                        void move(
                          pipeline.id,
                          event
                            .target
                            .value ||
                            null
                        )
                    }
                    value={
                      pipeline
                        .currentState
                        ?.stageId ??
                      ""
                    }
                  >
                    <option value="">
                      Sem etapa
                    </option>

                    {pipeline.stages.map(
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
                </label>
              )
            )}
          </div>

          {payload.transitions.length >
            0 && (
            <div className="contact-stage-history">
              <strong>
                Movimentações recentes
              </strong>

              {payload.transitions
                .slice(
                  0,
                  4
                )
                .map(
                  transition => (
                    <div
                      key={
                        transition.id
                      }
                    >
                      <span>
                        {transition
                          .pipeline
                          .name}
                      </span>

                      <p>
                        {transition
                          .fromStage
                          ?.name ??
                          "Sem etapa"}{" "}
                        →{" "}
                        {transition
                          .toStage
                          ?.name ??
                          "Sem etapa"}
                      </p>

                      <small>
                        {transition
                          .actorMembership
                          ?.user.name ??
                          "Sistema"}{" "}
                        ·{" "}
                        {dateTimeLabel(
                          transition.createdAt
                        )}
                      </small>
                    </div>
                  )
                )}
            </div>
          )}
        </div>
      )}
    </section>
  );
}
