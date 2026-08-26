#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.4] Building authenticated Next.js shell..."

if [[ ! -f "apps/web/package.json" ]]; then
  echo "ERROR: apps/web/package.json not found. Run P0.2 first."
  exit 1
fi

mkdir -p \
  apps/web/app/login \
  apps/web/app/dashboard \
  apps/web/components \
  apps/web/lib

cat > apps/web/lib/api.ts <<'EOF'
export const API_URL =
  process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "") ??
  "http://localhost:4000";

export interface ApiErrorBody {
  error?: {
    code?: string;
    message?: string;
    details?: unknown;
  };
}

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly code = "API_ERROR",
    public readonly details?: unknown
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function apiFetch(
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  return fetch(`${API_URL}${path}`, {
    ...init,
    credentials: "include",
    headers: {
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers
    }
  });
}

export async function parseApiError(response: Response): Promise<ApiError> {
  let body: ApiErrorBody | undefined;

  try {
    body = (await response.json()) as ApiErrorBody;
  } catch {
    // Keep the fallback below when the API did not return JSON.
  }

  return new ApiError(
    body?.error?.message ?? `A API respondeu com status ${response.status}.`,
    response.status,
    body?.error?.code ?? "API_ERROR",
    body?.error?.details
  );
}

export async function expectJson<T>(response: Response): Promise<T> {
  if (!response.ok) {
    throw await parseApiError(response);
  }

  return (await response.json()) as T;
}
EOF

cat > apps/web/lib/auth-types.ts <<'EOF'
export type Role = "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";

export interface AuthUser {
  id: string;
  name: string;
  email: string;
}

export interface AuthCompany {
  id: string;
  name: string;
  slug: string;
}

export interface AuthSession {
  user: AuthUser;
  company: AuthCompany;
  role: Role;
}

export interface LoginResponse extends AuthSession {
  accessToken: string;
}

export interface RefreshResponse {
  accessToken: string;
}

export interface CompanyChoice {
  membershipId: string;
  role: Role;
  company: AuthCompany;
}

export interface CompanyRequiredDetails {
  companies?: CompanyChoice[];
}
EOF

cat > apps/web/components/auth-provider.tsx <<'EOF'
"use client";

import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";

import {
  ApiError,
  apiFetch,
  expectJson
} from "@/lib/api";
import type {
  AuthSession,
  CompanyRequiredDetails,
  LoginResponse,
  RefreshResponse
} from "@/lib/auth-types";

interface LoginInput {
  email: string;
  password: string;
  companySlug?: string;
}

