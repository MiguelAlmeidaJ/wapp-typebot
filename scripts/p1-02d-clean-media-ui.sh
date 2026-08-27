#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PAGE="apps/web/app/dashboard/conversations/page.tsx"
CSS="apps/web/app/globals.css"

for required in "$PAGE" "$CSS"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

echo "[P1.2d] Cleaning media message presentation..."

node <<'NODE'
const fs = require("node:fs");

const pagePath =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(pagePath, "utf8");

if (!content.includes("<MessageMedia")) {
  throw new Error(
    "MessageMedia is not present. Apply and finish P1.2 before P1.2d."
  );
}

if (!content.includes("function isMediaMessage(")) {
  const anchor = `function ticketPreview(ticket: Ticket) {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find ticketPreview anchor."
    );
  }

  const helpers = `function isMediaMessage(type: MessageType) {
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

`;

  content = content.replace(
    anchor,
    `${helpers}${anchor}`
  );
}

if (!content.includes("message-bubble--media")) {
  const articleRegex =
    /<article className="message-bubble">\s*\{message\.type !== "TEXT" && \(\s*<span className="message-kind">\s*\{messageFallback\(message\.type\)\}\s*<\/span>\s*\)\}\s*<MessageMedia[\s\S]*?\/>\s*<p>\{message\.body \?\? messageFallback\(message\.type\)\}<\/p>\s*\{message\.mediaFileName && \(\s*<small className="message-file">\s*\{message\.mediaFileName\}\s*<\/small>\s*\)\}\s*<time>\{dateTimeLabel\(message\.timestamp\)\}<\/time>\s*<\/article>/;

  const match = content.match(articleRegex);

  if (!match) {
    throw new Error(
      "Could not find the current media message article block."
    );
  }

  const replacement = `<article
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
                    </article>`;

  content = content.replace(
    articleRegex,
    replacement
  );
}

fs.writeFileSync(pagePath, content);

console.log("Media message JSX cleaned.");
NODE

if ! grep -q "WAPP P1.2d / Media visual cleanup" "$CSS"; then
  cat >> "$CSS" <<'EOF'

/* --- WAPP P1.2d / Media visual cleanup -------------------------------- */

.message-bubble--media {
  width: fit-content;
  max-width: min(560px, calc(100% - 12px));
  gap: 8px;
  padding: 10px;
}

.message-bubble--media > p {
  max-width: 500px;
  margin: 2px 4px 0;
}

.message-bubble--media > time {
  margin: 0 4px;
  align-self: end;
}

.message-bubble--media .message-media-image,
.message-bubble--media .message-media-video,
.message-bubble--media .message-media-audio,
.message-bubble--media .message-media-document {
  margin: 0;
}
EOF
fi

echo "[P1.2d] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.2d] Media UI cleanup complete."
echo
echo "Restart if needed:"
echo "  pnpm dev"
