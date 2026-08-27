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

for token in \
  'const [attachment, setAttachment]' \
  'const attachmentInputRef' \
  'function chooseAttachment' \
  'conversation-composer--attachments' \
  'className="composer__attach"'
do
  if ! grep -Fq "$token" "$PAGE"; then
    echo "ERROR: P1.3 token not found: $token"
    echo "P1.4 expects P1.3 outbound attachments to be applied first."
    exit 1
  fi
done

echo "[P1.4] Adding browser audio recording..."

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

/* -----------------------------------------------------------------------
 * Shared helpers
 * --------------------------------------------------------------------- */

if (!content.includes("function recordingTimeLabel(")) {
  const anchor = `function dateTimeLabel(value: string) {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find dateTimeLabel helper."
    );
  }

  const helpers = `function recordingTimeLabel(
  seconds: number
) {
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;

  return \`\${String(minutes).padStart(2, "0")}:\${String(
    remainder
  ).padStart(2, "0")}\`;
}

function preferredRecordingMimeType() {
  if (
    typeof MediaRecorder === "undefined"
  ) {
    return "";
  }

  const candidates = [
    "audio/ogg;codecs=opus",
    "audio/webm;codecs=opus",
    "audio/webm",
    "audio/mp4"
  ];

  return (
    candidates.find(candidate =>
      MediaRecorder.isTypeSupported(candidate)
    ) ?? ""
  );
}

function recordingExtension(
  mimeType: string
) {
  const normalized =
    mimeType
      .split(";")[0]
      ?.trim()
      .toLowerCase() ?? "";

  if (normalized === "audio/ogg") {
    return "ogg";
  }

  if (normalized === "audio/mp4") {
    return "m4a";
  }

  return "webm";
}

`;

  content = content.replace(
    anchor,
    `${helpers}${anchor}`
  );
}

/* -----------------------------------------------------------------------
 * State
 * --------------------------------------------------------------------- */

if (!content.includes("const [recording, setRecording]")) {
  const anchor = `  const [attachmentPreviewUrl, setAttachmentPreviewUrl] =
    useState<string | null>(null);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find P1.3 attachment preview state."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const [recording, setRecording] =
    useState(false);
  const [recordingSeconds, setRecordingSeconds] =
    useState(0);`
  );
}

/* -----------------------------------------------------------------------
 * Refs
 * --------------------------------------------------------------------- */

if (!content.includes("const mediaRecorderRef =")) {
  const anchor = `  const attachmentInputRef =
    useRef<HTMLInputElement | null>(null);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find P1.3 attachment input ref."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  const mediaRecorderRef =
    useRef<MediaRecorder | null>(null);
  const mediaStreamRef =
    useRef<MediaStream | null>(null);
  const audioChunksRef =
    useRef<Blob[]>([]);
  const recordingTimerRef =
    useRef<number | null>(null);
  const recordingStartedAtRef =
    useRef<number | null>(null);
  const discardRecordingRef =
    useRef(false);`
  );
}

/* -----------------------------------------------------------------------
 * Attachment preview supports recorded/uploaded audio too.
 * --------------------------------------------------------------------- */

const oldPreviewCondition = `    if (
      !attachment.type.startsWith("image/")
    ) {
      setAttachmentPreviewUrl(null);
      return;
    }`;

const newPreviewCondition = `    if (
      !attachment.type.startsWith("image/") &&
      !attachment.type.startsWith("audio/")
    ) {
      setAttachmentPreviewUrl(null);
      return;
    }`;

if (content.includes(oldPreviewCondition)) {
  content = content.replace(
    oldPreviewCondition,
    newPreviewCondition
  );
}

/* -----------------------------------------------------------------------
 * Unmount cleanup.
 * --------------------------------------------------------------------- */

if (!content.includes("[P1.4 recorder cleanup]")) {
  const previewEffectMarker =
    `  // [P1.3 attachment preview]`;

  const markerIndex =
    content.indexOf(previewEffectMarker);

  if (markerIndex < 0) {
    throw new Error(
      "Could not find P1.3 attachment preview effect."
    );
  }

  const nextFunctionIndex =
    content.indexOf(
      "\n  async function",
      markerIndex
    );

  const nextPlainFunctionIndex =
    content.indexOf(
      "\n  function",
      markerIndex
    );

  const insertionCandidates = [
    nextFunctionIndex,
    nextPlainFunctionIndex
  ].filter(value => value > markerIndex);

  const insertionIndex =
    Math.min(...insertionCandidates);

  if (!Number.isFinite(insertionIndex)) {
    throw new Error(
      "Could not find function boundary after attachment preview."
    );
  }

  const cleanupEffect = `

  // [P1.4 recorder cleanup]
  useEffect(() => {
    return () => {
      if (recordingTimerRef.current !== null) {
        window.clearInterval(
          recordingTimerRef.current
        );
      }

      const recorder =
        mediaRecorderRef.current;

      if (
        recorder &&
        recorder.state !== "inactive"
      ) {
        recorder.ondataavailable = null;
        recorder.onstop = null;
        recorder.stop();
      }

      mediaStreamRef.current
        ?.getTracks()
        .forEach(track => track.stop());
    };
  }, []);
`;

  content =
    content.slice(0, insertionIndex) +
    cleanupEffect +
    content.slice(insertionIndex);
}

