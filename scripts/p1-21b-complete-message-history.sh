#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.21b] Completing message-history pagination after partial install..."

for required in \
  "apps/api/src/modules/tickets/ticket-message-history.service.ts" \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
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

if ! grep -q 'listTicketMessagePage' apps/api/src/modules/tickets/ticket.routes.ts; then
  echo "ERROR: P1.21 API pagination was not applied. Do not continue."
  exit 1
fi

if ! grep -q 'messageId: string' apps/web/components/conversations/conversation-search.tsx; then
  echo "ERROR: P1.21 search deep-link change was not applied. Do not continue."
  exit 1
fi

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

function replaceOnce(
  before,
  after,
  label
) {
  if (
    content.includes(
      after
    )
  ) {
    return;
  }

  if (
    !content.includes(
      before
    )
  ) {
    throw new Error(
      `Could not find ${label} anchor.`
    );
  }

  content =
    content.replace(
      before,
      after
    );
}

replaceOnce(
  [
    "interface MessagesResponse {",
    "  messages: Message[];",
    "}"
  ].join("\n"),
  [
    "interface MessagePagination {",
    "  hasMoreBefore: boolean;",
    "  olderCursor: string | null;",
    "  hasMoreAfter: boolean;",
    "  newerCursor: string | null;",
    "}",
    "",
    "interface MessagesResponse {",
    "  messages: Message[];",
    "  pagination: MessagePagination;",
    "}"
  ].join("\n"),
  "MessagesResponse"
);

if (
  !content.includes(
    "function mergeMessagePages"
  )
) {
  const anchor =
    [
      'function dateTimeLabel(value: string) {',
      '  return new Intl.DateTimeFormat("pt-BR", {',
      '    day: "2-digit",',
      '    month: "2-digit",',
      '    hour: "2-digit",',
      '    minute: "2-digit"',
      '  }).format(new Date(value));',
      '}'
    ].join("\n");

  const helper =
    [
      anchor,
      "",
      "function mergeMessagePages(",
      "  ...pages: Message[][]",
      ") {",
      "  const byId =",
      "    new Map<",
      "      string,",
      "      Message",
      "    >();",
      "",
      "  for (",
      "    const page",
      "    of pages",
      "  ) {",
      "    for (",
      "      const message",
      "      of page",
      "    ) {",
      "      byId.set(",
      "        message.id,",
      "        message",
      "      );",
      "    }",
      "  }",
      "",
      "  return Array.from(",
      "    byId.values()",
      "  ).sort(",
      "    (left, right) => {",
      "      const time =",
      "        new Date(",
      "          left.timestamp",
      "        ).getTime() -",
      "        new Date(",
      "          right.timestamp",
      "        ).getTime();",
      "",
      "      return (",
      "        time ||",
      "        left.id.localeCompare(",
      "          right.id",
      "        )",
      "      );",
      "    }",
      "  );",
      "}"
    ].join("\n");

  if (
    !content.includes(
      anchor
    )
  ) {
    throw new Error(
      "Could not find dateTimeLabel anchor."
    );
  }

  content =
    content.replace(
      anchor,
      helper
    );
}

replaceOnce(
  [
    "  const [messages, setMessages] = useState<Message[]>([]);",
    "  const [notes, setNotes] = useState<TicketNote[]>([]);"
  ].join("\n"),
  [
    "  const [messages, setMessages] = useState<Message[]>([]);",
    "  const [messagePagination, setMessagePagination] =",
    "    useState<MessagePagination>({",
    "      hasMoreBefore: false,",
    "      olderCursor: null,",
    "      hasMoreAfter: false,",
    "      newerCursor: null",
    "    });",
    "  const [loadingOlderMessages, setLoadingOlderMessages] =",
    "    useState(false);",
    "  const [loadingNewerMessages, setLoadingNewerMessages] =",
    "    useState(false);",
    "  const [focusedMessageId, setFocusedMessageId] =",
    "    useState<string | null>(null);",
    "  const [notes, setNotes] = useState<TicketNote[]>([]);"
  ].join("\n"),
  "message pagination state"
);

