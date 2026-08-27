#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.6] Building internal ticket notes..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/modules/tickets/ticket.routes.ts" \
  "apps/api/src/modules/tickets/ticket.service.ts" \
  "apps/api/src/modules/realtime/realtime.bus.ts" \
  "apps/web/lib/realtime-types.ts" \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Prisma: immutable internal notes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

if (!schema.includes("ticketNotes")) {
  schema = schema.replace(
    `  messages            Message[]
  queues              Queue[]`,
    `  messages            Message[]
  ticketNotes         TicketNote[]
  queues              Queue[]`
  );

  schema = schema.replace(
    `  assignedTickets  Ticket[]
  createdAt        DateTime`,
    `  assignedTickets  Ticket[]
  ticketNotes       TicketNote[]
  createdAt        DateTime`
  );

  schema = schema.replace(
    `  messages             Message[]
  createdAt            DateTime`,
    `  messages             Message[]
  notes                TicketNote[]
  createdAt            DateTime`
  );
}

if (!schema.includes("model TicketNote {")) {
  const anchor = `model Message {`;

  if (!schema.includes(anchor)) {
    throw new Error("Message model anchor not found.");
  }

  const model = `model TicketNote {
  id                 String            @id @default(uuid()) @db.Char(36)
  companyId          String            @db.Char(36)
  ticketId           String            @db.Char(36)
  authorMembershipId String            @db.Char(36)
  body               String            @db.Text
  company            Company           @relation(fields: [companyId], references: [id], onDelete: Cascade)
  ticket             Ticket            @relation(fields: [ticketId], references: [id], onDelete: Cascade)
  authorMembership   CompanyMembership @relation(fields: [authorMembershipId], references: [id], onDelete: Restrict)
  createdAt          DateTime          @default(now())

  @@index([ticketId, createdAt])
  @@index([companyId, createdAt])
  @@index([authorMembershipId, createdAt])
}

`;

  schema = schema.replace(
    anchor,
    `${model}${anchor}`
  );
}

fs.writeFileSync(path, schema);
console.log("TicketNote schema installed.");
NODE

# ---------------------------------------------------------------------------
# Ticket service
# ---------------------------------------------------------------------------

cat >> apps/api/src/modules/tickets/ticket.service.ts <<'EOF'

export async function listTicketNotes(
  companyId: string,
  ticketId: string
) {
  await getTicket(companyId, ticketId);

  return prisma.ticketNote.findMany({
    where: {
      companyId,
      ticketId
    },
    include: {
      authorMembership: {
        select: {
          id: true,
          role: true,
          user: {
            select: {
              id: true,
              name: true,
              email: true
            }
          }
        }
      }
    },
    orderBy: {
      createdAt: "asc"
    },
    take: 200
  });
}

export async function createTicketNote(input: {
  companyId: string;
  ticketId: string;
  authorMembershipId: string;
  role: WappRole;
  body: string;
}) {
  const ticket = await getTicket(
    input.companyId,
    input.ticketId
  );

  assertCanOperateTicket(
    ticket.assignedMembershipId,
    input.authorMembershipId,
    input.role
  );

  const membership =
    await validateMembership(
      input.companyId,
      input.authorMembershipId
    );

  const note = await prisma.ticketNote.create({
    data: {
      companyId: input.companyId,
      ticketId: input.ticketId,
      authorMembershipId: membership.id,
      body: input.body.trim()
    },
    include: {
      authorMembership: {
        select: {
          id: true,
          role: true,
          user: {
            select: {
              id: true,
              name: true,
              email: true
            }
          }
        }
      }
    }
  });

  publishRealtime(input.companyId, {
    type: "note.created",
    ticketId: input.ticketId,
    noteId: note.id
  });

  return note;
}
EOF

# Avoid duplicate append if script is re-run after a previous partial execution.
node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content = fs.readFileSync(path, "utf8");

const marker =
  "export async function listTicketNotes(";

const first = content.indexOf(marker);
const second =
  first >= 0
    ? content.indexOf(marker, first + marker.length)
    : -1;