/* -----------------------------------------------------------------------
 * Recorder functions.
 * --------------------------------------------------------------------- */

if (!content.includes("async function startRecording(")) {
  const anchor = `  function chooseAttachment(
    file: File | undefined
  ) {`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find P1.3 chooseAttachment."
    );
  }

  const functions = `  function stopRecordingResources() {
    if (recordingTimerRef.current !== null) {
      window.clearInterval(
        recordingTimerRef.current
      );
      recordingTimerRef.current = null;
    }

    recordingStartedAtRef.current = null;

    mediaStreamRef.current
      ?.getTracks()
      .forEach(track => track.stop());

    mediaStreamRef.current = null;
  }

  async function startRecording() {
    if (sending || attachment || recording) {
      return;
    }

    if (
      !navigator.mediaDevices?.getUserMedia ||
      typeof MediaRecorder === "undefined"
    ) {
      setError(
        "Este navegador não oferece suporte à gravação de áudio."
      );
      return;
    }

    setError("");
    discardRecordingRef.current = false;

    try {
      const stream =
        await navigator.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true
          }
        });

      mediaStreamRef.current = stream;

      const mimeType =
        preferredRecordingMimeType();

      const recorder = mimeType
        ? new MediaRecorder(stream, {
            mimeType
          })
        : new MediaRecorder(stream);

      mediaRecorderRef.current = recorder;
      audioChunksRef.current = [];

      recorder.ondataavailable = event => {
        if (event.data.size > 0) {
          audioChunksRef.current.push(
            event.data
          );
        }
      };

      recorder.onerror = () => {
        setError(
          "A gravação de áudio foi interrompida pelo navegador."
        );
      };

      recorder.onstop = () => {
        stopRecordingResources();
        setRecording(false);
        setRecordingSeconds(0);

        if (discardRecordingRef.current) {
          audioChunksRef.current = [];
          discardRecordingRef.current = false;
          return;
        }

        const finalMimeType =
          recorder.mimeType ||
          mimeType ||
          "audio/webm";

        const blob = new Blob(
          audioChunksRef.current,
          {
            type: finalMimeType
          }
        );

        audioChunksRef.current = [];

        if (blob.size === 0) {
          setError(
            "O navegador não gerou conteúdo para esta gravação."
          );
          return;
        }

        const extension =
          recordingExtension(
            finalMimeType
          );

        const stamp = new Date()
          .toISOString()
          .replace(/[:.]/g, "-");

        const file = new File(
          [blob],
          \`audio-wapp-\${stamp}.\${extension}\`,
          {
            type: finalMimeType
          }
        );

        const maxBytes =
          25 * 1024 * 1024;

        if (file.size > maxBytes) {
          setError(
            "A gravação excedeu o limite de 25 MB."
          );
          return;
        }

        setAttachment(file);
      };

      recorder.start(250);

      recordingStartedAtRef.current =
        Date.now();

      setRecordingSeconds(0);
      setRecording(true);

      recordingTimerRef.current =
        window.setInterval(() => {
          const startedAt =
            recordingStartedAtRef.current;

          if (!startedAt) {
            return;
          }

          setRecordingSeconds(
            Math.floor(
              (Date.now() - startedAt) /
                1000
            )
          );
        }, 250);
    } catch (caught) {
      stopRecordingResources();

      if (
        caught instanceof DOMException &&
        (caught.name === "NotAllowedError" ||
          caught.name ===
            "PermissionDeniedError")
      ) {
        setError(
          "Permita o acesso ao microfone para gravar áudio."
        );
        return;
      }

      setError(
        "Não foi possível iniciar o microfone."
      );
    }
  }

  function stopRecording() {
    const recorder =
      mediaRecorderRef.current;

    if (
      !recorder ||
      recorder.state === "inactive"
    ) {
      return;
    }

    recorder.stop();
  }

  function cancelRecording() {
    discardRecordingRef.current = true;

    const recorder =
      mediaRecorderRef.current;

    if (
      recorder &&
      recorder.state !== "inactive"
    ) {
      recorder.stop();
      return;
    }

    stopRecordingResources();
    setRecording(false);
    setRecordingSeconds(0);
  }

`;

  content = content.replace(
    anchor,
    `${functions}${anchor}`
  );
}

