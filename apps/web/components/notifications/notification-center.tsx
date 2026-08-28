"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState
} from "react";
import {
  useRouter
} from "next/navigation";

import {
  useAuth
} from "@/components/auth-provider";
import {
  ApiError
} from "@/lib/api";

interface WappNotification {
  id: string;
  ticketId:
    | string
    | null;
  contactId:
    | string
    | null;
  messageId:
    | string
    | null;
  type:
    | "NEW_TICKET"
    | "INBOUND_MESSAGE"
    | "ASSIGNED_TO_YOU"
    | string;
  title: string;
  body: string;
  occurrenceCount:
    number;
  readAt:
    | string
    | null;
  createdAt:
    string;
  updatedAt:
    string;
}

interface NotificationPayload {
  notifications:
    WappNotification[];
  unreadCount:
    number;
}

function relativeTime(
  value: string
) {
  const seconds =
    Math.max(
      0,
      Math.floor(
        (
          Date.now() -
          new Date(
            value
          ).getTime()
        ) /
          1000
      )
    );

  if (
    seconds <
    60
  ) {
    return "agora";
  }

  const minutes =
    Math.floor(
      seconds /
      60
    );

  if (
    minutes <
    60
  ) {
    return `${minutes} min`;
  }

  const hours =
    Math.floor(
      minutes /
      60
    );

  if (
    hours <
    24
  ) {
    return `${hours}h`;
  }

  const days =
    Math.floor(
      hours /
      24
    );

  return `${days}d`;
}

