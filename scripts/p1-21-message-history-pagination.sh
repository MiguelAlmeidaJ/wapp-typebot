#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.21] Building cursor-paginated message history..."

for required in \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/components/conversations/conversation-search.tsx" \
  "apps/web/components/conversations/closed-tickets-drawer.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/tickets \
  docs

# ---------------------------------------------------------------------------
# API: dedicated cursor-paginated message history service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tickets/ticket-message-history.service.ts <<'EOF'
import type {
  Prisma
} from "../../generated/prisma/client.js";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { getTicket } from "./ticket.service.js";

interface MessageCursor {
  id: string;
  timestamp: Date;
}

interface MessagePageInput {
  companyId: string;
  ticketId: string;
  limit: number;
  before?: string;
  after?: string;
  around?: string;
}

function beforeCursorWhere(
  cursor: MessageCursor
): Prisma.MessageWhereInput {
  return {
    OR: [
      {
        timestamp: {
          lt:
            cursor.timestamp
        }
      },
      {
        timestamp:
          cursor.timestamp,
        id: {
          lt:
            cursor.id
        }
      }
    ]
  };
}

function afterCursorWhere(
  cursor: MessageCursor
): Prisma.MessageWhereInput {
  return {
    OR: [
      {
        timestamp: {
          gt:
            cursor.timestamp
        }
      },
      {
        timestamp:
          cursor.timestamp,
        id: {
          gt:
            cursor.id
        }
      }
    ]
  };
}

async function messageCursor(
  input: {
    companyId: string;
    ticketId: string;
    messageId: string;
  }
): Promise<MessageCursor> {
  const message =
    await prisma.message.findFirst({
      where: {
        id:
          input.messageId,
        companyId:
          input.companyId,
        ticketId:
          input.ticketId
      },
      select: {
        id: true,
        timestamp: true
      }
    });

  if (!message) {
    throw new AppError(
      "Mensagem não encontrada neste atendimento.",
      404,
      "TICKET_MESSAGE_NOT_FOUND"
    );
  }

  return message;
}

const ascOrder:
  Prisma.MessageOrderByWithRelationInput[] =
  [
    {
      timestamp:
        "asc"
    },
    {
      id:
        "asc"
    }
  ];

const descOrder:
  Prisma.MessageOrderByWithRelationInput[] =
  [
    {
      timestamp:
        "desc"
    },
    {
      id:
        "desc"
    }
  ];

function pageResult(
  messages:
    Awaited<
      ReturnType<
        typeof prisma.message.findMany
      >
    >,
  input: {
    hasMoreBefore: boolean;
    hasMoreAfter: boolean;
  }
) {
  return {
    messages,
    pagination: {
      hasMoreBefore:
        input.hasMoreBefore,
      olderCursor:
        input.hasMoreBefore
          ? messages[0]?.id ??
            null
          : null,
      hasMoreAfter:
        input.hasMoreAfter,
      newerCursor:
        input.hasMoreAfter
          ? messages[
              messages.length -
                1
            ]?.id ??
            null
          : null
    }
  };
}

