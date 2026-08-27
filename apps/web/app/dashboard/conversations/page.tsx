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
import fixWebmDuration from "fix-webm-duration";

import { useAuth } from "@/components/auth-provider";
import { MessageMedia } from "@/components/messages/message-media";
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
  mediaStatus: "NONE" | "PENDING" | "READY" | "FAILED";
  mediaSize: number | null;
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

function isMediaMessage(type: MessageType) {
  return [
    "IMAGE",
    "AUDIO",
    "VIDEO",
    "DOCUMENT",
    "STICKER"
  ].includes(type);
}

function visibleMessageBody(
  message: Pick<Message, "type" | "body">
) {
  if (!message.body) {
    return isMediaMessage(message.type)
      ? null
      : messageFallback(message.type);
  }

  if (
    isMediaMessage(message.type) &&
    message.body === messageFallback(message.type)
  ) {
    return null;
  }

  return message.body;
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

function recordingTimeLabel(
  seconds: number
) {
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;

  return `${String(minutes).padStart(2, "0")}:${String(
    remainder
  ).padStart(2, "0")}`;
}

function preferredRecordingMimeType() {
  if (
    typeof MediaRecorder === "undefined"
  ) {
    return "";
  }

  const candidates = [
    "audio/ogg;codecs=opus",
    "audio/webm;codecs=opus",
    "audio/webm",
    "audio/mp4"
  ];

  return (
    candidates.find(candidate =>
      MediaRecorder.isTypeSupported(candidate)
    ) ?? ""
  );
}

function recordingExtension(
  mimeType: string
) {
  const normalized =
    mimeType
      .split(";")[0]
      ?.trim()
      .toLowerCase() ?? "";

  if (normalized === "audio/ogg") {
    return "ogg";
  }

  if (normalized === "audio/mp4") {
    return "m4a";
  }

  return "webm";
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
  const [attachment, setAttachment] =
    useState<File | null>(null);
  const [attachmentPreviewUrl, setAttachmentPreviewUrl] =
    useState<string | null>(null);
  const [attachmentIsVoiceNote, setAttachmentIsVoiceNote] =
    useState(false);
  const [recording, setRecording] =
    useState(false);
  const [recordingSeconds, setRecordingSeconds] =
    useState(0);
  const [sending, setSending] = useState(false);
  const [closing, setClosing] = useState(false);
  const [claiming, setClaiming] = useState(false);
  const [transferring, setTransferring] = useState(false);
  const [transferQueueId, setTransferQueueId] = useState("");
  const [transferMembershipId, setTransferMembershipId] = useState("");
  const [error, setError] = useState("");
  const [onlineMembershipIds, setOnlineMembershipIds] = useState<string[]>([]);
  const bottomRef = useRef<HTMLDivElement | null>(null);
  const attachmentInputRef =
    useRef<HTMLInputElement | null>(null);
  const mediaRecorderRef =
    useRef<MediaRecorder | null>(null);
  const mediaStreamRef =
    useRef<MediaStream | null>(null);
  const audioChunksRef =
    useRef<Blob[]>([]);
  const recordingTimerRef =
    useRef<number | null>(null);
  const recordingStartedAtRef =
    useRef<number | null>(null);
  const discardRecordingRef =
    useRef(false);

  const selectedTicket = useMemo(
    () => tickets.find(ticket => ticket.id === selectedId) ?? null,
    [selectedId, tickets]
  );

  const pendingCount = tickets.filter(
    ticket => ticket.status === "PENDING"
  ).length;
  const openCount = tickets.filter(ticket => ticket.status === "OPEN").length;

  const hasPendingMedia = messages.some(
    message => message.mediaStatus === "PENDING"
  );

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

  // [P1.3 attachment preview]
  useEffect(() => {
    if (!attachment) {
      setAttachmentPreviewUrl(null);
      return;
    }

    if (
      !attachment.type.startsWith("image/") &&
      !attachment.type.startsWith("audio/")
    ) {
      setAttachmentPreviewUrl(null);
      return;
    }

    const url =
      URL.createObjectURL(attachment);

    setAttachmentPreviewUrl(url);

    return () => {
      URL.revokeObjectURL(url);
    };
  }, [attachment]);

  // [P1.2f pending media fallback]
  // SSE remains primary. This polls only while media is still processing.
  useEffect(() => {
    if (
      !session ||
      !selectedId ||
      !hasPendingMedia
    ) {
      return;
    }

    let cancelled = false;

    const refreshPendingMedia = async () => {
      try {
        const payload = await request<MessagesResponse>(
          `/api/v1/tickets/${selectedId}/messages`
        );

        if (!cancelled) {
          setMessages(payload.messages);
        }
      } catch {
        // Non-fatal fallback. Realtime or the next tick can recover.
      }
    };

    const interval = window.setInterval(
      () => {
        void refreshPendingMedia();
      },
      1_200
    );

    void refreshPendingMedia();

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [
    hasPendingMedia,
    request,
    selectedId,
    session
  ]);


  // [P1.4 recorder cleanup]
  useEffect(() => {
    return () => {
      if (recordingTimerRef.current !== null) {
        window.clearInterval(
          recordingTimerRef.current
        );
      }

      const recorder =
        mediaRecorderRef.current;

      if (
        recorder &&
        recorder.state !== "inactive"
      ) {
        recorder.ondataavailable = null;
        recorder.onstop = null;
        recorder.stop();
      }

      mediaStreamRef.current
        ?.getTracks()
        .forEach(track => track.stop());
    };
  }, []);

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

  function stopRecordingResources() {
    if (recordingTimerRef.current !== null) {
      window.clearInterval(
        recordingTimerRef.current
      );
      recordingTimerRef.current = null;
    }

    recordingStartedAtRef.current = null;

    mediaStreamRef.current
      ?.getTracks()
      .forEach(track => track.stop());

    mediaStreamRef.current = null;
  }

  async function startRecording() {
    if (sending || attachment || recording) {
      return;
    }

    if (text.trim()) {
      setError(
        "Envie ou apague o texto antes de gravar uma mensagem de voz."
      );
      return;
    }

    if (
      !navigator.mediaDevices?.getUserMedia ||
      typeof MediaRecorder === "undefined"
    ) {
      setError(
        "Este navegador não oferece suporte à gravação de áudio."
      );
      return;
    }

    setError("");
    discardRecordingRef.current = false;

    try {
      const stream =
        await navigator.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true
          }
        });

      mediaStreamRef.current = stream;

      const mimeType =
        preferredRecordingMimeType();

      const recorder = mimeType
        ? new MediaRecorder(stream, {
            mimeType
          })
        : new MediaRecorder(stream);

      mediaRecorderRef.current = recorder;
      audioChunksRef.current = [];

      recorder.ondataavailable = event => {
        if (event.data.size > 0) {
          audioChunksRef.current.push(
            event.data
          );
        }
      };

      recorder.onerror = () => {
        setError(
          "A gravação de áudio foi interrompida pelo navegador."
        );
      };

      recorder.onstop = async () => {
        const startedAt =
          recordingStartedAtRef.current;

        const durationMs = startedAt
          ? Math.max(
              1,
              Date.now() - startedAt
            )
          : 1;

        stopRecordingResources();
        setRecording(false);
        setRecordingSeconds(0);

        if (discardRecordingRef.current) {
          audioChunksRef.current = [];
          discardRecordingRef.current = false;
          return;
        }

        const finalMimeType =
          recorder.mimeType ||
          mimeType ||
          "audio/webm";

        let blob = new Blob(
          audioChunksRef.current,
          {
            type: finalMimeType
          }
        );

        audioChunksRef.current = [];

        if (blob.size === 0) {
          setError(
            "O navegador não gerou conteúdo para esta gravação."
          );
          return;
        }

        // [P1.4b WebM duration metadata]
        // Chromium can produce MediaRecorder WebM blobs without Duration.
        // Repair it before preview/upload so the player knows the real length.
        if (
          finalMimeType
            .toLowerCase()
            .startsWith("audio/webm")
        ) {
          try {
            blob = await fixWebmDuration(
              blob,
              durationMs,
              {
                logger: false
              }
            );
          } catch {
            // Keep the original recording if metadata repair fails.
            // Sending audio must not depend on the preview-only correction.
          }
        }

        const extension =
          recordingExtension(
            finalMimeType
          );

        const stamp = new Date()
          .toISOString()
          .replace(/[:.]/g, "-");

        const file = new File(
          [blob],
          `audio-wapp-${stamp}.${extension}`,
          {
            type: finalMimeType
          }
        );

        const maxBytes =
          25 * 1024 * 1024;

        if (file.size > maxBytes) {
          setError(
            "A gravação excedeu o limite de 25 MB."
          );
          return;
        }

        setAttachmentIsVoiceNote(true);
        setAttachment(file);
      };

      recorder.start(250);

      recordingStartedAtRef.current =
        Date.now();

      setRecordingSeconds(0);
      setRecording(true);

      recordingTimerRef.current =
        window.setInterval(() => {
          const startedAt =
            recordingStartedAtRef.current;

          if (!startedAt) {
            return;
          }

          setRecordingSeconds(
            Math.floor(
              (Date.now() - startedAt) /
                1000
            )
          );
        }, 250);
    } catch (caught) {
      stopRecordingResources();

      if (
        caught instanceof DOMException &&
        (caught.name === "NotAllowedError" ||
          caught.name ===
            "PermissionDeniedError")
      ) {
        setError(
          "Permita o acesso ao microfone para gravar áudio."
        );
        return;
      }

      setError(
        "Não foi possível iniciar o microfone."
      );
    }
  }

  function stopRecording() {
    const recorder =
      mediaRecorderRef.current;

    if (
      !recorder ||
      recorder.state === "inactive"
    ) {
      return;
    }

    recorder.stop();
  }

  function cancelRecording() {
    discardRecordingRef.current = true;

    const recorder =
      mediaRecorderRef.current;

    if (
      recorder &&
      recorder.state !== "inactive"
    ) {
      recorder.stop();
      return;
    }

    stopRecordingResources();
    setRecording(false);
    setRecordingSeconds(0);
  }

  function chooseAttachment(
    file: File | undefined
  ) {
    if (!file) {
      return;
    }

    const maxBytes =
      25 * 1024 * 1024;

    if (file.size > maxBytes) {
      setError(
        "O arquivo excede o limite de 25 MB."
      );
      return;
    }

    setError("");
    setAttachmentIsVoiceNote(false);
    setAttachment(file);
  }

  async function handleSend(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !selectedId ||
      recording ||
      (!text.trim() && !attachment)
    ) {
      return;
    }

    setSending(true);
    setError("");

    try {
      if (attachment) {
        const form = new FormData();

        // Put value fields before the file so Fastify multipart
        // has them available while consuming the upload.
        form.append(
          "caption",
          attachmentIsVoiceNote
            ? ""
            : text.trim()
        );
        form.append(
          "voiceNote",
          attachmentIsVoiceNote
            ? "true"
            : "false"
        );
        form.append(
          "file",
          attachment,
          attachment.name
        );

        await request(
          `/api/v1/tickets/${selectedId}/media`,
          {
            method: "POST",
            body: form
          }
        );

        setAttachment(null);
        setAttachmentIsVoiceNote(false);

        if (
          attachmentInputRef.current
        ) {
          attachmentInputRef.current.value =
            "";
        }
      } else {
        await request(
          `/api/v1/tickets/${selectedId}/messages`,
          {
            method: "POST",
            body: JSON.stringify({
              text: text.trim()
            })
          }
        );
      }

      setText("");

      await Promise.all([
        loadMessages(selectedId),
        loadTickets()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : attachment
            ? "Não foi possível enviar o anexo."
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
    <main className="inbox-screen inbox-screen--contained">
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

        <section className="conversation-panel">
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

              <div className="conversation-body">
                <div className="conversation-scroll">
                {messages.map(message => (
                  <div
                    className={
                      message.direction === "OUTBOUND"
                        ? "message-row message-row--out"
                        : "message-row message-row--in"
                    }
                    key={message.id}
                  >
                    <article
                      className={
                        isMediaMessage(message.type)
                          ? "message-bubble message-bubble--media"
                          : "message-bubble"
                      }
                    >
                      {!isMediaMessage(message.type) &&
                        message.type !== "TEXT" && (
                          <span className="message-kind">
                            {messageFallback(message.type)}
                          </span>
                        )}

                      <MessageMedia
                        fileName={message.mediaFileName}
                        messageId={message.id}
                        mimeType={message.mediaMimeType}
                        status={message.mediaStatus}
                        type={message.type}
                      />

                      {visibleMessageBody(message) && (
                        <p>{visibleMessageBody(message)}</p>
                      )}

                      {!isMediaMessage(message.type) &&
                        message.mediaFileName && (
                          <small className="message-file">
                            {message.mediaFileName}
                          </small>
                        )}

                      <time>
                        {dateTimeLabel(message.timestamp)}
                      </time>
                    </article>
                  </div>
                ))}
                <div ref={bottomRef} />
                              </div>

                <form
                  className="conversation-composer conversation-composer--attachments conversation-composer--voice"
                  onSubmit={handleSend}
                >
                  <input
                    accept="image/jpeg,image/png,image/webp,image/gif,audio/ogg,audio/mpeg,audio/mp4,audio/webm,audio/wav,video/mp4,video/webm,application/pdf,text/plain,application/zip,.doc,.docx,.xls,.xlsx,.ppt,.pptx"
                    className="composer-file-input"
                    onChange={event =>
                      chooseAttachment(
                        event.target.files?.[0]
                      )
                    }
                    ref={attachmentInputRef}
                    type="file"
                  />

                  {attachment && (
                    <div className="composer-attachment-preview">
                      {attachmentPreviewUrl &&
                      attachment.type.startsWith("image/") ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          alt="Prévia do anexo"
                          src={attachmentPreviewUrl}
                        />
                      ) : (
                        <div className="composer-attachment-preview__icon">
                          {attachment.type.startsWith("audio/")
                            ? "ÁUDIO"
                            : "ARQ"}
                        </div>
                      )}

                      <div className="composer-attachment-preview__copy">
                        <strong>
                          {attachmentIsVoiceNote
                            ? "Mensagem de voz"
                            : attachment.name}
                        </strong>
                        <span>
                          {(attachment.size / 1024 / 1024).toFixed(2)} MB
                          {" · "}
                          {attachment.type || "arquivo"}
                        </span>
                      </div>

                      {attachmentPreviewUrl &&
                        attachment.type.startsWith("audio/") && (
                          <audio
                            className="composer-attachment-preview__audio"
                            controls
                            preload="metadata"
                            src={attachmentPreviewUrl}
                          />
                        )}

                      <button
                        aria-label="Remover anexo"
                        className="composer-attachment-preview__remove"
                        disabled={sending}
                        onClick={() => {
                          setAttachment(null);
                          setAttachmentIsVoiceNote(false);

                          if (
                            attachmentInputRef.current
                          ) {
                            attachmentInputRef.current.value =
                              "";
                          }
                        }}
                        type="button"
                      >
                        ×
                      </button>
                    </div>
                  )}

                  {recording && (
                    <div className="composer-recording">
                      <span
                        className="composer-recording__dot"
                        aria-hidden="true"
                      />
                      <strong>Gravando áudio</strong>
                      <time>
                        {recordingTimeLabel(
                          recordingSeconds
                        )}
                      </time>
                      <button
                        className="composer-recording__cancel"
                        onClick={cancelRecording}
                        type="button"
                      >
                        Cancelar
                      </button>
                    </div>
                  )}

                  <button
                    aria-label="Anexar arquivo"
                    className="composer__attach"
                    disabled={sending || recording}
                    onClick={() =>
                      attachmentInputRef.current?.click()
                    }
                    type="button"
                  >
                    +
                  </button>

                  <button
                    aria-label={
                      recording
                        ? "Parar gravação"
                        : "Gravar áudio"
                    }
                    className={
                      recording
                        ? "composer__record composer__record--active"
                        : "composer__record"
                    }
                    disabled={
                      sending ||
                      (!!attachment && !recording)
                    }
                    onClick={() => {
                      if (recording) {
                        stopRecording();
                      } else {
                        void startRecording();
                      }
                    }}
                    type="button"
                  >
                    {recording ? "■" : "●"}
                  </button>

                  <textarea
                  disabled={
                    recording ||
                    attachmentIsVoiceNote
                  }
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
                  disabled={
                    sending ||
                    recording ||
                    (!text.trim() && !attachment)
                  }
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