interface AuthContextValue {
  session: AuthSession | null;
  loading: boolean;
  login(input: LoginInput): Promise<void>;
  logout(): Promise<void>;
  request<T>(path: string, init?: RequestInit): Promise<T>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

async function refreshAccessToken(): Promise<string> {
  const response = await apiFetch("/api/v1/auth/refresh", {
    method: "POST"
  });

  const payload = await expectJson<RefreshResponse>(response);
  return payload.accessToken;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const accessTokenRef = useRef<string | null>(null);
  const refreshPromiseRef = useRef<Promise<string> | null>(null);

  const [session, setSession] = useState<AuthSession | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshToken = useCallback(async () => {
    if (!refreshPromiseRef.current) {
      refreshPromiseRef.current = refreshAccessToken().finally(() => {
        refreshPromiseRef.current = null;
      });
    }

    const accessToken = await refreshPromiseRef.current;
    accessTokenRef.current = accessToken;
    return accessToken;
  }, []);

  const authenticatedFetch = useCallback(
    async (path: string, init: RequestInit = {}) => {
      let accessToken = accessTokenRef.current;

      if (!accessToken) {
        accessToken = await refreshToken();
      }

      const execute = (token: string) =>
        apiFetch(path, {
          ...init,
          headers: {
            ...init.headers,
            Authorization: `Bearer ${token}`
          }
        });

      let response = await execute(accessToken);

      if (response.status === 401) {
        accessToken = await refreshToken();
        response = await execute(accessToken);
      }

      return response;
    },
    [refreshToken]
  );

  const loadSession = useCallback(async () => {
    const response = await authenticatedFetch("/api/v1/auth/me");
    const payload = await expectJson<AuthSession>(response);
    setSession(payload);
    return payload;
  }, [authenticatedFetch]);

  useEffect(() => {
    let active = true;

    async function bootstrap() {
      try {
        await refreshToken();

        if (!active) {
          return;
        }

        await loadSession();
      } catch {
        accessTokenRef.current = null;

        if (active) {
          setSession(null);
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    }

    void bootstrap();

    return () => {
      active = false;
    };
  }, [loadSession, refreshToken]);

  const login = useCallback(
    async (input: LoginInput) => {
      const response = await apiFetch("/api/v1/auth/login", {
        method: "POST",
        body: JSON.stringify(input)
      });

      const payload = await expectJson<LoginResponse>(response);

      accessTokenRef.current = payload.accessToken;
      setSession({
        user: payload.user,
        company: payload.company,
        role: payload.role
      });
    },
    []
  );

  const logout = useCallback(async () => {
    try {
      await apiFetch("/api/v1/auth/logout", {
        method: "POST"
      });
    } finally {
      accessTokenRef.current = null;
      setSession(null);
    }
  }, []);

  const request = useCallback(
    async <T,>(path: string, init: RequestInit = {}) => {
      const response = await authenticatedFetch(path, init);
      return expectJson<T>(response);
    },
    [authenticatedFetch]
  );

  const value = useMemo<AuthContextValue>(
    () => ({
      session,
      loading,
      login,
      logout,
      request
    }),
    [session, loading, login, logout, request]
  );

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error("useAuth must be used inside AuthProvider.");
  }

  return context;
}

export function getCompanyChoices(error: unknown) {
  if (!(error instanceof ApiError) || error.code !== "COMPANY_REQUIRED") {
    return [];
  }

  const details = error.details as CompanyRequiredDetails | undefined;
  return details?.companies ?? [];
}
EOF

cat > apps/web/components/wapp-mark.tsx <<'EOF'
export function WappMark({ compact = false }: { compact?: boolean }) {
  return (
    <div className={compact ? "brand brand--compact" : "brand"}>
      <span className="brand__mark" aria-hidden="true">
        W
      </span>
      <span className="brand__name">Wapp</span>
    </div>
  );
}
EOF

cat > apps/web/app/layout.tsx <<'EOF'
import type { Metadata } from "next";
import type { ReactNode } from "react";

import { AuthProvider } from "@/components/auth-provider";

import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Wapp",
    template: "%s · Wapp"
  },
  description: "Atendimento, automação e operação de conversas.",
  authors: [
    {
      name: "Miguel Almeida",
      url: "https://github.com/MiguelAlmeidaJ"
    }
  ]
};

