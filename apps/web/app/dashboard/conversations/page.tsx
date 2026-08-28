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
import { ConversationSearch } from "@/components/conversations/conversation-search";
import { ClosedTicketsDrawer } from "@/components/conversations/closed-tickets-drawer";
import { SlaMonitorDrawer } from "@/components/conversations/sla-monitor-drawer";
import { TicketHistoryDrawer } from "@/components/conversations/ticket-history-drawer";
import { ApiError } from "@/lib/api";

interface Contact {
  id: string;
  name: string;
  remoteJid: string;
  phoneNumber: string | null;
  whatsappName:
    | string
    | null;
  isGroup: boolean;
}

interface Connection {
  id: string;
  name: string;
  status: string;
  phoneNumber: string | null;
}

interface TagInfo {
  id: string;
  name: string;
  colorKey:
    | "GREEN"
    | "BLUE"
    | "ORANGE"
    | "RED"
    | "PURPLE"
    | "GRAY";
  isActive: boolean;
}

interface TicketTagInfo {
  tagId: string;
  tag: TagInfo;
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
  tags: TicketTagInfo[];
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

interface MessageReaction {
  id: string;
  reactorKey: string;
  reactorJid:
    | string
    | null;
  fromMe: boolean;
  emoji: string;
  actorName:
    | string
    | null;
  updatedAt: string;
}

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
  deliveryStatus: "NONE" | "PENDING" | "SENT" | "DELIVERED" | "READ" | "PLAYED" | "FAILED";
  deliveredAt: string | null;
  readAt: string | null;
  playedAt: string | null;
  deliveryError: string | null;
  timestamp: string;
  sentByUserId: string | null;
  quotedExternalId:
    | string
    | null;
  quotedMessage:
    | {
        id: string;
        externalId: string;
        direction:
          | "INBOUND"
          | "OUTBOUND";
        type:
          MessageType;
        body:
          | string
          | null;
        mediaFileName:
          | string
          | null;
        timestamp:
          string;
      }
    | null;
  reactions: MessageReaction[];
}

interface QuickReply {
  id: string;
  shortcut: string;
  title: string;
  body: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
  createdByMembership: {
    id: string;
    user: {
      id: string;
      name: string;
    };
  } | null;
}

interface TagsResponse {
  tags: TagInfo[];
}

interface QuickRepliesResponse {
  quickReplies: QuickReply[];
}

interface TicketNote {
  id: string;
  body: string;
  createdAt: string;
  authorMembership: {
    id: string;
    role: "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";
    user: {
      id: string;
      name: string;
      email: string;
    };
  };
}

interface NotesResponse {
  notes: TicketNote[];
}

interface QueueOption {
  id: string;
  name: string;
  members?: Array<{
    membershipId: string;
  }>;
}

type TicketStatusFilter =
  | "ACTIVE"
  | "PENDING"
  | "OPEN";

type TicketConversationFilter =
  | "ALL"
  | "DIRECT"
  | "GROUP";

interface InboxFilterState {
  search: string;
  status:
    TicketStatusFilter;
  queueId: string;
  assigneeId: string;
  unreadOnly: boolean;
  tagId: string;
  conversationType:
    TicketConversationFilter;
}

interface TicketsResponse {
  tickets: Ticket[];
}

interface MessagePagination {
  hasMoreBefore: boolean;
  olderCursor: string | null;
  hasMoreAfter: boolean;
  newerCursor: string | null;
}