replaceOnce(
  [
    "  const bottomRef = useRef<HTMLDivElement | null>(null);",
    "  const attachmentInputRef ="
  ].join("\n"),
  [
    "  const bottomRef = useRef<HTMLDivElement | null>(null);",
    "  const conversationScrollRef =",
    "    useRef<HTMLDivElement | null>(null);",
    "  const shouldScrollToBottomRef =",
    "    useRef(true);",
    "  const skipNextSelectedLoadRef =",
    "    useRef(false);",
    "  const attachmentInputRef ="
  ].join("\n"),
  "conversation refs"
);

if (
  !content.includes(
    "const loadOlderMessages"
  )
) {
  const oldLoad =
    [
      "  const loadMessages = useCallback(",
      "    async (ticketId: string) => {",
      "      const payload = await request<MessagesResponse>(",
      "        `/api/v1/tickets/${ticketId}/messages`",
      "      );",
      "      setMessages(payload.messages);",
      "      await request(`/api/v1/tickets/${ticketId}/read`, {",
      '        method: "POST"',
      "      });",
      "    },",
      "    [request]",
      "  );"
    ].join("\n");

  const newLoad =
    [
      "  const loadMessages = useCallback(",
      "    async (",
      "      ticketId: string,",
      "      options: {",
      "        around?: string;",
      "      } = {}",
      "    ) => {",
      "      const params =",
      "        new URLSearchParams({",
      '          limit: "80"',
      "        });",
      "",
      "      if (options.around) {",
      "        params.set(",
      '          "around",',
      "          options.around",
      "        );",
      "      }",
      "",
      "      const payload =",
      "        await request<MessagesResponse>(",
      "          `/api/v1/tickets/${ticketId}/messages?${params.toString()}`",
      "        );",
      "",
      "      shouldScrollToBottomRef.current =",
      "        !options.around;",
      "",
      "      setMessages(",
      "        payload.messages",
      "      );",
      "",
      "      setMessagePagination(",
      "        payload.pagination",
      "      );",
      "",
      "      await request(",
      "        `/api/v1/tickets/${ticketId}/read`,",
      "        {",
      '          method: "POST"',
      "        }",
      "      );",
      "",
      "      if (options.around) {",
      "        const anchorId =",
      "          options.around;",
      "",
      "        setFocusedMessageId(",
      "          anchorId",
      "        );",
      "",
      "        window.requestAnimationFrame(",
      "          () => {",
      "            window.requestAnimationFrame(",
      "              () => {",
      "                document",
      "                  .querySelector(",
      "                    `[data-message-id=\"${anchorId}\"]`",
      "                  )",
      "                  ?.scrollIntoView({",
      "                    behavior:",
      '                      "smooth",',
      "                    block:",
      '                      "center"',
      "                  });",
      "              }",
      "            );",
      "          }",
      "        );",
      "",
      "        window.setTimeout(",
      "          () => {",
      "            setFocusedMessageId(",
      "              current =>",
      "                current ===",
      "                anchorId",
      "                  ? null",
      "                  : current",
      "            );",
      "          },",
      "          3_000",
      "        );",
      "      }",
      "    },",
      "    [request]",
      "  );",
      "",
      "  const loadOlderMessages = useCallback(",
      "    async () => {",
      "      if (",
      "        !selectedId ||",
      "        !messagePagination.hasMoreBefore ||",
      "        !messagePagination.olderCursor ||",
      "        loadingOlderMessages",
      "      ) {",
      "        return;",
      "      }",
      "",
      "      const scroller =",
      "        conversationScrollRef.current;",
      "",
      "      const previousHeight =",
      "        scroller?.scrollHeight ??",
      "        0;",
      "",
      "      const previousTop =",
      "        scroller?.scrollTop ??",
      "        0;",
      "",
      "      setLoadingOlderMessages(",
      "        true",
      "      );",
      "",
      "      try {",
      "        const params =",
      "          new URLSearchParams({",
      '            limit: "80",',
      "            before:",
      "              messagePagination.olderCursor",
      "          });",
      "",
      "        const payload =",
      "          await request<MessagesResponse>(",
      "            `/api/v1/tickets/${selectedId}/messages?${params.toString()}`",
      "          );",
      "",
      "        shouldScrollToBottomRef.current =",
      "          false;",
      "",
      "        setMessages(",
      "          current =>",
      "            mergeMessagePages(",
      "              payload.messages,",
      "              current",
      "            )",
      "        );",
      "",
      "        setMessagePagination(",
      "          current => ({",
      "            ...current,",
      "            hasMoreBefore:",
      "              payload",
      "                .pagination",
      "                .hasMoreBefore,",
      "            olderCursor:",
      "              payload",
      "                .pagination",
      "                .olderCursor",
      "          })",
      "        );",
      "",
      "        window.requestAnimationFrame(",
      "          () => {",
      "            const currentScroller =",
      "              conversationScrollRef.current;",
      "",
      "            if (",
      "              !currentScroller",
      "            ) {",
      "              return;",
      "            }",
      "",
      "            currentScroller.scrollTop =",
      "              currentScroller.scrollHeight -",
      "              previousHeight +",
      "              previousTop;",
      "          }",
      "        );",
      "      } finally {",
      "        setLoadingOlderMessages(",
      "          false",
      "        );",
      "      }",
      "    },",
      "    [",
      "      loadingOlderMessages,",
      "      messagePagination.hasMoreBefore,",
      "      messagePagination.olderCursor,",
      "      request,",
      "      selectedId",
      "    ]",
      "  );",
      "",
      "  const loadNewerMessages = useCallback(",
      "    async () => {",
      "      if (",
      "        !selectedId ||",
      "        !messagePagination.hasMoreAfter ||",
      "        !messagePagination.newerCursor ||",
      "        loadingNewerMessages",
      "      ) {",
      "        return;",
      "      }",
      "",
      "      setLoadingNewerMessages(",
      "        true",
      "      );",
      "",
      "      try {",
      "        const params =",
      "          new URLSearchParams({",
      '            limit: "80",',
      "            after:",
      "              messagePagination.newerCursor",
      "          });",
      "",
      "        const payload =",
      "          await request<MessagesResponse>(",
      "            `/api/v1/tickets/${selectedId}/messages?${params.toString()}`",
      "          );",
      "",
      "        shouldScrollToBottomRef.current =",
      "          false;",
      "",
      "        setMessages(",
      "          current =>",
      "            mergeMessagePages(",
      "              current,",
      "              payload.messages",
      "            )",
      "        );",
      "",
      "        setMessagePagination(",
      "          current => ({",
      "            ...current,",
      "            hasMoreAfter:",
      "              payload",
      "                .pagination",
      "                .hasMoreAfter,",
      "            newerCursor:",
      "              payload",
      "                .pagination",
      "                .newerCursor",
      "          })",
      "        );",
      "      } finally {",
      "        setLoadingNewerMessages(",
      "          false",
      "        );",
      "      }",
      "    },",
      "    [",
      "      loadingNewerMessages,",
      "      messagePagination.hasMoreAfter,",
      "      messagePagination.newerCursor,",
      "      request,",
      "      selectedId",
      "    ]",
      "  );",
      "",
      "  const refreshLatestMessages = useCallback(",
      "    async (",
      "      ticketId: string,",
      "      scrollToBottom =",
      "        false",
      "    ) => {",
      "      if (",
      "        messagePagination.hasMoreAfter",
      "      ) {",
      "        return;",
      "      }",
      "",
      "      const payload =",
      "        await request<MessagesResponse>(",
      "          `/api/v1/tickets/${ticketId}/messages?limit=80`",
      "        );",
      "",
      "      shouldScrollToBottomRef.current =",
      "        scrollToBottom;",
      "",
      "      setMessages(",
      "        current =>",
      "          mergeMessagePages(",
      "            current,",
      "            payload.messages",
      "          )",
      "      );",
      "    },",
      "    [",
      "      messagePagination.hasMoreAfter,",
      "      request",
      "    ]",
      "  );"
    ].join("\n");

  if (
    !content.includes(
      oldLoad
    )
  ) {
    throw new Error(
      "Could not find original loadMessages block."
    );
  }

  content =
    content.replace(
      oldLoad,
      newLoad
    );
}

