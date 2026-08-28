"use client";

import QRCode from "qrcode";
import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type ConnectionStatus =
  | "CREATED"
  | "CONNECTING"
  | "CONNECTED"
  | "DISCONNECTED"
  | "ERROR";

type HealthStatus =
  | "UNKNOWN"
  | "HEALTHY"
  | "DEGRADED"
  | "DOWN";

interface QueueOption {
  id: string;
  name: string;
}

interface WhatsAppConnection {
  id: string;
  name: string;
  provider: "EVOLUTION_BAILEYS" | "META_CLOUD";
  instanceName: string;
  status: ConnectionStatus;
  phoneNumber: string | null;
  profileName: string | null;
  lastError: string | null;
  lastEventAt: string | null;
  healthStatus: HealthStatus;
  lastHealthCheckAt: string | null;
  lastHealthOkAt: string | null;
  healthError: string | null;
  consecutiveHealthFailures: number;
  acceptGroups: boolean;
  defaultQueueId: string | null;
  defaultQueue?: QueueOption | null;
  createdAt: string;
}

interface QrPayload {
  code?: string;
  base64?: string;
  pairingCode?: string;
  count?: number;
}

interface ListResponse {
  connections: WhatsAppConnection[];
}

interface QueuesResponse {
  queues: QueueOption[];
}

interface CreateResponse {
  connection: WhatsAppConnection;
  qr: QrPayload;
}

interface ConnectResponse {
  qr: QrPayload;
}

interface SyncResponse {
  connection: WhatsAppConnection;
}

interface SettingsResponse {
  connection: WhatsAppConnection;
}

const statusLabels: Record<ConnectionStatus, string> = {
  CREATED: "Criada",
  CONNECTING: "Aguardando QR",
  CONNECTED: "Conectada",
  DISCONNECTED: "Desconectada",
  ERROR: "Erro"
};

const healthLabels: Record<HealthStatus, string> = {
  UNKNOWN: "Aguardando checagem",
  HEALTHY: "Saudável",
  DEGRADED: "Degradada",
  DOWN: "Evolution indisponível"
};