if (second >= 0) {
  content = content.slice(0, second).trimEnd() + "\n";
  fs.writeFileSync(path, content);
  console.log("Removed duplicate TicketNote service append.");
}
NODE

# ---------------------------------------------------------------------------
# Ticket routes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.routes.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("createTicketNote,")) {
  content = content.replace(
    `  claimTicket,
  closeTicket,`,
    `  claimTicket,
  closeTicket,
  createTicketNote,`
  );
}

if (!content.includes("listTicketNotes,")) {
  content = content.replace(
    `  listTicketMessages,
  listTickets,`,
    `  listTicketMessages,
  listTicketNotes,
  listTickets,`
  );
}

if (!content.includes("const createNoteSchema")) {
  const anchor = `const sendTextSchema = z.object({
  text: z.string().trim().min(1).max(4096)
});`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find sendTextSchema anchor."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

const createNoteSchema = z.object({
  body: z.string().trim().min(1).max(10_000)
});`
  );
}

if (
  !content.includes(
    '"/api/v1/tickets/:id/notes"'
  )
) {
  const anchor = `  app.get(
    "/api/v1/tickets/:id/messages",`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticket messages route anchor."
    );
  }

  const routes = `  app.get(
    "/api/v1/tickets/:id/notes",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);

      return {
        notes: await listTicketNotes(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/tickets/:id/notes",
    async request => {
      const auth = await requireAuth(request);
      const params = ticketIdSchema.parse(request.params);
      const input = createNoteSchema.parse(request.body);

      return {
        note: await createTicketNote({
          companyId: auth.companyId,
          ticketId: params.id,
          authorMembershipId: auth.membershipId,
          role: auth.role,
          body: input.body
        })
      };
    }
  );

`;

  content = content.replace(
    anchor,
    `${routes}${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Ticket note routes installed.");
NODE

# ---------------------------------------------------------------------------
# Realtime note.created
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

for (const path of [
  "apps/api/src/modules/realtime/realtime.bus.ts",
  "apps/web/lib/realtime-types.ts"
]) {
  let content = fs.readFileSync(path, "utf8");

  if (
    content.includes('| "message.updated"') &&
    !content.includes('| "note.created"')
  ) {
    content = content.replace(
      '| "message.updated"',
      '| "message.updated"\n  | "note.created"'
    );
  }

  if (
    content.includes("messageId?: string;") &&
    !content.includes("noteId?: string;")
  ) {
    content = content.replace(
      "messageId?: string;",
      "messageId?: string;\n  noteId?: string;"
    );
  }

  fs.writeFileSync(path, content);
}

console.log("Realtime note.created installed.");
NODE

# ---------------------------------------------------------------------------
# Frontend state/types/API
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("interface TicketNote {")) {
  const anchor = `interface QueueOption {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find QueueOption interface anchor."
    );
  }

  const types = `interface TicketNote {
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

`;

  content = content.replace(
    anchor,
    `${types}${anchor}`
  );
}

if (!content.includes("const [notes, setNotes]")) {
  const anchor =
    '  const [messages, setMessages] = useState<Message[]>([]);';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find messages state."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [notes, setNotes] = useState<TicketNote[]>([]);
  const [notesOpen, setNotesOpen] = useState(false);
  const [noteText, setNoteText] = useState("");
  const [savingNote, setSavingNote] = useState(false);`
  );
}

if (!content.includes("const loadNotes = useCallback(")) {
  const anchor = `  const loadMessages = useCallback(
    async (ticketId: string) => {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find loadMessages callback."
    );
  }

  const callback = `  const loadNotes = useCallback(
    async (ticketId: string) => {
      const payload = await request<NotesResponse>(
        \`/api/v1/tickets/\${ticketId}/notes\`
      );

      setNotes(payload.notes);
    },
    [request]
  );

`;

  content = content.replace(
    anchor,
    `${callback}${anchor}`
  );
}

/*
 * Selected ticket effect: load notes alongside messages.
 */
const oldSelectedEffect = `    void loadMessages(selectedId).catch(() => {
      setError("Não foi possível carregar as mensagens.");
    });
  }, [loadMessages, selectedId]);`;

const newSelectedEffect = `    void Promise.all([
      loadMessages(selectedId),
      loadNotes(selectedId)
    ]).catch(() => {
      setError(
        "Não foi possível carregar o atendimento."
      );
    });
  }, [loadMessages, loadNotes, selectedId]);`;

if (content.includes(oldSelectedEffect)) {
  content = content.replace(
    oldSelectedEffect,
    newSelectedEffect
  );
}

/*
 * Clear note state when no ticket.
 */
content = content.replace(
  `    if (!selectedId) {
      setMessages([]);
      return;
    }`,
  `    if (!selectedId) {
      setMessages([]);
      setNotes([]);
      setNotesOpen(false);
      return;
    }`
);

/*
 * Realtime note.created.
 */
if (
  content.includes('event.type === "message.created"') &&
  !content.includes('event.type === "note.created"')
) {
  const anchor = `      if (event.type === "queue.updated") {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find realtime queue block."
    );
  }

  const realtime = `      if (
        event.type === "note.created" &&
        selectedId &&
        (!event.ticketId ||
          event.ticketId === selectedId)
      ) {
        void loadNotes(selectedId);
      }

`;

  content = content.replace(
    anchor,
    `${realtime}${anchor}`
  );

  /*
   * Ensure hook dependency.
   */
  content = content.replace(
    `    loadMessages,
    loadReferenceData,`,
    `    loadMessages,
    loadNotes,
    loadReferenceData,`
  );
}

/*
 * Create note handler.
 */
if (!content.includes("async function handleCreateNote(")) {
  const anchor =
    "  async function handleClaim() {";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find handleClaim anchor."
    );
  }

  const handler = `  async function handleCreateNote(
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
        \`/api/v1/tickets/\${selectedId}/notes\`,
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

`;

  content = content.replace(
    anchor,
    `${handler}${anchor}`
  );
}

/*
 * Add notes button immediately after transfer button.
 */
if (!content.includes('className="ticket-notes-toggle"')) {
  const transferButton = `                <button
                  className="secondary-button"
                  disabled={transferring}
                  onClick={handleTransfer}
                  type="button"
                >
                  {transferring ? "Transferindo…" : "Aplicar transferência"}
                </button>`;

  if (!content.includes(transferButton)) {
    throw new Error(
      "Could not find transfer button."
    );
  }

  content = content.replace(
    transferButton,
    `${transferButton}

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
                </button>`
  );
}

/*
 * Drawer inside conversation-body, absolute so it never changes the
 * stable message/composer grid.
 */
if (!content.includes('className="ticket-notes-drawer"')) {
  const anchor = `              <div className="conversation-body">
                <div className="conversation-scroll">`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find canonical conversation-body anchor."
    );
  }

  const drawer = `              <div className="conversation-body">
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

                <div className="conversation-scroll">`;

  content = content.replace(
    anchor,
    drawer
  );
}

fs.writeFileSync(path, content);
console.log("Internal notes UI installed.");
NODE

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.6 / Internal ticket notes" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.6 / Internal ticket notes -------------------------------- */

.conversation-body {
  position: relative;
}

.ticket-notes-toggle {
  display: inline-flex;
  min-height: 40px;
  align-items: center;
  justify-content: center;
  gap: 7px;
  border: 1px solid var(--line);
  border-radius: 11px;
  background: #fff;
  color: var(--ink);
  padding: 0 12px;
  font-size: 10px;
  font-weight: 750;
}

.ticket-notes-toggle:hover {
  border-color: var(--line-strong);
  background: var(--surface-subtle);
}

.ticket-notes-toggle > span {
  display: grid;
  min-width: 18px;
  height: 18px;
  place-items: center;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 0 5px;
  font-size: 8px;
}

.ticket-notes-drawer {
  position: absolute;
  z-index: 30;
  top: 0;
  right: 0;
  bottom: 0;
  display: grid;
  width: min(390px, 88%);
  min-height: 0;
  grid-template-rows: auto minmax(0, 1fr) auto;
  border-left: 1px solid var(--line);
  background: #fbfcfa;
  box-shadow: -18px 0 38px rgba(26, 35, 29, 0.08);
}

.ticket-notes-drawer__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  border-bottom: 1px solid var(--line);
  padding: 18px;
}

.ticket-notes-drawer__header > div {
  display: grid;
  gap: 4px;
}

.ticket-notes-drawer__header strong {
  font-size: 15px;
}

.ticket-notes-drawer__header small {
  color: var(--muted);
  font-size: 9px;
}

.ticket-notes-drawer__header > button {
  display: grid;
  width: 30px;
  height: 30px;
  place-items: center;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--muted);
  font-size: 21px;
}

.ticket-notes-drawer__header > button:hover {
  background: #e8ece9;
  color: var(--ink);
}

.ticket-notes-list {
  min-height: 0;
  overflow-y: auto;
  padding: 14px;
}

.ticket-notes-empty {
  display: grid;
  min-height: 180px;
  place-items: center;
  color: var(--muted);
  padding: 24px;
  text-align: center;
  font-size: 10px;
  line-height: 1.6;
}

.ticket-note {
  display: grid;
  gap: 7px;
  margin-bottom: 10px;
  border: 1px solid #e6dfbf;
  border-radius: 12px;
  background: #fffdf2;
  padding: 11px 12px;
}

.ticket-note__meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.ticket-note__meta strong {
  font-size: 9px;
}

.ticket-note__meta span {
  color: #918a70;
  font-size: 8px;
}

.ticket-note p {
  margin: 0;
  color: #39372d;
  font-size: 10px;
  line-height: 1.55;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.ticket-note-form {
  display: grid;
  gap: 9px;
  border-top: 1px solid var(--line);
  background: #fff;
  padding: 12px;
}

.ticket-note-form textarea {
  width: 100%;
  resize: vertical;
  border: 1px solid var(--line);
  border-radius: 11px;
  outline: none;
  background: var(--surface-subtle);
  padding: 10px 11px;
  font: inherit;
  font-size: 10px;
  line-height: 1.5;
}

.ticket-note-form textarea:focus {
  border-color: var(--accent);
  background: #fff;
}

.ticket-note-form .primary-button {
  width: 100%;
  height: 40px;
  margin: 0;
}

@media (max-width: 680px) {
  .ticket-notes-drawer {
    width: 100%;
    border-left: 0;
  }

  .ticket-notes-toggle {
    min-height: 36px;
    padding: 0 9px;
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

cat > docs/INTERNAL_NOTES.md <<'EOF'
# Internal ticket notes

P1.6 adds an internal collaboration timeline to each ticket.

Internal notes are not WhatsApp messages.

They:

- are never sent to the customer;
- do not modify `Ticket.lastMessage`;
- are stored separately from `Message`;
- record the author's company membership;
- are visible to the company team;
- update other open Wapp sessions through realtime.

## Model

```text
Ticket
  |
  +-- TicketNote
        |
        +-- authorMembership
        +-- body
        +-- createdAt
```

Notes are append-only in P1.6. There is intentionally no edit/delete endpoint
yet, preserving a simple operational audit trail.

## Authorization

Reading notes requires access to the company ticket.

Creating a note uses the same assignment protection as ticket operations:
an AGENT cannot add a note to a ticket assigned to another agent, while
OWNER/ADMIN/SUPERVISOR retain override capability.

Creating a note does not automatically claim an unassigned ticket.

## Realtime

Creation publishes:

`note.created`

with `ticketId` and `noteId`.

The drawer refreshes when another operator adds a note to the selected ticket.
EOF

echo "[P1.6] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.6] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.6] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.6] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.6] Internal ticket notes installed."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name internal_ticket_notes"
echo "  pnpm dev"
echo
echo "Test with two users/tabs:"
echo "  1. open the same ticket"
echo "  2. click Notas"
echo "  3. add an internal note"
echo "  4. confirm it appears in the other session without refresh"