replaceOnce(
  [
    "  useEffect(() => {",
    "    if (!selectedId) {",
    "      setMessages([]);",
    "      setNotes([]);",
    "      setNotesOpen(false);",
    "      return;",
    "    }",
    "",
    "    void Promise.all([",
    "      loadMessages(selectedId),",
    "      loadNotes(selectedId)",
    "    ]).catch(() => {",
    "      setError(",
    '        "Não foi possível carregar o atendimento."',
    "      );",
    "    });",
    "  }, [loadMessages, loadNotes, selectedId]);"
  ].join("\n"),
  [
    "  useEffect(() => {",
    "    if (!selectedId) {",
    "      setMessages([]);",
    "      setMessagePagination({",
    "        hasMoreBefore:",
    "          false,",
    "        olderCursor:",
    "          null,",
    "        hasMoreAfter:",
    "          false,",
    "        newerCursor:",
    "          null",
    "      });",
    "      setNotes([]);",
    "      setNotesOpen(false);",
    "      return;",
    "    }",
    "",
    "    if (",
    "      skipNextSelectedLoadRef.current",
    "    ) {",
    "      skipNextSelectedLoadRef.current =",
    "        false;",
    "      return;",
    "    }",
    "",
    "    void Promise.all([",
    "      loadMessages(",
    "        selectedId",
    "      ),",
    "      loadNotes(",
    "        selectedId",
    "      )",
    "    ]).catch(() => {",
    "      setError(",
    '        "Não foi possível carregar o atendimento."',
    "      );",
    "    });",
    "  }, [",
    "    loadMessages,",
    "    loadNotes,",
    "    selectedId",
    "  ]);"
  ].join("\n"),
  "selected ticket effect"
);

