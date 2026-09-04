"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";
import {
  Bot,
  Cable,
  CheckCircle2,
  CircleOff,
  MessageSquareText,
  Play,
  Plus,
  Power,
  RefreshCw
} from "lucide-react";
import { useRouter } from "next/navigation";

import { AccessGate } from "@/components/access-gate";
import { AutomationTabs } from "@/components/automations/automation-tabs";
import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";
import { roleCan } from "@/lib/permissions";

import styles from "./page.module.css";

type ConnectionStatus =
  | "CREATED"
  | "CONNECTING"
  | "CONNECTED"
  | "DISCONNECTED"
  | "ERROR";

interface WhatsAppConnection {
  id: string;
  name: string;
  status: ConnectionStatus;
  phoneNumber: string | null;
  profileName: string | null;
}

interface ChatbotFlow {
  id: string;
  name: string;
  engine: "TYPEBOT";
  whatsappConnectionId: string;
  externalId: string;
  externalTypebotId: string | null;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
  whatsappConnection: {
    id: string;
    name: string;
    status: ConnectionStatus;
  };
  _count: {
    sessions: number;
  };
}

interface ChatbotsResponse {
  chatbots: ChatbotFlow[];
}

interface ConnectionsResponse {
  connections: WhatsAppConnection[];
}

interface ChatbotResponse {
  chatbot: ChatbotFlow;
}

interface TestResponse {
  sessionId?: string;
  messages: string[];
  waitingForInput: boolean;
}

const connectionLabels: Record<ConnectionStatus, string> = {
  CREATED: "Criada",
  CONNECTING: "Conectando",
  CONNECTED: "Conectada",
  DISCONNECTED: "Desconectada",
  ERROR: "Com erro"
};

function errorMessage(
  error: unknown,
  fallback: string
) {
  return error instanceof ApiError
    ? error.message
    : fallback;
}