interface MessagesResponse {
  messages: Message[];
  pagination: MessagePagination;
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

function groupedReactions(
  reactions:
    MessageReaction[]
) {
  const groups =
    new Map<
      string,
      {
        emoji: string;
        count: number;
        fromMe: boolean;
      }
    >();

  for (
    const reaction
    of reactions
  ) {
    const current =
      groups.get(
        reaction.emoji
      );

    groups.set(
      reaction.emoji,
      {
        emoji:
          reaction.emoji,
        count:
          (current?.count ?? 0) +
          1,
        fromMe:
          Boolean(
            current?.fromMe ||
            reaction.fromMe
          )
      }
    );
  }

  return Array.from(
    groups.values()
  );
}

function ownReaction(
  message: Message
) {
  return message.reactions.find(
    reaction =>
      reaction.fromMe
  );
}

function quotedMessagePreview(
  message:
    NonNullable<
      Message[
        "quotedMessage"
      ]
    >
) {
  if (
    message.body &&
    message.body.trim()
  ) {
    return message.body;
  }

  if (
    message.mediaFileName
  ) {
    return message.mediaFileName;
  }

  return messageFallback(
    message.type
  );
}

function replyTargetPreview(
  message: Message
) {
  return (
    visibleMessageBody(
      message
    ) ??
    message.mediaFileName ??
    messageFallback(
      message.type
    )
  );
}

function deliveryStatusPresentation(
  status: Message["deliveryStatus"]
) {
  switch (status) {
    case "PENDING":
      return {
        glyph: "○",
        label: "Enviando"
      };
    case "SENT":
      return {
        glyph: "✓",
        label: "Enviada"
      };
    case "DELIVERED":
      return {
        glyph: "✓✓",
        label: "Entregue"
      };
    case "READ":
      return {
        glyph: "✓✓",
        label: "Lida"
      };
    case "PLAYED":
      return {
        glyph: "✓✓",
        label: "Ouvida"
      };
    case "FAILED":
      return {
        glyph: "!",
        label: "Falhou"
      };
    default:
      return null;
  }
}

function expandQuickReply(
  body: string,
  context: {
    contactName: string;
    agentName: string;
    companyName: string;
  }
) {
  const firstName =
    context.contactName
      .trim()
      .split(/\s+/)[0] ??
    context.contactName;

  const variables: Record<string, string> = {
    "{{nome}}":
      context.contactName,
    "{{primeiro_nome}}":
      firstName,
    "{{atendente}}":
      context.agentName,
    "{{empresa}}":
      context.companyName
  };

  return Object.entries(
    variables
  ).reduce(
    (result, [token, value]) =>
      result.split(token).join(value),
    body
  );
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

function mergeMessagePages(
  ...pages: Message[][]
) {
  const byId =
    new Map<
      string,
      Message
    >();

  for (
    const page
    of pages
  ) {
    for (
      const message
      of page
    ) {
      byId.set(
        message.id,
        message
      );
    }
  }

  return Array.from(
    byId.values()
  ).sort(
    (left, right) => {
      const time =
        new Date(
          left.timestamp
        ).getTime() -
        new Date(
          right.timestamp
        ).getTime();

      return (
        time ||
        left.id.localeCompare(
          right.id
        )
      );
    }
  );
}

const REACTION_OPTIONS = [
  "👍",
  "❤️",
  "😂",
  "😮",
  "😢",
  "🙏"
] as const;

export default function ConversationsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();

  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [inboxFilters, setInboxFilters] =
    useState<InboxFilterState>({
      search: "",
      status:
        "ACTIVE",
      queueId: "",
      assigneeId: "",
      unreadOnly:
        false,
      tagId: "",
      conversationType:
        "ALL"
    });
  const [debouncedTicketSearch, setDebouncedTicketSearch] =
    useState("");
  const [queues, setQueues] = useState<QueueOption[]>([]);
  const [team, setTeam] = useState<TeamMembership[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [messagePagination, setMessagePagination] =
    useState<MessagePagination>({
      hasMoreBefore: false,
      olderCursor: null,
      hasMoreAfter: false,
      newerCursor: null
    });
  const [loadingOlderMessages, setLoadingOlderMessages] =
    useState(false);
  const [loadingNewerMessages, setLoadingNewerMessages] =
    useState(false);
  const [focusedMessageId, setFocusedMessageId] =
    useState<string | null>(null);
  const [notes, setNotes] = useState<TicketNote[]>([]);
  const [quickReplies, setQuickReplies] =
    useState<QuickReply[]>([]);
  const [tags, setTags] =
    useState<TagInfo[]>([]);
  const [managedTags, setManagedTags] =
    useState<TagInfo[]>([]);
  const [tagPickerOpen, setTagPickerOpen] =
    useState(false);
  const [conversationSearchOpen, setConversationSearchOpen] =
    useState(false);
  const [closedTicketsOpen, setClosedTicketsOpen] =
    useState(false);
  const [slaMonitorOpen, setSlaMonitorOpen] =
    useState(false);
  const [ticketHistoryOpen, setTicketHistoryOpen] =
    useState(false);
  const [operationNotice, setOperationNotice] =
    useState("");
  const [tagManagerOpen, setTagManagerOpen] =
    useState(false);
  const [ticketTagFilter, setTicketTagFilter] =
    useState("");
  const [tagName, setTagName] =
    useState("");
  const [tagColorKey, setTagColorKey] =
    useState<TagInfo["colorKey"]>("GREEN");
  const [editingTagId, setEditingTagId] =
    useState<string | null>(null);
  const [savingTag, setSavingTag] =
    useState(false);
  const [updatingTicketTags, setUpdatingTicketTags] =
    useState(false);
  const [managedQuickReplies, setManagedQuickReplies] =
    useState<QuickReply[]>([]);
  const [quickRepliesOpen, setQuickRepliesOpen] =
    useState(false);
  const [quickReplyManagerOpen, setQuickReplyManagerOpen] =
    useState(false);
  const [quickReplySearch, setQuickReplySearch] =
    useState("");
  const [quickReplyShortcut, setQuickReplyShortcut] =
    useState("");
  const [quickReplyTitle, setQuickReplyTitle] =
    useState("");
  const [quickReplyBody, setQuickReplyBody] =
    useState("");
  const [editingQuickReplyId, setEditingQuickReplyId] =
    useState<string | null>(null);
  const [savingQuickReply, setSavingQuickReply] =
    useState(false);
  const [notesOpen, setNotesOpen] = useState(false);
  const [noteText, setNoteText] = useState("");
  const [savingNote, setSavingNote] = useState(false);
  const [text, setText] = useState("");
  const [replyingTo, setReplyingTo] =
    useState<Message | null>(null);
  const [reactionPickerMessageId, setReactionPickerMessageId] =
    useState<string | null>(null);
  const [reactingMessageId, setReactingMessageId] =
    useState<string | null>(null);
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
  const conversationScrollRef =
    useRef<HTMLDivElement | null>(null);
  const shouldScrollToBottomRef =
    useRef(true);
  const skipNextSelectedLoadRef =
    useRef(false);
  const attachmentInputRef =
    useRef<HTMLInputElement | null>(null);
  const composerTextRef =
    useRef<HTMLTextAreaElement | null>(null);
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

  const canManageQuickReplies =
    session
      ? ["OWNER", "ADMIN", "SUPERVISOR"].includes(
          session.role
        )
      : false;

  const canManageTags =
    session
      ? ["OWNER", "ADMIN", "SUPERVISOR"].includes(
          session.role
        )
      : false;

  const selectedTicket = useMemo(
    () => tickets.find(ticket => ticket.id === selectedId) ?? null,
    [selectedId, tickets]
  );

  const visibleTickets = useMemo(
    () =>
      ticketTagFilter
        ? tickets.filter(ticket =>
            ticket.tags.some(
              link =>
                link.tag.id ===
                ticketTagFilter
            )
          )
        : tickets,
    [
      ticketTagFilter,
      tickets
    ]
  );

  const activeInboxFilterCount =
    [
      inboxFilters.status !==
        "ACTIVE",
      Boolean(
        inboxFilters.queueId
      ),
      Boolean(
        inboxFilters.assigneeId
      ),
      inboxFilters.unreadOnly,
      Boolean(
        inboxFilters.tagId
      ),
      inboxFilters.conversationType !==
        "ALL"
    ].filter(
      Boolean
    ).length;

  const hasInboxFilter =
    Boolean(
      debouncedTicketSearch ||
      activeInboxFilterCount
    );

  const pendingCount = tickets.filter(
    ticket => ticket.status === "PENDING"
  ).length;
  const openCount = tickets.filter(ticket => ticket.status === "OPEN").length;

  const filteredQuickReplies = useMemo(() => {
    const slashQuery =
      text.startsWith("/")
        ? text.slice(1).trim()
        : "";

    const query =
      (
        slashQuery ||
        quickReplySearch
      )
        .toLowerCase()
        .trim();

    return quickReplies
      .filter(reply =>
        reply.isActive
      )
      .filter(reply => {
        if (!query) {
          return true;
        }

        return (
          reply.shortcut
            .toLowerCase()
            .includes(query) ||
          reply.title
            .toLowerCase()
            .includes(query) ||
          reply.body
            .toLowerCase()
            .includes(query)
        );
      })
      .slice(0, 12);
  }, [
    quickReplies,
    quickReplySearch,
    text
  ]);

  const hasPendingMedia = messages.some(
    message => message.mediaStatus === "PENDING"
  );

  const loadTickets = useCallback(async () => {
    const params =
      new URLSearchParams({
        status:
          inboxFilters.status
      });

    if (
      debouncedTicketSearch
    ) {
      params.set(
        "q",
        debouncedTicketSearch
      );
    }

    if (
      inboxFilters.queueId
    ) {
      params.set(
        "queueId",
        inboxFilters.queueId
      );
    }

    if (
      inboxFilters.assigneeId
    ) {
      params.set(
        "assigneeId",
        inboxFilters.assigneeId
      );
    }

    if (
      inboxFilters.unreadOnly
    ) {
      params.set(
        "unreadOnly",
        "true"
      );
    }

    if (
      inboxFilters.tagId
    ) {
      params.set(
        "tagId",
        inboxFilters.tagId
      );
    }

    if (
      inboxFilters.conversationType !==
      "ALL"
    ) {
      params.set(
        "conversationType",
        inboxFilters.conversationType
      );
    }

    const payload =
      await request<TicketsResponse>(
        `/api/v1/tickets?${params.toString()}`
      );

    setTickets(
      payload.tickets
    );

    setSelectedId(
      current => {
        if (!current) {
          return null;
        }

        return payload.tickets.some(
          ticket =>
            ticket.id ===
            current
        )
          ? current
          : null;
      }
    );
  }, [
    debouncedTicketSearch,
    inboxFilters.assigneeId,
    inboxFilters.conversationType,
    inboxFilters.queueId,
    inboxFilters.status,
    inboxFilters.tagId,
    inboxFilters.unreadOnly,
    request
  ]);

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

  const loadTags = useCallback(
    async () => {
      const payload =
        await request<TagsResponse>(
          "/api/v1/tags"
        );

      setTags(payload.tags);
    },
    [request]
  );

  const loadManagedTags = useCallback(
    async () => {
      if (!canManageTags) {
        setManagedTags([]);
        return;
      }

      const payload =
        await request<TagsResponse>(
          "/api/v1/tags/manage"
        );

      setManagedTags(
        payload.tags
      );
    },
    [
      canManageTags,
      request
    ]
  );

  const loadQuickReplies = useCallback(
    async () => {
      const payload =
        await request<QuickRepliesResponse>(
          "/api/v1/quick-replies"
        );

      setQuickReplies(
        payload.quickReplies
      );
    },
    [request]
  );

  const loadManagedQuickReplies = useCallback(
    async () => {
      if (!canManageQuickReplies) {
        setManagedQuickReplies([]);
        return;
      }

      const payload =
        await request<QuickRepliesResponse>(
          "/api/v1/quick-replies/manage"
        );

      setManagedQuickReplies(
        payload.quickReplies
      );
    },
    [
      canManageQuickReplies,
      request
    ]
  );

  const loadNotes = useCallback(
    async (ticketId: string) => {
      const payload = await request<NotesResponse>(
        `/api/v1/tickets/${ticketId}/notes`
      );

      setNotes(payload.notes);
    },
    [request]
  );

  const loadMessages = useCallback(
    async (
      ticketId: string,
      options: {
        around?: string;
      } = {}
    ) => {
      const params =
        new URLSearchParams({
          limit: "80"
        });

      if (options.around) {
        params.set(
          "around",
          options.around
        );
      }

      const payload =
        await request<MessagesResponse>(
          `/api/v1/tickets/${ticketId}/messages?${params.toString()}`
        );

      shouldScrollToBottomRef.current =
        !options.around;

      setMessages(
        payload.messages
      );

      setMessagePagination(
        payload.pagination
      );

      await request(
        `/api/v1/tickets/${ticketId}/read`,
        {
          method: "POST"
        }
      );

      if (options.around) {
        const anchorId =
          options.around;

        setFocusedMessageId(
          anchorId
        );

        window.requestAnimationFrame(
          () => {
            window.requestAnimationFrame(
              () => {
                document
                  .querySelector(
                    `[data-message-id="${anchorId}"]`
                  )
                  ?.scrollIntoView({
                    behavior:
                      "smooth",
                    block:
                      "center"
                  });
              }
            );
          }
        );

        window.setTimeout(
          () => {
            setFocusedMessageId(
              current =>
                current ===
                anchorId
                  ? null
                  : current
            );
          },
          3_000
        );
      }
    },
    [request]
  );

  const loadOlderMessages = useCallback(
    async () => {
      if (
        !selectedId ||
        !messagePagination.hasMoreBefore ||
        !messagePagination.olderCursor ||
        loadingOlderMessages
      ) {
        return;
      }

      const scroller =
        conversationScrollRef.current;

      const previousHeight =
        scroller?.scrollHeight ??
        0;

      const previousTop =
        scroller?.scrollTop ??
        0;

      setLoadingOlderMessages(
        true
      );

      try {
        const params =
          new URLSearchParams({
            limit: "80",
            before:
              messagePagination.olderCursor
          });

        const payload =
          await request<MessagesResponse>(
            `/api/v1/tickets/${selectedId}/messages?${params.toString()}`
          );

        shouldScrollToBottomRef.current =
          false;

        setMessages(
          current =>
            mergeMessagePages(
              payload.messages,
              current
            )
        );

        setMessagePagination(
          current => ({
            ...current,
            hasMoreBefore:
              payload
                .pagination
                .hasMoreBefore,
            olderCursor:
              payload
                .pagination
                .olderCursor
          })
        );

        window.requestAnimationFrame(
          () => {
            const currentScroller =
              conversationScrollRef.current;

            if (
              !currentScroller
            ) {
              return;
            }

            currentScroller.scrollTop =
              currentScroller.scrollHeight -
              previousHeight +
              previousTop;
          }
        );
      } finally {
        setLoadingOlderMessages(
          false
        );
      }
    },
    [
      loadingOlderMessages,
      messagePagination.hasMoreBefore,
      messagePagination.olderCursor,
      request,
      selectedId
    ]
  );

  const loadNewerMessages = useCallback(
    async () => {
      if (
        !selectedId ||
        !messagePagination.hasMoreAfter ||
        !messagePagination.newerCursor ||
        loadingNewerMessages
      ) {
        return;
      }

      setLoadingNewerMessages(
        true
      );

      try {
        const params =
          new URLSearchParams({
            limit: "80",
            after:
              messagePagination.newerCursor
          });

        const payload =
          await request<MessagesResponse>(
            `/api/v1/tickets/${selectedId}/messages?${params.toString()}`
          );

        shouldScrollToBottomRef.current =
          false;

        setMessages(
          current =>
            mergeMessagePages(
              current,
              payload.messages
            )
        );

        setMessagePagination(
          current => ({
            ...current,
            hasMoreAfter:
              payload
                .pagination
                .hasMoreAfter,
            newerCursor:
              payload
                .pagination
                .newerCursor
          })
        );
      } finally {
        setLoadingNewerMessages(
          false
        );
      }
    },
    [
      loadingNewerMessages,
      messagePagination.hasMoreAfter,
      messagePagination.newerCursor,
      request,
      selectedId
    ]
  );

  const refreshMessageReactions = useCallback(
    async (
      ticketId: string,
      messageId: string
    ) => {
      const payload =
        await request<{
          reactions:
            MessageReaction[];
        }>(
          `/api/v1/tickets/${ticketId}/messages/${messageId}/reactions`
        );

      setMessages(
        current =>
          current.map(
            message =>
              message.id ===
              messageId
                ? {
                    ...message,
                    reactions:
                      payload.reactions
                  }
                : message
          )
      );
    },
    [request]
  );

  const refreshLatestMessages = useCallback(
    async (
      ticketId: string,
      scrollToBottom =
        false
    ) => {
      if (
        messagePagination.hasMoreAfter
      ) {
        return;
      }

      const payload =
        await request<MessagesResponse>(
          `/api/v1/tickets/${ticketId}/messages?limit=80`
        );

      shouldScrollToBottomRef.current =
        scrollToBottom;

      setMessages(
        current =>
          mergeMessagePages(
            current,
            payload.messages
          )
      );
    },
    [
      messagePagination.hasMoreAfter,
      request
    ]
  );

  useEffect(() => {
    const timeout =
      window.setTimeout(
        () => {
          setDebouncedTicketSearch(
            inboxFilters.search
              .trim()
          );
        },
        280
      );

    return () =>
      window.clearTimeout(
        timeout
      );
  }, [
    inboxFilters.search
  ]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void Promise.all([
        loadTickets(),
        loadReferenceData(),
        loadQuickReplies(),
        loadTags()
      ]).catch(() => {
        setError("Não foi possível carregar os atendimentos.");
      });
    }
  }, [
    loadQuickReplies,
    loadReferenceData,
    loadTags,
    loadTags,
    loadTickets,
    loading,
    router,
    session
  ]);

