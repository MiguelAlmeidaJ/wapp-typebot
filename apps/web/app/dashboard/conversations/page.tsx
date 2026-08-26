"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

interface Contact {
  id: string;
  name: string;
  remoteJid: string;
  phoneNumber: string | null;
  isGroup: boolean;
}

interface Connection {
  id: string;
  name: string;
  status: string;
  phoneNumber: string | null;
}

interface QueueInfo {
  id: string;
  name: string;
}

interface TeamMembership {
  id: string;
  role: "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";
  user: {
    id: string;
    name: string;
    email: string;
  };
}

type AssignedMembership = TeamMembership;

interface TicketMessagePreview {
  id: string;
  direction: "INBOUND" | "OUTBOUND";
  type: MessageType;
  body: string | null;
  timestamp: string;
}

interface Ticket {
  id: string;
  status: "OPEN" | "PENDING" | "CLOSED";
  unreadCount: number;
  lastMessage: string | null;
  lastMessageAt: string;
  queueId: string | null;
  assignedMembershipId: string | null;
  contact: Contact;
  whatsappConnection: Connection;
  queue: QueueInfo | null;
  assignedMembership: AssignedMembership | null;
  messages: TicketMessagePreview[];
}

type MessageType =
  | "TEXT"
  | "IMAGE"
  | "AUDIO"
  | "VIDEO"
  | "DOCUMENT"
  | "STICKER"
  | "LOCATION"
  | "CONTACT"
  | "UNKNOWN";

interface Message {
  id: string;
  externalId: string;
  direction: "INBOUND" | "OUTBOUND";
  type: MessageType;
  body: string | null;
  mediaMimeType: string | null;
  mediaFileName: string | null;
  timestamp: string;
  sentByUserId: string | null;
}

interface QueueOption {
  id: string;
  name: string;
  members?: Array<{
    membershipId: string;
  }>;
}

interface TicketsResponse {
  tickets: Ticket[];
}

interface MessagesResponse {
  messages: Message[];
}

interface QueuesResponse {
  queues: QueueOption[];
}

interface TeamResponse {
  memberships: TeamMembership[];
}

function messageFallback(type: MessageType) {
  const labels: Record<MessageType, string> = {
    TEXT: "Mensagem",
    IMAGE: "Imagem",
    AUDIO: "Áudio",
    VIDEO: "Vídeo",
    DOCUMENT: "Documento",
    STICKER: "Sticker",
    LOCATION: "Localização",
    CONTACT: "Contato",
    UNKNOWN: "Mensagem"
  };

  return `[${labels[type]}]`;
}

function ticketPreview(ticket: Ticket) {
  return (
    ticket.lastMessage ??
    ticket.messages[0]?.body ??
    (ticket.messages[0]
      ? messageFallback(ticket.messages[0].type)
      : "Nova conversa")
  );
}

function timeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

