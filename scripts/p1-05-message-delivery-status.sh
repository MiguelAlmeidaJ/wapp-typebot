#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.5] Building outbound delivery/read status..."

for required in \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/integrations/whatsapp/provider.ts" \
  "apps/api/src/integrations/whatsapp/evolution.client.ts" \
  "apps/api/src/modules/whatsapp/whatsapp.service.ts" \
  "apps/api/src/modules/webhooks/evolution-webhook.routes.ts" \
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

mkdir -p apps/api/src/modules/messages docs

# ---------------------------------------------------------------------------
# Prisma delivery status
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

if (!schema.includes("enum MessageDeliveryStatus")) {
  const anchor = "enum MessageDirection {";

  if (!schema.includes(anchor)) {
    throw new Error(
      "Could not find MessageDirection enum."
    );
  }

  schema = schema.replace(
    anchor,
    `enum MessageDeliveryStatus {
  NONE
  PENDING
  SENT
  DELIVERED
  READ
  PLAYED
  FAILED
}

${anchor}`
  );
}

const match = schema.match(
  /model Message \{[\s\S]*?\n\}/
);

if (!match) {
  throw new Error("Message model not found.");
}

let model = match[0];

if (!/^\s*deliveryStatus\s+MessageDeliveryStatus/m.test(model)) {
  const anchor =
    /^(\s*mediaError\s+String\?\s+@db\.Text\s*)$/m;

  if (!anchor.test(model)) {
    throw new Error(
      "Could not find Message.mediaError."
    );
  }

  model = model.replace(
    anchor,
    `$1
  deliveryStatus       MessageDeliveryStatus @default(NONE)
  deliveredAt          DateTime?
  readAt               DateTime?
  playedAt             DateTime?
  deliveryError        String?               @db.Text`
  );
}

if (!model.includes("@@index([companyId, deliveryStatus])")) {
  const anchor =
    "  @@index([companyId, mediaStatus])";

  if (!model.includes(anchor)) {
    throw new Error(
      "Could not find Message media status index."
    );
  }

  model = model.replace(
    anchor,
    `${anchor}
  @@index([companyId, deliveryStatus])`
  );
}

schema = schema.replace(match[0], model);
fs.writeFileSync(path, schema);

console.log("Message delivery status schema installed.");
NODE

# ---------------------------------------------------------------------------
# Provider webhook configuration contract
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/provider.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("export interface ConfigureWebhookInput")) {
  const anchor =
    "export interface DownloadMediaInput {";

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find provider DownloadMediaInput anchor."
    );
  }

  content = content.replace(
    anchor,
    `export interface ConfigureWebhookInput {
  instanceName: string;
  webhookUrl: string;
  events: string[];
}

${anchor}`
  );
}