function healthCheckLabel(
  value: string | null
) {
  if (!value) {
    return "ainda não verificada";
  }

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

function normalizeBase64(value?: string) {
  if (!value) return undefined;
  if (value.startsWith("data:image")) return value;
  return `data:image/png;base64,${value}`;
}

export default function ConnectionsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();

  const [connections, setConnections] = useState<WhatsAppConnection[]>([]);
  const [queues, setQueues] = useState<QueueOption[]>([]);
  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [qrConnectionId, setQrConnectionId] = useState<string | null>(null);
  const [qrImage, setQrImage] = useState<string | null>(null);
  const [pairingCode, setPairingCode] = useState<string | null>(null);
  const [testConnectionId, setTestConnectionId] = useState<string | null>(null);
  const [testNumber, setTestNumber] = useState("");
  const [testText, setTestText] = useState("Teste enviado pelo Wapp.");
  const [testResult, setTestResult] = useState("");

  const loadConnections = useCallback(async () => {
    const payload = await request<ListResponse>(
      "/api/v1/whatsapp/connections"
    );
    setConnections(payload.connections);
  }, [request]);

  const loadQueues = useCallback(async () => {
    const payload = await request<QueuesResponse>("/api/v1/queues");
    setQueues(payload.queues);
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void Promise.all([loadConnections(), loadQueues()]).catch(() => {
        setError("Não foi possível carregar as conexões.");
      });
    }
  }, [loading, loadConnections, loadQueues, router, session]);

  useEffect(() => {
    if (!session) return;

    return subscribe("/api/v1/realtime/events", event => {
      if (
        event.type === "connection.updated" ||
        event.type === "queue.updated"
      ) {
        void loadConnections();
        void loadQueues();
      }
    });
  }, [loadConnections, loadQueues, session, subscribe]);

  useEffect(() => {
    if (!session) return;

    const timer = window.setInterval(() => {
      void Promise.all(
        connections
          .filter(
            connection =>
              connection.status ===
              "CONNECTING"
          )
          .map(async connection => {
            try {
              const payload = await request<SyncResponse>(
                `/api/v1/whatsapp/connections/${connection.id}/sync`,
                { method: "POST" }
              );

              setConnections(current =>
                current.map(item =>
                  item.id === payload.connection.id
                    ? { ...item, ...payload.connection }
                    : item
                )
              );

              if (
                payload.connection.id === qrConnectionId &&
                payload.connection.status === "CONNECTED"
              ) {
                setQrConnectionId(null);
                setQrImage(null);
                setPairingCode(null);
              }
            } catch {
              // Status stays visible on the card.
            }
          })
      );
    }, 8000);

    return () => window.clearInterval(timer);
  }, [connections, qrConnectionId, request, session]);

  async function showQr(connectionId: string, qr: QrPayload) {
    setQrConnectionId(connectionId);
    setPairingCode(qr.pairingCode ?? null);

    const imageFromEvolution = normalizeBase64(qr.base64);
    if (imageFromEvolution) {
      setQrImage(imageFromEvolution);
      return;
    }

    if (qr.code) {
      const image = await QRCode.toDataURL(qr.code, {
        width: 340,
        margin: 2,
        errorCorrectionLevel: "M"
      });
      setQrImage(image);
      return;
    }

    setQrImage(null);
  }

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setCreating(true);

    try {
      const payload = await request<CreateResponse>(
        "/api/v1/whatsapp/connections",
        {
          method: "POST",
          body: JSON.stringify({ name })
        }
      );

      setConnections(current => [
        payload.connection,
        ...current.filter(item => item.id !== payload.connection.id)
      ]);
      setName("");
      await showQr(payload.connection.id, payload.qr);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível criar a conexão."
      );
    } finally {
      setCreating(false);
    }
  }

  async function updateSettings(
    connection: WhatsAppConnection,
    settings: {
      acceptGroups?: boolean;
      defaultQueueId?: string | null;
    }
  ) {
    setBusyId(connection.id);

    try {
      const payload = await request<SettingsResponse>(
        `/api/v1/whatsapp/connections/${connection.id}/settings`,
        {
          method: "PATCH",
          body: JSON.stringify(settings)
        }
      );

      setConnections(current =>
        current.map(item =>
          item.id === payload.connection.id
            ? payload.connection
            : item
        )
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar a conexão."
      );
    } finally {
      setBusyId(null);
    }
  }

  async function handleConnect(connection: WhatsAppConnection) {
    setBusyId(connection.id);
    setError("");

    try {
      const payload = await request<ConnectResponse>(
        `/api/v1/whatsapp/connections/${connection.id}/connect`,
        { method: "POST" }
      );
      await showQr(connection.id, payload.qr);
      await loadConnections();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível gerar o QR Code."
      );
    } finally {
      setBusyId(null);
    }
  }

  async function handleSync(connection: WhatsAppConnection) {
    setBusyId(connection.id);
    try {
      const payload = await request<SyncResponse>(
        `/api/v1/whatsapp/connections/${connection.id}/sync`,
        { method: "POST" }
      );
      setConnections(current =>
        current.map(item =>
          item.id === payload.connection.id
            ? { ...item, ...payload.connection }
            : item
        )
      );
    } finally {
      setBusyId(null);
    }
  }

  async function handleTestMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!testConnectionId) return;

    setBusyId(testConnectionId);
    setTestResult("");

    try {
      await request(
        `/api/v1/whatsapp/connections/${testConnectionId}/test-message`,
        {
          method: "POST",
          body: JSON.stringify({
            number: testNumber,
            text: testText
          })
        }
      );
      setTestResult("Mensagem enviada pela Evolution API.");
    } catch (caught) {
      setTestResult(
        caught instanceof ApiError
          ? caught.message
          : "Falha ao enviar mensagem."
      );
    } finally {
      setBusyId(null);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando conexões…</main>;
  }

  const isAdmin = session.role === "OWNER" || session.role === "ADMIN";

  return (
    <main className="connections-screen">
      <header className="connections-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">WhatsApp</span>
          <h1>Conexões</h1>
          <p>
            Configure o comportamento de cada número, inclusive grupos e fila
            padrão de entrada.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() => router.push("/dashboard/queues")}
          type="button"
        >
          Gerenciar filas
        </button>
      </header>

      {error && <div className="form-error">{error}</div>}

      {isAdmin && (
        <form className="connection-create" onSubmit={handleCreate}>
          <div>
            <strong>Nova conexão</strong>
            <span>Novas conexões ignoram grupos por padrão.</span>
          </div>
          <input
            maxLength={120}
            onChange={event => setName(event.target.value)}
            placeholder="Ex.: Comercial, Suporte, Matriz"
            required
            value={name}
          />
          <button
            className="primary-button connection-create__button"
            disabled={creating}
            type="submit"
          >
            <span>{creating ? "Criando…" : "Criar conexão"}</span>
            <span>+</span>
          </button>
        </form>
      )}

      <section className="connection-list">
        {connections.length === 0 ? (
          <div className="connection-empty">
            <strong>Nenhuma conexão criada.</strong>
            <p>Crie a primeira instância para iniciar o vínculo.</p>
          </div>
        ) : (
          connections.map(connection => (
            <article className="connection-card" key={connection.id}>
              <div className="connection-card__main">
                <div>
                  <div className="connection-card__title">
                    <h2>{connection.name}</h2>
                    <span
                      className={`connection-status connection-status--${connection.status.toLowerCase()}`}
                    >
                      {statusLabels[connection.status]}
                    </span>
                  </div>
                  <p>{connection.instanceName}</p>
                  <div className="connection-meta">
                    <span>
                      Provider <strong>Evolution / Baileys</strong>
                    </span>
                    {connection.phoneNumber && (
                      <span>
                        Número <strong>{connection.phoneNumber}</strong>
                      </span>
                    )}
                    <span>
                      Saúde{" "}
                      <strong>
                        {healthLabels[connection.healthStatus]}
                      </strong>
                    </span>
                    <span>
                      Checagem{" "}
                      <strong>
                        {healthCheckLabel(connection.lastHealthCheckAt)}
                      </strong>
                    </span>
                  </div>

                  {isAdmin && (
                    <div className="connection-settings">
                      <label className="connection-toggle">
                        <input
                          checked={connection.acceptGroups}
                          disabled={busyId === connection.id}
                          onChange={event =>
                            void updateSettings(connection, {
                              acceptGroups: event.target.checked
                            })
                          }
                          type="checkbox"
                        />
                        <span>
                          <strong>Aceitar grupos</strong>
                          <small>
                            Desligado: novas mensagens de grupo são ignoradas.
                          </small>
                        </span>
                      </label>

                      <label className="connection-queue-setting">
                        <span>Fila padrão</span>
                        <select
                          disabled={busyId === connection.id}
                          onChange={event =>
                            void updateSettings(connection, {
                              defaultQueueId: event.target.value || null
                            })
                          }
                          value={connection.defaultQueueId ?? ""}
                        >
                          <option value="">Sem fila padrão</option>
                          {queues.map(queue => (
                            <option key={queue.id} value={queue.id}>
                              {queue.name}
                            </option>
                          ))}
                        </select>
                      </label>
                    </div>
                  )}

                  {connection.lastError && (
                    <div className="connection-error">
                      {connection.lastError}
                    </div>
                  )}

                  {connection.healthError &&
                    connection.healthError !== connection.lastError && (
                      <div className="connection-error">
                        Evolution: {connection.healthError}
                      </div>
                    )}
                </div>

                <div className="connection-actions">
                  {isAdmin && connection.status !== "CONNECTED" && (
                    <button
                      className="secondary-button"
                      disabled={busyId === connection.id}
                      onClick={() => handleConnect(connection)}
                      type="button"
                    >
                      Gerar QR
                    </button>
                  )}
                  <button
                    className="ghost-button"
                    disabled={busyId === connection.id}
                    onClick={() => handleSync(connection)}
                    type="button"
                  >
                    Atualizar status
                  </button>
                  {connection.status === "CONNECTED" && (
                    <button
                      className="secondary-button"
                      onClick={() => setTestConnectionId(connection.id)}
                      type="button"
                    >
                      Testar envio
                    </button>
                  )}
                </div>
              </div>
            </article>
          ))
        )}
      </section>

      {qrConnectionId && (
        <div className="modal-backdrop">
          <section className="qr-modal">
            <button
              aria-label="Fechar"
              className="modal-close"
              onClick={() => {
                setQrConnectionId(null);
                setQrImage(null);
                setPairingCode(null);
              }}
              type="button"
            >
              ×
            </button>
            <span className="eyebrow">Conectar aparelho</span>
            <h2>Escaneie pelo WhatsApp</h2>
            <p>
              No celular, abra WhatsApp → Aparelhos conectados → Conectar um
              aparelho.
            </p>
            {qrImage ? (
              <div className="qr-frame">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img alt="QR Code do WhatsApp" src={qrImage} />
              </div>
            ) : (
              <div className="qr-waiting">
                O QR ainda não foi retornado. Tente novamente em alguns segundos.
              </div>
            )}
            {pairingCode && (
              <div className="pairing-code">
                Código de pareamento: <strong>{pairingCode}</strong>
              </div>
            )}
          </section>
        </div>
      )}

      {testConnectionId && (
        <div className="modal-backdrop">
          <form className="test-modal" onSubmit={handleTestMessage}>
            <button
              aria-label="Fechar"
              className="modal-close"
              onClick={() => {
                setTestConnectionId(null);
                setTestResult("");
              }}
              type="button"
            >
              ×
            </button>
            <span className="eyebrow">Teste controlado</span>
            <h2>Enviar mensagem</h2>
            <p>Use DDI + DDD + número, somente dígitos.</p>
            <label className="field">
              <span>Número</span>
              <input
                inputMode="numeric"
                onChange={event =>
                  setTestNumber(event.target.value.replace(/\D/g, ""))
                }
                placeholder="5531999999999"
                required
                value={testNumber}
              />
            </label>
            <label className="field">
              <span>Mensagem</span>
              <textarea
                onChange={event => setTestText(event.target.value)}
                required
                rows={4}
                value={testText}
              />
            </label>
            <button
              className="primary-button"
              disabled={busyId === testConnectionId}
              type="submit"
            >
              <span>
                {busyId === testConnectionId ? "Enviando…" : "Enviar teste"}
              </span>
              <span>→</span>
            </button>
            {testResult && (
              <div className="connection-test-result">{testResult}</div>
            )}
          </form>
        </div>
      )}
    </main>
  );
}
