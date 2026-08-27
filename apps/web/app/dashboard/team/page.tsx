"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type Role =
  | "OWNER"
  | "ADMIN"
  | "SUPERVISOR"
  | "AGENT";

interface TeamMembership {
  id: string;
  role: Role;
  isActive: boolean;
  user: {
    id: string;
    name: string;
    email: string;
    isActive: boolean;
  };
  queueMemberships: Array<{
    queueId: string;
  }>;
}

const labels: Record<Role, string> = {
  OWNER: "Proprietário",
  ADMIN: "Administrador",
  SUPERVISOR: "Supervisor",
  AGENT: "Atendente"
};

export default function TeamPage() {
  const router = useRouter();
  const { session, loading, request } = useAuth();

  const [members, setMembers] = useState<TeamMembership[]>([]);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] =
    useState<"ADMIN" | "SUPERVISOR" | "AGENT">("AGENT");
  const [busy, setBusy] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const canManage =
    session?.role === "OWNER" ||
    session?.role === "ADMIN";

  const load = useCallback(async () => {
    const response = await request<{
      memberships: TeamMembership[];
    }>("/api/v1/team/memberships?includeInactive=true");

    setMembers(response.memberships);
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

  async function create(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCreating(true);
    setError("");
    setNotice("");

    try {
      const response = await request<{
        linkedExistingUser: boolean;
      }>("/api/v1/team/memberships", {
        method: "POST",
        body: JSON.stringify({
          name,
          email,
          temporaryPassword: password || undefined,
          role
        })
      });

      setNotice(
        response.linkedExistingUser
          ? "Usuário existente vinculado à empresa."
          : "Usuário criado com sucesso."
      );

      setName("");
      setEmail("");
      setPassword("");
      setRole("AGENT");
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível adicionar a pessoa."
      );
    } finally {
      setCreating(false);
    }
  }

  async function update(
    member: TeamMembership,
    data: {
      role?: "ADMIN" | "SUPERVISOR" | "AGENT";
      isActive?: boolean;
    }
  ) {
    setBusy(member.id);
    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/team/memberships/${member.id}`,
        {
          method: "PATCH",
          body: JSON.stringify(data)
        }
      );

      setNotice("Acesso atualizado.");
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível alterar o acesso."
      );
    } finally {
      setBusy(null);
    }
  }

  if (loading || !session) {
    return (
      <main className="dashboard-loading">
        Carregando equipe…
      </main>
    );
  }

  const createRoles =
    session.role === "OWNER"
      ? ["ADMIN", "SUPERVISOR", "AGENT"] as const
      : ["SUPERVISOR", "AGENT"] as const;

  return (
    <main className="team-screen">
      <header className="team-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">Administração</span>
          <h1>Equipe</h1>
          <p>
            Usuários, papéis e acesso à empresa atual.
          </p>
        </div>
        <button
          className="ghost-button"
          onClick={() => router.push("/dashboard/queues")}
          type="button"
        >
          Filas
        </button>
      </header>

      {error && <div className="team-feedback team-feedback--error">{error}</div>}
      {notice && <div className="team-feedback">{notice}</div>}

      {canManage && (
        <form className="team-create" onSubmit={create}>
          <input
            onChange={event => setName(event.target.value)}
            placeholder="Nome"
            required
            value={name}
          />
          <input
            onChange={event => setEmail(event.target.value)}
            placeholder="E-mail"
            required
            type="email"
            value={email}
          />
          <input
            minLength={12}
            onChange={event => setPassword(event.target.value)}
            placeholder="Senha temporária (novo usuário)"
            type="password"
            value={password}
          />
          <select
            onChange={event =>
              setRole(
                event.target.value as
                  | "ADMIN"
                  | "SUPERVISOR"
                  | "AGENT"
              )
            }
            value={role}
          >
            {createRoles.map(item => (
              <option key={item} value={item}>
                {labels[item]}
              </option>
            ))}
          </select>
          <button
            className="primary-button"
            disabled={creating}
            type="submit"
          >
            <span>{creating ? "Criando…" : "Adicionar"}</span>
            <span>+</span>
          </button>
        </form>
      )}

      <section className="team-list">
        {members.map(member => {
          const protectedMember =
            member.role === "OWNER" ||
            member.user.id === session.user.id ||
            (session.role === "ADMIN" &&
              member.role === "ADMIN");

          const editableRoles =
            session.role === "OWNER"
              ? ["ADMIN", "SUPERVISOR", "AGENT"] as const
              : ["SUPERVISOR", "AGENT"] as const;

          return (
            <article
              className={
                member.isActive
                  ? "team-member"
                  : "team-member team-member--inactive"
              }
              key={member.id}
            >
              <div className="team-avatar">
                {member.user.name.slice(0, 1).toUpperCase()}
              </div>

              <div className="team-copy">
                <strong>{member.user.name}</strong>
                <span>{member.user.email}</span>
                <small>
                  {member.queueMemberships.length} fila(s)
                </small>
              </div>

              <div>
                {protectedMember || !canManage ? (
                  <span className="team-badge">
                    {labels[member.role]}
                  </span>
                ) : (
                  <select
                    disabled={busy === member.id}
                    onChange={event =>
                      void update(member, {
                        role: event.target.value as
                          | "ADMIN"
                          | "SUPERVISOR"
                          | "AGENT"
                      })
                    }
                    value={
                      member.role as
                        | "ADMIN"
                        | "SUPERVISOR"
                        | "AGENT"
                    }
                  >
                    {editableRoles.map(item => (
                      <option key={item} value={item}>
                        {labels[item]}
                      </option>
                    ))}
                  </select>
                )}
              </div>

              <div className="team-actions">
                <span className="team-badge">
                  {member.isActive ? "Ativo" : "Desativado"}
                </span>

                {canManage && !protectedMember && (
                  <button
                    className="ghost-button"
                    disabled={busy === member.id}
                    onClick={() =>
                      void update(member, {
                        isActive: !member.isActive
                      })
                    }
                    type="button"
                  >
                    {member.isActive ? "Desativar" : "Reativar"}
                  </button>
                )}
              </div>
            </article>
          );
        })}
      </section>
    </main>
  );
}