if (!content.includes("configureWebhook(")) {
  const anchor = `  connectionState(
    instanceName: string
  ): Promise<WhatsAppConnectionState>;`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find provider connectionState contract."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

  configureWebhook(
    input: ConfigureWebhookInput
  ): Promise<unknown>;`
  );
}

fs.writeFileSync(path, content);
console.log("Webhook provider contract installed.");
NODE

# ---------------------------------------------------------------------------
# Evolution client: MESSAGES_UPDATE + set webhook
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/evolution.client.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("ConfigureWebhookInput")) {
  const marker =
    "  CreateWhatsAppInstanceInput,";

  if (!content.includes(marker)) {
    throw new Error(
      "Could not find provider import block."
    );
  }

  content = content.replace(
    marker,
    `${marker}
  ConfigureWebhookInput,`
  );
}

/*
 * New instances must subscribe from creation time.
 */
const createEventsAnchor = `                "MESSAGES_UPSERT",
                "CONNECTION_UPDATE"`;

if (
  content.includes(createEventsAnchor) &&
  !content.includes(
    `"MESSAGES_UPSERT",
                "MESSAGES_UPDATE",
                "CONNECTION_UPDATE"`
  )
) {
  content = content.replace(
    createEventsAnchor,
    `                "MESSAGES_UPSERT",
                "MESSAGES_UPDATE",
                "CONNECTION_UPDATE"`
  );
}

/*
 * Existing instances can be reconfigured through /webhook/set/:instance.
 */
if (!content.includes("async configureWebhook(")) {
  const anchor = `  async sendText(
    input: SendTextInput
  ): Promise<unknown> {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find sendText method anchor."
    );
  }

  const method = `  async configureWebhook(
    input: ConfigureWebhookInput
  ): Promise<unknown> {
    return this.request(
      \`/webhook/set/\${encodeURIComponent(
        input.instanceName
      )}\`,
      {
        method: "POST",
        body: JSON.stringify({
          enabled: true,
          url: input.webhookUrl,
          webhookByEvents: false,
          webhookBase64: false,
          base64: false,
          events: input.events
        })
      }
    );
  }

`;

  content = content.replace(
    anchor,
    `${method}${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Evolution webhook status subscription installed.");
NODE

# ---------------------------------------------------------------------------
# Existing connection webhook reconfiguration on sync/connect
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/whatsapp/whatsapp.service.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("const WAPP_WEBHOOK_EVENTS")) {
  const anchor = `function webhookUrl() {
  return \`\${env.EVOLUTION_WEBHOOK_BASE_URL}/api/v1/webhooks/evolution/\${env.EVOLUTION_WEBHOOK_SECRET}\`;
}`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find webhookUrl helper."
    );
  }

  const addition = `${anchor}

const WAPP_WEBHOOK_EVENTS = [
  "QRCODE_UPDATED",
  "MESSAGES_UPSERT",
  "MESSAGES_UPDATE",
  "CONNECTION_UPDATE"
];

async function ensureWebhook(
  instanceName: string
) {
  await evolutionWhatsAppClient.configureWebhook({
    instanceName,
    webhookUrl: webhookUrl(),
    events: WAPP_WEBHOOK_EVENTS
  });
}`;

  content = content.replace(
    anchor,
    addition
  );
}

/*
 * connectConnection: configure first, then connect.
 */
if (
  !content.includes(
    "await ensureWebhook(\n    connection.instanceName\n  );\n\n  const qr"
  )
) {
  const anchor = `  const qr = await evolutionWhatsAppClient.connect(
    connection.instanceName
  );`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find connectConnection Evolution call."
    );
  }

  content = content.replace(
    anchor,
    `  await ensureWebhook(
    connection.instanceName
  );

${anchor}`
  );
}

/*
 * syncConnection: reconfigure webhook before state lookup.
 * This upgrades already-existing instances without recreating them.
 */
