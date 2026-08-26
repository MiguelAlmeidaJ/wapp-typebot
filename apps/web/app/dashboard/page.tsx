"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { WappMark } from "@/components/wapp-mark";
import { ApiError } from "@/lib/api";

interface AdminPingResponse {
  status: "ok";
  companyId: string;
  role: string;
  message: string;
}

const roleLabels = {
  OWNER: "Proprietário",
  ADMIN: "Administrador",
  SUPERVISOR: "Supervisor",
  AGENT: "Atendente"
} as const;

const navigation = [
  "Visão geral",
  "Conversas",
  "Contatos",
  "Filas",
  "Conexões",
  "Automações"
];

export default function DashboardPage() {
  const router = useRouter();
  const { session, loading, logout, request, subscribe } = useAuth();

  const [rbacState, setRbacState] = useState<
    "idle" | "checking" | "success" | "forbidden" | "error"
  >("idle");

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
    }
  }, [loading, router, session]);

  useEffect(() => {
    if (!session) return;
    return subscribe("/api/v1/realtime/events", () => {});
  }, [session, subscribe]);

  async function handleLogout() {
    await logout();
    router.replace("/login");
  }

  async function testRbac() {
    setRbacState("checking");

    try {
      await request<AdminPingResponse>("/api/v1/admin/ping");
      setRbacState("success");
    } catch (error) {
      if (error instanceof ApiError && error.status === 403) {
        setRbacState("forbidden");
        return;
      }

      setRbacState("error");
    }
  }

  if (loading || !session) {
    return (
      <main className="dashboard-loading">
        Carregando workspace…
      </main>
    );
  }

  return (
    <main className="workspace">
      <aside className="sidebar">
        <div className="sidebar__top">
          <WappMark compact />

          <nav className="sidebar__nav" aria-label="Navegação principal">
            {navigation.map((item, index) => (
              <button
                className={index === 0 ? "nav-item nav-item--active" : "nav-item"}
                key={item}
                onClick={() => {
                  if (item === "Conversas") {
                    router.push("/dashboard/conversations");
                  }

                  if (item === "Conexões") {
                    router.push("/dashboard/connections");
                  }

                  if (item === "Filas") {
                    router.push("/dashboard/queues");
                  }
                }}
                type="button"
              >
                <span className="nav-item__dot" aria-hidden="true" />
                <span>{item}</span>
              </button>
            ))}
          </nav>
        </div>

        <div className="sidebar__user">
          <div className="avatar">
            {session.user.name.slice(0, 1).toUpperCase()}
          </div>
          <div className="sidebar__user-copy">
            <strong>{session.user.name}</strong>
            <span>{roleLabels[session.role]}</span>
          </div>
        </div>
      </aside>

      <section className="workspace__content">
        <header className="topbar">
          <div>
            <span className="topbar__company">
              {session.company.name}
            </span>
            <span className="topbar__separator">/</span>
            <span className="topbar__section">Visão geral</span>
          </div>

          <button
            className="ghost-button"
            onClick={handleLogout}
            type="button"
          >
            Sair
          </button>
        </header>

        <div className="dashboard">
          <div className="dashboard__intro">
            <div>
              <span className="eyebrow">Workspace ativo</span>
              <h1>Olá, {session.user.name.split(" ")[0]}.</h1>
              <p>
                A autenticação do Wapp já está conectada à nova API.
                Agora podemos começar a colocar os módulos de operação aqui.
              </p>
            </div>

            <span className="role-badge">
              {roleLabels[session.role]}
            </span>
          </div>

          <div className="metric-grid">
            <article className="metric-card">
              <span className="metric-card__label">Conversas abertas</span>
              <strong>—</strong>
              <small>Aguardando módulo de tickets</small>
            </article>

            <article className="metric-card">
              <span className="metric-card__label">Na fila</span>
              <strong>—</strong>
              <small>Aguardando módulo de filas</small>
            </article>

            <article className="metric-card">
              <span className="metric-card__label">Conexões</span>
              <strong>—</strong>
              <small>Aguardando módulo WhatsApp</small>
            </article>
          </div>

          <div className="dashboard-grid">
            <article className="panel">
              <div className="panel__heading">
                <div>
                  <span className="eyebrow">Sessão</span>
                  <h2>Fundação autenticada</h2>
                </div>
                <span className="status-pill status-pill--online">
                  online
                </span>
              </div>

              <dl className="details-list">
                <div>
                  <dt>Usuário</dt>
                  <dd>{session.user.email}</dd>
                </div>
                <div>
                  <dt>Empresa</dt>
                  <dd>{session.company.slug}</dd>
                </div>
                <div>
                  <dt>Perfil</dt>
                  <dd>{session.role}</dd>
                </div>
              </dl>
            </article>

            <article className="panel">
              <div className="panel__heading">
                <div>
                  <span className="eyebrow">Permissões</span>
                  <h2>Teste de RBAC</h2>
                </div>
              </div>

              <p className="panel__description">
                A rota abaixo aceita apenas OWNER e ADMIN. Ela valida sessão,
                empresa e papel diretamente na API.
              </p>

              <button
                className="secondary-button"
                disabled={rbacState === "checking"}
                onClick={testRbac}
                type="button"
              >
                {rbacState === "checking"
                  ? "Validando…"
                  : "Testar permissão administrativa"}
              </button>

              {rbacState === "success" && (
                <p className="inline-result inline-result--success">
                  RBAC validado. A API reconheceu seu acesso administrativo.
                </p>
              )}

              {rbacState === "forbidden" && (
                <p className="inline-result">
                  Seu perfil está autenticado, mas não possui acesso
                  administrativo.
                </p>
              )}

              {rbacState === "error" && (
                <p className="inline-result">
                  Não foi possível validar a permissão agora.
                </p>
              )}
            </article>
          </div>
        </div>
      </section>
    </main>
  );
}