  useEffect(() => {
    if (!selectedId) {
      setMessages([]);
      setReplyingTo(null);
      setMessagePagination({
        hasMoreBefore:
          false,
        olderCursor:
          null,
        hasMoreAfter:
          false,
        newerCursor:
          null
      });
      setNotes([]);
      setNotesOpen(false);
      return;
    }

    setReplyingTo(null);

    if (
      skipNextSelectedLoadRef.current
    ) {
      skipNextSelectedLoadRef.current =
        false;
      return;
    }

    void Promise.all([
      loadMessages(
        selectedId
      ),
      loadNotes(
        selectedId
      )
    ]).catch(() => {
      setError(
        "Não foi possível carregar o atendimento."
      );
    });
  }, [
    loadMessages,
    loadNotes,
    selectedId
  ]);

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

        if (
          selectedId &&
          (
            !event.ticketId ||
            event.ticketId ===
              selectedId
          )
        ) {
          void refreshLatestMessages(
            selectedId,
            event.type ===
              "message.created"
          );
        }
      }

      if (
        event.type ===
          "message.reaction.updated" &&
        selectedId &&
        event.ticketId ===
          selectedId &&
        event.messageId
      ) {
        void refreshMessageReactions(
          selectedId,
          event.messageId
        ).catch(() => {
          // The target can be outside the currently loaded P1.21 window.
        });
      }

      if (
        event.type === "note.created" &&
        selectedId &&
        (!event.ticketId ||
          event.ticketId === selectedId)
      ) {
        void loadNotes(selectedId);
      }

      if (
        event.type === "quick-reply.updated"
      ) {
        void loadQuickReplies();

        if (canManageQuickReplies) {
          void loadManagedQuickReplies();
        }
      }

      if (
        event.type === "tag.updated"
      ) {
        void loadTags();

        if (canManageTags) {
          void loadManagedTags();
        }

        void loadTickets();
      }

      if (event.type === "queue.updated") {
        void loadReferenceData();
      }
    });
  }, [
    canManageQuickReplies,
    canManageTags,
    loadManagedQuickReplies,
    loadManagedTags,
    loadMessages,
    loadNotes,
    loadQuickReplies,
    loadReferenceData,
    loadTickets,
    refreshLatestMessages,
    refreshMessageReactions,
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
    if (
      !shouldScrollToBottomRef.current
    ) {
      shouldScrollToBottomRef.current =
        true;
      return;
    }

    bottomRef.current
      ?.scrollIntoView({
        behavior:
          "smooth",
        block:
          "end"
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
  // SSE remains primary. Polling only refreshes the latest page while media
  // is processing and never discards older pages already loaded by P1.21.
  useEffect(() => {
    if (
      !session ||
      !selectedId ||
      !hasPendingMedia ||
      messagePagination.hasMoreAfter
    ) {
      return;
    }

    const refreshPendingMedia =
      async () => {
        try {
          await refreshLatestMessages(
            selectedId,
            false
          );
        } catch {
          // Non-fatal fallback. Realtime or the next tick can recover.
        }
      };

    const interval =
      window.setInterval(
        () => {
          void refreshPendingMedia();
        },
        1_200
      );

    void refreshPendingMedia();

    return () => {
      window.clearInterval(
        interval
      );
    };
  }, [
    hasPendingMedia,
    messagePagination.hasMoreAfter,
    refreshLatestMessages,
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

  async function toggleTicketTag(
    tagId: string
  ) {
    if (
      !selectedId ||
      !selectedTicket ||
      updatingTicketTags
    ) {
      return;
    }

    const currentIds =
      selectedTicket.tags.map(
        link => link.tag.id
      );

    const nextIds =
      currentIds.includes(tagId)
        ? currentIds.filter(
            id => id !== tagId
          )
        : [...currentIds, tagId];

    setUpdatingTicketTags(true);
    setError("");

    try {
      await request(
        `/api/v1/tickets/${selectedId}/tags`,
        {
          method: "PUT",
          body: JSON.stringify({
            tagIds: nextIds
          })
        }
      );

      await loadTickets();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar as etiquetas."
      );
    } finally {
      setUpdatingTicketTags(false);
    }
  }

  function resetTagForm() {
    setEditingTagId(null);
    setTagName("");
    setTagColorKey("GREEN");
  }

  function editTag(
    tag: TagInfo
  ) {
    setEditingTagId(tag.id);
    setTagName(tag.name);
    setTagColorKey(tag.colorKey);
  }

  async function saveTag(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !canManageTags ||
      !tagName.trim()
    ) {
      return;
    }

    setSavingTag(true);
    setError("");

    try {
      const payload = {
        name: tagName.trim(),
        colorKey: tagColorKey
      };

      if (editingTagId) {
        await request(
          `/api/v1/tags/${editingTagId}`,
          {
            method: "PATCH",
            body:
              JSON.stringify(
                payload
              )
          }
        );
      } else {
        await request(
          "/api/v1/tags",
          {
            method: "POST",
            body:
              JSON.stringify(
                payload
              )
          }
        );
      }

      resetTagForm();

      await Promise.all([
        loadTags(),
        loadManagedTags()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar a etiqueta."
      );
    } finally {
      setSavingTag(false);
    }
  }

  async function toggleTagActive(
    tag: TagInfo
  ) {
    if (!canManageTags) {
      return;
    }

    setError("");

    try {
      await request(
        `/api/v1/tags/${tag.id}`,
        {
          method: "PATCH",
          body: JSON.stringify({
            isActive:
              !tag.isActive
          })
        }
      );

      await Promise.all([
        loadTags(),
        loadManagedTags(),
        loadTickets()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível alterar a etiqueta."
      );
    }
  }

  function selectQuickReply(
    reply: QuickReply
  ) {
    if (
      !selectedTicket ||
      !session
    ) {
      return;
    }

    const expanded =
      expandQuickReply(
        reply.body,
        {
          contactName:
            selectedTicket.contact.name,
          agentName:
            session.user.name,
          companyName:
            session.company.name
        }
      );

    setText(expanded);
    setQuickRepliesOpen(false);
    setQuickReplySearch("");

    window.setTimeout(() => {
      composerTextRef.current?.focus();
      composerTextRef.current?.setSelectionRange(
        expanded.length,
        expanded.length
      );
    }, 0);
  }

  function resetQuickReplyForm() {
    setEditingQuickReplyId(null);
    setQuickReplyShortcut("");
    setQuickReplyTitle("");
    setQuickReplyBody("");
  }

  function editQuickReply(
    reply: QuickReply
  ) {
    setEditingQuickReplyId(
      reply.id
    );
    setQuickReplyShortcut(
      reply.shortcut
    );
    setQuickReplyTitle(
      reply.title
    );
    setQuickReplyBody(
      reply.body
    );
  }

  async function saveQuickReply(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !canManageQuickReplies ||
      !quickReplyShortcut.trim() ||
      !quickReplyTitle.trim() ||
      !quickReplyBody.trim()
    ) {
      return;
    }

    setSavingQuickReply(true);
    setError("");

    try {
      const payload = {
        shortcut:
          quickReplyShortcut.trim(),
        title:
          quickReplyTitle.trim(),
        body:
          quickReplyBody.trim()
      };

      if (editingQuickReplyId) {
        await request(
          `/api/v1/quick-replies/${editingQuickReplyId}`,
          {
            method: "PATCH",
            body:
              JSON.stringify(
                payload
              )
          }
        );
      } else {
        await request(
          "/api/v1/quick-replies",
          {
            method: "POST",
            body:
              JSON.stringify(
                payload
              )
          }
        );
      }

      resetQuickReplyForm();

      await Promise.all([
        loadQuickReplies(),
        loadManagedQuickReplies()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar a resposta rápida."
      );
    } finally {
      setSavingQuickReply(false);
    }
  }

  async function toggleQuickReply(
    reply: QuickReply
  ) {
    if (!canManageQuickReplies) {
      return;
    }

    setError("");

    try {
      await request(
        `/api/v1/quick-replies/${reply.id}`,
        {
          method: "PATCH",
          body: JSON.stringify({
            isActive:
              !reply.isActive
          })
        }
      );

      await Promise.all([
        loadQuickReplies(),
        loadManagedQuickReplies()
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível alterar a resposta rápida."
      );
    }
  }

  async function handleCreateNote(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!selectedId || !noteText.trim()) {
      return;
    }

    setSavingNote(true);
    setError("");

    try {
      await request(
        `/api/v1/tickets/${selectedId}/notes`,
        {
          method: "POST",
          body: JSON.stringify({
            body: noteText.trim()
          })
        }
      );

      setNoteText("");
      await loadNotes(selectedId);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar a nota interna."
      );
    } finally {
      setSavingNote(false);
    }
  }

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

  async function reactToMessage(
    message: Message,
    emoji: string
  ) {
    if (
      !selectedId ||
      reactingMessageId
    ) {
      return;
    }

    const current =
      ownReaction(
        message
      );

    const nextEmoji =
      current?.emoji ===
      emoji
        ? ""
        : emoji;

    setReactingMessageId(
      message.id
    );

    setReactionPickerMessageId(
      null
    );

    try {
      const payload =
        await request<{
          messageId: string;
          reactions:
            MessageReaction[];
        }>(
          `/api/v1/tickets/${selectedId}/messages/${message.id}/reaction`,
          {
            method:
              "POST",
            body:
              JSON.stringify({
                emoji:
                  nextEmoji
              })
          }
        );

      setMessages(
        currentMessages =>
          currentMessages.map(
            item =>
              item.id ===
              message.id
                ? {
                    ...item,
                    reactions:
                      payload.reactions
                  }
                : item
          )
      );
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : "Não foi possível reagir à mensagem."
      );
    } finally {
      setReactingMessageId(
        null
      );
    }
  }

  function startReply(
    message: Message
  ) {
    if (
      recording
    ) {
      return;
    }

    setReplyingTo(
      message
    );

    window.setTimeout(
      () => {
        composerTextRef
          .current
          ?.focus();
      },
      0
    );
  }

  async function jumpToQuotedMessage(
    message: Message
  ) {
    const target =
      message
        .quotedMessage;

    if (
      !target ||
      !selectedId
    ) {
      return;
    }

    const loaded =
      messages.some(
        item =>
          item.id ===
          target.id
      );

    if (loaded) {
      setFocusedMessageId(
        target.id
      );

      document
        .querySelector(
          `[data-message-id="${target.id}"]`
        )
        ?.scrollIntoView({
          behavior:
            "smooth",
          block:
            "center"
        });

      window.setTimeout(
        () => {
          setFocusedMessageId(
            current =>
              current ===
              target.id
                ? null
                : current
          );
        },
        3_000
      );

      return;
    }

    try {
      await loadMessages(
        selectedId,
        {
          around:
            target.id
        }
      );
    } catch {
      setError(
        "Não foi possível abrir a mensagem citada."
      );
    }
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
              text:
                text.trim(),
              ...(replyingTo
                ? {
                    replyToMessageId:
                      replyingTo.id
                  }
                : {})
            })
          }
        );
      }

      setText("");
      setReplyingTo(null);

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

  function clearInboxFilters() {
    setInboxFilters({
      search: "",
      status:
        "ACTIVE",
      queueId: "",
      assigneeId: "",
      unreadOnly:
        false,
      tagId: "",
      conversationType:
        "ALL"
    });

    setDebouncedTicketSearch(
      ""
    );
  }

  async function handleClose() {
    if (!selectedId) return;
    setClosing(true);

    try {
      await request(`/api/v1/tickets/${selectedId}/close`, {
        method: "POST"
      });
      setMessages([]);
      setReplyingTo(null);
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
            onClick={() => router.push("/dashboard/automations")}
            type="button"
          >
            Automações
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

      {operationNotice && (
        <div className="inbox-notice">
          <span>{operationNotice}</span>
          <button
            aria-label="Fechar aviso"
            onClick={() =>
              setOperationNotice("")
            }
            type="button"
          >
            ×
          </button>
        </div>
      )}

      <section className="inbox">
        <aside className="ticket-list">
          <div className="ticket-list__heading ticket-list__heading--filters">
            <div className="ticket-list__title-row">
              <div>
                <strong>
                  Atendimentos
                </strong>
                <span>
                  {tickets.length}
                  {hasInboxFilter
                    ? " encontrados"
                    : " ativos"}
                </span>
              </div>

              {hasInboxFilter && (
                <button
                  className="inbox-filter-clear"
                  onClick={
                    clearInboxFilters
                  }
                  type="button"
                >
                  Limpar
                </button>
              )}
            </div>

            <label className="inbox-ticket-search">
              <span>
                Buscar
              </span>
              <input
                onChange={event =>
                  setInboxFilters(
                    current => ({
                      ...current,
                      search:
                        event.target.value
                    })
                  )
                }
                placeholder="Nome, número ou mensagem"
                type="search"
                value={
                  inboxFilters.search
                }
              />
            </label>

            <div className="inbox-status-filters">
              {(
                [
                  [
                    "ACTIVE",
                    "Todos"
                  ],
                  [
                    "PENDING",
                    "Aguardando"
                  ],
                  [
                    "OPEN",
                    "Atendendo"
                  ]
                ] as const
              ).map(
                ([
                  value,
                  label
                ]) => (
                  <button
                    className={
                      inboxFilters.status ===
                      value
                        ? "inbox-status-chip inbox-status-chip--active"
                        : "inbox-status-chip"
                    }
                    key={value}
                    onClick={() =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          status:
                            value
                        })
                      )
                    }
                    type="button"
                  >
                    {label}
                  </button>
                )
              )}

              <button
                className={
                  inboxFilters.unreadOnly
                    ? "inbox-status-chip inbox-status-chip--active"
                    : "inbox-status-chip"
                }
                onClick={() =>
                  setInboxFilters(
                    current => ({
                      ...current,
                      unreadOnly:
                        !current.unreadOnly
                    })
                  )
                }
                type="button"
              >
                Não lidas
              </button>
            </div>

            <details
              className={
                activeInboxFilterCount > 0
                  ? "inbox-advanced-filters inbox-advanced-filters--active"
                  : "inbox-advanced-filters"
              }
            >
              <summary>
                Filtros
                {activeInboxFilterCount > 0 && (
                  <span>
                    {activeInboxFilterCount}
                  </span>
                )}
              </summary>

              <div className="inbox-advanced-filters__body">
                <label>
                  <span>
                    Fila
                  </span>
                  <select
                    onChange={event =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          queueId:
                            event.target.value
                        })
                      )
                    }
                    value={
                      inboxFilters.queueId
                    }
                  >
                    <option value="">
                      Todas
                    </option>
                    <option value="NONE">
                      Sem fila
                    </option>
                    {queues.map(
                      queue => (
                        <option
                          key={
                            queue.id
                          }
                          value={
                            queue.id
                          }
                        >
                          {queue.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label>
                  <span>
                    Atendente
                  </span>
                  <select
                    onChange={event =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          assigneeId:
                            event.target.value
                        })
                      )
                    }
                    value={
                      inboxFilters.assigneeId
                    }
                  >
                    <option value="">
                      Todos
                    </option>
                    <option value="ME">
                      Meus atendimentos
                    </option>
                    <option value="NONE">
                      Sem atendente
                    </option>
                    {team.map(
                      membership => (
                        <option
                          key={
                            membership.id
                          }
                          value={
                            membership.id
                          }
                        >
                          {membership.user.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label>
                  <span>
                    Etiqueta
                  </span>
                  <select
                    onChange={event =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          tagId:
                            event.target.value
                        })
                      )
                    }
                    value={
                      inboxFilters.tagId
                    }
                  >
                    <option value="">
                      Todas
                    </option>
                    {tags.map(
                      tag => (
                        <option
                          key={
                            tag.id
                          }
                          value={
                            tag.id
                          }
                        >
                          {tag.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label>
                  <span>
                    Tipo
                  </span>
                  <select
                    onChange={event =>
                      setInboxFilters(
                        current => ({
                          ...current,
                          conversationType:
                            event.target.value as
                              TicketConversationFilter
                        })
                      )
                    }
                    value={
                      inboxFilters.conversationType
                    }
                  >
                    <option value="ALL">
                      Todos
                    </option>
                    <option value="DIRECT">
                      Contatos
                    </option>
                    <option value="GROUP">
                      Grupos
                    </option>
                  </select>
                </label>
              </div>
            </details>
          </div>

          <div className="ticket-list__items">
            {tickets.length === 0 ? (
              <div className="ticket-list__empty">
                <strong>
                  {hasInboxFilter
                    ? "Nenhuma conversa encontrada."
                    : "Nenhuma conversa ativa."}
                </strong>
                <p>
                  {hasInboxFilter
                    ? "Ajuste ou limpe os filtros para ampliar a busca."
                    : "Novas mensagens entram aqui em tempo real."}
                </p>
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
            <div className="conversation-home conversation-home--refined">
              <header className="conversation-home-top">
                <div className="conversation-home-top__copy">
                  <span className="eyebrow">
                    Central de atendimento
                  </span>

                  <h2>
                    O que precisa de atenção agora
                  </h2>

                  <p>
                    {pendingCount > 0
                      ? `${pendingCount} conversa${pendingCount === 1 ? "" : "s"} aguardando atendimento.`
                      : "Nenhuma conversa aguardando. A operação está em dia."}
                  </p>
                </div>

                <div className="conversation-home-summary">
                  <div>
                    <strong>
                      {pendingCount}
                    </strong>
                    <span>
                      aguardando
                    </span>
                  </div>

                  <div>
                    <strong>
                      {openCount}
                    </strong>
                    <span>
                      em atendimento
                    </span>
                  </div>

                  <div>
                    <strong>
                      {onlineMembershipIds.length}
                    </strong>
                    <span>
                      equipe online
                    </span>
                  </div>
                </div>
              </header>

              <div className="conversation-home-grid">
                <section className="conversation-focus-card">
                  <header className="conversation-section-header">
                    <div>
                      <span className="conversation-section-kicker">
                        Prioridade
                      </span>
                      <h3>
                        Aguardando atendimento
                      </h3>
                    </div>

                    <span className="conversation-section-count">
                      {pendingCount}
                    </span>
                  </header>

                  <div className="conversation-priority-list">
                    {tickets
                      .filter(
                        ticket =>
                          ticket.status ===
                          "PENDING"
                      )
                      .slice(
                        0,
                        8
                      )
                      .map(
                        ticket => (
                          <button
                            className="conversation-priority-item"
                            key={
                              ticket.id
                            }
                            onClick={() =>
                              setSelectedId(
                                ticket.id
                              )
                            }
                            type="button"
                          >
                            <div className="conversation-home__avatar">
                              {ticket.contact.name
                                .slice(
                                  0,
                                  1
                                )
                                .toUpperCase()}
                            </div>

                            <div className="conversation-priority-item__content">
                              <div>
                                <strong>
                                  {ticket.contact.name}
                                </strong>
                                <time>
                                  {timeLabel(
                                    ticket.lastMessageAt
                                  )}
                                </time>
                              </div>

                              <p>
                                {ticketPreview(
                                  ticket
                                )}
                              </p>

                              <span>
                                {ticket.queue?.name ??
                                  "Sem fila"}
                              </span>
                            </div>

                            <span className="conversation-priority-item__action">
                              Abrir
                            </span>
                          </button>
                        )
                      )}

                    {pendingCount === 0 && (
                      <div className="conversation-priority-empty">
                        <div>
                          ✓
                        </div>
                        <strong>
                          Nenhuma conversa esperando
                        </strong>
                        <p>
                          Quando um novo atendimento chegar, ele aparece aqui.
                        </p>
                      </div>
                    )}
                  </div>
                </section>

                <aside className="conversation-home-side">
                  <section className="conversation-overview-card">
                    <header className="conversation-section-header conversation-section-header--compact">
                      <div>
                        <span className="conversation-section-kicker">
                          Operação
                        </span>
                        <h3>
                          Distribuição por fila
                        </h3>
                      </div>
                    </header>

                    <div className="conversation-queue-overview">
                      <div>
                        <span>
                          Sem fila
                        </span>
                        <strong>
                          {tickets.filter(
                            ticket =>
                              !ticket.queueId
                          ).length}
                        </strong>
                      </div>

                      {queues
                        .filter(
                          queue =>
                            tickets.some(
                              ticket =>
                                ticket.queueId ===
                                queue.id
                            )
                        )
                        .slice(
                          0,
                          5
                        )
                        .map(
                          queue => (
                            <div
                              key={
                                queue.id
                              }
                            >
                              <span>
                                {queue.name}
                              </span>
                              <strong>
                                {tickets.filter(
                                  ticket =>
                                    ticket.queueId ===
                                    queue.id
                                ).length}
                              </strong>
                            </div>
                          )
                        )}
                    </div>
                  </section>

                  <section className="conversation-overview-card">
                    <header className="conversation-section-header conversation-section-header--compact">
                      <div>
                        <span className="conversation-section-kicker">
                          Disponibilidade
                        </span>
                        <h3>
                          Equipe online
                        </h3>
                      </div>

                      <span className="conversation-online-dot">
                        {onlineMembershipIds.length}
                      </span>
                    </header>

                    <div className="conversation-team-online">
                      {team
                        .filter(
                          member =>
                            onlineMembershipIds.includes(
                              member.id
                            )
                        )
                        .slice(
                          0,
                          6
                        )
                        .map(
                          member => (
                            <div
                              key={
                                member.id
                              }
                            >
                              <span className="conversation-team-avatar">
                                {member.user.name
                                  .slice(
                                    0,
                                    1
                                  )
                                  .toUpperCase()}
                              </span>

                              <div>
                                <strong>
                                  {member.user.name}
                                </strong>
                                <span>
                                  {member.role}
                                </span>
                              </div>
                            </div>
                          )
                        )}

                      {onlineMembershipIds.length === 0 && (
                        <div className="conversation-team-empty">
                          Nenhum atendente com presença ativa agora.
                        </div>
                      )}
                    </div>
                  </section>

                  <section className="conversation-overview-note">
                    <span>
                      {tickets.length}
                    </span>
                    <p>
                      conversas ativas na caixa neste momento
                    </p>
                  </section>
                </aside>
              </div>
            </div>
          ) : (
            <>
              <header className="chat-header chat-header--p07">
                <div className="chat-header__contact">
                  <button
                    aria-label="Voltar ao painel de conversas"
                    className="conversation-home-back"
                    onClick={() =>
                      setSelectedId(
                        null
                      )
                    }
                    title="Painel de conversas"
                    type="button"
                  >
                    ←
                  </button>
                  <div className="ticket-avatar">
                    {selectedTicket.contact.name.slice(0, 1).toUpperCase()}
                  </div>
                  <div>
                    <strong>{selectedTicket.contact.name}</strong>
                    <span>
                      {selectedTicket.contact.whatsappName &&
                      selectedTicket.contact.whatsappName !==
                        selectedTicket.contact.name
                        ? `${selectedTicket.contact.whatsappName} · `
                        : ""}
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

                <button
                  className="ticket-notes-toggle"
                  onClick={() =>
                    setNotesOpen(current => !current)
                  }
                  type="button"
                >
                  Notas
                  {notes.length > 0 && (
                    <span>{notes.length}</span>
                  )}
                </button>

                <button
                  className="ticket-tags-toggle"
                  onClick={() =>
                    setTagPickerOpen(
                      current => !current
                    )
                  }
                  type="button"
                >
                  Etiquetas
                  {selectedTicket.tags.length > 0 && (
                    <span>
                      {selectedTicket.tags.length}
                    </span>
                  )}
                </button>

                <button
                  className={
                    conversationSearchOpen
                      ? "conversation-search-toggle conversation-search-toggle--active"
                      : "conversation-search-toggle"
                  }
                  onClick={() => {
                    setConversationSearchOpen(
                      current => !current
                    );
                    setTagPickerOpen(false);
                    setTagManagerOpen(false);
                    setNotesOpen(false);
                    setQuickReplyManagerOpen(false);
                  }}
                  type="button"
                >
                  Buscar
                </button>

                <button
                  className={
                    closedTicketsOpen
                      ? "closed-tickets-toggle closed-tickets-toggle--active"
                      : "closed-tickets-toggle"
                  }
                  onClick={() => {
                    setClosedTicketsOpen(
                      current => !current
                    );
                    setConversationSearchOpen(false);
                    setTagPickerOpen(false);
                    setTagManagerOpen(false);
                    setNotesOpen(false);
                    setQuickReplyManagerOpen(false);
                    setOperationNotice("");
                  }}
                  type="button"
                >
                  Encerrados
                </button>

                <button
                  className={
                    slaMonitorOpen
                      ? "sla-monitor-toggle sla-monitor-toggle--active"
                      : "sla-monitor-toggle"
                  }
                  onClick={() => {
                    setSlaMonitorOpen(
                      current => !current
                    );
                    setClosedTicketsOpen(false);
                    setConversationSearchOpen(false);
                    setTagPickerOpen(false);
                    setTagManagerOpen(false);
                    setNotesOpen(false);
                    setQuickReplyManagerOpen(false);
                  }}
                  type="button"
                >
                  SLA
                </button>

                <button
                  className={
                    ticketHistoryOpen
                      ? "ticket-history-toggle ticket-history-toggle--active"
                      : "ticket-history-toggle"
                  }
                  onClick={() => {
                    setTicketHistoryOpen(
                      current => !current
                    );
                    setSlaMonitorOpen(false);
                    setClosedTicketsOpen(false);
                    setConversationSearchOpen(false);
                    setTagPickerOpen(false);
                    setTagManagerOpen(false);
                    setNotesOpen(false);
                    setQuickReplyManagerOpen(false);
                  }}
                  type="button"
                >
                  Histórico
                </button>

                <small>
                  Atual: {selectedTicket.queue?.name ?? "sem fila"} · {" "}
                  {selectedTicket.assignedMembership?.user.name ?? "sem atendente"}
                </small>

                {selectedTicket.tags.length > 0 && (
                  <div className="selected-ticket-tags">
                    {selectedTicket.tags.map(link => (
                      <span
                        className={`tag-chip tag-chip--${link.tag.colorKey.toLowerCase()}`}
                        key={link.tag.id}
                      >
                        {link.tag.name}
                      </span>
                    ))}
                  </div>
                )}
              </div>

              <div className="conversation-body">
                {ticketHistoryOpen &&
                  selectedTicket && (
                    <TicketHistoryDrawer
                      contactName={
                        selectedTicket.contact.name
                      }
                      onClose={() =>
                        setTicketHistoryOpen(false)
                      }
                      ticketId={
                        selectedTicket.id
                      }
                    />
                  )}
                {slaMonitorOpen && (
                  <SlaMonitorDrawer
                    onClose={() =>
                      setSlaMonitorOpen(false)
                    }
                    onOpenTicket={ticketId => {
                      setSelectedId(ticketId);
                      setSlaMonitorOpen(false);
                    }}
                  />
                )}
                {closedTicketsOpen && (
                  <ClosedTicketsDrawer
                    onClose={() =>
                      setClosedTicketsOpen(false)
                    }
                    onReopened={(
                      ticketId,
                      reusedExisting
                    ) => {
                      setClosedTicketsOpen(false);
                      setOperationNotice(
                        reusedExisting
                          ? "Já havia um atendimento ativo para este contato. Abrimos o atendimento existente."
                          : "Atendimento reaberto e atribuído a você."
                      );

                      void loadTickets()
                        .then(() => {
                          setSelectedId(ticketId);
                        });
                    }}
                  />
                )}
                {conversationSearchOpen && (
                  <ConversationSearch
                    onClose={() =>
                      setConversationSearchOpen(false)
                    }
                    onOpenTicket={(
                      ticketId,
                      messageId
                    ) => {
                      if (
                        ticketId !==
                        selectedId
                      ) {
                        skipNextSelectedLoadRef.current =
                          true;
                      }

                      setSelectedId(
                        ticketId
                      );

                      setConversationSearchOpen(
                        false
                      );

                      void Promise.all([
                        loadMessages(
                          ticketId,
                          {
                            around:
                              messageId
                          }
                        ),
                        loadNotes(
                          ticketId
                        )
                      ]).catch(() => {
                        setError(
                          "Não foi possível abrir a mensagem encontrada."
                        );
                      });
                    }}
                    selectedTicketId={selectedId}
                  />
                )}
                {tagPickerOpen && (
                  <div className="ticket-tag-picker">
                    <header>
                      <strong>
                        Etiquetas do atendimento
                      </strong>

                      <div>
                        {canManageTags && (
                          <button
                            onClick={() => {
                              setTagPickerOpen(false);
                              setTagManagerOpen(true);
                              setNotesOpen(false);
                              setQuickReplyManagerOpen(false);
                              void loadManagedTags();
                            }}
                            type="button"
                          >
                            Gerenciar
                          </button>
                        )}

                        <button
                          aria-label="Fechar etiquetas"
                          onClick={() =>
                            setTagPickerOpen(false)
                          }
                          type="button"
                        >
                          ×
                        </button>
                      </div>
                    </header>

                    <div className="ticket-tag-picker__list">
                      {tags.length === 0 ? (
                        <div className="ticket-tag-picker__empty">
                          Nenhuma etiqueta cadastrada.
                        </div>
                      ) : (
                        tags.map(tag => {
                          const checked =
                            selectedTicket.tags.some(
                              link =>
                                link.tag.id ===
                                tag.id
                            );

                          return (
                            <button
                              className={
                                checked
                                  ? "ticket-tag-option ticket-tag-option--active"
                                  : "ticket-tag-option"
                              }
                              disabled={updatingTicketTags}
                              key={tag.id}
                              onClick={() =>
                                void toggleTicketTag(
                                  tag.id
                                )
                              }
                              type="button"
                            >
                              <span
                                className={`tag-dot tag-dot--${tag.colorKey.toLowerCase()}`}
                              />
                              <strong>
                                {tag.name}
                              </strong>
                              <span>
                                {checked
                                  ? "✓"
                                  : ""}
                              </span>
                            </button>
                          );
                        })
                      )}
                    </div>
                  </div>
                )}

                {tagManagerOpen &&
                  canManageTags && (
                    <aside className="tag-manager">
                      <header className="tag-manager__header">
                        <div>
                          <span className="eyebrow">
                            Organização
                          </span>
                          <strong>
                            Etiquetas
                          </strong>
                          <small>
                            Compartilhadas pela empresa.
                          </small>
                        </div>

                        <button
                          aria-label="Fechar gerenciamento de etiquetas"
                          onClick={() => {
                            setTagManagerOpen(false);
                            resetTagForm();
                          }}
                          type="button"
                        >
                          ×
                        </button>
                      </header>

                      <div className="tag-manager__list">
                        {managedTags.length === 0 ? (
                          <div className="tag-manager__empty">
                            Nenhuma etiqueta cadastrada.
                          </div>
                        ) : (
                          managedTags.map(tag => (
                            <article
                              className={
                                tag.isActive
                                  ? "tag-admin-item"
                                  : "tag-admin-item tag-admin-item--inactive"
                              }
                              key={tag.id}
                            >
                              <div>
                                <span
                                  className={`tag-dot tag-dot--${tag.colorKey.toLowerCase()}`}
                                />
                                <strong>
                                  {tag.name}
                                </strong>
                              </div>

                              <span>
                                {tag.isActive
                                  ? "Ativa"
                                  : "Inativa"}
                              </span>

                              <div className="tag-admin-item__actions">
                                <button
                                  onClick={() =>
                                    editTag(tag)
                                  }
                                  type="button"
                                >
                                  Editar
                                </button>

                                <button
                                  onClick={() =>
                                    void toggleTagActive(
                                      tag
                                    )
                                  }
                                  type="button"
                                >
                                  {tag.isActive
                                    ? "Desativar"
                                    : "Ativar"}
                                </button>
                              </div>
                            </article>
                          ))
                        )}
                      </div>

                      <form
                        className="tag-form"
                        onSubmit={saveTag}
                      >
                        <div className="tag-form__heading">
                          <strong>
                            {editingTagId
                              ? "Editar etiqueta"
                              : "Nova etiqueta"}
                          </strong>

                          {editingTagId && (
                            <button
                              onClick={resetTagForm}
                              type="button"
                            >
                              Cancelar edição
                            </button>
                          )}
                        </div>

                        <label>
                          <span>Nome</span>
                          <input
                            maxLength={80}
                            onChange={event =>
                              setTagName(
                                event.target.value
                              )
                            }
                            placeholder="Ex.: Urgente"
                            required
                            value={tagName}
                          />
                        </label>

                        <label>
                          <span>Cor</span>
                          <select
                            onChange={event =>
                              setTagColorKey(
                                event.target.value as TagInfo["colorKey"]
                              )
                            }
                            value={tagColorKey}
                          >
                            <option value="GREEN">
                              Verde
                            </option>
                            <option value="BLUE">
                              Azul
                            </option>
                            <option value="ORANGE">
                              Laranja
                            </option>
                            <option value="RED">
                              Vermelho
                            </option>
                            <option value="PURPLE">
                              Roxo
                            </option>
                            <option value="GRAY">
                              Cinza
                            </option>
                          </select>
                        </label>

                        <button
                          className="primary-button"
                          disabled={
                            savingTag ||
                            !tagName.trim()
                          }
                          type="submit"
                        >
                          <span>
                            {savingTag
                              ? "Salvando…"
                              : editingTagId
                                ? "Salvar alterações"
                                : "Criar etiqueta"}
                          </span>
                          <span>→</span>
                        </button>
                      </form>
                    </aside>
                  )}
                {quickReplyManagerOpen &&
                  canManageQuickReplies && (
                    <aside className="quick-reply-manager">
                      <header className="quick-reply-manager__header">
                        <div>
                          <span className="eyebrow">
                            Atendimento
                          </span>
                          <strong>
                            Respostas rápidas
                          </strong>
                          <small>
                            Biblioteca compartilhada pela empresa.
                          </small>
                        </div>

                        <button
                          aria-label="Fechar respostas rápidas"
                          onClick={() => {
                            setQuickReplyManagerOpen(false);
                            resetQuickReplyForm();
                          }}
                          type="button"
                        >
                          ×
                        </button>
                      </header>

                      <div className="quick-reply-manager__list">
                        {managedQuickReplies.length === 0 ? (
                          <div className="quick-reply-manager__empty">
                            Nenhuma resposta rápida cadastrada.
                          </div>
                        ) : (
                          managedQuickReplies.map(reply => (
                            <article
                              className={
                                reply.isActive
                                  ? "quick-reply-admin-item"
                                  : "quick-reply-admin-item quick-reply-admin-item--inactive"
                              }
                              key={reply.id}
                            >
                              <div className="quick-reply-admin-item__heading">
                                <div>
                                  <code>
                                    /{reply.shortcut}
                                  </code>
                                  <strong>
                                    {reply.title}
                                  </strong>
                                </div>

                                <span>
                                  {reply.isActive
                                    ? "Ativa"
                                    : "Inativa"}
                                </span>
                              </div>

                              <p>{reply.body}</p>

                              <div className="quick-reply-admin-item__actions">
                                <button
                                  onClick={() =>
                                    editQuickReply(reply)
                                  }
                                  type="button"
                                >
                                  Editar
                                </button>

                                <button
                                  onClick={() =>
                                    void toggleQuickReply(
                                      reply
                                    )
                                  }
                                  type="button"
                                >
                                  {reply.isActive
                                    ? "Desativar"
                                    : "Ativar"}
                                </button>
                              </div>
                            </article>
                          ))
                        )}
                      </div>

                      <form
                        className="quick-reply-form"
                        onSubmit={saveQuickReply}
                      >
                        <div className="quick-reply-form__heading">
                          <strong>
                            {editingQuickReplyId
                              ? "Editar resposta"
                              : "Nova resposta"}
                          </strong>

                          {editingQuickReplyId && (
                            <button
                              onClick={resetQuickReplyForm}
                              type="button"
                            >
                              Cancelar edição
                            </button>
                          )}
                        </div>

                        <label>
                          <span>Atalho</span>
                          <div className="quick-reply-shortcut-field">
                            <span>/</span>
                            <input
                              maxLength={50}
                              onChange={event =>
                                setQuickReplyShortcut(
                                  event.target.value
                                )
                              }
                              placeholder="saudacao"
                              required
                              value={quickReplyShortcut}
                            />
                          </div>
                        </label>

                        <label>
                          <span>Título</span>
                          <input
                            maxLength={160}
                            onChange={event =>
                              setQuickReplyTitle(
                                event.target.value
                              )
                            }
                            placeholder="Saudação inicial"
                            required
                            value={quickReplyTitle}
                          />
                        </label>

                        <label>
                          <span>Mensagem</span>
                          <textarea
                            maxLength={10_000}
                            onChange={event =>
                              setQuickReplyBody(
                                event.target.value
                              )
                            }
                            placeholder="Olá, {{primeiro_nome}}! Como posso ajudar?"
                            required
                            rows={5}
                            value={quickReplyBody}
                          />
                        </label>

                        <small>
                          Variáveis: {"{{nome}}"}, {"{{primeiro_nome}}"}, {"{{atendente}}"}, {"{{empresa}}"}
                        </small>

                        <button
                          className="primary-button"
                          disabled={savingQuickReply}
                          type="submit"
                        >
                          <span>
                            {savingQuickReply
                              ? "Salvando…"
                              : editingQuickReplyId
                                ? "Salvar alterações"
                                : "Criar resposta"}
                          </span>
                          <span>→</span>
                        </button>
                      </form>
                    </aside>
                  )}

                {notesOpen && (
                  <aside className="ticket-notes-drawer">
                    <header className="ticket-notes-drawer__header">
                      <div>
                        <span className="eyebrow">
                          Equipe
                        </span>
                        <strong>Notas internas</strong>
                        <small>
                          Não são enviadas ao cliente.
                        </small>
                      </div>

                      <button
                        aria-label="Fechar notas internas"
                        onClick={() => setNotesOpen(false)}
                        type="button"
                      >
                        ×
                      </button>
                    </header>

                    <div className="ticket-notes-list">
                      {notes.length === 0 ? (
                        <div className="ticket-notes-empty">
                          Nenhuma nota interna neste atendimento.
                        </div>
                      ) : (
                        notes.map(note => (
                          <article
                            className="ticket-note"
                            key={note.id}
                          >
                            <div className="ticket-note__meta">
                              <strong>
                                {note.authorMembership.user.name}
                              </strong>
                              <span>
                                {dateTimeLabel(note.createdAt)}
                              </span>
                            </div>

                            <p>{note.body}</p>
                          </article>
                        ))
                      )}
                    </div>

                    <form
                      className="ticket-note-form"
                      onSubmit={handleCreateNote}
                    >
                      <textarea
                        maxLength={10_000}
                        onChange={event =>
                          setNoteText(event.target.value)
                        }
                        placeholder="Ex.: cliente pediu retorno amanhã após 14h…"
                        rows={3}
                        value={noteText}
                      />

                      <button
                        className="primary-button"
                        disabled={
                          savingNote ||
                          !noteText.trim()
                        }
                        type="submit"
                      >
                        <span>
                          {savingNote
                            ? "Salvando…"
                            : "Adicionar nota"}
                        </span>
                        <span>+</span>
                      </button>
                    </form>
                  </aside>
                )}

                <div
                  className="conversation-scroll"
                  ref={conversationScrollRef}
                >
                {messagePagination.hasMoreBefore && (
                  <div className="message-history-loader">
                    <button
                      disabled={loadingOlderMessages}
                      onClick={() =>
                        void loadOlderMessages()
                      }
                      type="button"
                    >
                      {loadingOlderMessages
                        ? "Carregando…"
                        : "Carregar mensagens anteriores"}
                    </button>
                  </div>
                )}
                {messages.map(message => (
                  <div
                    className={`${
                      message.direction === "OUTBOUND"
                        ? "message-row message-row--out"
                        : "message-row message-row--in"
                    }${
                      focusedMessageId === message.id
                        ? " message-row--focused"
                        : ""
                    }`}
                    data-message-id={message.id}
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

                      {message.quotedExternalId && (
                        <button
                          className="message-quoted-preview"
                          disabled={
                            !message.quotedMessage
                          }
                          onClick={() =>
                            void jumpToQuotedMessage(
                              message
                            )
                          }
                          title={
                            message.quotedMessage
                              ? "Abrir mensagem citada"
                              : "Mensagem citada não está disponível no histórico local"
                          }
                          type="button"
                        >
                          <span>
                            {message.quotedMessage?.direction ===
                            "OUTBOUND"
                              ? "Você"
                              : selectedTicket.contact.name}
                          </span>
                          <p>
                            {message.quotedMessage
                              ? quotedMessagePreview(
                                  message.quotedMessage
                                )
                              : "Mensagem citada"}
                          </p>
                        </button>
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

                      {message.reactions.length > 0 && (
                        <div className="message-reactions">
                          {groupedReactions(
                            message.reactions
                          ).map(
                            reaction => (
                              <button
                                className={
                                  reaction.fromMe
                                    ? "message-reaction-badge message-reaction-badge--mine"
                                    : "message-reaction-badge"
                                }
                                disabled={
                                  reactingMessageId ===
                                  message.id
                                }
                                key={
                                  reaction.emoji
                                }
                                onClick={() =>
                                  void reactToMessage(
                                    message,
                                    reaction.emoji
                                  )
                                }
                                title={
                                  reaction.fromMe
                                    ? "Sua reação — clique para remover"
                                    : "Reagir também"
                                }
                                type="button"
                              >
                                <span>
                                  {reaction.emoji}
                                </span>
                                {reaction.count > 1 && (
                                  <small>
                                    {reaction.count}
                                  </small>
                                )}
                              </button>
                            )
                          )}
                        </div>
                      )}

                      <div className="message-meta">
                        <div className="message-reaction-action">
                          <button
                            aria-label="Reagir à mensagem"
                            className="message-reaction-trigger"
                            disabled={
                              reactingMessageId ===
                              message.id
                            }
                            onClick={() =>
                              setReactionPickerMessageId(
                                current =>
                                  current ===
                                  message.id
                                    ? null
                                    : message.id
                              )
                            }
                            title="Reagir"
                            type="button"
                          >
                            ☺
                          </button>

                          {reactionPickerMessageId ===
                            message.id && (
                            <div className="message-reaction-picker">
                              {REACTION_OPTIONS.map(
                                emoji => (
                                  <button
                                    className={
                                      ownReaction(
                                        message
                                      )?.emoji ===
                                      emoji
                                        ? "message-reaction-option message-reaction-option--active"
                                        : "message-reaction-option"
                                    }
                                    key={emoji}
                                    onClick={() =>
                                      void reactToMessage(
                                        message,
                                        emoji
                                      )
                                    }
                                    title={
                                      ownReaction(
                                        message
                                      )?.emoji ===
                                      emoji
                                        ? "Remover reação"
                                        : `Reagir com ${emoji}`
                                    }
                                    type="button"
                                  >
                                    {emoji}
                                  </button>
                                )
                              )}
                            </div>
                          )}
                        </div>

                        <button
                          aria-label="Responder esta mensagem"
                          className="message-reply-action"
                          onClick={() =>
                            startReply(
                              message
                            )
                          }
                          title="Responder"
                          type="button"
                        >
                          ↩
                        </button>

                        {message.direction === "OUTBOUND" &&
                          deliveryStatusPresentation(
                            message.deliveryStatus
                          ) && (
                            <span
                              className={
                                message.deliveryStatus === "READ" ||
                                message.deliveryStatus === "PLAYED"
                                  ? "message-delivery message-delivery--read"
                                  : message.deliveryStatus === "FAILED"
                                    ? "message-delivery message-delivery--failed"
                                    : "message-delivery"
                              }
                              title={
                                message.deliveryStatus === "FAILED" &&
                                message.deliveryError
                                  ? `Falhou: ${message.deliveryError}`
                                  : deliveryStatusPresentation(
                                      message.deliveryStatus
                                    )?.label
                              }
                            >
                              {
                                deliveryStatusPresentation(
                                  message.deliveryStatus
                                )?.glyph
                              }
                            </span>
                          )}

                        <time>
                          {dateTimeLabel(message.timestamp)}
                        </time>
                      </div>
                    </article>
                  </div>
                ))}

                {messagePagination.hasMoreAfter && (
                  <div className="message-history-loader message-history-loader--newer">
                    <button
                      disabled={loadingNewerMessages}
                      onClick={() =>
                        void loadNewerMessages()
                      }
                      type="button"
                    >
                      {loadingNewerMessages
                        ? "Carregando…"
                        : "Carregar mensagens mais recentes"}
                    </button>
                  </div>
                )}

                <div ref={bottomRef} />
                              </div>

                {(quickRepliesOpen ||
                  (text.startsWith("/") &&
                    !attachment &&
                    !recording)) && (
                  <div className="quick-reply-palette">
                    <div className="quick-reply-palette__header">
                      <input
                        autoFocus={quickRepliesOpen}
                        onChange={event =>
                          setQuickReplySearch(
                            event.target.value
                          )
                        }
                        placeholder="Buscar resposta rápida…"
                        value={
                          text.startsWith("/")
                            ? text.slice(1)
                            : quickReplySearch
                        }
                      />

                      {canManageQuickReplies && (
                        <button
                          onClick={() => {
                            setQuickRepliesOpen(false);
                            setQuickReplyManagerOpen(true);
                            setNotesOpen(false);
                            void loadManagedQuickReplies();
                          }}
                          type="button"
                        >
                          Gerenciar
                        </button>
                      )}
                    </div>

                    <div className="quick-reply-palette__items">
                      {filteredQuickReplies.length === 0 ? (
                        <div className="quick-reply-palette__empty">
                          Nenhuma resposta encontrada.
                        </div>
                      ) : (
                        filteredQuickReplies.map(reply => (
                          <button
                            className="quick-reply-option"
                            key={reply.id}
                            onClick={() =>
                              selectQuickReply(reply)
                            }
                            type="button"
                          >
                            <div>
                              <code>
                                /{reply.shortcut}
                              </code>
                              <strong>
                                {reply.title}
                              </strong>
                            </div>

                            <p>{reply.body}</p>
                          </button>
                        ))
                      )}
                    </div>
                  </div>
                )}

                <form
                  className="conversation-composer conversation-composer--attachments conversation-composer--voice conversation-composer--quick-replies"
                  onSubmit={handleSend}
                >
                  {replyingTo && (
                    <div className="composer-reply-preview">
                      <div>
                        <span>
                          Respondendo a{" "}
                          {replyingTo.direction ===
                          "OUTBOUND"
                            ? "você"
                            : selectedTicket.contact.name}
                        </span>
                        <strong>
                          {replyTargetPreview(
                            replyingTo
                          )}
                        </strong>
                      </div>

                      <button
                        aria-label="Cancelar resposta"
                        disabled={sending}
                        onClick={() =>
                          setReplyingTo(
                            null
                          )
                        }
                        title="Cancelar resposta"
                        type="button"
                      >
                        ×
                      </button>
                    </div>
                  )}

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
                    aria-label="Respostas rápidas"
                    className={
                      quickRepliesOpen
                        ? "composer__quick-reply composer__quick-reply--active"
                        : "composer__quick-reply"
                    }
                    disabled={
                      sending ||
                      recording ||
                      !!attachment
                    }
                    onClick={() => {
                      setQuickRepliesOpen(
                        current => !current
                      );
                      setQuickReplySearch("");
                    }}
                    title="Respostas rápidas (ou digite /)"
                    type="button"
                  >
                    ↯
                  </button>

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
                  ref={composerTextRef}
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
