"use client";

import { type FormEvent, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

interface TeamMembership {
  id: string;
  role: "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";
  user: {
    id: string;
    name: string;
    email: string;
  };
}

interface QueueMember {
  id: string;
  membershipId: string;
  membership: TeamMembership;
}

interface QueueItem {
  id: string;
  name: string;
  isActive: boolean;
  members: QueueMember[];
  _count: {
    tickets: number;
  };
}

interface QueuesResponse {
  queues: QueueItem[];
}

interface TeamResponse {
  memberships: TeamMembership[];
}

export default function QueuesPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();

  const [queues, setQueues] = useState<QueueItem[]>([]);
  const [team, setTeam] = useState<TeamMembership[]>([]);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [onlineMembershipIds, setOnlineMembershipIds] = useState<string[]>([]);

  const load = useCallback(async () => {
    const [queuesPayload, teamPayload, presencePayload] = await Promise.all([
      request<QueuesResponse>("/api/v1/queues"),
      request<TeamResponse>("/api/v1/team/memberships"),
      request<{ membershipIds: string[] }>("/api/v1/realtime/presence")
    ]);

    setQueues(queuesPayload.queues);
    setTeam(teamPayload.memberships);
    setOnlineMembershipIds(presencePayload.membershipIds);
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void load();
    }
  }, [load, loading, router, session]);

  useEffect(() => {
    if (!session) return;

    return subscribe("/api/v1/realtime/events", event => {
      if (event.type === "queue.updated") {
        void load();
      }

      if (event.type === "presence.updated" && event.membershipId) {
        setOnlineMembershipIds(current => {
          const next = new Set(current);
          if (event.online) next.add(event.membershipId!);
          else next.delete(event.membershipId!);
          return [...next];
        });
      }
    });
  }, [load, session, subscribe]);

  async function create(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy("create");
    setError("");

    try {
      await request("/api/v1/queues", {
        method: "POST",
        body: JSON.stringify({ name })
      });
      setName("");
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível criar a fila."
      );
    } finally {
      setBusy(null);
    }
  }

  async function toggleMember(
    queue: QueueItem,
    membershipId: string,
    checked: boolean
  ) {
    setBusy(queue.id);
    setError("");

    const current = new Set(
      queue.members.map(member => member.membershipId)
    );

    if (checked) {
      current.add(membershipId);
    } else {
      current.delete(membershipId);
    }

    try {
      const payload = await request<QueuesResponse>(
        `/api/v1/queues/${queue.id}/members`,
        {
          method: "PUT",
          body: JSON.stringify({
            membershipIds: [...current]
          })
        }
      );

      setQueues(payload.queues);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar os atendentes."
      );
    } finally {
      setBusy(null);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando filas…</main>;
  }

  const canManage = session.role === "OWNER" || session.role === "ADMIN";

  return (
    <main className="queue-screen">
      <header className="queue-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">Operação</span>
          <h1>Filas</h1>
          <p>
            Organize os atendimentos e defina quais pessoas podem atuar em cada
            fila.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() => router.push("/dashboard/conversations")}
          type="button"
        >
          Conversas
        </button>
      </header>

      {error && <div className="inbox-error">{error}</div>}

      {canManage && (
        <form className="queue-create" onSubmit={create}>
          <div>
            <strong>Nova fila</strong>
            <span>Ex.: Comercial, Suporte, Financeiro</span>
          </div>
          <input
            maxLength={120}
            onChange={event => setName(event.target.value)}
            placeholder="Nome da fila"
            required
            value={name}
          />
          <button
            className="primary-button"
            disabled={busy === "create"}
            type="submit"
          >
            <span>{busy === "create" ? "Criando…" : "Criar fila"}</span>
            <span>+</span>
          </button>
        </form>
      )}

      <section className="queue-grid">
        {queues.length === 0 ? (
          <div className="connection-empty">
            <strong>Nenhuma fila criada.</strong>
            <p>Crie a primeira fila para começar a distribuir atendimentos.</p>
          </div>
        ) : (
          queues.map(queue => {
            const memberIds = new Set(
              queue.members.map(member => member.membershipId)
            );

            return (
              <article className="queue-card" key={queue.id}>
                <div className="queue-card__heading">
                  <div>
                    <span className="eyebrow">Fila</span>
                    <h2>{queue.name}</h2>
                  </div>
                  <span className="role-badge">
                    {queue.members.length} atendente
                    {queue.members.length === 1 ? "" : "s"}
                  </span>
                </div>

                <div className="queue-members">
                  {team.map(membership => (
                    <label className="queue-member" key={membership.id}>
                      <input
                        checked={memberIds.has(membership.id)}
                        disabled={!canManage || busy === queue.id}
                        onChange={event =>
                          void toggleMember(
                            queue,
                            membership.id,
                            event.target.checked
                          )
                        }
                        type="checkbox"
                      />
                      <span className="queue-member__avatar">
                        {membership.user.name.slice(0, 1).toUpperCase()}
                      </span>
                      <span className="queue-member__copy">
                        <strong>
                          {membership.user.name}
                          <span
                            className={
                              onlineMembershipIds.includes(membership.id)
                                ? "presence-dot presence-dot--online"
                                : "presence-dot"
                            }
                            title={
                              onlineMembershipIds.includes(membership.id)
                                ? "Online"
                                : "Offline"
                            }
                          />
                        </strong>
                        <small>{membership.role}</small>
                      </span>
                    </label>
                  ))}
                </div>
              </article>
            );
          })
        )}
      </section>
    </main>
  );
}