/* -----------------------------------------------------------------------
 * Do not submit while the recorder is active.
 * --------------------------------------------------------------------- */

content = content.replace(
  `      !selectedId ||
      (!text.trim() && !attachment)`,
  `      !selectedId ||
      recording ||
      (!text.trim() && !attachment)`
);

/* -----------------------------------------------------------------------
 * Form class gains voice capability.
 * --------------------------------------------------------------------- */

content = content.replace(
  'className="conversation-composer conversation-composer--attachments"',
  'className="conversation-composer conversation-composer--attachments conversation-composer--voice"'
);

/* -----------------------------------------------------------------------
 * Audio preview in selected attachment card.
 * --------------------------------------------------------------------- */

const oldMediaPreview = `{attachmentPreviewUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          alt="Prévia do anexo"
                          src={attachmentPreviewUrl}
                        />
                      ) : (
                        <div className="composer-attachment-preview__icon">
                          ARQ
                        </div>
                      )}`;

const newMediaPreview = `{attachmentPreviewUrl &&
                      attachment.type.startsWith("image/") ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          alt="Prévia do anexo"
                          src={attachmentPreviewUrl}
                        />
                      ) : (
                        <div className="composer-attachment-preview__icon">
                          {attachment.type.startsWith("audio/")
                            ? "ÁUDIO"
                            : "ARQ"}
                        </div>
                      )}`;

if (content.includes(oldMediaPreview)) {
  content = content.replace(
    oldMediaPreview,
    newMediaPreview
  );
}

if (
  !content.includes(
    'className="composer-attachment-preview__audio"'
  )
) {
  const removeAnchor = `                      <button
                        aria-label="Remover anexo"
                        className="composer-attachment-preview__remove"`;

  if (!content.includes(removeAnchor)) {
    throw new Error(
      "Could not find attachment remove button."
    );
  }

  content = content.replace(
    removeAnchor,
    `                      {attachmentPreviewUrl &&
                        attachment.type.startsWith("audio/") && (
                          <audio
                            className="composer-attachment-preview__audio"
                            controls
                            preload="metadata"
                            src={attachmentPreviewUrl}
                          />
                        )}

${removeAnchor}`
  );
}

/* -----------------------------------------------------------------------
 * Recording status + microphone button.
 * --------------------------------------------------------------------- */

if (!content.includes('className="composer-recording"')) {
  const attachButton = `                  <button
                    aria-label="Anexar arquivo"
                    className="composer__attach"
                    disabled={sending}
                    onClick={() =>
                      attachmentInputRef.current?.click()
                    }
                    type="button"
                  >
                    +
                  </button>`;

  if (!content.includes(attachButton)) {
    throw new Error(
      "Could not find P1.3 attachment button."
    );
  }

  const recordingUi = `                  {recording && (
                    <div className="composer-recording">
                      <span
                        className="composer-recording__dot"
                        aria-hidden="true"
                      />
                      <strong>Gravando áudio</strong>
                      <time>
                        {recordingTimeLabel(
                          recordingSeconds
                        )}
                      </time>
                      <button
                        className="composer-recording__cancel"
                        onClick={cancelRecording}
                        type="button"
                      >
                        Cancelar
                      </button>
                    </div>
                  )}

${attachButton.replace(
  "disabled={sending}",
  "disabled={sending || recording}"
)}

                  <button
                    aria-label={
                      recording
                        ? "Parar gravação"
                        : "Gravar áudio"
                    }
                    className={
                      recording
                        ? "composer__record composer__record--active"
                        : "composer__record"
                    }
                    disabled={
                      sending ||
                      (!!attachment && !recording)
                    }
                    onClick={() => {
                      if (recording) {
                        stopRecording();
                      } else {
                        void startRecording();
                      }
                    }}
                    type="button"
                  >
                    {recording ? "■" : "●"}
                  </button>`;

  content = content.replace(
    attachButton,
    recordingUi
  );
}

/* -----------------------------------------------------------------------
 * Text area and send button state.
 * --------------------------------------------------------------------- */

if (
  content.includes(
    'placeholder="Digite uma mensagem…"'
  ) &&
  !content.includes(
    'disabled={recording}\n                  maxLength={4096}'
  )
) {
  content = content.replace(
    `                <textarea
                  maxLength={4096}`,
    `                <textarea
                  disabled={recording}
                  maxLength={4096}`
  );
}

