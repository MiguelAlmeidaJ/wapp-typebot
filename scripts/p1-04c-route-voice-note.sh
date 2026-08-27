#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILES=(
  "apps/api/src/integrations/whatsapp/provider.ts"
  "apps/api/src/integrations/whatsapp/evolution.client.ts"
  "apps/api/src/modules/tickets/ticket.service.ts"
  "apps/api/src/modules/tickets/ticket-media.routes.ts"
  "apps/web/app/dashboard/conversations/page.tsx"
)

for required in "${FILES[@]}"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

echo "[P1.4c] Routing recorded voice notes through Evolution WhatsApp audio endpoint..."

# ---------------------------------------------------------------------------
# Provider contract
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/provider.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("export interface SendWhatsAppAudioInput")) {
  const anchor = `export interface DownloadMediaInput {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find DownloadMediaInput anchor."
    );
  }

  const addition = `export interface SendWhatsAppAudioInput {
  instanceName: string;
  number: string;
  mimetype: string;
  fileName: string;
  buffer: Buffer;
}

`;

  content = content.replace(
    anchor,
    `${addition}${anchor}`
  );
}

if (!content.includes("sendWhatsAppAudio(")) {
  const anchor = `  sendMedia(
    input: SendMediaInput
  ): Promise<unknown>;`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find sendMedia contract."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

  sendWhatsAppAudio(
    input: SendWhatsAppAudioInput
  ): Promise<unknown>;`
  );
}

fs.writeFileSync(path, content);
console.log("Provider voice-note contract installed.");
NODE

# ---------------------------------------------------------------------------
# Evolution dedicated voice endpoint
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/integrations/whatsapp/evolution.client.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("SendWhatsAppAudioInput")) {
  content = content.replace(
    `  SendTextInput,`,
    `  SendTextInput,
  SendWhatsAppAudioInput,`
  );
}

if (!content.includes("async sendWhatsAppAudio(")) {
  const anchor = `  async downloadMedia(
    input: DownloadMediaInput
  ): Promise<DownloadMediaResult> {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find downloadMedia method anchor."
    );
  }

  const method = `  async sendWhatsAppAudio(
    input: SendWhatsAppAudioInput
  ): Promise<unknown> {
    const form = new FormData();

    form.append(
      "number",
      input.number
    );

    const blob = new Blob(
      [
        new Uint8Array(
          input.buffer
        )
      ],
      {
        type: input.mimetype
      }
    );

    /*
     * Evolution 2.3.7 exposes a dedicated WhatsApp-audio route.
     * The router uses multer upload.single("file").
     */
    form.append(
      "file",
      blob,
      input.fileName
    );

    return this.request(
      \`/message/sendWhatsAppAudio/\${encodeURIComponent(
        input.instanceName
      )}\`,
      {
        method: "POST",
        body: form
      },
      60_000
    );
  }

`;

  content = content.replace(
    anchor,
    `${method}${anchor}`
  );
}

fs.writeFileSync(path, content);
console.log("Evolution dedicated WhatsApp audio endpoint installed.");
NODE

# ---------------------------------------------------------------------------
# Ticket service chooses voice endpoint only for recorded voice notes
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket.service.ts";

let content = fs.readFileSync(path, "utf8");

const signatureOld = `  caption?: string;
}) {`;

const signatureNew = `  caption?: string;
  voiceNote?: boolean;
}) {`;

const functionIndex =
  content.indexOf(
    "export async function sendTicketMedia("
  );

if (functionIndex < 0) {
  throw new Error(
    "sendTicketMedia not found."
  );
}

const afterFunction =
  content.slice(functionIndex);

if (
  afterFunction.includes(signatureOld) &&
  !afterFunction.includes(
    "voiceNote?: boolean;"
  )
) {
  const absoluteIndex =
    functionIndex +
    afterFunction.indexOf(signatureOld);

  content =
    content.slice(0, absoluteIndex) +
    signatureNew +
    content.slice(
      absoluteIndex +
      signatureOld.length
    );
}

if (!content.includes("const isVoiceNote =")) {
  const anchor = `  const caption =
    input.caption?.trim() || null;

  const result =
    await evolutionWhatsAppClient.sendMedia({`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find outbound media send block."
    );
  }

  const replacement = `  const caption =
    input.caption?.trim() || null;

  const isVoiceNote =
    input.voiceNote === true &&
    descriptor.messageType === "AUDIO";

  if (
    input.voiceNote === true &&
    descriptor.messageType !== "AUDIO"
  ) {
    throw new AppError(
      "Voice note precisa ser um arquivo de áudio.",
      422,
      "VOICE_NOTE_INVALID_MEDIA"
    );
  }

  if (isVoiceNote && caption) {
    throw new AppError(
      "Mensagem de voz não aceita legenda.",
      422,
      "VOICE_NOTE_CAPTION_NOT_SUPPORTED"
    );
  }

  const result = isVoiceNote
    ? await evolutionWhatsAppClient.sendWhatsAppAudio({
        instanceName:
          ticket.whatsappConnection.instanceName,
        number:
          ticket.contact.remoteJid,
        mimetype:
          input.mimetype,
        fileName,
        buffer:
          input.buffer
      })
    : await evolutionWhatsAppClient.sendMedia({`;

  content = content.replace(
    anchor,
    replacement
  );

  const oldClosing = `      caption:
        caption ?? ""
    });

  const timestamp =`;

  const newClosing = `      caption:
        caption ?? ""
    });

  const timestamp =`;

  if (!content.includes(oldClosing)) {
    throw new Error(
      "Could not find sendMedia closing block."
    );
  }

  // Same text remains valid because ternary's second branch closes here.
  // This validation simply confirms the structure.
}

/*
 * Store no caption for voice note.
 */
