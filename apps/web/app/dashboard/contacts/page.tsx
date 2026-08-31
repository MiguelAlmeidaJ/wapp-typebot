"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ContactCrmPanel } from "@/components/contacts/contact-crm-panel";
import { ContactPipelineSummary } from "@/components/contacts/contact-pipeline-summary";
import { ContactTasksPanel } from "@/components/contacts/contact-tasks-panel";
import { ContactCampaignConsent } from "@/components/contacts/contact-campaign-consent";
import { ApiError } from "@/lib/api";

type ContactFilter =
  | "ALL"
  | "PEOPLE"
  | "GROUPS";

interface TicketSummary {
  id: string;
  status: "OPEN" | "PENDING" | "CLOSED";
  lastMessage: string | null;
  lastMessageAt: string;
  whatsappConnection: {
    id: string;
    name: string;
  };
}

interface ContactSummary {
  id: string;
  name: string;
  whatsappName: string | null;
  email: string | null;
  phoneNumber: string | null;
  remoteJid: string;
  isGroup: boolean;
  lastSeenAt: string | null;
  updatedAt: string;
  _count: {
    tickets: number;
  };
  tickets: TicketSummary[];
}

interface ContactDetail {
  id: string;
  name: string;
  whatsappName: string | null;
  email: string | null;
  notes: string | null;
  phoneNumber: string | null;
  remoteJid: string;
  isGroup: boolean;
  lastSeenAt: string | null;
  createdAt: string;
  updatedAt: string;
  tickets: Array<{
    id: string;
    status: "OPEN" | "PENDING" | "CLOSED";
    lastMessage: string | null;
    lastMessageAt: string;
    closedAt: string | null;
    queue: {
      id: string;
      name: string;
    } | null;
    assignedMembership: {
      id: string;
      user: {
        id: string;
        name: string;
      };
    } | null;
    whatsappConnection: {
      id: string;
      name: string;
      phoneNumber: string | null;
    };
  }>;
}

interface ContactStats {
  ticketCount: number;
  openTicketCount: number;
  messageCount: number;
}

interface ContactsResponse {
  contacts: ContactSummary[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    pages: number;
  };
}