if (
  !content.includes(
    "await ensureWebhook(\n      connection.instanceName\n    );\n\n    const state"
  )
) {
  const anchor = `    const state = await evolutionWhatsAppClient.connectionState(
      connection.instanceName
    );`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find syncConnection state lookup."
    );
  }

  content = content.replace(
    anchor,
    `    await ensureWebhook(
      connection.instanceName
    );

${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Existing Evolution instances will refresh webhook on sync/connect.");
NODE

# ---------------------------------------------------------------------------
# Delivery status parser/service
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/messages/message-status.service.ts <<'EOF'
import type {
  MessageDeliveryStatus,
  WhatsAppConnection
} from "../../generated/prisma/client.js";

import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

type UnknownRecord = Record<string, unknown>;

const statusRank: Record<
  MessageDeliveryStatus,
  number
> = {
  NONE: 0,
  PENDING: 1,
  SENT: 2,
  DELIVERED: 3,
  READ: 4,
  PLAYED: 5,
  FAILED: 99
};

function record(
  value: unknown
): UnknownRecord | undefined {
  return value &&
    typeof value === "object" &&
    !Array.isArray(value)
    ? (value as UnknownRecord)
    : undefined;
}

function stringValue(
  value: unknown
) {
  if (
    typeof value === "string" &&
    value.trim()
  ) {
    return value.trim();
  }

  return undefined;
}

function normalizeStatus(
  value: unknown
): MessageDeliveryStatus | undefined {
  if (typeof value === "number") {
    switch (value) {
      case 0:
        return "FAILED";
      case 1:
        return "PENDING";
      case 2:
        return "SENT";
      case 3:
        return "DELIVERED";
      case 4:
        return "READ";
      case 5:
        return "PLAYED";
      default:
        return undefined;
    }
  }

  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value
    .trim()
    .toUpperCase()
    .replace(/[\s.-]+/g, "_");

  switch (normalized) {
    case "ERROR":
    case "FAILED":
    case "FAILURE":
      return "FAILED";

    case "PENDING":
      return "PENDING";

    case "SERVER_ACK":
    case "SENT":
      return "SENT";

    case "DELIVERY_ACK":
    case "DELIVERED":
      return "DELIVERED";

    case "READ":
      return "READ";

    case "PLAYED":
      return "PLAYED";

    default:
      return undefined;
  }
}

function updateItems(
  body: UnknownRecord
): UnknownRecord[] {
  const data = body.data;

  if (Array.isArray(data)) {
    return data
      .map(item => record(item))
      .filter(
        (item): item is UnknownRecord =>
          Boolean(item)
      );
  }

  const dataRecord = record(data);

  return dataRecord
    ? [dataRecord]
    : [];
}

function externalId(
  item: UnknownRecord
) {
  const key = record(item.key);

  return (
    stringValue(key?.id) ??
    stringValue(item.id) ??
    stringValue(
      record(item.message)?.id
    )
  );
}

function itemStatus(
  item: UnknownRecord
) {
  const update = record(item.update);

  return normalizeStatus(
    update?.status ??
    item.status
  );
}

function failureReason(
  item: UnknownRecord
) {
  const update = record(item.update);

  const candidates = [
    update?.message,
    update?.error,
    item.message,
    item.error
  ];

  for (const candidate of candidates) {
    const value = stringValue(candidate);

    if (value) {
      return value.slice(0, 2_000);
    }
  }

  return null;
}

function shouldAdvance(
  current: MessageDeliveryStatus,
  next: MessageDeliveryStatus
) {
  if (next === "FAILED") {
    return (
      current !== "READ" &&
      current !== "PLAYED"
    );
  }

  if (current === "FAILED") {
    return false;
  }

  return (
    statusRank[next] >
    statusRank[current]
  );
}

export async function ingestEvolutionMessageUpdate(
  body: UnknownRecord,
  connection: WhatsAppConnection
) {
  const results: Array<{
    externalId: string;
    status: MessageDeliveryStatus;
    updated: boolean;
  }> = [];

  for (const item of updateItems(body)) {
    const id = externalId(item);
    const status = itemStatus(item);

    if (!id || !status) {
      continue;
    }

    const current =
      await prisma.message.findUnique({
        where: {
          whatsappConnectionId_externalId: {
            whatsappConnectionId:
              connection.id,
            externalId: id
          }
        },
        select: {
          id: true,
          ticketId: true,
          companyId: true,
          direction: true,
          deliveryStatus: true
        }
      });

    if (
      !current ||
      current.direction !== "OUTBOUND"
    ) {
      results.push({
        externalId: id,
        status,
        updated: false
      });
      continue;
    }

    if (
      current.deliveryStatus === status ||
      !shouldAdvance(
        current.deliveryStatus,
        status
      )
    ) {
      results.push({
        externalId: id,
        status,
        updated: false
      });
      continue;
    }

    const now = new Date();

    await prisma.message.update({
      where: {
        id: current.id
      },
      data: {
        deliveryStatus: status,
        ...(status === "DELIVERED"
          ? {
              deliveredAt: now
            }
          : {}),
        ...(status === "READ"
          ? {
              deliveredAt:
                now,
              readAt: now
            }
          : {}),
        ...(status === "PLAYED"
          ? {
              deliveredAt:
                now,
              readAt: now,
              playedAt: now
            }
          : {}),
        ...(status === "FAILED"
          ? {
              deliveryError:
                failureReason(item) ??
                "A Evolution informou falha na entrega."
            }
          : {
              deliveryError: null
            })
      }
    });

    publishRealtime(
      current.companyId,
      {
        type: "message.updated",
        ticketId: current.ticketId,
        messageId: current.id
      }
    );

    results.push({
      externalId: id,
      status,
      updated: true
    });
  }

  return results;
}
EOF

# ---------------------------------------------------------------------------
# Webhook consumes MESSAGES_UPDATE
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/webhooks/evolution-webhook.routes.ts";

let content = fs.readFileSync(path, "utf8");

const importLine =
  'import { ingestEvolutionMessageUpdate } from "../messages/message-status.service.js";';

if (!content.includes(importLine)) {
  const anchor =
    'import { ingestEvolutionMessage } from "../messages/message-ingestion.service.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find message ingestion import."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (!content.includes('event === "MESSAGES_UPDATE"')) {
  const anchor = `      } else if (event === "MESSAGES_UPSERT") {
        const result = await ingestEvolutionMessage(
          body,
          connection
        );

        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance,
            result
          },
          "Evolution message processed"
        );
      } else {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find MESSAGES_UPSERT webhook block."
    );
  }

  const replacement = `      } else if (event === "MESSAGES_UPSERT") {
        const result = await ingestEvolutionMessage(
          body,
          connection
        );

        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance,
            result
          },
          "Evolution message processed"
        );
      } else if (event === "MESSAGES_UPDATE") {
        const result =
          await ingestEvolutionMessageUpdate(
            body,
            connection
          );

        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance,
            result
          },
          "Evolution message status processed"
        );
      } else {`;

  content = content.replace(
    anchor,
    replacement
  );
}