export function NotificationCenter() {
  const router =
    useRouter();

  const {
    session,
    loading,
    request,
    subscribe
  } =
    useAuth();

  const [
    open,
    setOpen
  ] =
    useState(
      false
    );

  const [
    items,
    setItems
  ] =
    useState<
      WappNotification[]
    >([]);

  const [
    unreadCount,
    setUnreadCount
  ] =
    useState(
      0
    );

  const [
    error,
    setError
  ] =
    useState("");

  const [
    browserPermission,
    setBrowserPermission
  ] =
    useState<
      NotificationPermission
      | "unsupported"
    >(
      "unsupported"
    );

  const mountedRef =
    useRef(
      false
    );

  const load =
    useCallback(
      async () => {
        const payload =
          await request<
            NotificationPayload
          >(
            "/api/v1/notifications?limit=40"
          );

        setItems(
          payload.notifications
        );

        setUnreadCount(
          payload.unreadCount
        );

        return payload;
      },
      [
        request
      ]
    );

  const showBrowserNotification =
    useCallback(
      (
        item:
          WappNotification
      ) => {
        if (
          typeof window ===
            "undefined" ||
          typeof Notification ===
            "undefined" ||
          Notification.permission !==
            "granted" ||
          document.visibilityState ===
            "visible"
        ) {
          return;
        }

        const browserNotification =
          new Notification(
            item.title,
            {
              body:
                item.body,
              tag:
                `wapp-${item.id}`
            }
          );

        browserNotification.onclick =
          () => {
            window.focus();

            if (
              item.ticketId
            ) {
              router.push(
                `/dashboard/conversations?ticket=${item.ticketId}`
              );
            } else if (
              item.contactId
            ) {
              router.push(
                `/dashboard/contacts?contact=${item.contactId}`
              );
            }

            browserNotification.close();
          };
      },
      [
        router
      ]
    );

  useEffect(
    () => {
      mountedRef.current =
        true;

      if (
        typeof Notification !==
        "undefined"
      ) {
        setBrowserPermission(
          Notification.permission
        );
      }

      return () => {
        mountedRef.current =
          false;
      };
    },
    []
  );

  useEffect(
    () => {
      if (
        loading ||
        !session
      ) {
        return;
      }

      void load()
        .catch(() => {});

      return subscribe(
        "/api/v1/realtime/events",
        event => {
          if (
            event.type !==
              "notification.created" ||
            !event.notificationId
          ) {
            return;
          }

          void load()
            .then(
              payload => {
                const item =
                  payload.notifications.find(
                    notification =>
                      notification.id ===
                      event.notificationId
                  );

                if (
                  item
                ) {
                  showBrowserNotification(
                    item
                  );
                }
              }
            )
            .catch(() => {});
        }
      );
    },
    [
      load,
      loading,
      session,
      showBrowserNotification,
      subscribe
    ]
  );

  async function enableBrowserNotifications() {
    if (
      typeof Notification ===
      "undefined"
    ) {
      setBrowserPermission(
        "unsupported"
      );

      return;
    }

    const permission =
      await Notification.requestPermission();

    if (
      mountedRef.current
    ) {
      setBrowserPermission(
        permission
      );
    }
  }

  async function markRead(
    id: string
  ) {
    try {
      await request(
        `/api/v1/notifications/${id}/read`,
        {
          method:
            "POST"
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível atualizar a notificação."
      );
    }
  }

  async function openNotification(
    item:
      WappNotification
  ) {
    if (
      !item.readAt
    ) {
      await markRead(
        item.id
      );
    }

    setOpen(
      false
    );

    if (
      item.ticketId
    ) {
      router.push(
        `/dashboard/conversations?ticket=${item.ticketId}`
      );
    } else if (
      item.contactId
    ) {
      router.push(
        `/dashboard/contacts?contact=${item.contactId}`
      );
    }
  }

  async function markAll() {
    try {
      await request(
        "/api/v1/notifications/read-all",
        {
          method:
            "POST"
        }
      );

      await load();
    } catch (caught) {
      setError(
        caught instanceof
          ApiError
          ? caught.message
          : "Não foi possível marcar as notificações como lidas."
      );
    }
  }

  if (
    loading ||
    !session
  ) {
    return null;
  }

  return (
    <aside
      className={
        open
          ? "notification-center notification-center--open"
          : "notification-center"
      }
    >
      <button
        aria-expanded={
          open
        }
        className="notification-center__trigger"
        onClick={() => {
          setOpen(
            current =>
              !current
          );

          setError("");

          if (
            !open
          ) {
            void load()
              .catch(() => {});
          }
        }}
        type="button"
      >
        <span>
          Avisos
        </span>

        {unreadCount >
          0 && (
          <strong>
            {unreadCount >
            99
              ? "99+"
              : unreadCount}
          </strong>
        )}
      </button>

      {open && (
        <div className="notification-center__panel">
          <header>
            <div>
              <span className="eyebrow">
                Central
              </span>

              <strong>
                Notificações
              </strong>
            </div>

            {unreadCount >
              0 && (
              <button
                onClick={() =>
                  void markAll()
                }
                type="button"
              >
                Marcar todas como lidas
              </button>
            )}
          </header>

          {browserPermission !==
            "granted" && (
            <div className="notification-browser-optin">
              <div>
                <strong>
                  Alertas do navegador
                </strong>

                <span>
                  Receba avisos quando o Wapp estiver em segundo plano.
                </span>
              </div>

              <button
                disabled={
                  browserPermission ===
                    "denied" ||
                  browserPermission ===
                    "unsupported"
                }
                onClick={() =>
                  void enableBrowserNotifications()
                }
                type="button"
              >
                {browserPermission ===
                "denied"
                  ? "Bloqueado"
                  : browserPermission ===
                      "unsupported"
                    ? "Indisponível"
                    : "Ativar"}
              </button>
            </div>
          )}

          {error && (
            <div className="notification-center__error">
              {error}
            </div>
          )}

          <div className="notification-center__list">
            {items.length ===
            0 ? (
              <div className="notification-center__empty">
                Nenhum aviso por aqui.
              </div>
            ) : (
              items.map(
                item => (
                  <button
                    className={
                      item.readAt
                        ? "notification-item"
                        : "notification-item notification-item--unread"
                    }
                    key={
                      item.id
                    }
                    onClick={() =>
                      void openNotification(
                        item
                      )
                    }
                    type="button"
                  >
                    <span className="notification-item__indicator" />

                    <div className="notification-item__copy">
                      <div>
                        <strong>
                          {item.title}
                        </strong>

                        <time>
                          {relativeTime(
                            item.updatedAt
                          )}
                        </time>
                      </div>

                      <p>
                        {item.body}
                      </p>

                      {item.occurrenceCount >
                        1 && (
                        <small>
                          {item.occurrenceCount} ocorrências nesta conversa
                        </small>
                      )}
                    </div>
                  </button>
                )
              )
            )}
          </div>
        </div>
      )}
    </aside>
  );
}