export default function RootLayout({
  children
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <html lang="pt-BR">
      <body>
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
EOF

cat > apps/web/app/page.tsx <<'EOF'
import { redirect } from "next/navigation";

export default function HomePage() {
  redirect("/login");
}
EOF

cat > apps/web/app/login/page.tsx <<'EOF'
"use client";

import { type FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import {
  getCompanyChoices,
  useAuth
} from "@/components/auth-provider";
import { WappMark } from "@/components/wapp-mark";
import { ApiError } from "@/lib/api";
import type { CompanyChoice } from "@/lib/auth-types";

export default function LoginPage() {
  const router = useRouter();
  const { session, loading, login } = useAuth();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [companyChoices, setCompanyChoices] = useState<CompanyChoice[]>([]);
  const [companySlug, setCompanySlug] = useState<string | undefined>();
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!loading && session) {
      router.replace("/dashboard");
    }
  }, [loading, router, session]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setSubmitting(true);

    try {
      await login({
        email,
        password,
        companySlug
      });

      router.replace("/dashboard");
    } catch (caught) {
      const choices = getCompanyChoices(caught);

      if (choices.length > 0) {
        setCompanyChoices(choices);
        setCompanySlug(choices[0]?.company.slug);
        setError("Escolha a empresa que deseja acessar.");
      } else if (caught instanceof ApiError) {
        setError(caught.message);
      } else {
        setError("Não foi possível entrar. Verifique se a API está disponível.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  if (loading || session) {
    return (
      <main className="auth-screen">
        <div className="auth-loading">Preparando seu ambiente…</div>
      </main>
    );
  }

  return (
    <main className="auth-screen">
      <section className="auth-visual">
        <div className="auth-visual__inner">
          <WappMark />

          <div className="auth-visual__copy">
            <span className="eyebrow">Operação centralizada</span>
            <h1>Conversas organizadas para quem precisa atender de verdade.</h1>
            <p>
              Uma nova base para atendimento, automações, filas e integrações
              sem carregar a estrutura visual do sistema legado.
            </p>
          </div>

          <div className="auth-visual__footer">
            <span>Wapp · nova arquitetura</span>
            <span>TypeScript · Next.js · Node.js</span>
          </div>
        </div>
      </section>

      <section className="auth-panel">
        <div className="auth-panel__inner">
          <div className="auth-panel__mobile-brand">
            <WappMark compact />
          </div>

          <div className="auth-heading">
            <span className="eyebrow">Acesso</span>
            <h2>Entre no seu workspace</h2>
            <p>Use seu usuário para acessar a operação da empresa.</p>
          </div>

          <form className="auth-form" onSubmit={handleSubmit}>
            <label className="field">
              <span>E-mail</span>
              <input
                autoComplete="email"
                inputMode="email"
                onChange={event => setEmail(event.target.value)}
                placeholder="voce@empresa.com.br"
                required
                type="email"
                value={email}
              />
            </label>

            <label className="field">
              <span>Senha</span>
              <input
                autoComplete="current-password"
                minLength={8}
                onChange={event => setPassword(event.target.value)}
                placeholder="Sua senha"
                required
                type="password"
                value={password}
              />
            </label>

            {companyChoices.length > 0 && (
              <label className="field">
                <span>Empresa</span>
                <select
                  onChange={event => setCompanySlug(event.target.value)}
                  value={companySlug}
                >
                  {companyChoices.map(choice => (
                    <option
                      key={choice.membershipId}
                      value={choice.company.slug}
                    >
                      {choice.company.name} · {choice.role}
                    </option>
                  ))}
                </select>
              </label>
            )}

            {error && <div className="form-error">{error}</div>}

            <button
              className="primary-button"
              disabled={submitting}
              type="submit"
            >
              <span>{submitting ? "Entrando…" : "Entrar"}</span>
              <span aria-hidden="true">→</span>
            </button>
          </form>

          <p className="auth-note">
            O refresh da sessão fica protegido em cookie HttpOnly. O token de
            acesso não é salvo no localStorage.
          </p>
        </div>
      </section>
    </main>
  );
}
EOF

cat > apps/web/app/dashboard/page.tsx <<'EOF'
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
  const { session, loading, logout, request } = useAuth();

  const [rbacState, setRbacState] = useState<
    "idle" | "checking" | "success" | "forbidden" | "error"
  >("idle");

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
    }
  }, [loading, router, session]);

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
EOF

cat > apps/web/app/globals.css <<'EOF'
:root {
  --background: #f3f4f1;
  --surface: #ffffff;
  --surface-subtle: #f8f8f6;
  --ink: #111814;
  --muted: #68716c;
  --line: #dde1dd;
  --line-strong: #cbd1cc;
  --accent: #1f7a50;
  --accent-dark: #155c3b;
  --accent-soft: #e4f2e9;
  --sidebar: #111713;
  --sidebar-muted: #869089;
  --danger: #a34040;
  --danger-soft: #f7e9e9;
  --shadow: 0 24px 80px rgba(24, 33, 27, 0.08);
}

* {
  box-sizing: border-box;
}

html,
body {
  margin: 0;
  min-height: 100%;
}

