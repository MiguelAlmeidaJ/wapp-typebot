#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.2b] Finishing media frontend after partial P1.2..."

for required in \
  "apps/web/app/dashboard/conversations/page.tsx" \
  "apps/web/components/messages/message-media.tsx" \
  "apps/web/app/globals.css" \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/modules/media/media.routes.ts" \
  "apps/api/src/modules/media/media-capture.service.ts"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    echo "P1.2b expects the original P1.2 script to have run until the frontend step."
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

const importLine =
  'import { MessageMedia } from "@/components/messages/message-media";';

if (!content.includes(importLine)) {
  const anchor =
    'import { useAuth } from "@/components/auth-provider";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find auth-provider import in Conversations."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}\n${importLine}`
  );
}

if (!content.includes('mediaStatus: "NONE" | "PENDING" | "READY" | "FAILED";')) {
  const anchor =
    `  mediaMimeType: string | null;
  mediaFileName: string | null;
  timestamp: string;`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find Message media fields in Conversations."
    );
  }

  content = content.replace(
    anchor,
    `  mediaMimeType: string | null;
  mediaFileName: string | null;
  mediaStatus: "NONE" | "PENDING" | "READY" | "FAILED";
  mediaSize: number | null;
  timestamp: string;`
  );
}

if (!content.includes("<MessageMedia")) {
  const bodyLine =
    '<p>{message.body ?? messageFallback(message.type)}</p>';

  if (!content.includes(bodyLine)) {
    throw new Error(
      "Could not find the current message body render line."
    );
  }

  content = content.replace(
    bodyLine,
    `<MessageMedia
                        fileName={message.mediaFileName}
                        messageId={message.id}
                        mimeType={message.mediaMimeType}
                        status={message.mediaStatus}
                        type={message.type}
                      />
                      ${bodyLine}`
  );
}

if (
  content.includes('event.type === "message.created"') &&
  !content.includes('event.type === "message.updated"')
) {
  content = content.replace(
    'event.type === "message.created" ||',
    `event.type === "message.created" ||
        event.type === "message.updated" ||`
  );
}

fs.writeFileSync(path, content);

console.log("Conversations media rendering completed.");
NODE

if ! grep -q "WAPP P1.2 / Media" apps/web/app/globals.css; then
  cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P1.2 / Media ------------------------------------------------- */

.message-media-image,
.message-media-video {
  display: block;
  width: min(440px, 100%);
  max-height: 420px;
  object-fit: contain;
  border-radius: 12px;
  background: #f0f2f0;
}

.message-media-image--sticker {
  width: min(180px, 55vw);
  max-height: 180px;
  background: transparent;
}

.message-media-video {
  background: #111;
}

.message-media-audio {
  display: block;
  width: min(360px, 72vw);
  margin: 2px 0;
}

.message-media-document {
  display: grid;
  gap: 4px;
  min-width: min(300px, 65vw);
  border: 1px solid var(--line);
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.72);
  color: inherit;
  padding: 12px;
  text-decoration: none;
}

.message-media-document span {
  color: var(--accent-dark);
  font-size: 8px;
  font-weight: 800;
  text-transform: uppercase;
}

.message-media-document strong {
  overflow: hidden;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.message-media-state {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  min-width: 210px;
  border-radius: 9px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 9px 10px;
  font-size: 9px;
}

.message-media-state--error {
  background: var(--danger-soft);
  color: var(--danger);
}

.message-media-state button {
  border: 0;
  background: transparent;
  color: inherit;
  font-size: 9px;
  font-weight: 800;
  text-decoration: underline;
}
EOF
fi

if [[ ! -f docs/MEDIA.md ]]; then
  cat > docs/MEDIA.md <<'EOF'
# Media pipeline

P1.2 adds binary media handling without storing files inside MySQL.

```text
Evolution MESSAGES_UPSERT
        |
        v
Message row
mediaStatus=PENDING
        |
        v
background capture
        |
        +--> Evolution getBase64FromMediaMessage
        |
        v
.runtime/media/<company>/<message>.<ext>
        |
        v
mediaStatus=READY
        |
        v
authenticated GET /api/v1/messages/:id/media
```

## Stored in MySQL

- mediaStatus
- mediaStorageKey
- mediaSize
- mediaMimeType
- mediaFileName
- mediaError

The binary is not stored in the database.

## Local storage

Development uses `.runtime/media`.

Production should replace the storage adapter with S3-compatible object
storage. The domain does not expose the local path to the browser.

## Security

Media delivery checks the authenticated user's company before reading the file.
The browser retrieves media through authenticated fetch and creates a temporary
object URL.

## Retry

A failed media message can be retried with:

`POST /api/v1/messages/:id/media/retry`

A media capture failure must never prevent the text/message metadata from
reaching the inbox.
EOF
fi

echo "[P1.2b] Formatting Prisma schema..."
pnpm --filter @wapp/api exec prisma format

echo "[P1.2b] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P1.2b] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.2b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.2b] Media implementation completed."
echo
echo "Continue with:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name message_media"
echo "  pnpm dev"
