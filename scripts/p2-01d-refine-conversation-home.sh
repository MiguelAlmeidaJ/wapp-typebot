#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PAGE="apps/web/app/dashboard/conversations/page.tsx"
CSS="apps/web/app/globals.css"

echo "[P2.1d] Refining the conversations home..."

for required in "$PAGE" "$CSS"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -Fq -- 'className="conversation-home"' "$PAGE"; then
  echo "ERROR: P2.1b conversation home was not found."
  echo "Inspect the current page before applying this refinement."
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const startMarker = `          {!selectedTicket ? (
            <div className="conversation-home">`;

const endMarker = `            </div>
          ) : (`;

const start =
  content.indexOf(
    startMarker
  );

if (start < 0) {
  if (
    content.includes(
      'className="conversation-home conversation-home--refined"'
    )
  ) {
    console.log(
      "Refined conversation home already present."
    );

    process.exit(0);
  }

  throw new Error(
    "Conversation home start marker not found."
  );
}

const end =
  content.indexOf(
    endMarker,
    start
  );

if (end < 0) {
  throw new Error(
    "Conversation home end marker not found."
  );
}

const replacement = `          {!selectedTicket ? (
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
                      ? \`\${pendingCount} conversa\${pendingCount === 1 ? "" : "s"} aguardando atendimento.\`
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
          ) : (`;

content =
  content.slice(
    0,
    start
  ) +
  replacement +
  content.slice(
    end +
      endMarker.length
  );

fs.writeFileSync(
  path,
  content
);

console.log(
  "Conversation home JSX refined."
);
NODE

if ! grep -Fq -- "WAPP P2.1d / REFINED CONVERSATION HOME" "$CSS"; then
  cat >> "$CSS" <<'EOF'

/* --- WAPP P2.1d / REFINED CONVERSATION HOME --------------------------- */

.conversation-home--refined {
  padding: 30px 34px 34px;
  background:
    linear-gradient(
      180deg,
      rgba(247, 249, 247, 0.96),
      rgba(250, 251, 250, 1)
    );
}

.conversation-home--refined::-webkit-scrollbar {
  width: 7px;
}

.conversation-home--refined::-webkit-scrollbar-thumb {
  border-radius: 999px;
  background: rgba(17, 31, 23, 0.18);
}

.conversation-home-top {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 28px;
  padding: 0 2px 22px;
  border-bottom: 1px solid var(--line);
}

.conversation-home-top__copy {
  min-width: 0;
}

.conversation-home-top__copy h2 {
  margin: 7px 0 7px;
  font-size: clamp(25px, 2.2vw, 32px);
  font-weight: 680;
  letter-spacing: -0.045em;
}

.conversation-home-top__copy p {
  max-width: 600px;
  margin: 0;
  color: var(--muted);
  font-size: 12px;
  line-height: 1.5;
}

.conversation-home-summary {
  display: flex;
  flex: 0 0 auto;
  align-items: center;
  gap: 8px;
}

.conversation-home-summary > div {
  display: grid;
  min-width: 105px;
  gap: 1px;
  border-left: 1px solid var(--line);
  padding: 2px 0 2px 15px;
}

.conversation-home-summary > div:first-child {
  border-left: 0;
}

.conversation-home-summary strong {
  font-size: 21px;
  font-weight: 700;
  letter-spacing: -0.04em;
}

.conversation-home-summary span {
  color: var(--muted);
  font-size: 9px;
  white-space: nowrap;
}

.conversation-home-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.65fr) minmax(255px, 0.75fr);
  gap: 16px;
  align-items: start;
  margin-top: 18px;
}

.conversation-focus-card,
.conversation-overview-card {
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.86);
}

.conversation-section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 15px 17px;
  border-bottom: 1px solid var(--line);
}

.conversation-section-header--compact {
  padding-bottom: 13px;
}

.conversation-section-header > div {
  display: grid;
  gap: 2px;
}