if (
  !content.includes(
    "void refreshLatestMessages("
  )
) {
  const before =
    [
      "        if (selectedId && (!event.ticketId || event.ticketId === selectedId)) {",
      "          void loadMessages(selectedId);",
      "        }"
    ].join("\n");

  const after =
    [
      "        if (",
      "          selectedId &&",
      "          (",
      "            !event.ticketId ||",
      "            event.ticketId ===",
      "              selectedId",
      "          )",
      "        ) {",
      "          void refreshLatestMessages(",
      "            selectedId,",
      "            event.type ===",
      '              "message.created"',
      "          );",
      "        }"
    ].join("\n");

  if (
    !content.includes(
      before
    )
  ) {
    throw new Error(
      "Could not find realtime message reload block."
    );
  }

  content =
    content.replace(
      before,
      after
    );
}

if (
  content.includes(
    [
      "    loadReferenceData,",
      "    loadTickets,",
      "    selectedId,"
    ].join("\n")
  ) &&
  !content.includes(
    [
      "    loadReferenceData,",
      "    loadTickets,",
      "    refreshLatestMessages,",
      "    selectedId,"
    ].join("\n")
  )
) {
  content =
    content.replace(
      [
        "    loadReferenceData,",
        "    loadTickets,",
        "    selectedId,"
      ].join("\n"),
      [
        "    loadReferenceData,",
        "    loadTickets,",
        "    refreshLatestMessages,",
        "    selectedId,"
      ].join("\n")
    );
}

replaceOnce(
  [
    "  useEffect(() => {",
    "    bottomRef.current?.scrollIntoView({",
    '      behavior: "smooth",',
    '      block: "end"',
    "    });",
    "  }, [messages]);"
  ].join("\n"),
  [
    "  useEffect(() => {",
    "    if (",
    "      !shouldScrollToBottomRef.current",
    "    ) {",
    "      shouldScrollToBottomRef.current =",
    "        true;",
    "      return;",
    "    }",
    "",
    "    bottomRef.current",
    "      ?.scrollIntoView({",
    "        behavior:",
    '          "smooth",',
    "        block:",
    '          "end"',
    "      });",
    "  }, [messages]);"
  ].join("\n"),
  "bottom scroll effect"
);