body {
  background: var(--background);
  color: var(--ink);
  font-family:
    Arial,
    Helvetica,
    sans-serif;
  -webkit-font-smoothing: antialiased;
}

button,
input,
select {
  font: inherit;
}

button {
  cursor: pointer;
}

button:disabled {
  cursor: wait;
  opacity: 0.65;
}

.brand {
  display: inline-flex;
  align-items: center;
  gap: 14px;
  color: white;
}

.brand__mark {
  display: grid;
  width: 44px;
  height: 44px;
  place-items: center;
  border: 1px solid rgba(255, 255, 255, 0.25);
  border-radius: 13px;
  font-size: 20px;
  font-weight: 800;
  letter-spacing: -0.05em;
}

.brand__name {
  font-size: 24px;
  font-weight: 760;
  letter-spacing: -0.045em;
}

.brand--compact {
  gap: 11px;
}

.brand--compact .brand__mark {
  width: 38px;
  height: 38px;
  border-radius: 11px;
  font-size: 18px;
}

.brand--compact .brand__name {
  font-size: 21px;
}

.eyebrow {
  display: inline-block;
  color: var(--accent);
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
}

.auth-screen {
  display: grid;
  min-height: 100vh;
  grid-template-columns: minmax(420px, 1.08fr) minmax(420px, 0.92fr);
}

.auth-visual {
  position: relative;
  overflow: hidden;
  padding: 56px;
  background:
    radial-gradient(circle at 72% 18%, rgba(70, 145, 102, 0.34), transparent 30%),
    linear-gradient(145deg, #101713 0%, #14231a 55%, #0f1612 100%);
  color: white;
}

.auth-visual::before {
  position: absolute;
  right: -120px;
  bottom: -190px;
  width: 560px;
  height: 560px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 50%;
  content: "";
}

.auth-visual::after {
  position: absolute;
  right: -20px;
  bottom: -90px;
  width: 360px;
  height: 360px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 50%;
  content: "";
}

.auth-visual__inner {
  position: relative;
  z-index: 1;
  display: flex;
  min-height: calc(100vh - 112px);
  flex-direction: column;
}

.auth-visual__copy {
  max-width: 700px;
  margin: auto 0;
  padding: 80px 0;
}

.auth-visual__copy .eyebrow {
  color: #9cd2b2;
}

.auth-visual__copy h1 {
  max-width: 670px;
  margin: 18px 0 24px;
  font-size: clamp(46px, 5vw, 76px);
  font-weight: 640;
  letter-spacing: -0.058em;
  line-height: 0.98;
}

.auth-visual__copy p {
  max-width: 580px;
  margin: 0;
  color: #aeb8b1;
  font-size: 17px;
  line-height: 1.65;
}

.auth-visual__footer {
  display: flex;
  justify-content: space-between;
  gap: 24px;
  color: #78827b;
  font-size: 12px;
}

.auth-panel {
  display: grid;
  place-items: center;
  padding: 64px;
  background: var(--surface);
}

.auth-panel__inner {
  width: min(420px, 100%);
}

.auth-panel__mobile-brand {
  display: none;
}

.auth-heading {
  margin-bottom: 38px;
}

.auth-heading h2 {
  margin: 12px 0 10px;
  font-size: 34px;
  font-weight: 680;
  letter-spacing: -0.045em;
}

.auth-heading p {
  margin: 0;
  color: var(--muted);
  line-height: 1.55;
}

.auth-form {
  display: grid;
  gap: 20px;
}

.field {
  display: grid;
  gap: 9px;
}

.field > span {
  font-size: 13px;
  font-weight: 700;
}

.field input,
.field select {
  width: 100%;
  height: 52px;
  border: 1px solid var(--line);
  border-radius: 12px;
  outline: none;
  background: var(--surface-subtle);
  color: var(--ink);
  padding: 0 15px;
  transition:
    border-color 160ms ease,
    box-shadow 160ms ease,
    background 160ms ease;
}

.field input:focus,
.field select:focus {
  border-color: var(--accent);
  background: white;
  box-shadow: 0 0 0 3px rgba(31, 122, 80, 0.1);
}

.primary-button,
.secondary-button,
.ghost-button {
  border: 0;
  border-radius: 12px;
  transition:
    transform 160ms ease,
    background 160ms ease,
    border-color 160ms ease;
}

.primary-button {
  display: flex;
  height: 54px;
  align-items: center;
  justify-content: space-between;
  margin-top: 5px;
  background: var(--ink);
  color: white;
  padding: 0 18px;
  font-weight: 700;
}

.primary-button:hover:not(:disabled) {
  transform: translateY(-1px);
  background: #1c2821;
}

.form-error {
  border: 1px solid #eccdcd;
  border-radius: 10px;
  background: var(--danger-soft);
  color: var(--danger);
  padding: 12px 14px;
  font-size: 13px;
  line-height: 1.45;
}

.auth-note {
  margin: 24px 0 0;
  color: #929a95;
  font-size: 11px;
  line-height: 1.5;
}

.auth-loading,
.dashboard-loading {
  display: grid;
  min-height: 100vh;
  place-items: center;
  background: var(--background);
  color: var(--muted);
  font-size: 14px;
}

.workspace {
  display: grid;
  min-height: 100vh;
  grid-template-columns: 238px 1fr;
}

.sidebar {
  position: sticky;
  top: 0;
  display: flex;
  height: 100vh;
  flex-direction: column;
  justify-content: space-between;
  background: var(--sidebar);
  padding: 25px 18px 20px;
}

.sidebar__top {
  display: grid;
  gap: 38px;
}

.sidebar__nav {
  display: grid;
  gap: 5px;
}

.nav-item {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 12px;
  border: 0;
  border-radius: 10px;
  background: transparent;
  color: var(--sidebar-muted);
  padding: 11px 12px;
  text-align: left;
}

.nav-item:hover {
  background: rgba(255, 255, 255, 0.045);
  color: white;
}

.nav-item--active {
  background: rgba(255, 255, 255, 0.075);
  color: white;
}

.nav-item__dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
  opacity: 0.72;
}