content = content.replace(
  `disabled={sending || (!text.trim() && !attachment)}`,
  `disabled={
                    sending ||
                    recording ||
                    (!text.trim() && !attachment)
                  }`
);

fs.writeFileSync(path, content);

console.log("Browser microphone recorder installed.");
NODE

if ! grep -q "WAPP P1.4 / Browser audio recording" "$CSS"; then
  cat >> "$CSS" <<'EOF'

/* --- WAPP P1.4 / Browser audio recording ------------------------------ */

.conversation-composer--voice {
  grid-template-columns:
    42px
    42px
    minmax(0, 1fr)
    46px !important;
}

.composer__record {
  display: grid;
  width: 42px;
  height: 46px;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: var(--surface-subtle);
  color: var(--muted);
  font-size: 13px;
}

.composer__record:hover:not(:disabled) {
  border-color: var(--line-strong);
  background: #fff;
  color: var(--ink);
}

.composer__record--active {
  border-color: #d6aaa7;
  background: #fff2f0;
  color: #a63f37;
}

.composer__record:disabled {
  opacity: 0.4;
}

.composer-recording {
  display: grid;
  grid-column: 1 / -1;
  grid-template-columns:
    10px
    auto
    1fr
    auto;
  align-items: center;
  gap: 9px;
  min-height: 46px;
  border: 1px solid #ead1ce;
  border-radius: 12px;
  background: #fff7f5;
  padding: 9px 11px;
}

.composer-recording__dot {
  width: 8px;
  height: 8px;
  border-radius: 999px;
  background: #b7473e;
  animation:
    wapp-recording-pulse
    1.15s ease-in-out
    infinite;
}

.composer-recording strong {
  font-size: 10px;
}

.composer-recording time {
  color: var(--muted);
  font-variant-numeric: tabular-nums;
  font-size: 10px;
}

.composer-recording__cancel {
  border: 0;
  background: transparent;
  color: #9b4b45;
  padding: 4px 5px;
  font-size: 9px;
  font-weight: 750;
}

@keyframes wapp-recording-pulse {
  0%,
  100% {
    opacity: 1;
    transform: scale(1);
  }

  50% {
    opacity: 0.35;
    transform: scale(0.78);
  }
}

.composer-attachment-preview__audio {
  display: block;
  width: 100%;
  height: 36px;
  grid-column: 1 / -1;
  grid-row: 2;
}

.composer-attachment-preview__remove {
  grid-column: 3;
  grid-row: 1;
}

@media (max-width: 620px) {
  .conversation-composer--voice {
    grid-template-columns:
      38px
      38px
      minmax(0, 1fr)
      44px !important;
  }

  .composer__record {
    width: 38px;
    height: 44px;
  }

  .composer-recording {
    grid-template-columns:
      10px
      1fr
      auto;
  }

  .composer-recording time {
    justify-self: end;
  }

  .composer-recording__cancel {
    grid-column: 2 / -1;
    justify-self: start;
    padding-left: 0;
  }
}
EOF
fi

cat > docs/AUDIO_RECORDING.md <<'EOF'
# Browser audio recording

P1.4 adds microphone capture to the existing P1.3 outbound-media flow.

No new API route or database migration is required.

## Flow

```text
operator clicks microphone
        |
        v
getUserMedia(audio)
        |
        v
MediaRecorder
        |
        v
Blob / File
        |
        v
local audio preview
        |
        v
existing P1.3 multipart upload
        |
        v
Evolution sendMedia
        |
        v
WhatsApp
```

## Browser formats

Wapp selects the first format supported by the browser from:

1. `audio/ogg;codecs=opus`
2. `audio/webm;codecs=opus`
3. `audio/webm`
4. `audio/mp4`

The server already normalizes MIME parameters before classifying outbound audio.

## UX and failure behavior

- Recording requires explicit microphone permission.
- The operator can stop or cancel a recording.
- After stopping, the recording becomes the selected attachment.
- The recording can be played before sending.
- The selected recording is preserved when the API/Evolution send fails.
- The existing 25 MiB upload limit still applies.

P1.4 sends the capture through the normal audio-media path. A future milestone
can introduce WhatsApp-native PTT/voice-note semantics if required.
EOF

echo "[P1.4] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.4] Browser audio recording installed."
echo "No Prisma migration is required."
echo
echo "Restart if needed:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Test:"
echo "  1. click the microphone"
echo "  2. allow microphone permission"
echo "  3. record for a few seconds"
echo "  4. stop"
echo "  5. play the preview"
echo "  6. send"
