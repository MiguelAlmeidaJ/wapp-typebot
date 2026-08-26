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