.conversation-section-kicker {
  color: var(--accent-dark);
  font-size: 8px;
  font-weight: 850;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.conversation-section-header h3 {
  margin: 0;
  font-size: 13px;
  font-weight: 720;
  letter-spacing: -0.02em;
}

.conversation-section-count,
.conversation-online-dot {
  display: grid;
  min-width: 27px;
  height: 25px;
  place-items: center;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 0 8px;
  font-size: 10px;
  font-weight: 850;
}

.conversation-priority-list {
  display: grid;
}

.conversation-priority-item {
  display: grid;
  grid-template-columns: 36px minmax(0, 1fr) auto;
  align-items: center;
  gap: 12px;
  width: 100%;
  min-width: 0;
  border: 0;
  border-bottom: 1px solid #edf0ed;
  background: transparent;
  padding: 12px 16px;
  text-align: left;
}

.conversation-priority-item:last-child {
  border-bottom: 0;
}

.conversation-priority-item:hover {
  background: #f7faf8;
}

.conversation-priority-item__content {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.conversation-priority-item__content > div {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.conversation-priority-item__content strong {
  overflow: hidden;
  font-size: 11px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.conversation-priority-item__content time {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 8px;
}

.conversation-priority-item__content p {
  overflow: hidden;
  margin: 0;
  color: #536057;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.conversation-priority-item__content > span {
  color: var(--muted);
  font-size: 8px;
}

.conversation-priority-item__action {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  height: 27px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: white;
  color: var(--ink);
  padding: 0 10px;
  font-size: 9px;
  font-weight: 750;
}

.conversation-priority-item:hover
  .conversation-priority-item__action {
  border-color: rgba(31, 122, 80, 0.3);
  color: var(--accent-dark);
}

.conversation-priority-empty {
  display: grid;
  place-items: center;
  padding: 45px 20px;
  text-align: center;
}

.conversation-priority-empty > div {
  display: grid;
  width: 34px;
  height: 34px;
  place-items: center;
  margin-bottom: 10px;
  border-radius: 50%;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 14px;
  font-weight: 850;
}

.conversation-priority-empty strong {
  font-size: 12px;
}

.conversation-priority-empty p {
  max-width: 290px;
  margin: 5px 0 0;
  color: var(--muted);
  font-size: 10px;
  line-height: 1.5;
}

.conversation-home-side {
  display: grid;
  gap: 12px;
}

.conversation-queue-overview {
  display: grid;
  padding: 4px 15px 10px;
}

.conversation-queue-overview > div {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  min-width: 0;
  border-bottom: 1px solid #eef0ee;
  padding: 9px 1px;
}

.conversation-queue-overview > div:last-child {
  border-bottom: 0;
}

.conversation-queue-overview span {
  overflow: hidden;
  color: #4e5b52;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.conversation-queue-overview strong {
  flex: 0 0 auto;
  font-size: 11px;
}

.conversation-team-online {
  display: grid;
  padding: 6px 15px 12px;
}

.conversation-team-online > div:not(.conversation-team-empty) {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 6px 0;
}

.conversation-team-avatar {
  display: grid;
  width: 28px;
  height: 28px;
  flex: 0 0 28px;
  place-items: center;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-size: 9px;
  font-weight: 850;
}

.conversation-team-online > div > div {
  display: grid;
  min-width: 0;
  gap: 1px;
}

.conversation-team-online strong {
  overflow: hidden;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.conversation-team-online > div > div > span {
  color: var(--muted);
  font-size: 8px;
}

.conversation-team-empty {
  color: var(--muted);
  padding: 16px 0;
  font-size: 10px;
  line-height: 1.45;
}

.conversation-overview-note {
  display: flex;
  align-items: center;
  gap: 11px;
  border: 1px solid rgba(31, 122, 80, 0.14);
  border-radius: 12px;
  background: rgba(31, 122, 80, 0.055);
  padding: 12px 14px;
}

.conversation-overview-note > span {
  font-size: 20px;
  font-weight: 720;
  letter-spacing: -0.04em;
}

.conversation-overview-note p {
  margin: 0;
  color: #536057;
  font-size: 9px;
  line-height: 1.4;
}

@media (max-width: 1180px) {
  .conversation-home-top {
    align-items: flex-start;
    flex-direction: column;
    gap: 15px;
  }

  .conversation-home-summary {
    width: 100%;
  }

  .conversation-home-summary > div {
    flex: 1 1 0;
  }

  .conversation-home-grid {
    grid-template-columns: 1fr;
  }

  .conversation-home-side {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .conversation-overview-note {
    grid-column: 1 / -1;
  }
}

@media (max-width: 760px) {
  .conversation-home--refined {
    padding: 20px 14px 24px;
  }

  .conversation-home-summary {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  .conversation-home-summary > div {
    min-width: 0;
    border-left: 0;
    padding: 0;
  }

  .conversation-home-side {
    grid-template-columns: 1fr;
  }

  .conversation-overview-note {
    grid-column: auto;
  }

  .conversation-priority-item {
    grid-template-columns: 34px minmax(0, 1fr);
  }

  .conversation-priority-item__action {
    display: none;
  }
}

/* --- /WAPP P2.1d ------------------------------------------------------ */
EOF
fi

echo "[P2.1d] Typechecking Web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P2.1d] Conversation home refinement installed."
echo "No API or database change."
