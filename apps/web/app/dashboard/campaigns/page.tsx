"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";
import { roleCan } from "@/lib/permissions";

interface Segment {
  id: string;
  name: string;
}
interface Connection {
  id: string;
  name: string;
  status: string;
}
interface Campaign {
  id: string;
  name: string;
  body: string;
  status: "DRAFT" | "RUNNING" | "COMPLETED" | "CANCELLED" | "FAILED";
  segmentId: string;
  whatsappConnectionId: string;
  ratePerMinute: number;
  windowStartAt: string;
  windowEndAt: string;
  segment: { id: string; name: string };
  whatsappConnection: { id: string; name: string; status: string };
  recipientStatus: Record<string, number>;
}
interface Preview {
  segmentContacts: number;
  eligibleRecipients: number;
  optedOutRecipients: number;
  unknownConsent: number;
  blocked: boolean;
  blockReason: string | null;
  estimatedLastSendAt: string | null;
}
interface Recipient {
  id: string;
  status: string;
  snapshotName: string;
  plannedFor: string | null;
  sentAt: string | null;
  exclusionReason: string | null;
  error: string | null;
  contact: {
    id: string;
    name: string;
    phoneNumber: string | null;
    email: string | null;
  };
}

function localValue(date: Date) {
  return new Date(
    date.getTime() - date.getTimezoneOffset() * 60_000
  ).toISOString().slice(0, 16);
}

function initialWindow() {
  const start = new Date(Date.now() + 5 * 60_000);
  const end = new Date(start.getTime() + 4 * 60 * 60_000);
  return { start: localValue(start), end: localValue(end) };
}

function dt(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short"
  }).format(new Date(value));
}

