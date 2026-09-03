"use client";

import {
  useEffect,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";
import { OperationalDashboard } from "@/components/dashboard/operational-dashboard";
import { roleLabels } from "@/components/dashboard/dashboard-navigation";
import { ApiError } from "@/lib/api";
import { roleCan } from "@/lib/permissions";

interface AdminPingResponse {
  status: "ok";
  companyId: string;
  role: string;
  message: string;
}

export default function DashboardPage() {
  const {
    session,
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

  const canTestAdmin =
    session &&
    roleCan(session.role, "admin.test");

  useEffect(() => {
    if (!session) {
      return;
    }

    return subscribe(
      "/api/v1/realtime/events",
      () => {}
    );
  }, [session, subscribe]);

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

  if (!session) {
    return (
      <main className="dashboard-loading">
        Carregando workspace…
      </main>
    );
  }

  return (
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
  );
}