function dateLabel(value: string | null) {
  if (!value) {
    return "—";
  }

  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function initials(name: string) {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map(part =>
      part.slice(0, 1).toUpperCase()
    )
    .join("");
}

export default function ContactsPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const targetContactId =
    searchParams.get(
      "contact"
    );
  const {
    session,
    loading,
    request
  } = useAuth();

  const [contacts, setContacts] = useState<
    ContactSummary[]
  >([]);
  const [pagination, setPagination] =
    useState<ContactsResponse["pagination"]>({
      page: 1,
      limit: 30,
      total: 0,
      pages: 1
    });

  const [search, setSearch] = useState("");
  const [filter, setFilter] =
    useState<ContactFilter>("PEOPLE");
  const [page, setPage] = useState(1);

  const [selectedId, setSelectedId] =
    useState<string | null>(null);
  const [detail, setDetail] =
    useState<ContactDetail | null>(null);
  const [stats, setStats] =
    useState<ContactStats | null>(null);

  const [editName, setEditName] = useState("");
  const [editEmail, setEditEmail] = useState("");
  const [editNotes, setEditNotes] = useState("");

  const [loadingList, setLoadingList] =
    useState(false);
  const [loadingDetail, setLoadingDetail] =
    useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const loadContacts = useCallback(async () => {
    setLoadingList(true);

    try {
      const params = new URLSearchParams({
        type: filter,
        page: String(page),
        limit: "30"
      });

      if (search.trim()) {
        params.set("search", search.trim());
      }

      const payload =
        await request<ContactsResponse>(
          `/api/v1/contacts?${params.toString()}`
        );

      setContacts(payload.contacts);
      setPagination(payload.pagination);

      setSelectedId(current => {
        if (
          targetContactId
        ) {
          return targetContactId;
        }

        if (
          current &&
          payload.contacts.some(
            contact => contact.id === current
          )
        ) {
          return current;
        }

        return payload.contacts[0]?.id ?? null;
      });
    } catch {
      setError(
        "Não foi possível carregar os contatos."
      );
    } finally {
      setLoadingList(false);
    }
  }, [filter, page, request, search, targetContactId]);

  const loadDetail = useCallback(
    async (contactId: string) => {
      setLoadingDetail(true);

      try {
        const payload = await request<{
          contact: ContactDetail;
          stats: ContactStats;
        }>(
          `/api/v1/contacts/${contactId}`
        );

        setDetail(payload.contact);
        setStats(payload.stats);
        setEditName(payload.contact.name);
        setEditEmail(
          payload.contact.email ?? ""
        );
        setEditNotes(
          payload.contact.notes ?? ""
        );
      } catch {
        setError(
          "Não foi possível carregar o contato."
        );
      } finally {
        setLoadingDetail(false);
      }
    },
    [request]
  );

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
    }
  }, [loading, router, session]);

  useEffect(() => {
    if (!session) {
      return;
    }

    const timer = window.setTimeout(() => {
      void loadContacts();
    }, 250);

    return () => window.clearTimeout(timer);
  }, [loadContacts, session]);

  useEffect(() => {
    if (
      targetContactId &&
      detail?.id ===
        targetContactId
    ) {
      router.replace(
        "/dashboard/contacts",
        {
          scroll:
            false
        }
      );
    }
  }, [
    detail?.id,
    router,
    targetContactId
  ]);

  useEffect(() => {
    if (!selectedId) {
      setDetail(null);
      setStats(null);
      return;
    }

    void loadDetail(selectedId);
  }, [loadDetail, selectedId]);

  async function saveContact(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!detail) {
      return;
    }

    setSaving(true);
    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/contacts/${detail.id}`,
        {
          method: "PATCH",
          body: JSON.stringify({
            name: editName,
            email:
              editEmail.trim() || null,
            notes:
              editNotes.trim() || null
          })
        }
      );

      setNotice("Contato atualizado.");

      await Promise.all([
        loadContacts(),
        loadDetail(detail.id)
      ]);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível salvar o contato."
      );
    } finally {
      setSaving(false);
    }
  }

  if (loading || !session) {
    return (
      <main className="dashboard-loading">
        Carregando contatos…
      </main>
    );
  }

  return (
    <main className="contacts-screen">
      <header className="contacts-header">
        <div>
          <button
            className="connections-back"
            onClick={() =>
              router.push("/dashboard")
            }
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">
            Relacionamento
          </span>
          <h1>Contatos</h1>
          <p>
            Pessoas e grupos que já interagiram
            com os canais da empresa.
          </p>
        </div>

        <button
          className="ghost-button"
          onClick={() =>
            router.push(
              "/dashboard/conversations"
            )
          }
          type="button"
        >
          Conversas
        </button>
      </header>

      {error && (
        <div className="contacts-feedback contacts-feedback--error">
          {error}
        </div>
      )}

      {notice && (
        <div className="contacts-feedback">
          {notice}
        </div>
      )}

      <section className="contacts-toolbar">
        <input
          onChange={event => {
            setSearch(event.target.value);
            setPage(1);
          }}
          placeholder="Buscar por nome, número ou e-mail…"
          value={search}
        />

        <div className="contacts-filter">
          {(
            [
              ["PEOPLE", "Pessoas"],
              ["GROUPS", "Grupos"],
              ["ALL", "Todos"]
            ] as const
          ).map(([value, label]) => (
            <button
              className={
                filter === value
                  ? "contacts-filter__button contacts-filter__button--active"
                  : "contacts-filter__button"
              }
              key={value}
              onClick={() => {
                setFilter(value);
                setPage(1);
              }}
              type="button"
            >
              {label}
            </button>
          ))}
        </div>

        <span className="contacts-total">
          {pagination.total} registros
        </span>
      </section>

      <section className="contacts-workspace">
        <aside className="contacts-list">
          {loadingList ? (
            <div className="contacts-empty">
              Carregando…
            </div>
          ) : contacts.length === 0 ? (
            <div className="contacts-empty">
              Nenhum contato encontrado.
            </div>
          ) : (
            contacts.map(contact => (
              <button
                className={
                  selectedId === contact.id
                    ? "contact-row contact-row--active"
                    : "contact-row"
                }
                key={contact.id}
                onClick={() =>
                  setSelectedId(contact.id)
                }
                type="button"
              >
                <div className="contact-row__avatar">
                  {initials(contact.name)}
                </div>

                <div className="contact-row__copy">
                  <strong>{contact.name}</strong>
                  <span>
                    {contact.phoneNumber ??
                      contact.remoteJid}
                  </span>
                  <small>
                    {contact._count.tickets}
                    {" "}
                    atendimento(s)
                  </small>
                </div>

                <div className="contact-row__meta">
                  {contact.isGroup && (
                    <span>Grupo</span>
                  )}
                  <time>
                    {dateLabel(
                      contact.lastSeenAt
                    )}
                  </time>
                </div>
              </button>
            ))
          )}

          {pagination.pages > 1 && (
            <div className="contacts-pagination">
              <button
                className="ghost-button"
                disabled={page <= 1}
                onClick={() =>
                  setPage(current =>
                    Math.max(1, current - 1)
                  )
                }
                type="button"
              >
                Anterior
              </button>

              <span>
                {pagination.page} /{" "}
                {pagination.pages}
              </span>

              <button
                className="ghost-button"
                disabled={
                  page >= pagination.pages
                }
                onClick={() =>
                  setPage(current =>
                    Math.min(
                      pagination.pages,
                      current + 1
                    )
                  )
                }
                type="button"
              >
                Próxima
              </button>
            </div>
          )}
        </aside>

        <section className="contact-profile">
          {!selectedId ? (
            <div className="contact-profile__empty">
              Selecione um contato.
            </div>
          ) : loadingDetail || !detail ? (
            <div className="contact-profile__empty">
              Carregando ficha…
            </div>
          ) : (
            <>
              <header className="contact-profile__header">
                <div className="contact-profile__identity">
                  <div className="contact-profile__avatar">
                    {initials(detail.name)}
                  </div>
                  <div>
                    <span className="eyebrow">
                      {detail.isGroup
                        ? "Grupo"
                        : "Contato"}
                    </span>
                    <h2>{detail.name}</h2>
                    <p>
                      {detail.phoneNumber ??
                        detail.remoteJid}
                    </p>
                  </div>
                </div>

                {detail.whatsappName &&
                  detail.whatsappName !==
                    detail.name && (
                    <span className="contact-profile__whatsapp-name">
                      WhatsApp:{" "}
                      {detail.whatsappName}
                    </span>
                  )}
              </header>

              <div className="contact-stats">
                <article>
                  <strong>
                    {stats?.ticketCount ?? 0}
                  </strong>
                  <span>Atendimentos</span>
                </article>
                <article>
                  <strong>
                    {stats?.openTicketCount ?? 0}
                  </strong>
                  <span>Ativos</span>
                </article>
                <article>
                  <strong>
                    {stats?.messageCount ?? 0}
                  </strong>
                  <span>Mensagens</span>
                </article>
              </div>

              <form
                className="contact-form"
                onSubmit={saveContact}
              >
                <div className="contact-form__grid">
                  <label className="field">
                    <span>Nome no Wapp</span>
                    <input
                      maxLength={190}
                      onChange={event =>
                        setEditName(
                          event.target.value
                        )
                      }
                      required
                      value={editName}
                    />
                  </label>

                  <label className="field">
                    <span>E-mail</span>
                    <input
                      maxLength={190}
                      onChange={event =>
                        setEditEmail(
                          event.target.value
                        )
                      }
                      placeholder="Opcional"
                      type="email"
                      value={editEmail}
                    />
                  </label>
                </div>

                <label className="field">
                  <span>Anotações</span>
                  <textarea
                    maxLength={10_000}
                    onChange={event =>
                      setEditNotes(
                        event.target.value
                      )
                    }
                    placeholder="Contexto importante sobre este contato…"
                    rows={4}
                    value={editNotes}
                  />
                </label>

                <div className="contact-form__footer">
                  <div>
                    <span>
                      Última interação
                    </span>
                    <strong>
                      {dateLabel(
                        detail.lastSeenAt
                      )}
                    </strong>
                  </div>

                  <button
                    className="primary-button"
                    disabled={saving}
                    type="submit"
                  >
                    <span>
                      {saving
                        ? "Salvando…"
                        : "Salvar contato"}
                    </span>
                    <span>→</span>
                  </button>
                </div>
              </form>

              <ContactCampaignConsent
                contactId={
                  detail.id
                }
              />

              <ContactTasksPanel
                contactId={
                  detail.id
                }
                contactName={
                  detail.name
                }
              />

              <ContactPipelineSummary
                contactId={
                  detail.id
                }
              />

              <ContactCrmPanel
                contactId={
                  detail.id
                }
                contactName={
                  detail.name
                }
              />

              <section className="contact-history">
                <div className="contact-history__heading">
                  <span className="eyebrow">
                    Histórico
                  </span>
                  <h3>Atendimentos recentes</h3>
                </div>

                {detail.tickets.length === 0 ? (
                  <p className="contact-history__empty">
                    Nenhum atendimento registrado.
                  </p>
                ) : (
                  <div className="contact-history__list">
                    {detail.tickets.map(ticket => (
                      <article
                        className="contact-ticket"
                        key={ticket.id}
                      >
                        <div>
                          <strong>
                            {ticket.lastMessage ??
                              "Atendimento"}
                          </strong>
                          <span>
                            {ticket.whatsappConnection.name}
                            {" · "}
                            {ticket.queue?.name ??
                              "Sem fila"}
                          </span>
                        </div>

                        <div className="contact-ticket__right">
                          <span
                            className={`contact-ticket__status contact-ticket__status--${ticket.status.toLowerCase()}`}
                          >
                            {ticket.status}
                          </span>
                          <time>
                            {dateLabel(
                              ticket.lastMessageAt
                            )}
                          </time>
                        </div>
                      </article>
                    ))}
                  </div>
                )}
              </section>
            </>
          )}
        </section>
      </section>
    </main>
  );
}