content = content.replace(
  `        body: caption,
        mediaMimeType:`,
  `        body: isVoiceNote ? null : caption,
        mediaMimeType:`
);

content = content.replace(
  `        body: caption,
        mediaMimeType:`,
  `        body: isVoiceNote ? null : caption,
        mediaMimeType:`
);

content = content.replace(
  `      lastMessage:
        caption ??
        descriptor.preview,`,
  `      lastMessage:
        isVoiceNote
          ? "[Áudio]"
          : caption ??
            descriptor.preview,`
);

fs.writeFileSync(path, content);
console.log("Ticket service now distinguishes voice notes from uploaded audio.");
NODE

# ---------------------------------------------------------------------------
# Multipart route reads voiceNote
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket-media.routes.ts";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("const voiceNoteSchema")) {
  const anchor = `const captionSchema = z
  .string()
  .trim()
  .max(4096);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find caption schema."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

const voiceNoteSchema = z
  .enum(["true", "false"])
  .default("false")
  .transform(value => value === "true");`
  );
}

if (!content.includes("const voiceNote =")) {
  const anchor = `      const caption =
        captionSchema.parse(
          multipartField(
            upload.fields,
            "caption"
          )
        );`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find caption parsing."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}

      const voiceNote =
        voiceNoteSchema.parse(
          multipartField(
            upload.fields,
            "voiceNote"
          ) || "false"
        );`
  );
}

if (!content.includes("voiceNote\n")) {
  const anchor = `            caption:
              caption || undefined`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find sendTicketMedia caption input."
    );
  }

  content = content.replace(
    anchor,
    `${anchor},
            voiceNote`
  );
}

fs.writeFileSync(path, content);
console.log("Multipart voiceNote flag wired to service.");
NODE

# ---------------------------------------------------------------------------
# Frontend: track whether selected audio came from recorder
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

if (!content.includes("const [attachmentIsVoiceNote")) {
  const anchor = `  const [attachmentPreviewUrl, setAttachmentPreviewUrl] =
    useState<string | null>(null);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find attachment preview state."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [attachmentIsVoiceNote, setAttachmentIsVoiceNote] =
    useState(false);`
  );
}

/* Uploaded files are not voice notes. */
if (!content.includes("setAttachmentIsVoiceNote(false);")) {
  const anchor = `    setError("");
    setAttachment(file);
  }`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find chooseAttachment setter."
    );
  }

  content = content.replace(
    anchor,
    `    setError("");
    setAttachmentIsVoiceNote(false);
    setAttachment(file);
  }`
  );
}

/* Recorder output is a voice note. */
const recorderSetAnchor = `        setAttachment(file);`;

const recorderIndex =
  content.indexOf(
    recorderSetAnchor,
    content.indexOf(
      "recorder.onstop"
    )
  );

if (
  recorderIndex >= 0 &&
  !content.slice(
    Math.max(
      0,
      recorderIndex - 100
    ),
    recorderIndex + 100
  ).includes(
    "setAttachmentIsVoiceNote(true)"
  )
) {
  content =
    content.slice(0, recorderIndex) +
    `        setAttachmentIsVoiceNote(true);
` +
    content.slice(recorderIndex);
}

/* Start recording only with empty composer text. */
const startGuardOld = `    if (sending || attachment || recording) {
      return;
    }`;

const startGuardNew = `    if (sending || attachment || recording) {
      return;
    }

    if (text.trim()) {
      setError(
        "Envie ou apague o texto antes de gravar uma mensagem de voz."
      );
      return;
    }`;

if (content.includes(startGuardOld)) {
  content = content.replace(
    startGuardOld,
    startGuardNew
  );
}

/* Send multipart flag before file. */
if (!content.includes('form.append(\n          "voiceNote"')) {
  const anchor = `        form.append(
          "caption",
          text.trim()
        );
        form.append(
          "file",`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find P1.3 FormData composer block."
    );
  }

  content = content.replace(
    anchor,
    `        form.append(
          "caption",
          attachmentIsVoiceNote
            ? ""
            : text.trim()
        );
        form.append(
          "voiceNote",
          attachmentIsVoiceNote
            ? "true"
            : "false"
        );
        form.append(
          "file",`
  );
}

/* Clear voice-note flag after successful send. */
if (
  !content.includes(
    "setAttachmentIsVoiceNote(false);\n\n        if ("
  )
) {
  const anchor = `        setAttachment(null);

        if (
          attachmentInputRef.current
        ) {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find successful attachment cleanup."
    );
  }

  content = content.replace(
    anchor,
    `        setAttachment(null);
        setAttachmentIsVoiceNote(false);

        if (
          attachmentInputRef.current
        ) {`
  );
}

/* Clear flag on manual remove. */
content = content.replace(
  `                          setAttachment(null);

                          if (`,
  `                          setAttachment(null);
                          setAttachmentIsVoiceNote(false);

                          if (`
);

/* Textarea disabled while selected voice note exists. */
content = content.replace(
  `disabled={recording}
                  maxLength={4096}`,
  `disabled={
                    recording ||
                    attachmentIsVoiceNote
                  }
                  maxLength={4096}`
);

/* More accurate selected file label. */
if (
  !content.includes(
    'attachmentIsVoiceNote\n                            ? "Mensagem de voz"'
  )
) {
  const anchor = `{attachment.name}`;

  if (content.includes(anchor)) {
    content = content.replace(
      anchor,
      `{attachmentIsVoiceNote
                            ? "Mensagem de voz"
                            : attachment.name}`
    );
  }
}

fs.writeFileSync(path, content);
console.log("Recorded audio now carries voiceNote=true to the API.");
NODE

echo "[P1.4c] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.4c] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.4c] Voice-note routing installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then record a fresh voice note and verify it arrives in WhatsApp."