function ChatbotsContent() {
  const router = useRouter();
  const {
    session,
    request
  } = useAuth();

  const [chatbots, setChatbots] = useState<ChatbotFlow[]>([]);
  const [connections, setConnections] = useState<WhatsAppConnection[]>([]);
  const [name, setName] = useState("");
  const [connectionId, setConnectionId] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [loadingList, setLoadingList] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [testResults, setTestResults] = useState<
    Record<string, TestResponse | undefined>
  >({});

  const canManage = Boolean(
    session &&
    roleCan(session.role, "chatbots.manage")
  );

  const load = useCallback(async () => {
    const [
      chatbotPayload,
      connectionPayload
    ] = await Promise.all([
      request<ChatbotsResponse>("/api/v1/chatbots"),
      request<ConnectionsResponse>("/api/v1/whatsapp/connections")
    ]);

    setChatbots(chatbotPayload.chatbots);
    setConnections(connectionPayload.connections);

    setConnectionId(current => {
      if (
        current &&
        connectionPayload.connections.some(
          connection => connection.id === current
        )
      ) {
        return current;
      }

      return connectionPayload.connections[0]?.id ?? "";
    });
  }, [request]);

  useEffect(() => {
    let active = true;

    async function bootstrap() {
      setLoadingList(true);

      try {
        await load();
      } catch (caught) {
        if (active) {
          setError(
            errorMessage(
              caught,
              "Não foi possível carregar os chatbots."
            )
          );
        }
      } finally {
        if (active) {
          setLoadingList(false);
        }
      }
    }

    void bootstrap();

    return () => {
      active = false;
    };
  }, [load]);

  async function createChatbot(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!canManage) return;

    const trimmedName = name.trim();

    if (!trimmedName || !connectionId) {
      setError(
        "Informe o nome e escolha uma conexão para criar o chatbot."
      );
      return;
    }

    setBusy("create");
    setError("");
    setNotice("");

    try {
      const payload = await request<ChatbotResponse>(
        "/api/v1/chatbots",
        {
          method: "POST",
          body: JSON.stringify({
            name: trimmedName,
            whatsappConnectionId: connectionId,
            isActive: false
          })
        }
      );

      setName("");
      setNotice(
        `${payload.chatbot.name} foi criado e ficou inativo até você concluir o fluxo.`
      );

      await load();
    } catch (caught) {
      setError(
        errorMessage(
          caught,
          "Não foi possível criar o chatbot."
        )
      );
    } finally {
      setBusy(null);
    }
  }

  async function toggleChatbot(
    chatbot: ChatbotFlow
  ) {
    if (!canManage) return;

    if (
      !chatbot.isActive &&
      !window.confirm(
        `Ativar "${chatbot.name}" nesta conexão? Novas conversas poderão ser processadas pelo chatbot.`
      )
    ) {
      return;
    }

    setBusy(`toggle:${chatbot.id}`);
    setError("");
    setNotice("");

    try {
      await request<ChatbotResponse>(
        `/api/v1/chatbots/${chatbot.id}`,
        {
          method: "PATCH",
          body: JSON.stringify({
            isActive: !chatbot.isActive
          })
        }
      );

      setNotice(
        chatbot.isActive
          ? `${chatbot.name} foi desativado.`
          : `${chatbot.name} foi ativado.`
      );

      await load();
    } catch (caught) {
      setError(
        errorMessage(
          caught,
          "Não foi possível alterar o chatbot."
        )
      );
    } finally {
      setBusy(null);
    }
  }

  async function testChatbot(
    chatbot: ChatbotFlow
  ) {
    if (!canManage) return;

    setBusy(`test:${chatbot.id}`);
    setError("");
    setNotice("");

    try {
      const payload = await request<TestResponse>(
        `/api/v1/chatbots/${chatbot.id}/test`,
        {
          method: "POST"
        }
      );

      setTestResults(current => ({
        ...current,
        [chatbot.id]: payload
      }));
    } catch (caught) {
      setError(
        errorMessage(
          caught,
          "Não foi possível testar o chatbot."
        )
      );
    } finally {
      setBusy(null);
    }
  }

  return (
    <main className={styles.screen}>
      <header className={styles.header}>
        <div>
          <button
            className={styles.back}
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>

          <span className="eyebrow">
            Operação
          </span>

          <h1>Automações</h1>

          <p>
            Crie e acompanhe fluxos de atendimento sem sair do Wapp.
          </p>
        </div>

        <div className={styles.headerActions}>
          <button
            className={styles.secondaryButton}
            onClick={() =>
              router.push("/dashboard/connections")
            }
            type="button"
          >
            <Cable size={17} />
            Conexões
          </button>

          <button
            className={styles.secondaryButton}
            disabled={loadingList || busy !== null}
            onClick={() => {
              setError("");
              setNotice("");
              setLoadingList(true);

              void load()
                .catch(caught => {
                  setError(
                    errorMessage(
                      caught,
                      "Não foi possível atualizar os chatbots."
                    )
                  );
                })
                .finally(() => {
                  setLoadingList(false);
                });
            }}
            type="button"
          >
            <RefreshCw size={17} />
            Atualizar
          </button>
        </div>
      </header>

      <AutomationTabs active="chatbots" />

      {error && (
        <div className={styles.error}>
          {error}
        </div>
      )}

      {notice && (
        <div className={styles.notice}>
          <CheckCircle2
            aria-hidden="true"
            size={18}
          />
          {notice}
        </div>
      )}

      <section className={styles.hero}>
        <div className={styles.heroCopy}>
          <span className="eyebrow">
            Chatbots
          </span>

          <h2>
            Atendimento conversacional controlado pelo Wapp
          </h2>

          <p>
            Cada chatbot fica ligado a uma conexão WhatsApp. O Wapp
            controla ativação, sessões, histórico e transferência para
            atendimento humano.
          </p>
        </div>

        <div className={styles.heroMetric}>
          <strong>{chatbots.length}</strong>
          <span>
            {chatbots.length === 1
              ? "chatbot cadastrado"
              : "chatbots cadastrados"}
          </span>
        </div>
      </section>

      {canManage && (
        <form
          className={styles.createCard}
          onSubmit={createChatbot}
        >
          <div className={styles.createIntro}>
            <span className="eyebrow">
              Novo chatbot
            </span>
            <h2>Crie o fluxo dentro do Wapp</h2>
            <p>
              Ele será criado inativo. Assim você pode preparar o fluxo
              antes de colocá-lo em uma conexão em produção.
            </p>
          </div>

          <div className={styles.formGrid}>
            <label className={styles.field}>
              <span>Nome do chatbot</span>
              <input
                maxLength={160}
                onChange={event =>
                  setName(event.target.value)
                }
                placeholder="Ex.: Atendimento inicial"
                required
                value={name}
              />
            </label>

            <label className={styles.field}>
              <span>Conexão WhatsApp</span>
              <select
                onChange={event =>
                  setConnectionId(event.target.value)
                }
                required
                value={connectionId}
              >
                {connections.length === 0 && (
                  <option value="">
                    Nenhuma conexão disponível
                  </option>
                )}

                {connections.map(connection => (
                  <option
                    key={connection.id}
                    value={connection.id}
                  >
                    {connection.name} · {
                      connectionLabels[connection.status]
                    }
                  </option>
                ))}
              </select>
            </label>
          </div>

          <div className={styles.createFooter}>
            <span>
              O chatbot só responderá clientes depois que você o ativar.
            </span>

            <button
              className={styles.primaryButton}
              disabled={
                busy === "create" ||
                !name.trim() ||
                !connectionId
              }
              type="submit"
            >
              <Plus size={17} />
              {busy === "create"
                ? "Criando…"
                : "Criar chatbot"}
            </button>
          </div>
        </form>
      )}

      {!canManage && (
        <div className={styles.readOnly}>
          Você possui acesso de leitura aos chatbots. Alterações ficam
          disponíveis para supervisores e administradores.
        </div>
      )}

      <section className={styles.listSection}>
        <div className={styles.sectionHeader}>
          <div>
            <span className="eyebrow">
              Fluxos
            </span>
            <h2>Chatbots cadastrados</h2>
          </div>

          <span className={styles.sectionCount}>
            {chatbots.length}
          </span>
        </div>

        {loadingList ? (
          <div className={styles.emptyState}>
            <RefreshCw
              className={styles.spin}
              size={22}
            />
            <strong>Carregando chatbots…</strong>
          </div>
        ) : chatbots.length === 0 ? (
          <div className={styles.emptyState}>
            <Bot size={28} />
            <strong>Nenhum chatbot cadastrado</strong>
            <p>
              Crie o primeiro fluxo para começar a estruturar o
              atendimento conversacional.
            </p>
          </div>
        ) : (
          <div className={styles.cards}>
            {chatbots.map(chatbot => {
              const testing = busy === `test:${chatbot.id}`;
              const toggling = busy === `toggle:${chatbot.id}`;
              const result = testResults[chatbot.id];

              return (
                <article
                  className={styles.card}
                  key={chatbot.id}
                >
                  <div className={styles.cardTop}>
                    <div className={styles.botIdentity}>
                      <span className={styles.botIcon}>
                        <Bot size={20} />
                      </span>

                      <div>
                        <div className={styles.titleRow}>
                          <h3>{chatbot.name}</h3>

                          <span
                            className={
                              chatbot.isActive
                                ? styles.activeBadge
                                : styles.inactiveBadge
                            }
                          >
                            {chatbot.isActive
                              ? "Ativo"
                              : "Inativo"}
                          </span>
                        </div>

                        <p>
                          {chatbot.externalTypebotId
                            ? "Gerenciado pelo Wapp"
                            : "Fluxo vinculado"}
                        </p>
                      </div>
                    </div>

                    <div className={styles.connection}>
                      <Cable size={16} />
                      <div>
                        <strong>
                          {chatbot.whatsappConnection.name}
                        </strong>
                        <span>
                          {
                            connectionLabels[
                              chatbot.whatsappConnection.status
                            ]
                          }
                        </span>
                      </div>
                    </div>
                  </div>

                  <div className={styles.cardStats}>
                    <div>
                      <strong>{chatbot._count.sessions}</strong>
                      <span>
                        {chatbot._count.sessions === 1
                          ? "execução registrada"
                          : "execuções registradas"}
                      </span>
                    </div>

                    <div>
                      <strong>
                        {new Intl.DateTimeFormat(
                          "pt-BR",
                          {
                            dateStyle: "short"
                          }
                        ).format(
                          new Date(chatbot.updatedAt)
                        )}
                      </strong>
                      <span>última alteração</span>
                    </div>
                  </div>

                  {result && (
                    <div className={styles.testResult}>
                      <div className={styles.testResultTitle}>
                        <MessageSquareText size={16} />
                        <strong>Resultado do teste</strong>
                      </div>

                      {result.messages.length > 0 ? (
                        <div className={styles.testMessages}>
                          {result.messages.map((message, index) => (
                            <p key={`${chatbot.id}-${index}`}>
                              {message}
                            </p>
                          ))}
                        </div>
                      ) : (
                        <p className={styles.testEmpty}>
                          A sessão foi iniciada, mas o fluxo ainda não
                          retornou mensagens.
                        </p>
                      )}

                      <span className={styles.testMeta}>
                        {result.waitingForInput
                          ? "Aguardando resposta do usuário"
                          : "Sem entrada pendente"}
                      </span>
                    </div>
                  )}

                  <div className={styles.cardFooter}>
                    <div className={styles.statusHint}>
                      {chatbot.isActive ? (
                        <>
                          <CheckCircle2 size={16} />
                          Pode processar novas conversas
                        </>
                      ) : (
                        <>
                          <CircleOff size={16} />
                          Não processa novas conversas
                        </>
                      )}
                    </div>

                    {canManage && (
                      <div className={styles.cardActions}>
                        <button
                          className={styles.secondaryButton}
                          disabled={busy !== null}
                          onClick={() =>
                            void testChatbot(chatbot)
                          }
                          type="button"
                        >
                          <Play size={16} />
                          {testing ? "Testando…" : "Testar"}
                        </button>

                        <button
                          className={
                            chatbot.isActive
                              ? styles.dangerButton
                              : styles.primaryButton
                          }
                          disabled={busy !== null}
                          onClick={() =>
                            void toggleChatbot(chatbot)
                          }
                          type="button"
                        >
                          <Power size={16} />
                          {toggling
                            ? "Salvando…"
                            : chatbot.isActive
                              ? "Desativar"
                              : "Ativar"}
                        </button>
                      </div>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>
    </main>
  );
}

export default function ChatbotsPage() {
  return (
    <AccessGate permission="chatbots.view">
      <ChatbotsContent />
    </AccessGate>
  );
}