if (
  content.includes(
    "const refreshPendingMedia = async () =>"
  )
) {
  const startMarker =
    "  // [P1.2f pending media fallback]";

  const endMarker =
    "\n\n\n  // [P1.4 recorder cleanup]";

  const start =
    content.indexOf(
      startMarker
    );

  const end =
    content.indexOf(
      endMarker,
      start
    );

  if (
    start < 0 ||
    end < 0
  ) {
    throw new Error(
      "Could not bound pending media fallback."
    );
  }

  const replacement =
    [
      "  // [P1.2f pending media fallback]",
      "  // SSE remains primary. Polling only refreshes the latest page while media",
      "  // is processing and never discards older pages already loaded by P1.21.",
      "  useEffect(() => {",
      "    if (",
      "      !session ||",
      "      !selectedId ||",
      "      !hasPendingMedia ||",
      "      messagePagination.hasMoreAfter",
      "    ) {",
      "      return;",
      "    }",
      "",
      "    const refreshPendingMedia =",
      "      async () => {",
      "        try {",
      "          await refreshLatestMessages(",
      "            selectedId,",
      "            false",
      "          );",
      "        } catch {",
      "          // Non-fatal fallback. Realtime or the next tick can recover.",
      "        }",
      "      };",
      "",
      "    const interval =",
      "      window.setInterval(",
      "        () => {",
      "          void refreshPendingMedia();",
      "        },",
      "        1_200",
      "      );",
      "",
      "    void refreshPendingMedia();",
      "",
      "    return () => {",
      "      window.clearInterval(",
      "        interval",
      "      );",
      "    };",
      "  }, [",
      "    hasPendingMedia,",
      "    messagePagination.hasMoreAfter,",
      "    refreshLatestMessages,",
      "    selectedId,",
      "    session",
      "  ]);"
    ].join("\n");

  content =
    content.slice(
      0,
      start
    ) +
    replacement +
    content.slice(
      end
    );
}

replaceOnce(
  [
    "                    onOpenTicket={ticketId => {",
    "                      setSelectedId(ticketId);",
    "                      setConversationSearchOpen(false);",
    "                    }}"
  ].join("\n"),
  [
    "                    onOpenTicket={(",
    "                      ticketId,",
    "                      messageId",
    "                    ) => {",
    "                      if (",
    "                        ticketId !==",
    "                        selectedId",
    "                      ) {",
    "                        skipNextSelectedLoadRef.current =",
    "                          true;",
    "                      }",
    "",
    "                      setSelectedId(",
    "                        ticketId",
    "                      );",
    "",
    "                      setConversationSearchOpen(",
    "                        false",
    "                      );",
    "",
    "                      void Promise.all([",
    "                        loadMessages(",
    "                          ticketId,",
    "                          {",
    "                            around:",
    "                              messageId",
    "                          }",
    "                        ),",
    "                        loadNotes(",
    "                          ticketId",
    "                        )",
    "                      ]).catch(() => {",
    "                        setError(",
    '                          "Não foi possível abrir a mensagem encontrada."',
    "                        );",
    "                      });",
    "                    }}"
  ].join("\n"),
  "search open callback"
);

replaceOnce(
  [
    '                <div className="conversation-scroll">',
    "                {messages.map(message => ("
  ].join("\n"),
  [
    "                <div",
    '                  className="conversation-scroll"',
    "                  ref={conversationScrollRef}",
    "                >",
    "                {messagePagination.hasMoreBefore && (",
    '                  <div className="message-history-loader">',
    "                    <button",
    "                      disabled={loadingOlderMessages}",
    "                      onClick={() =>",
    "                        void loadOlderMessages()",
    "                      }",
    '                      type="button"',
    "                    >",
    "                      {loadingOlderMessages",
    '                        ? "Carregando…"',
    '                        : "Carregar mensagens anteriores"}',
    "                    </button>",
    "                  </div>",
    "                )}",
    "                {messages.map(message => ("
  ].join("\n"),
  "conversation scroll"
);

if (
  !content.includes(
    "data-message-id={message.id}"
  )
) {
  const before =
    [
      "                    className={",
      '                      message.direction === "OUTBOUND"',
      '                        ? "message-row message-row--out"',
      '                        : "message-row message-row--in"',
      "                    }",
      "                    key={message.id}"
    ].join("\n");

  const after =
    [
      "                    className={`${",
      '                      message.direction === "OUTBOUND"',
      '                        ? "message-row message-row--out"',
      '                        : "message-row message-row--in"',
      "                    }${",
      "                      focusedMessageId === message.id",
      '                        ? " message-row--focused"',
      '                        : ""',
      "                    }`}",
      "                    data-message-id={message.id}",
      "                    key={message.id}"
    ].join("\n");

  if (
    !content.includes(
      before
    )
  ) {
    throw new Error(
      "Could not find message-row render block."
    );
  }

  content =
    content.replace(
      before,
      after
    );
}