fs.writeFileSync(path, content);
console.log("MESSAGES_UPDATE webhook handler installed.");
NODE

# ---------------------------------------------------------------------------
# Outbound text/media start PENDING
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content = fs.readFileSync(path, "utf8");

/*
 * Text create.
 */
const textCreateAnchor = `      direction: "OUTBOUND",
      type: "TEXT",
      body: input.text,`;

if (
  content.includes(textCreateAnchor) &&
  !content.includes(
    `direction: "OUTBOUND",
      type: "TEXT",
      deliveryStatus: "PENDING",
      body: input.text,`
  )
) {
  content = content.replace(
    textCreateAnchor,
    `      direction: "OUTBOUND",
      type: "TEXT",
      deliveryStatus: "PENDING",
      body: input.text,`
  );
}

/*
 * Media update/create. Do this only inside sendTicketMedia area.
 */
const mediaIndex =
  content.indexOf(
    "export async function sendTicketMedia("
  );

if (mediaIndex >= 0) {
  let before =
    content.slice(0, mediaIndex);
  let media =
    content.slice(mediaIndex);

  if (
    media.includes(
      `direction: "OUTBOUND",
        type:
          descriptor.messageType,`
    ) &&
    !media.includes(
      `direction: "OUTBOUND",
        type:
          descriptor.messageType,
        deliveryStatus: "PENDING",`
    )
  ) {
    media = media.replace(
      `direction: "OUTBOUND",
        type:
          descriptor.messageType,`,
      `direction: "OUTBOUND",
        type:
          descriptor.messageType,
        deliveryStatus: "PENDING",`
    );
  }

  /*
   * The upsert update branch may not repeat direction.
   */
  if (
    media.includes(
      `type:
          descriptor.messageType,
        body:`
    ) &&
    !media.includes(
      `type:
          descriptor.messageType,
        deliveryStatus: "PENDING",
        body:`
    )
  ) {
    media = media.replace(
      `type:
          descriptor.messageType,
        body:`,
      `type:
          descriptor.messageType,
        deliveryStatus: "PENDING",
        body:`
    );
  }

  content = before + media;
}

fs.writeFileSync(path, content);
console.log("Outbound messages now begin at deliveryStatus=PENDING.");
NODE

# ---------------------------------------------------------------------------
# Realtime already has message.updated from P1.2; validate it
# ---------------------------------------------------------------------------

for file in \
  apps/api/src/modules/realtime/realtime.bus.ts \
  apps/web/lib/realtime-types.ts
do
  if ! grep -Fq '"message.updated"' "$file"; then
    echo "ERROR: message.updated realtime event missing from $file"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Frontend delivery indicators
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

/*
 * Message DTO
 */