.sidebar__user {
  display: flex;
  align-items: center;
  gap: 11px;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  padding: 18px 4px 0;
}

.avatar {
  display: grid;
  width: 36px;
  height: 36px;
  flex: 0 0 36px;
  place-items: center;
  border-radius: 10px;
  background: #d8eee0;
  color: #1f6343;
  font-size: 13px;
  font-weight: 800;
}

.sidebar__user-copy {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.sidebar__user-copy strong {
  overflow: hidden;
  color: #f2f4f2;
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sidebar__user-copy span {
  color: var(--sidebar-muted);
  font-size: 10px;
}

.workspace__content {
  min-width: 0;
}

.topbar {
  display: flex;
  height: 68px;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--line);
  background: rgba(255, 255, 255, 0.82);
  padding: 0 34px;
  backdrop-filter: blur(14px);
}

.topbar__company {
  font-size: 13px;
  font-weight: 750;
}

.topbar__separator {
  margin: 0 8px;
  color: var(--line-strong);
}

.topbar__section {
  color: var(--muted);
  font-size: 13px;
}

.ghost-button {
  border: 1px solid var(--line);
  background: white;
  color: var(--muted);
  padding: 8px 13px;
  font-size: 12px;
  font-weight: 700;
}

.ghost-button:hover {
  border-color: var(--line-strong);
  color: var(--ink);
}

.dashboard {
  max-width: 1280px;
  margin: 0 auto;
  padding: 52px 46px 80px;
}

.dashboard__intro {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 36px;
  margin-bottom: 38px;
}

.dashboard__intro h1 {
  margin: 10px 0 12px;
  font-size: clamp(38px, 5vw, 58px);
  font-weight: 640;
  letter-spacing: -0.055em;
  line-height: 1;
}

.dashboard__intro p {
  max-width: 650px;
  margin: 0;
  color: var(--muted);
  font-size: 15px;
  line-height: 1.65;
}

.role-badge {
  border: 1px solid #cbe1d2;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 8px 12px;
  font-size: 11px;
  font-weight: 750;
}

.metric-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
}