replaceOnce(
  [
    "                ))}",
    "                <div ref={bottomRef} />",
    "                              </div>"
  ].join("\n"),
  [
    "                ))}",
    "",
    "                {messagePagination.hasMoreAfter && (",
    '                  <div className="message-history-loader message-history-loader--newer">',
    "                    <button",
    "                      disabled={loadingNewerMessages}",
    "                      onClick={() =>",
    "                        void loadNewerMessages()",
    "                      }",
    '                      type="button"',
    "                    >",
    "                      {loadingNewerMessages",
    '                        ? "Carregando…"',
    '                        : "Carregar mensagens mais recentes"}',
    "                    </button>",
    "                  </div>",
    "                )}",
    "",
    "                <div ref={bottomRef} />",
    "                              </div>"
  ].join("\n"),
  "conversation bottom"
);

fs.writeFileSync(
  path,
  content
);

console.log(
  "Active conversation pagination completed."
);
NODE

# ---------------------------------------------------------------------------
# Closed tickets drawer
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

function replaceOnce(
  before,
  after,
  label
) {
  if (
    content.includes(
      after
    )
  ) {
    return;
  }

  if (
    !content.includes(
      before
    )
  ) {
    throw new Error(
      `Could not find ${label} anchor.`
    );
  }

  content =
    content.replace(
      before,
      after
    );
}

replaceOnce(
  [
    "interface MessagesResponse {",
    "  messages: ArchivedMessage[];",
    "}"
  ].join("\n"),
  [
    "interface MessagesResponse {",
    "  messages: ArchivedMessage[];",
    "  pagination: {",
    "    hasMoreBefore: boolean;",
    "    olderCursor: string | null;",
    "    hasMoreAfter: boolean;",
    "    newerCursor: string | null;",
    "  };",
    "}"
  ].join("\n"),
  "closed MessagesResponse"
);

if (
  !content.includes(
    "function mergeArchivedMessages"
  )
) {
  const marker =
    "\nexport function ClosedTicketsDrawer";

  const index =
    content.indexOf(
      marker
    );

  if (index < 0) {
    throw new Error(
      "ClosedTicketsDrawer export anchor not found."
    );
  }

  const helper =
    [
      "",
      "function mergeArchivedMessages(",
      "  older: ArchivedMessage[],",
      "  current: ArchivedMessage[]",
      ") {",
      "  const byId =",
      "    new Map<",
      "      string,",
      "      ArchivedMessage",
      "    >();",
      "",
      "  for (",
      "    const message",
      "    of [",
      "      ...older,",
      "      ...current",
      "    ]",
      "  ) {",
      "    byId.set(",
      "      message.id,",
      "      message",
      "    );",
      "  }",
      "",
      "  return Array.from(",
      "    byId.values()",
      "  ).sort(",
      "    (left, right) =>",
      "      new Date(",
      "        left.timestamp",
      "      ).getTime() -",
      "        new Date(",
      "          right.timestamp",
      "        ).getTime() ||",
      "      left.id.localeCompare(",
      "        right.id",
      "      )",
      "  );",
      "}",
      ""
    ].join("\n");

  content =
    content.slice(
      0,
      index
    ) +
    helper +
    content.slice(
      index
    );
}

replaceOnce(
  [
    "  const [messages, setMessages] =",
    "    useState<ArchivedMessage[]>([]);",
    "  const [loadingTickets, setLoadingTickets] ="
  ].join("\n"),
  [
    "  const [messages, setMessages] =",
    "    useState<ArchivedMessage[]>([]);",
    "  const [messagePagination, setMessagePagination] =",
    "    useState({",
    "      hasMoreBefore: false,",
    "      olderCursor: null as",
    "        | string",
    "        | null",
    "    });",
    "  const [loadingOlderMessages, setLoadingOlderMessages] =",
    "    useState(false);",
    "  const [loadingTickets, setLoadingTickets] ="
  ].join("\n"),
  "closed pagination state"
);

if (
  content.includes(
    "`/api/v1/tickets/${selectedId}/messages`"
  )
) {
  content =
    content.replace(
      "`/api/v1/tickets/${selectedId}/messages`",
      "`/api/v1/tickets/${selectedId}/messages?limit=80`"
    );
}