if (
  !content.includes(
    `deliveryStatus: "NONE" | "PENDING" | "SENT" | "DELIVERED" | "READ" | "PLAYED" | "FAILED";`
  )
) {
  const anchor = `  mediaSize: number | null;
  timestamp: string;`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find Message mediaSize/timestamp DTO fields."
    );
  }

  content = content.replace(
    anchor,
    `  mediaSize: number | null;
  deliveryStatus: "NONE" | "PENDING" | "SENT" | "DELIVERED" | "READ" | "PLAYED" | "FAILED";
  deliveredAt: string | null;
  readAt: string | null;
  playedAt: string | null;
  deliveryError: string | null;
  timestamp: string;`
  );
}

/*
 * Helper
 */
if (!content.includes("function deliveryStatusPresentation(")) {
  const anchor = `function ticketPreview(ticket: Ticket) {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticketPreview helper."
    );
  }

  const helper = `function deliveryStatusPresentation(
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

`;

  content = content.replace(
    anchor,
    `${helper}${anchor}`
  );
}

/*
 * Replace message time-only footer with status + time for outbound.
 */
if (
  !content.includes(
    'className="message-delivery"'
  )
) {
  const timeBlock = `                      <time>
                        {dateTimeLabel(message.timestamp)}
                      </time>`;

  if (!content.includes(timeBlock)) {
    throw new Error(
      "Could not find current message time block."
    );
  }

  const footer = `                      <div className="message-meta">
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
                                  ? \`Falhou: \${message.deliveryError}\`
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
                      </div>`;

  content = content.replace(
    timeBlock,
    footer
  );
}

fs.writeFileSync(path, content);
console.log("Message delivery indicators installed.");
NODE

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

if ! grep -q "WAPP P1.5 / Message delivery status" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.5 / Message delivery status ------------------------------ */

.message-meta {
  display: flex;
  min-height: 15px;
  align-items: center;
  justify-content: flex-end;
  gap: 5px;
  margin-top: 5px;
}

.message-meta > time,
.message-bubble--media > .message-meta > time {
  margin: 0;
}

.message-delivery {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: #8d9690;
  font-size: 9px;
  font-weight: 800;
  letter-spacing: -0.12em;
  line-height: 1;
  cursor: default;
}

.message-delivery--read {
  color: #287b57;
}

.message-delivery--failed {
  width: 15px;
  height: 15px;
  border-radius: 999px;
  background: var(--danger-soft);
  color: var(--danger);
  letter-spacing: 0;
}
EOF
fi

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/MESSAGE_DELIVERY_STATUS.md <<'EOF'
# Message delivery status

P1.5 tracks the lifecycle of outbound WhatsApp messages.

```text
PENDING
   |
   v
SENT
   |
   v
DELIVERED
   |
   v
READ
   |
   +--> PLAYED (voice/audio)
```

A message can also enter `FAILED`.

## Evolution

Evolution initially returns sent messages as `PENDING`.

Later delivery/read changes are delivered through the `MESSAGES_UPDATE`
webhook.

For the Baileys integration Wapp accepts both numeric and textual status forms:

- 1 / PENDING
- 2 / SERVER_ACK / SENT
- 3 / DELIVERY_ACK / DELIVERED
- 4 / READ
- 5 / PLAYED
- 0 / ERROR / FAILED

Updates are monotonic: an out-of-order webhook cannot downgrade READ back to
DELIVERED.

## Existing instances

P1.5 adds `MESSAGES_UPDATE` to new-instance configuration.

Existing Evolution instances are upgraded when the Wapp connection is synced
or reconnected. `syncConnection` calls `/webhook/set/:instance` with the Wapp
event list.

## UI

Outbound bubbles show:

- circle: pending
- one check: sent
- double check: delivered
- green double check: read/played
- error indicator: failed

The API remains the source of truth; the UI does not infer delivery from a
successful HTTP send.
EOF

echo "[P1.5] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.5] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.5] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.5] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.5] Delivery/read status installed."
echo
echo "Next:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name message_delivery_status"
echo "  pnpm dev"
echo
echo "After restart:"
echo "  open Connections and run Sync once on the active connection"
echo "  then send a fresh text and a fresh voice note"