.metric-card,
.panel {
  border: 1px solid var(--line);
  background: var(--surface);
  box-shadow: 0 8px 28px rgba(24, 33, 27, 0.025);
}

.metric-card {
  min-height: 166px;
  border-radius: 16px;
  padding: 22px;
}

.metric-card__label {
  display: block;
  color: var(--muted);
  font-size: 12px;
}

.metric-card strong {
  display: block;
  margin: 20px 0 14px;
  font-size: 34px;
  font-weight: 650;
}

.metric-card small {
  color: #929a95;
  font-size: 11px;
}

.dashboard-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-top: 16px;
}

.panel {
  border-radius: 16px;
  padding: 24px;
}

.panel__heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 20px;
}

.panel__heading h2 {
  margin: 8px 0 0;
  font-size: 20px;
  letter-spacing: -0.025em;
}

.status-pill {
  border-radius: 999px;
  padding: 6px 9px;
  font-size: 10px;
  font-weight: 800;
  text-transform: uppercase;
}

.status-pill--online {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.details-list {
  display: grid;
  margin: 24px 0 0;
}

.details-list div {
  display: grid;
  grid-template-columns: 110px 1fr;
  gap: 18px;
  border-top: 1px solid var(--line);
  padding: 14px 0;
}

.details-list dt {
  color: var(--muted);
  font-size: 11px;
}

.details-list dd {
  margin: 0;
  font-size: 12px;
  font-weight: 700;
}

.panel__description {
  max-width: 540px;
  margin: 20px 0;
  color: var(--muted);
  font-size: 13px;
  line-height: 1.6;
}

.secondary-button {
  border: 1px solid var(--line-strong);
  background: white;
  color: var(--ink);
  padding: 11px 14px;
  font-size: 12px;
  font-weight: 750;
}

.secondary-button:hover:not(:disabled) {
  border-color: var(--ink);
}

.inline-result {
  margin: 14px 0 0;
  color: var(--danger);
  font-size: 12px;
  line-height: 1.5;
}

.inline-result--success {
  color: var(--accent-dark);
}

@media (max-width: 980px) {
  .auth-screen {
    grid-template-columns: 1fr;
  }

  .auth-visual {
    display: none;
  }

  .auth-panel {
    min-height: 100vh;
    padding: 36px 24px;
  }

  .auth-panel__mobile-brand {
    display: block;
    margin-bottom: 54px;
  }

  .auth-panel__mobile-brand .brand {
    color: var(--ink);
  }

  .auth-panel__mobile-brand .brand__mark {
    border-color: var(--line-strong);
  }

  .workspace {
    grid-template-columns: 76px 1fr;
  }

  .sidebar {
    padding-inline: 12px;
  }

  .sidebar .brand__name,
  .sidebar__user-copy,
  .nav-item span:not(.nav-item__dot) {
    display: none;
  }

  .sidebar .brand {
    justify-content: center;
  }

  .nav-item {
    justify-content: center;
  }

  .sidebar__user {
    justify-content: center;
  }

  .dashboard {
    padding-inline: 26px;
  }

  .metric-grid,
  .dashboard-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .workspace {
    display: block;
  }

  .sidebar {
    display: none;
  }

  .topbar {
    padding: 0 18px;
  }

  .dashboard {
    padding: 34px 18px 60px;
  }

  .dashboard__intro {
    align-items: flex-start;
    flex-direction: column;
  }

  .auth-heading h2 {
    font-size: 30px;
  }
}
EOF

echo
echo "[P0.4] Web authentication shell created."
echo
echo "Checking TypeScript..."
pnpm --filter @wapp/web typecheck

echo
echo "Next:"
echo "  pnpm dev"
echo
echo "Open:"
echo "  http://localhost:3000/login"
echo
echo "Validate:"
echo "  1. login"
echo "  2. refresh after page reload"
echo "  3. RBAC button"
echo "  4. logout"