if (
  !content.includes(
    "setMessagePagination({"
  )
) {
  replaceOnce(
    [
      "          setMessages(",
      "            payload.messages",
      "          );"
    ].join("\n"),
    [
      "          setMessages(",
      "            payload.messages",
      "          );",
      "",
      "          setMessagePagination({",
      "            hasMoreBefore:",
      "              payload",
      "                .pagination",
      "                .hasMoreBefore,",
      "            olderCursor:",
      "              payload",
      "                .pagination",
      "                .olderCursor",
      "          });"
    ].join("\n"),
    "closed initial pagination"
  );
}

if (
  !content.includes(
    "async function loadOlderMessages()"
  )
) {
  const marker =
    [
      "  }, [",
      "    request,",
      "    selectedId",
      "  ]);",
      "",
      "  async function reopen() {"
    ].join("\n");

  const replacement =
    [
      "  }, [",
      "    request,",
      "    selectedId",
      "  ]);",
      "",
      "  async function loadOlderMessages() {",
      "    if (",
      "      !selectedId ||",
      "      !messagePagination.hasMoreBefore ||",
      "      !messagePagination.olderCursor ||",
      "      loadingOlderMessages",
      "    ) {",
      "      return;",
      "    }",
      "",
      "    setLoadingOlderMessages(",
      "      true",
      "    );",
      "",
      "    try {",
      "      const params =",
      "        new URLSearchParams({",
      '          limit: "80",',
      "          before:",
      "            messagePagination.olderCursor",
      "        });",
      "",
      "      const payload =",
      "        await request<MessagesResponse>(",
      "          `/api/v1/tickets/${selectedId}/messages?${params.toString()}`",
      "        );",
      "",
      "      setMessages(",
      "        current =>",
      "          mergeArchivedMessages(",
      "            payload.messages,",
      "            current",
      "          )",
      "      );",
      "",
      "      setMessagePagination({",
      "        hasMoreBefore:",
      "          payload",
      "            .pagination",
      "            .hasMoreBefore,",
      "        olderCursor:",
      "          payload",
      "            .pagination",
      "            .olderCursor",
      "      });",
      "    } catch {",
      "      setError(",
      '        "Não foi possível carregar mensagens mais antigas."',
      "      );",
      "    } finally {",
      "      setLoadingOlderMessages(",
      "        false",
      "      );",
      "    }",
      "  }",
      "",
      "  async function reopen() {"
    ].join("\n");

  if (
    !content.includes(
      marker
    )
  ) {
    throw new Error(
      "Could not find closed drawer effect boundary."
    );
  }

  content =
    content.replace(
      marker,
      replacement
    );
}

replaceOnce(
  [
    '              <div className="closed-ticket-history__messages">',
    "                {loadingMessages ? ("
  ].join("\n"),
  [
    '              <div className="closed-ticket-history__messages">',
    "                {messagePagination.hasMoreBefore && !loadingMessages && (",
    "                  <button",
    '                    className="closed-ticket-history__load-more"',
    "                    disabled={loadingOlderMessages}",
    "                    onClick={() =>",
    "                      void loadOlderMessages()",
    "                    }",
    '                    type="button"',
    "                  >",
    "                    {loadingOlderMessages",
    '                      ? "Carregando…"',
    '                      : "Carregar mensagens anteriores"}',
    "                  </button>",
    "                )}",
    "",
    "                {loadingMessages ? ("
  ].join("\n"),
  "closed history loader"
);

fs.writeFileSync(
  path,
  content
);

console.log(
  "Closed ticket pagination completed."
);
NODE

# ---------------------------------------------------------------------------
# CSS
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

The ticket message endpoint now opens the newest page and supports cursor
pagination with `before`, `after` and `around`.

Active conversations load the newest 80 messages first. Older pages are
prepended without replacing history already loaded.

Search results deep-link to the exact message using `around=<messageId>`.

Closed tickets can also load older history incrementally.

The canonical layout is preserved:

- `.conversation-panel`
- `.conversation-body`
- `.conversation-scroll` as the only message scroll
- `.conversation-composer` outside the scroll

No Prisma migration is required because the existing
`Message(ticketId, timestamp)` index is reused.
EOF

echo "[P1.21b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.21b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.21b] P1.21 completed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Validate:"
echo "  1. active conversation opens at newest messages"
echo "  2. Carregar mensagens anteriores works"
echo "  3. Buscar opens the exact old message"
echo "  4. Encerrados can load older messages"
