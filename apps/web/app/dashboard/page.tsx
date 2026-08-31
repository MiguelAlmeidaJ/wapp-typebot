"use client";

import {
  useEffect,
  useMemo,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { WappMark } from "@/components/wapp-mark";
import { OperationalDashboard } from "@/components/dashboard/operational-dashboard";
import { ApiError } from "@/lib/api";
import {
  roleCan,
  type UiPermission
} from "@/lib/permissions";

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

const navigation: Array<{
  label: string;
  href: string;
  permission: UiPermission;
}> = [
  {
    label: "Visão geral",
    href: "/dashboard",
    permission: "dashboard.view"
  },
  {
    label: "Conversas",
    href: "/dashboard/conversations",
    permission: "conversations.view"
  },
  {
    label: "Contatos",
    href: "/dashboard/contacts",
    permission: "contacts.view"
  },
  {
    label: "Pipeline",
    href: "/dashboard/pipeline",
    permission: "pipeline.view"
  },
  {
    label: "Tarefas",
    href: "/dashboard/tasks",
    permission: "tasks.view"
  },
  {
    label: "Segmentos",
    href: "/dashboard/segments",
    permission: "segments.view"
  },
  {
    label: "Campanhas",
    href: "/dashboard/campaigns",
    permission: "campaigns.view"
  },
  {
    label: "Dados",
    href: "/dashboard/data-quality",
    permission: "dataQuality.view"
  },
  {
    label: "Relatórios",
    href: "/dashboard/reports",
    permission: "reports.view"
  },
  {
    label: "Filas",
    href: "/dashboard/queues",
    permission: "queues.manage"
  },
  {
    label: "Conexões",
    href: "/dashboard/connections",
    permission: "connections.manage"
  },
  {
    label: "Equipe",
    href: "/dashboard/team",
    permission: "team.manage"
  }
];

export default function DashboardPage() {
  const router = useRouter();
  const {
    session,
    loading,
    logout,
    request,
    subscribe
  } = useAuth();

  const [rbacState, setRbacState] = useState<
    "idle" |
    "checking" |
    "success" |
    "forbidden" |
    "error"
  >("idle");

  const visibleNavigation = useMemo(
    () =>
      session
        ? navigation.filter(item =>
            roleCan(
              session.role,
              item.permission
            )
          )
        : [],
    [session]
  );

  const canTestAdmin =
    session &&
    roleCan(session.role, "admin.test");

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
    }
  }, [loading, router, session]);

  useEffect(() => {
    if (!session) {
      return;
    }

    return subscribe(
      "/api/v1/realtime/events",
      () => {}
    );
  }, [session, subscribe]);

  async function handleLogout() {
    await logout();
    router.replace("/login");
  }

  async function testRbac() {
    setRbacState("checking");

    try {
      await request<AdminPingResponse>(
        "/api/v1/admin/ping"
      );

      setRbacState("success");
    } catch (error) {
      if (
        error instanceof ApiError &&
        error.status === 403
      ) {
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

          <nav
            className="sidebar__nav"
            aria-label="Navegação principal"
          >
            {visibleNavigation.map(
              (item, index) => (
                <button
                  className={
                    index === 0
                      ? "nav-item nav-item--active"
                      : "nav-item"
                  }
                  key={item.href}
                  onClick={() =>
                    router.push(item.href)
                  }
                  type="button"
                >
                  <span
                    className="nav-item__dot"
                    aria-hidden="true"
                  />
                  <span>{item.label}</span>
                </button>
              )
            )}
          </nav>
        </div>

        <div className="sidebar__user">
          <div className="avatar">
            {session.user.name
              .slice(0, 1)
              .toUpperCase()}
          </div>
          <div className="sidebar__user-copy">
            <strong>
              {session.user.name}
            </strong>
            <span>
              {roleLabels[session.role]}
            </span>
          </div>
        </div>
      </aside>

      <section className="workspace__content">
        <header className="topbar">
          <div>
            <span className="topbar__company">
              {session.company.name}
            </span>
            <span className="topbar__separator">
              /
            </span>
            <span className="topbar__section">
              Visão geral
            </span>
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
              <span className="eyebrow">
                Workspace ativo
              </span>
              <h1>
                Olá,{" "}
                {session.user.name.split(" ")[0]}.
              </h1>
              <p>
                Seu acesso está carregado conforme
                o papel definido nesta empresa.
              </p>
            </div>

            <span className="role-badge">
              {roleLabels[session.role]}
            </span>
          </div>

          <OperationalDashboard />

          <div
            className={
              canTestAdmin
                ? "dashboard-grid"
                : "dashboard-grid dashboard-grid--single"
            }
          >
            <article className="panel">
              <div className="panel__heading">
                <div>
                  <span className="eyebrow">
                    Sessão
                  </span>
                  <h2>
                    Fundação autenticada
                  </h2>
                </div>
                <span className="status-pill status-pill--online">
                  online
                </span>
              </div>

              <dl className="details-list">
                <div>
                  <dt>Usuário</dt>
                  <dd>
                    {session.user.email}
                  </dd>
                </div>
                <div>
                  <dt>Empresa</dt>
                  <dd>
                    {session.company.slug}
                  </dd>
                </div>
                <div>
                  <dt>Perfil</dt>
                  <dd>{session.role}</dd>
                </div>
              </dl>
            </article>

            {canTestAdmin && (
              <article className="panel">
                <div className="panel__heading">
                  <div>
                    <span className="eyebrow">
                      Permissões
                    </span>
                    <h2>Teste de RBAC</h2>
                  </div>
                </div>

                <p className="panel__description">
                  Esta rota administrativa
                  valida sessão, empresa e
                  capability diretamente na API.
                </p>

                <button
                  className="secondary-button"
                  disabled={
                    rbacState === "checking"
                  }
                  onClick={testRbac}
                  type="button"
                >
                  {rbacState === "checking"
                    ? "Validando…"
                    : "Testar permissão administrativa"}
                </button>

                {rbacState === "success" && (
                  <p className="inline-result inline-result--success">
                    RBAC validado.
                  </p>
                )}

                {rbacState === "forbidden" && (
                  <p className="inline-result">
                    Acesso administrativo negado.
                  </p>
                )}

                {rbacState === "error" && (
                  <p className="inline-result">
                    Não foi possível validar
                    agora.
                  </p>
                )}
              </article>
            )}
          </div>
        </div>
      </section>
    </main>
  );
}
