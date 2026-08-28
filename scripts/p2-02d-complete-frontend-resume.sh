#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET="scripts/p2-02b-resume-message-reactions.sh"

echo "[P2.2d] Fixing P2.2b frontend resume state..."

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: missing $TARGET"
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const path =
  "scripts/p2-02b-resume-message-reactions.sh";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const frontendTypeCheckStart =
  'if ! grep -q "interface MessageReaction" "$PAGE"; then';

if (
  content.includes(
    frontendTypeCheckStart
  )
) {
  const nextNode =
    content.indexOf(
      "\nnode <<'NODE'\n",
      content.indexOf(
        frontendTypeCheckStart
      )
    );

  if (nextNode < 0) {
    throw new Error(
      "P2.2b frontend Node block not found."
    );
  }

  content =
    content.slice(
      0,
      content.indexOf(
        frontendTypeCheckStart
      )
    ) +
    content.slice(
      nextNode + 1
    );
}

const nodeAnchor = `function insertBefore(
  anchor,
  addition,
  already,
  label
) {`;

if (
  !content.includes(
    nodeAnchor
  )
) {
  throw new Error(
    "P2.2b insertBefore helper not found."
  );
}

if (
  !content.includes(
    "P2.2d frontend bootstrap"
  )
) {
  const bootstrap = `/* P2.2d frontend bootstrap */
if (
  !content.includes(
    "interface MessageReaction"
  )
) {
  const anchor =
    "interface Message {";

  if (!content.includes(anchor)) {
    throw new Error(
      "Message interface anchor not found."
    );
  }

  const type = \`interface MessageReaction {
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

\`;

  content =
    content.replace(
      anchor,
      \`\${type}\${anchor}\`
    );
}

if (
  !content.includes(
    "reactions: MessageReaction[];"
  )
) {
  const start =
    content.indexOf(
      "interface Message {"
    );

  const end =
    content.indexOf(
      "\\n}",
      start
    );

  if (
    start < 0 ||
    end < 0
  ) {
    throw new Error(
      "Message interface boundary not found."
    );
  }

  content =
    content.slice(
      0,
      end
    ) +
    "\\n  reactions: MessageReaction[];" +
    content.slice(
      end
    );
}

`;

  content =
    content.replace(
      nodeAnchor,
      `${bootstrap}${nodeAnchor}`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "P2.2b now supports a pristine frontend."
);
NODE

echo "[P2.2d] Checking resume installer syntax..."
bash -n "$TARGET"

echo "[P2.2d] Confirming backend partial state..."
grep -Fq -- "model MessageReaction" apps/api/prisma/schema.prisma
grep -Fq -- "reactions              MessageReaction[]" apps/api/prisma/schema.prisma
grep -Fq -- "async sendReaction(" apps/api/src/integrations/whatsapp/evolution.client.ts
grep -Fq -- "message.reaction.updated" apps/api/src/modules/realtime/realtime.bus.ts

echo "[P2.2d] Backend state confirmed."
echo "[P2.2d] Resuming P2.2..."
bash "$TARGET"