export async function listTicketMessagePage(
  input: MessagePageInput
) {
  await getTicket(
    input.companyId,
    input.ticketId
  );

  const baseWhere:
    Prisma.MessageWhereInput =
    {
      companyId:
        input.companyId,
      ticketId:
        input.ticketId
    };

  if (input.around) {
    const anchor =
      await messageCursor({
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        messageId:
          input.around
      });

    const olderLimit =
      Math.ceil(
        input.limit /
          2
      );

    const newerLimit =
      input.limit -
      olderLimit;

    const olderRaw =
      await prisma.message.findMany({
        where: {
          ...baseWhere,
          OR: [
            {
              timestamp: {
                lt:
                  anchor.timestamp
              }
            },
            {
              timestamp:
                anchor.timestamp,
              id: {
                lte:
                  anchor.id
              }
            }
          ]
        },
        orderBy:
          descOrder,
        take:
          olderLimit +
          1
      });

    const newerRaw =
      newerLimit > 0
        ? await prisma.message.findMany({
            where: {
              ...baseWhere,
              ...afterCursorWhere(
                anchor
              )
            },
            orderBy:
              ascOrder,
            take:
              newerLimit +
              1
          })
        : [];

    const hasMoreBefore =
      olderRaw.length >
      olderLimit;

    const hasMoreAfter =
      newerRaw.length >
      newerLimit;

    const older =
      olderRaw
        .slice(
          0,
          olderLimit
        )
        .reverse();

    const newer =
      newerRaw.slice(
        0,
        newerLimit
      );

    return pageResult(
      [
        ...older,
        ...newer
      ],
      {
        hasMoreBefore,
        hasMoreAfter
      }
    );
  }

  if (input.before) {
    const cursor =
      await messageCursor({
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        messageId:
          input.before
      });

    const raw =
      await prisma.message.findMany({
        where: {
          ...baseWhere,
          ...beforeCursorWhere(
            cursor
          )
        },
        orderBy:
          descOrder,
        take:
          input.limit +
          1
      });

    const hasMoreBefore =
      raw.length >
      input.limit;

    const messages =
      raw
        .slice(
          0,
          input.limit
        )
        .reverse();

    return pageResult(
      messages,
      {
        hasMoreBefore,
        hasMoreAfter:
          false
      }
    );
  }

  if (input.after) {
    const cursor =
      await messageCursor({
        companyId:
          input.companyId,
        ticketId:
          input.ticketId,
        messageId:
          input.after
      });

    const raw =
      await prisma.message.findMany({
        where: {
          ...baseWhere,
          ...afterCursorWhere(
            cursor
          )
        },
        orderBy:
          ascOrder,
        take:
          input.limit +
          1
      });

    const hasMoreAfter =
      raw.length >
      input.limit;

    const messages =
      raw.slice(
        0,
        input.limit
      );

    return pageResult(
      messages,
      {
        hasMoreBefore:
          false,
        hasMoreAfter
      }
    );
  }

  /*
   * Initial conversation load intentionally fetches the newest page.
   * The previous implementation sorted ASC + take(200), which returned
   * the oldest 200 messages of a long ticket.
   */
  const raw =
    await prisma.message.findMany({
      where:
        baseWhere,
      orderBy:
        descOrder,
      take:
        input.limit +
        1
    });

  const hasMoreBefore =
    raw.length >
    input.limit;

  const messages =
    raw
      .slice(
        0,
        input.limit
      )
      .reverse();

  return pageResult(
    messages,
    {
      hasMoreBefore,
      hasMoreAfter:
        false
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# API route
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.routes.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  );

content =
  content.replace(
    "  listTicketMessages,\n",
    ""
  );

const importLine =
  'import { listTicketMessagePage } from "./ticket-message-history.service.js";';

if (
  !content.includes(
    importLine
  )
) {
  const anchor =
    'import { listTicketEvents } from "./ticket-event.service.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "ticket route import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    "const messageListSchema"
  )
) {
  const anchor = `const ticketIdSchema = z.object({
  id: z.string().uuid()
});`;

  if (!content.includes(anchor)) {
    throw new Error(
      "ticketIdSchema anchor not found."
    );
  }

  const schema = `${anchor}

const messageListSchema = z
  .object({
    limit: z.coerce
      .number()
      .int()
      .min(20)
      .max(100)
      .default(80),
    before: z
      .string()
      .uuid()
      .optional(),
    after: z
      .string()
      .uuid()
      .optional(),
    around: z
      .string()
      .uuid()
      .optional()
  })
  .refine(
    value =>
      [
        value.before,
        value.after,
        value.around
      ].filter(Boolean)
        .length <= 1,
    {
      message:
        "Use apenas um cursor de mensagens por requisição."
    }
  );`;

  content =
    content.replace(
      anchor,
      schema
    );
}

const oldRoute = `  app.get(
    "/api/v1/tickets/:id/messages",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        messages: await listTicketMessages(
          auth.companyId,
          params.id
        )
      };
    }
  );`;

const newRoute = `  app.get(
    "/api/v1/tickets/:id/messages",
    async request => {
      const auth =
        await requireAuth(
          request
        );

      const params =
        ticketIdSchema.parse(
          request.params
        );

      const query =
        messageListSchema.parse(
          request.query
        );

      return listTicketMessagePage({
        companyId:
          auth.companyId,
        ticketId:
          params.id,
        limit:
          query.limit,
        before:
          query.before,
        after:
          query.after,
        around:
          query.around
      });
    }
  );`;

if (
  content.includes(
    oldRoute
  )
) {
  content =
    content.replace(
      oldRoute,
      newRoute
    );
} else if (
  !content.includes(
    "return listTicketMessagePage({"
  )
) {
  throw new Error(
    "ticket messages route anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Ticket message route now exposes cursor pagination."
);
NODE

# ---------------------------------------------------------------------------
# Conversation search: send message id to opener
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/components/conversations/conversation-search.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  );

const oldSignature = `  onOpenTicket: (
    ticketId: string
  ) => void;`;

const newSignature = `  onOpenTicket: (
    ticketId: string,
    messageId: string
  ) => void;`;

if (
  content.includes(
    oldSignature
  )
) {
  content =
    content.replace(
      oldSignature,
      newSignature
    );
} else if (
  !content.includes(
    "messageId: string"
  )
) {
  throw new Error(
    "ConversationSearch callback signature not found."
  );
}

const oldCall = `                          onOpenTicket(
                            message.ticketId
                          )`;

const newCall = `                          onOpenTicket(
                            message.ticketId,
                            message.id
                          )`;

if (
  content.includes(
    oldCall
  )
) {
  content =
    content.replace(
      oldCall,
      newCall
    );
} else if (
  !content.includes(
    "message.ticketId,\n                            message.id"
  )
) {
  throw new Error(
    "ConversationSearch open call not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Search results now deep-link to the exact message."
);
NODE

# ---------------------------------------------------------------------------
# Main conversations page
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  );

const oldMessagesResponse = `interface MessagesResponse {
  messages: Message[];
}`;

const newMessagesResponse = `interface MessagePagination {
  hasMoreBefore: boolean;
  olderCursor: string | null;
  hasMoreAfter: boolean;
  newerCursor: string | null;
}

interface MessagesResponse {
  messages: Message[];
  pagination: MessagePagination;
}`;

if (
  content.includes(
    oldMessagesResponse
  )
) {
  content =
    content.replace(
      oldMessagesResponse,
      newMessagesResponse
    );
} else if (
  !content.includes(
    "interface MessagePagination"
  )
) {
  throw new Error(
    "MessagesResponse interface anchor not found."
  );
}

if (
  !content.includes(
    "function mergeMessagePages"
  )
) {
  const anchor = `function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}`;

  if (!content.includes(anchor)) {
    throw new Error(
      "dateTimeLabel anchor not found."
    );
  }

  const helper = `${anchor}

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
}`;

  content =
    content.replace(
      anchor,
      helper
    );
}

const stateAnchor =
  `  const [messages, setMessages] = useState<Message[]>([]);
  const [notes, setNotes] = useState<TicketNote[]>([]);`;

if (
  !content.includes(
    "const [messagePagination"
  )
) {
  if (!content.includes(stateAnchor)) {
    throw new Error(
      "messages state anchor not found."
    );
  }

  content =
    content.replace(
      stateAnchor,
      `  const [messages, setMessages] = useState<Message[]>([]);
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
  const [notes, setNotes] = useState<TicketNote[]>([]);`
    );
}

const refAnchor =
  `  const bottomRef = useRef<HTMLDivElement | null>(null);
  const attachmentInputRef =`;

if (
  !content.includes(
    "conversationScrollRef"
  )
) {
  if (!content.includes(refAnchor)) {
    throw new Error(
      "bottomRef anchor not found."
    );
  }

  content =
    content.replace(
      refAnchor,
      `  const bottomRef = useRef<HTMLDivElement | null>(null);
  const conversationScrollRef =
    useRef<HTMLDivElement | null>(null);
  const shouldScrollToBottomRef =
    useRef(true);
  const skipNextSelectedLoadRef =
    useRef(false);
  const attachmentInputRef =`
    );
}

const oldLoad = `  const loadMessages = useCallback(
    async (ticketId: string) => {
      const payload = await request<MessagesResponse>(
        \`/api/v1/tickets/\${ticketId}/messages\`
      );
      setMessages(payload.messages);
      await request(\`/api/v1/tickets/\${ticketId}/read\`, {
        method: "POST"
      });
    },
    [request]
  );`;

const newLoad = `  const loadMessages = useCallback(
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
          \`/api/v1/tickets/\${ticketId}/messages?\${params.toString()}\`
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
        \`/api/v1/tickets/\${ticketId}/read\`,
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
                    \`[data-message-id="\${anchorId}"]\`
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
            \`/api/v1/tickets/\${selectedId}/messages?\${params.toString()}\`
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
            \`/api/v1/tickets/\${selectedId}/messages?\${params.toString()}\`
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
          \`/api/v1/tickets/\${ticketId}/messages?limit=80\`
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
  );`;

if (
  content.includes(
    oldLoad
  )
) {
  content =
    content.replace(
      oldLoad,
      newLoad
    );
} else if (
  !content.includes(
    "const loadOlderMessages"
  )
) {
  throw new Error(
    "loadMessages block not found."
  );
}

const oldSelectedEffect = `  useEffect(() => {
    if (!selectedId) {
      setMessages([]);
      setNotes([]);
      setNotesOpen(false);
      return;
    }

    void Promise.all([
      loadMessages(selectedId),
      loadNotes(selectedId)
    ]).catch(() => {
      setError(
        "Não foi possível carregar o atendimento."
      );
    });
  }, [loadMessages, loadNotes, selectedId]);`;

const newSelectedEffect = `  useEffect(() => {
    if (!selectedId) {
      setMessages([]);
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
  ]);`;

if (
  content.includes(
    oldSelectedEffect
  )
) {
  content =
    content.replace(
      oldSelectedEffect,
      newSelectedEffect
    );
} else if (
  !content.includes(
    "skipNextSelectedLoadRef.current"
  )
) {
  throw new Error(
    "selected ticket effect not found."
  );
}

const realtimeOld = `        if (selectedId && (!event.ticketId || event.ticketId === selectedId)) {
          void loadMessages(selectedId);
        }`;

const realtimeNew = `        if (
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
        }`;

if (
  content.includes(
    realtimeOld
  )
) {
  content =
    content.replace(
      realtimeOld,
      realtimeNew
    );
} else if (
  !content.includes(
    "void refreshLatestMessages("
  )
) {
  throw new Error(
    "realtime message refresh anchor not found."
  );
}

const depsOld = `    loadReferenceData,
    loadTickets,
    selectedId,`;

if (
  content.includes(
    depsOld
  ) &&
  !content.includes(
    "    refreshLatestMessages,\n    selectedId,"
  )
) {
  content =
    content.replace(
      depsOld,
      `    loadReferenceData,
    loadTickets,
    refreshLatestMessages,
    selectedId,`
    );
}

const scrollOld = `  useEffect(() => {
    bottomRef.current?.scrollIntoView({
      behavior: "smooth",
      block: "end"
    });
  }, [messages]);`;

const scrollNew = `  useEffect(() => {
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
  }, [messages]);`;

if (
  content.includes(
    scrollOld
  )
) {
  content =
    content.replace(
      scrollOld,
      scrollNew
    );
}

const pendingOld = `  // [P1.2f pending media fallback]
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
          \`/api/v1/tickets/\${selectedId}/messages\`
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
  ]);`;

const pendingNew = `  // [P1.2f pending media fallback]
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
  ]);`;

if (
  content.includes(
    pendingOld
  )
) {
  content =
    content.replace(
      pendingOld,
      pendingNew
    );
} else if (
  content.includes(
    "const refreshPendingMedia = async () =>"
  )
) {
  throw new Error(
    "pending media fallback format diverged."
  );
}

const searchOld = `                    onOpenTicket={ticketId => {
                      setSelectedId(ticketId);
                      setConversationSearchOpen(false);
                    }}`;

const searchNew = `                    onOpenTicket={(
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
                    }}`;

if (
  content.includes(
    searchOld
  )
) {
  content =
    content.replace(
      searchOld,
      searchNew
    );
} else if (
  !content.includes(
    "Não foi possível abrir a mensagem encontrada."
  )
) {
  throw new Error(
    "ConversationSearch parent callback not found."
  );
}

const scrollDivOld =
  `<div className="conversation-scroll">
                {messages.map(message => (`;

const scrollDivNew =
  `<div
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
                {messages.map(message => (`;

if (
  content.includes(
    scrollDivOld
  )
) {
  content =
    content.replace(
      scrollDivOld,
      scrollDivNew
    );
} else if (
  !content.includes(
    'ref={conversationScrollRef}'
  )
) {
  throw new Error(
    "conversation-scroll render anchor not found."
  );
}

const messageRowOld = `                    className={
                      message.direction === "OUTBOUND"
                        ? "message-row message-row--out"
                        : "message-row message-row--in"
                    }
                    key={message.id}`;

const messageRowNew = `                    className={\`${
                      message.direction === "OUTBOUND"
                        ? "message-row message-row--out"
                        : "message-row message-row--in"
                    }${
                      focusedMessageId === message.id
                        ? " message-row--focused"
                        : ""
                    }\`}
                    data-message-id={message.id}
                    key={message.id}`;

if (
  content.includes(
    messageRowOld
  )
) {
  content =
    content.replace(
      messageRowOld,
      messageRowNew
    );
} else if (
  !content.includes(
    "data-message-id={message.id}"
  )
) {
  throw new Error(
    "message row anchor not found."
  );
}

const bottomOld = `                ))}
                <div ref={bottomRef} />
                              </div>`;

const bottomNew = `                ))}

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
                              </div>`;

if (
  content.includes(
    bottomOld
  )
) {
  content =
    content.replace(
      bottomOld,
      bottomNew
    );
} else if (
  !content.includes(
    "message-history-loader--newer"
  )
) {
  throw new Error(
    "conversation bottom anchor not found."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Active conversation now supports bidirectional cursor history."
);
NODE

# ---------------------------------------------------------------------------
# Closed tickets drawer: older-message pagination
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/components/conversations/closed-tickets-drawer.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  );

const oldResponse = `interface MessagesResponse {
  messages: ArchivedMessage[];
}`;

const newResponse = `interface MessagesResponse {
  messages: ArchivedMessage[];
  pagination: {
    hasMoreBefore: boolean;
    olderCursor: string | null;
    hasMoreAfter: boolean;
    newerCursor: string | null;
  };
}`;

if (
  content.includes(
    oldResponse
  )
) {
  content =
    content.replace(
      oldResponse,
      newResponse
    );
}

if (
  !content.includes(
    "function mergeArchivedMessages"
  )
) {
  const anchor = `function messageFallback(
  type: MessageType
) {`;

  const start =
    content.indexOf(
      anchor
    );

  const end =
    content.indexOf(
      "\n}\n\nexport function ClosedTicketsDrawer",
      start
    );

  if (
    start < 0 ||
    end < 0
  ) {
    throw new Error(
      "closed drawer helper anchor not found."
    );
  }

  const insertAt =
    end + 3;

  const helper = `
function mergeArchivedMessages(
  older: ArchivedMessage[],
  current: ArchivedMessage[]
) {
  const byId =
    new Map<
      string,
      ArchivedMessage
    >();

  for (
    const message
    of [
      ...older,
      ...current
    ]
  ) {
    byId.set(
      message.id,
      message
    );
  }

  return Array.from(
    byId.values()
  ).sort(
    (left, right) =>
      new Date(
        left.timestamp
      ).getTime() -
        new Date(
          right.timestamp
        ).getTime() ||
      left.id.localeCompare(
        right.id
      )
  );
}
`;

  content =
    content.slice(
      0,
      insertAt
    ) +
    helper +
    content.slice(
      insertAt
    );
}

const stateAnchor = `  const [messages, setMessages] =
    useState<ArchivedMessage[]>([]);
  const [loadingTickets, setLoadingTickets] =`;

if (
  !content.includes(
    "const [messagePagination"
  )
) {
  if (!content.includes(stateAnchor)) {
    throw new Error(
      "closed messages state anchor not found."
    );
  }

  content =
    content.replace(
      stateAnchor,
      `  const [messages, setMessages] =
    useState<ArchivedMessage[]>([]);
  const [messagePagination, setMessagePagination] =
    useState({
      hasMoreBefore: false,
      olderCursor: null as
        | string
        | null
    });
  const [loadingOlderMessages, setLoadingOlderMessages] =
    useState(false);
  const [loadingTickets, setLoadingTickets] =`
    );
}

const requestOld =
  `            \`/api/v1/tickets/\${selectedId}/messages\``;

const requestNew =
  `            \`/api/v1/tickets/\${selectedId}/messages?limit=80\``;

if (
  content.includes(
    requestOld
  )
) {
  content =
    content.replace(
      requestOld,
      requestNew
    );
}

const setMessagesOld = `          setMessages(
            payload.messages
          );`;

const setMessagesNew = `          setMessages(
            payload.messages
          );

          setMessagePagination({
            hasMoreBefore:
              payload
                .pagination
                .hasMoreBefore,
            olderCursor:
              payload
                .pagination
                .olderCursor
          });`;

if (
  content.includes(
    setMessagesOld
  )
) {
  content =
    content.replace(
      setMessagesOld,
      setMessagesNew
    );
}

const effectEnd = `  }, [
    request,
    selectedId
  ]);

  async function reopen() {`;

if (
  !content.includes(
    "async function loadOlderMessages()"
  )
) {
  if (!content.includes(effectEnd)) {
    throw new Error(
      "closed drawer messages effect end not found."
    );
  }

  const loader = `  }, [
    request,
    selectedId
  ]);

  async function loadOlderMessages() {
    if (
      !selectedId ||
      !messagePagination.hasMoreBefore ||
      !messagePagination.olderCursor ||
      loadingOlderMessages
    ) {
      return;
    }

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
          \`/api/v1/tickets/\${selectedId}/messages?\${params.toString()}\`
        );

      setMessages(
        current =>
          mergeArchivedMessages(
            payload.messages,
            current
          )
      );

      setMessagePagination({
        hasMoreBefore:
          payload
            .pagination
            .hasMoreBefore,
        olderCursor:
          payload
            .pagination
            .olderCursor
      });
    } catch {
      setError(
        "Não foi possível carregar mensagens mais antigas."
      );
    } finally {
      setLoadingOlderMessages(
        false
      );
    }
  }

  async function reopen() {`;

  content =
    content.replace(
      effectEnd,
      loader
    );
}

const renderOld = `              <div className="closed-ticket-history__messages">
                {loadingMessages ? (`;

const renderNew = `              <div className="closed-ticket-history__messages">
                {messagePagination.hasMoreBefore && !loadingMessages && (
                  <button
                    className="closed-ticket-history__load-more"
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
                )}

                {loadingMessages ? (`;

if (
  content.includes(
    renderOld
  )
) {
  content =
    content.replace(
      renderOld,
      renderNew
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Closed ticket history now loads older messages incrementally."
);
NODE

# ---------------------------------------------------------------------------
# CSS: scoped controls only, no conversation layout rewrite
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.21 / MESSAGE HISTORY" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.21 / MESSAGE HISTORY --- */

.message-history-loader {
  display: flex;
  justify-content: center;
  padding: 10px 16px 14px;
}

.message-history-loader--newer {
  padding-top: 16px;
}

.message-history-loader button,
.closed-ticket-history__load-more {
  border: 1px solid rgba(20, 31, 25, 0.12);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.9);
  padding: 8px 14px;
  font: inherit;
  font-size: 12px;
  font-weight: 700;
  cursor: pointer;
}

.message-history-loader button:disabled,
.closed-ticket-history__load-more:disabled {
  cursor: wait;
  opacity: 0.58;
}

.message-row--focused .message-bubble {
  box-shadow:
    0 0 0 2px rgba(34, 126, 82, 0.24),
    0 8px 28px rgba(16, 42, 28, 0.08);
}

.closed-ticket-history__load-more {
  align-self: center;
  margin: 8px auto 14px;
}

/* --- /WAPP P1.21 --- */
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/MESSAGE_HISTORY_PAGINATION.md <<'EOF'
# P1.21 Message history cursor pagination

P1.21 removes the fixed message-history window from active and closed tickets.

## Previous behavior

`GET /api/v1/tickets/:id/messages` used:

- `orderBy timestamp ASC`;
- `take: 200`.

For tickets longer than 200 messages this returned the oldest 200 messages,
not the newest conversation window.

A global message search could find a much newer/older database record, but
opening the ticket did not guarantee that the found message existed in the
loaded window.

## New API

`GET /api/v1/tickets/:id/messages`

Query:

- `limit`: 20..100, default 80;
- `before=<message UUID>`: page older than a loaded message;
- `after=<message UUID>`: page newer than a loaded message;
- `around=<message UUID>`: load context centered around an exact message.

Only one cursor can be supplied per request.

Response:

```json
{
  "messages": [],
  "pagination": {
    "hasMoreBefore": true,
    "olderCursor": "uuid",
    "hasMoreAfter": false,
    "newerCursor": null
  }
}
```

Ordering sent to the browser remains chronological ascending.

The database already has an index on `Message(ticketId, timestamp)`, so P1.21
does not require a Prisma migration.

## Active conversation

Initial open:

- newest 80 messages;
- composer remains unchanged;
- `.conversation-scroll` remains the only message scroll container.

Older pages are prepended while preserving the user's visible scroll position.

If a search opens an old message, Wapp loads a page around that message,
scrolls it into view and temporarily highlights it.

When context is opened in the middle of a very long ticket, the user can page
both toward older and newer messages.

## Realtime and media processing

Realtime refreshes merge the latest page by message id instead of replacing
all pages already loaded.

When the user is viewing an older middle segment (`hasMoreAfter=true`), Wapp
does not splice the latest 80 messages across an unloaded gap. The user can
page forward normally until current history is reached.

The P1.2 pending-media fallback follows the same rule and does not discard
older pages.

## Closed tickets

The read-only closed-ticket drawer opens the newest page and can load older
messages incrementally.

## Migration

No Prisma migration is required.
EOF

echo "[P1.21] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.21] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.21] Message history pagination installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Validation:"
echo "  1. open an active conversation"
echo "  2. confirm it opens at the newest messages"
echo "  3. load previous messages"
echo "  4. use Buscar and open an older result"
echo "  5. confirm the exact result scrolls into view"
echo "  6. open Encerrados and load previous messages there"