export default function ConversationsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();

  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [queues, setQueues] = useState<QueueOption[]>([]);
  const [team, setTeam] = useState<TeamMembership[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [closing, setClosing] = useState(false);
  const [claiming, setClaiming] = useState(false);
  const [transferring, setTransferring] = useState(false);
  const [transferQueueId, setTransferQueueId] = useState("");
  const [transferMembershipId, setTransferMembershipId] = useState("");
  const [error, setError] = useState("");
  const [onlineMembershipIds, setOnlineMembershipIds] = useState<string[]>([]);
  const bottomRef = useRef<HTMLDivElement | null>(null);

  const selectedTicket = useMemo(
    () => tickets.find(ticket => ticket.id === selectedId) ?? null,
    [selectedId, tickets]
  );

  const pendingCount = tickets.filter(
    ticket => ticket.status === "PENDING"
  ).length;
  const openCount = tickets.filter(ticket => ticket.status === "OPEN").length;

  const loadTickets = useCallback(async () => {
    const payload = await request<TicketsResponse>(
      "/api/v1/tickets?status=ACTIVE"
    );

    setTickets(payload.tickets);
    setSelectedId(current => {
      if (current && payload.tickets.some(ticket => ticket.id === current)) {
        return current;
      }
      return payload.tickets[0]?.id ?? null;
    });
  }, [request]);

  const loadReferenceData = useCallback(async () => {
    const [queuesPayload, teamPayload, presencePayload] = await Promise.all([
      request<QueuesResponse>("/api/v1/queues"),
      request<TeamResponse>("/api/v1/team/memberships"),
      request<{ membershipIds: string[] }>("/api/v1/realtime/presence")
    ]);

    setQueues(queuesPayload.queues);
    setTeam(teamPayload.memberships);
    setOnlineMembershipIds(presencePayload.membershipIds);
  }, [request]);

  const loadMessages = useCallback(
    async (ticketId: string) => {
      const payload = await request<MessagesResponse>(
        `/api/v1/tickets/${ticketId}/messages`
      );
      setMessages(payload.messages);
      await request(`/api/v1/tickets/${ticketId}/read`, {
        method: "POST"
      });
    },
    [request]
  );

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void Promise.all([loadTickets(), loadReferenceData()]).catch(() => {
        setError("Não foi possível carregar os atendimentos.");
      });
    }
  }, [loadReferenceData, loadTickets, loading, router, session]);

  useEffect(() => {
    if (!selectedId) {
      setMessages([]);
      return;
    }

    void loadMessages(selectedId).catch(() => {
      setError("Não foi possível carregar as mensagens.");
    });
  }, [loadMessages, selectedId]);

  useEffect(() => {
    if (!selectedTicket) {
      setTransferQueueId("");
      setTransferMembershipId("");
      return;
    }

    setTransferQueueId(selectedTicket.queueId ?? "");
    setTransferMembershipId(selectedTicket.assignedMembershipId ?? "");
  }, [selectedTicket]);

  useEffect(() => {
    if (!session) return;

    return subscribe("/api/v1/realtime/events", event => {
      if (
        event.type === "ticket.created" ||
        event.type === "ticket.updated" ||
        event.type === "message.created"
      ) {
        void loadTickets();

        if (selectedId && (!event.ticketId || event.ticketId === selectedId)) {
          void loadMessages(selectedId);
        }
      }

      if (event.type === "queue.updated") {
        void loadReferenceData();
      }
    });
  }, [
    loadMessages,
    loadReferenceData,
    loadTickets,
    selectedId,
    session,
    subscribe
  ]);

  useEffect(() => {
    if (!session) return;

    const fallback = window.setInterval(() => {
      void loadTickets();
    }, 30_000);

    return () => window.clearInterval(fallback);
  }, [loadTickets, session]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({
      behavior: "smooth",
      block: "end"
    });
  }, [messages]);

  async function handleClaim() {
    if (!selectedId) return;
    setClaiming(true);
    setError("");

    try {
      await request(`/api/v1/tickets/${selectedId}/claim`, {
        method: "POST"
      });
      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível assumir o atendimento."
      );
    } finally {
      setClaiming(false);
    }
  }

  async function handleTransfer() {
    if (!selectedId) return;
    setTransferring(true);
    setError("");

    try {
      await request(`/api/v1/tickets/${selectedId}/transfer`, {
        method: "POST",
        body: JSON.stringify({
          queueId: transferQueueId || null,
          membershipId: transferMembershipId || null
        })
      });
      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível transferir o atendimento."
      );
    } finally {
      setTransferring(false);
    }
  }

  async function handleSend(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedId || !text.trim()) return;

    setSending(true);
    setError("");

    try {
      await request(`/api/v1/tickets/${selectedId}/messages`, {
        method: "POST",
        body: JSON.stringify({ text: text.trim() })
      });
      setText("");
      await Promise.all([loadMessages(selectedId), loadTickets()]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível enviar a mensagem."
      );
    } finally {
      setSending(false);
    }
  }

  async function handleClose() {
    if (!selectedId) return;
    setClosing(true);

    try {
      await request(`/api/v1/tickets/${selectedId}/close`, {
        method: "POST"
      });
      setMessages([]);
      setSelectedId(null);
      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível encerrar o atendimento."
      );
    } finally {
      setClosing(false);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando conversas…</main>;
  }

  return (
    <main className="inbox-screen">
      <header className="inbox-topbar">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">Atendimento · tempo real</span>
          <h1>Conversas</h1>
        </div>
        <div className="inbox-topbar__right">
          <span>{session.company.name}</span>
          <button
            className="ghost-button"
            onClick={() => router.push("/dashboard/queues")}
            type="button"
          >
            Filas
          </button>
          <button
            className="ghost-button"
            onClick={() => router.push("/dashboard/connections")}
            type="button"
          >
            Conexões
          </button>
        </div>
      </header>

      {error && <div className="inbox-error">{error}</div>}

      <section className="inbox">
        <aside className="ticket-list">
          <div className="ticket-list__heading ticket-list__heading--stacked">
            <strong>Atendimentos ativos</strong>
            <div className="ticket-counters">
              <span>{pendingCount} aguardando</span>
              <span>{openCount} em atendimento</span>
            </div>
          </div>

          <div className="ticket-list__items">
            {tickets.length === 0 ? (
              <div className="ticket-list__empty">
                <strong>Nenhuma conversa ativa.</strong>
                <p>Novas mensagens entram aqui em tempo real.</p>
              </div>
            ) : (
              tickets.map(ticket => (
                <button
                  className={
                    ticket.id === selectedId
                      ? "ticket-item ticket-item--active"
                      : "ticket-item"
                  }
                  key={ticket.id}
                  onClick={() => setSelectedId(ticket.id)}
                  type="button"
                >
                  <div className="ticket-avatar">
                    {ticket.contact.name.slice(0, 1).toUpperCase()}
                  </div>
                  <div className="ticket-item__body">
                    <div className="ticket-item__row">
                      <strong>{ticket.contact.name}</strong>
                      <time>{timeLabel(ticket.lastMessageAt)}</time>
                    </div>
                    <div className="ticket-item__row">
                      <span className="ticket-item__preview">
                        {ticketPreview(ticket)}
                      </span>
                      {ticket.unreadCount > 0 && (
                        <span className="unread-badge">
                          {ticket.unreadCount}
                        </span>
                      )}
                    </div>
                    <div className="ticket-item__footer">
                      <small>{ticket.queue?.name ?? "Sem fila"}</small>
                      <span
                        className={
                          ticket.status === "PENDING"
                            ? "ticket-state ticket-state--pending"
                            : "ticket-state ticket-state--open"
                        }
                      >
                        {ticket.status === "PENDING" ? "Aguardando" : "Atendendo"}
                      </span>
                    </div>
                  </div>
                </button>
              ))
            )}
          </div>
        </aside>

        <section className="chat-panel chat-panel--operations">
          {!selectedTicket ? (
            <div className="chat-empty">
              <div className="chat-empty__mark">W</div>
              <strong>Suas conversas vão aparecer aqui.</strong>
              <p>O realtime substitui o polling de três segundos do P0.6.</p>
            </div>
          ) : (
            <>
              <header className="chat-header chat-header--p07">
                <div className="chat-header__contact">
                  <div className="ticket-avatar">
                    {selectedTicket.contact.name.slice(0, 1).toUpperCase()}
                  </div>
                  <div>
                    <strong>{selectedTicket.contact.name}</strong>
                    <span>
                      {selectedTicket.contact.phoneNumber ??
                        selectedTicket.contact.remoteJid}
                    </span>
                  </div>
                </div>

                <div className="chat-header__actions">
                  {!selectedTicket.assignedMembership && (
                      <button
                        className="primary-button claim-button"
                        disabled={claiming}
                        onClick={handleClaim}
                        type="button"
                      >
                        <span>{claiming ? "Assumindo…" : "Assumir"}</span>
                      </button>
                    )}
                  <button
                    className="ghost-button"
                    disabled={closing}
                    onClick={handleClose}
                    type="button"
                  >
                    {closing ? "Encerrando…" : "Encerrar"}
                  </button>
                </div>
              </header>

              <div className="assignment-bar">
                <div>
                  <span>Fila</span>
                  <select
                    onChange={event => {
                      setTransferQueueId(event.target.value);
                      setTransferMembershipId("");
                    }}
                    value={transferQueueId}
                  >
                    <option value="">Sem fila</option>
                    {queues.map(queue => (
                      <option key={queue.id} value={queue.id}>
                        {queue.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <span>Atendente</span>
                  <select
                    onChange={event =>
                      setTransferMembershipId(event.target.value)
                    }
                    value={transferMembershipId}
                  >
                    <option value="">Aguardando alguém assumir</option>
                    {team
                      .filter(membership => {
                        if (!transferQueueId) return true;
                        const queue = queues.find(
                          item => item.id === transferQueueId
                        );
                        const memberIds = queue?.members?.map(
                          member => member.membershipId
                        );
                        return !memberIds?.length || memberIds.includes(membership.id);
                      })
                      .map(membership => (
                        <option key={membership.id} value={membership.id}>
                          {membership.user.name} · {membership.role}
                        </option>
                      ))}
                  </select>
                </div>

                <button
                  className="secondary-button"
                  disabled={transferring}
                  onClick={handleTransfer}
                  type="button"
                >
                  {transferring ? "Transferindo…" : "Aplicar transferência"}
                </button>

                <small>
                  Atual: {selectedTicket.queue?.name ?? "sem fila"} · {" "}
                  {selectedTicket.assignedMembership?.user.name ?? "sem atendente"}
                </small>
              </div>

              <div className="message-list message-list--assignment">
                <div className="message-scroll">
                {messages.map(message => (
                  <div
                    className={
                      message.direction === "OUTBOUND"
                        ? "message-row message-row--out"
                        : "message-row message-row--in"
                    }
                    key={message.id}
                  >
                    <article className="message-bubble">
                      {message.type !== "TEXT" && (
                        <span className="message-kind">
                          {messageFallback(message.type)}
                        </span>
                      )}
                      <p>{message.body ?? messageFallback(message.type)}</p>
                      {message.mediaFileName && (
                        <small className="message-file">
                          {message.mediaFileName}
                        </small>
                      )}
                      <time>{dateTimeLabel(message.timestamp)}</time>
                    </article>
                  </div>
                ))}
                <div ref={bottomRef} />
                              </div>

                <form className="composer composer--sticky" onSubmit={handleSend}>
                <textarea
                  maxLength={4096}
                  onChange={event => setText(event.target.value)}
                  onKeyDown={event => {
                    if (event.key === "Enter" && !event.shiftKey) {
                      event.preventDefault();
                      event.currentTarget.form?.requestSubmit();
                    }
                  }}
                  placeholder="Digite uma mensagem…"
                  rows={1}
                  value={text}
                />
                <button
                  className="composer__send"
                  disabled={sending || !text.trim()}
                  type="submit"
                >
                  {sending ? "…" : "→"}
                </button>
              </form>
              </div>
            </>
          )}
        </section>
      </section>
    </main>
  );
}