export default function CampaignsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();
  const defaults = useMemo(() => initialWindow(), []);

  const [campaigns, setCampaigns] = useState<Campaign[]>([]);
  const [segments, setSegments] = useState<Segment[]>([]);
  const [connections, setConnections] = useState<Connection[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [recipients, setRecipients] = useState<Recipient[]>([]);
  const [preview, setPreview] = useState<Preview | null>(null);

  const [name, setName] = useState("");
  const [segmentId, setSegmentId] = useState("");
  const [connectionId, setConnectionId] = useState("");
  const [body, setBody] = useState("");
  const [rate, setRate] = useState(6);
  const [windowStart, setWindowStart] = useState(defaults.start);
  const [windowEnd, setWindowEnd] = useState(defaults.end);
  const [confirmation, setConfirmation] = useState("");

  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const canManage = session
    ? roleCan(session.role, "campaigns.manage")
    : false;
  const canSend = session
    ? roleCan(session.role, "campaigns.send")
    : false;

  const selected = useMemo(
    () => campaigns.find(item => item.id === selectedId) ?? null,
    [campaigns, selectedId]
  );

  const load = useCallback(async () => {
    const [campaignPayload, context] = await Promise.all([
      request<{ campaigns: Campaign[] }>("/api/v1/campaigns"),
      request<{ segments: Segment[]; connections: Connection[] }>(
        "/api/v1/campaigns/context"
      )
    ]);
    setCampaigns(campaignPayload.campaigns);
    setSegments(context.segments);
    setConnections(context.connections);
    setSegmentId(current => current || context.segments[0]?.id || "");
    setConnectionId(
      current =>
        current ||
        context.connections.find(item => item.status === "CONNECTED")?.id ||
        context.connections[0]?.id ||
        ""
    );
  }, [request]);

  const loadRecipients = useCallback(async (campaignId: string) => {
    const payload = await request<{ recipients: Recipient[] }>(
      `/api/v1/campaigns/${campaignId}/recipients?limit=200`
    );
    setRecipients(payload.recipients);
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }
    if (session && !roleCan(session.role, "campaigns.view")) {
      router.replace("/dashboard");
      return;
    }
    if (session) {
      setBusy(true);
      void load()
        .catch(() => setError("Não foi possível carregar campanhas."))
        .finally(() => setBusy(false));
    }
  }, [load, loading, router, session]);

  useEffect(() => {
    if (!session) return;
    return subscribe("/api/v1/realtime/events", event => {
      if (event.type === "campaign.updated") {
        void load();
        if (
          selectedId &&
          (!event.campaignId || event.campaignId === selectedId)
        ) {
          void loadRecipients(selectedId);
        }
      }
    });
  }, [load, loadRecipients, selectedId, session, subscribe]);

  function resetDraft() {
    const next = initialWindow();
    setSelectedId(null);
    setRecipients([]);
    setPreview(null);
    setName("");
    setBody("");
    setRate(6);
    setWindowStart(next.start);
    setWindowEnd(next.end);
    setConfirmation("");
    setError("");
    setNotice("");
  }

  function choose(campaign: Campaign) {
    setSelectedId(campaign.id);
    setName(campaign.name);
    setSegmentId(campaign.segmentId);
    setConnectionId(campaign.whatsappConnectionId);
    setBody(campaign.body);
    setRate(campaign.ratePerMinute);
    setWindowStart(localValue(new Date(campaign.windowStartAt)));
    setWindowEnd(localValue(new Date(campaign.windowEndAt)));
    setPreview(null);
    setConfirmation("");
    setError("");
    setNotice("");
    void loadRecipients(campaign.id);
  }

  async function save() {
    if (!canManage) return;
    setSaving(true);
    setError("");
    setNotice("");

    try {
      const payload = await request<{ campaign: Campaign }>(
        selectedId
          ? `/api/v1/campaigns/${selectedId}`
          : "/api/v1/campaigns",
        {
          method: selectedId ? "PATCH" : "POST",
          body: JSON.stringify({
            segmentId,
            whatsappConnectionId: connectionId,
            name: name.trim(),
            body: body.trim(),
            ratePerMinute: rate,
            windowStartAt: new Date(windowStart).toISOString(),
            windowEndAt: new Date(windowEnd).toISOString()
          })
        }
      );

      setSelectedId(payload.campaign.id);
      setPreview(null);
      setNotice(selectedId ? "Rascunho atualizado." : "Rascunho criado.");
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar a campanha."
      );
    } finally {
      setSaving(false);
    }
  }

  async function previewAudience() {
    if (!selectedId) {
      setError("Salve o rascunho antes da prévia.");
      return;
    }
    setSaving(true);
    setError("");
    try {
      setPreview(
        await request<Preview>(
          `/api/v1/campaigns/${selectedId}/preview`,
          { method: "POST" }
        )
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível calcular a audiência."
      );
    } finally {
      setSaving(false);
    }
  }

  async function start() {
    if (!selectedId || !preview || preview.blocked) return;
    setSaving(true);
    setError("");
    try {
      const result = await request<{
        queued: number;
        durableRecipients: number;
      }>(
        `/api/v1/campaigns/${selectedId}/start`,
        {
          method: "POST",
          body: JSON.stringify({
            confirmation,
            confirmedAudienceCount: preview.eligibleRecipients
          })
        }
      );
      setNotice(
        `Campanha iniciada: ${result.durableRecipients} destinatários persistidos, ${result.queued} jobs enfileirados agora.`
      );
      setConfirmation("");
      await Promise.all([load(), loadRecipients(selectedId)]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível iniciar a campanha."
      );
    } finally {
      setSaving(false);
    }
  }

  async function cancel() {
    if (!selectedId) return;
    setSaving(true);
    setError("");
    try {
      await request(`/api/v1/campaigns/${selectedId}/cancel`, {
        method: "POST"
      });
      setNotice("Campanha cancelada. Envios já realizados não são revertidos.");
      await Promise.all([load(), loadRecipients(selectedId)]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível cancelar."
      );
    } finally {
      setSaving(false);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando campanhas…</main>;
  }

  const editable = !selected || selected.status === "DRAFT";

  return (
    <main className="campaign-screen">
      <header className="campaign-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">CRM</span>
          <h1>Campanhas</h1>
          <p>
            Envios controlados com segmento, consentimento explícito,
            janela e limite de velocidade.
          </p>
        </div>
        {canManage && (
          <button className="ghost-button" onClick={resetDraft} type="button">
            Nova campanha
          </button>
        )}
      </header>

      {error && (
        <div className="campaign-feedback campaign-feedback--error">
          {error}
        </div>
      )}
      {notice && <div className="campaign-feedback">{notice}</div>}

      <section className="campaign-layout">
        <aside className="campaign-list">
          <header>
            <strong>Campanhas</strong>
            <span>{campaigns.length}</span>
          </header>
          <div>
            {campaigns.map(campaign => (
              <button
                className={
                  selectedId === campaign.id
                    ? "campaign-list-item campaign-list-item--active"
                    : "campaign-list-item"
                }
                key={campaign.id}
                onClick={() => choose(campaign)}
                type="button"
              >
                <div>
                  <strong>{campaign.name}</strong>
                  <small>{campaign.segment.name}</small>
                </div>
                <span>{campaign.status}</span>
              </button>
            ))}
            {!busy && campaigns.length === 0 && (
              <div className="campaign-empty">Nenhuma campanha criada.</div>
            )}
          </div>
        </aside>

        <section className="campaign-builder">
          <header>
            <div>
              <strong>{selected?.name ?? "Novo rascunho"}</strong>
              <span>
                A audiência é recalculada novamente na confirmação final.
              </span>
            </div>
            {selected &&
              ["DRAFT", "RUNNING"].includes(selected.status) &&
              canManage && (
                <button
                  className="ghost-button"
                  disabled={saving}
                  onClick={() => void cancel()}
                  type="button"
                >
                  Cancelar
                </button>
              )}
          </header>

          <div className="campaign-consent-rule">
            <strong>Consentimento obrigatório</strong>
            <p>
              Somente contatos marcados como “Autorizado” na ficha podem
              receber. Opt-out e consentimento desconhecido são suprimidos.
            </p>
          </div>

          <div className="campaign-form-grid">
            <label>
              <span>Nome</span>
              <input
                disabled={!editable}
                maxLength={160}
                onChange={event => setName(event.target.value)}
                value={name}
              />
            </label>
            <label>
              <span>Segmento</span>
              <select
                disabled={!editable}
                onChange={event => setSegmentId(event.target.value)}
                value={segmentId}
              >
                <option value="">Selecionar…</option>
                {segments.map(item => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Conexão</span>
              <select
                disabled={!editable}
                onChange={event => setConnectionId(event.target.value)}
                value={connectionId}
              >
                <option value="">Selecionar…</option>
                {connections.map(item => (
                  <option key={item.id} value={item.id}>
                    {item.name} · {item.status}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Velocidade</span>
              <select
                disabled={!editable}
                onChange={event => setRate(Number(event.target.value))}
                value={rate}
              >
                {[1, 2, 3, 4, 5, 6, 8, 10].map(value => (
                  <option key={value} value={value}>
                    {value}/min
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Início</span>
              <input
                disabled={!editable}
                onChange={event => setWindowStart(event.target.value)}
                type="datetime-local"
                value={windowStart}
              />
            </label>
            <label>
              <span>Fim</span>
              <input
                disabled={!editable}
                onChange={event => setWindowEnd(event.target.value)}
                type="datetime-local"
                value={windowEnd}
              />
            </label>
          </div>

          <label className="campaign-message-field">
            <span>Mensagem</span>
            <textarea
              disabled={!editable}
              maxLength={3800}
              onChange={event => setBody(event.target.value)}
              placeholder="Olá, {{primeiro_nome}}! ..."
              rows={7}
              value={body}
            />
            <small>
              Variáveis: {"{{nome}}"} e {"{{primeiro_nome}}"}. O aviso
              “responda SAIR” é anexado automaticamente.
            </small>
          </label>

          {canManage && editable && (
            <div className="campaign-builder__actions">
              <button
                className="primary-button"
                disabled={
                  saving ||
                  !name.trim() ||
                  !segmentId ||
                  !connectionId ||
                  !body.trim()
                }
                onClick={() => void save()}
                type="button"
              >
                <span>
                  {selectedId ? "Atualizar rascunho" : "Salvar rascunho"}
                </span>
              </button>
              {selectedId && (
                <button
                  className="ghost-button"
                  disabled={saving}
                  onClick={() => void previewAudience()}
                  type="button"
                >
                  Calcular audiência
                </button>
              )}
            </div>
          )}

          {preview && (
            <section className="campaign-preview">
              <div className="campaign-preview__numbers">
                <article><span>Segmento</span><strong>{preview.segmentContacts}</strong></article>
                <article><span>Autorizados</span><strong>{preview.eligibleRecipients}</strong></article>
                <article><span>Opt-out</span><strong>{preview.optedOutRecipients}</strong></article>
                <article><span>Sem consentimento</span><strong>{preview.unknownConsent}</strong></article>
              </div>

              {preview.blocked ? (
                <p className="campaign-preview__blocked">
                  {preview.blockReason}
                </p>
              ) : (
                <>
                  <p>
                    Último envio estimado:{" "}
                    <strong>{dt(preview.estimatedLastSendAt)}</strong>
                  </p>
                  {canSend && (
                    <div className="campaign-launch">
                      <label>
                        <span>Confirmação final</span>
                        <input
                          onChange={event => setConfirmation(event.target.value)}
                          placeholder="INICIAR CAMPANHA"
                          value={confirmation}
                        />
                      </label>
                      <button
                        className="primary-button"
                        disabled={
                          saving || confirmation !== "INICIAR CAMPANHA"
                        }
                        onClick={() => void start()}
                        type="button"
                      >
                        <span>
                          Iniciar para {preview.eligibleRecipients} contatos
                        </span>
                      </button>
                    </div>
                  )}
                </>
              )}
            </section>
          )}
        </section>

        <section className="campaign-recipients">
          <header>
            <div>
              <strong>Destinatários</strong>
              <span>{selected?.status ?? "Selecione uma campanha"}</span>
            </div>
            {selected && (
              <small>
                Enviados {selected.recipientStatus.SENT ?? 0} · Falhas{" "}
                {selected.recipientStatus.FAILED ?? 0} · Suprimidos{" "}
                {selected.recipientStatus.SUPPRESSED ?? 0}
              </small>
            )}
          </header>
          <div>
            {recipients.map(item => (
              <article className="campaign-recipient" key={item.id}>
                <button
                  onClick={() =>
                    router.push(
                      `/dashboard/contacts?contact=${item.contact.id}`
                    )
                  }
                  type="button"
                >
                  <strong>{item.snapshotName}</strong>
                  <small>
                    {item.contact.phoneNumber ??
                      item.contact.email ??
                      "Contato"}
                  </small>
                </button>
                <div>
                  <span>{item.status}</span>
                  <small>
                    {item.sentAt
                      ? dt(item.sentAt)
                      : item.plannedFor
                        ? dt(item.plannedFor)
                        : item.exclusionReason ?? "—"}
                  </small>
                </div>
                {item.error && <p>{item.error}</p>}
              </article>
            ))}
            {selected && recipients.length === 0 && (
              <div className="campaign-empty">
                O snapshot aparece quando a campanha for iniciada.
              </div>
            )}
            {!selected && (
              <div className="campaign-empty">
                Selecione uma campanha para acompanhar.
              </div>
            )}
          </div>
        </section>
      </section>
    </main>
  );
}
