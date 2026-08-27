#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PAGE="apps/web/app/dashboard/conversations/page.tsx"

if [[ ! -f "$PAGE" ]]; then
  echo "ERROR: missing $PAGE"
  exit 1
fi

if ! grep -Fq 'async function startRecording()' "$PAGE"; then
  echo "ERROR: P1.4 browser recording is not present."
  exit 1
fi

echo "[P1.4b] Installing WebM duration metadata fix..."
pnpm --filter @wapp/web add fix-webm-duration@1.0.6

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/web/app/dashboard/conversations/page.tsx";

let content = fs.readFileSync(path, "utf8");

/* Import */
const importLine =
  'import fixWebmDuration from "fix-webm-duration";';

if (!content.includes(importLine)) {
  const anchor =
    'import { useRouter } from "next/navigation";';

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find next/navigation import."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}\nimport fixWebmDuration from "fix-webm-duration";`
  );
}

/*
 * MediaRecorder WebM output may omit Duration metadata.
 * Capture duration BEFORE stopRecordingResources() clears the start timestamp.
 */
const oldStart = `      recorder.onstop = () => {
        stopRecordingResources();
        setRecording(false);
        setRecordingSeconds(0);`;

const newStart = `      recorder.onstop = async () => {
        const startedAt =
          recordingStartedAtRef.current;

        const durationMs = startedAt
          ? Math.max(
              1,
              Date.now() - startedAt
            )
          : 1;

        stopRecordingResources();
        setRecording(false);
        setRecordingSeconds(0);`;

if (content.includes(oldStart)) {
  content = content.replace(
    oldStart,
    newStart
  );
} else if (
  !content.includes(
    "const durationMs = startedAt"
  )
) {
  throw new Error(
    "Could not find P1.4 recorder onstop block."
  );
}

/* Change blob to mutable so WebM can be repaired. */
const oldBlob = `        const blob = new Blob(
          audioChunksRef.current,
          {
            type: finalMimeType
          }
        );

        audioChunksRef.current = [];

        if (blob.size === 0) {`;

const newBlob = `        let blob = new Blob(
          audioChunksRef.current,
          {
            type: finalMimeType
          }
        );

        audioChunksRef.current = [];

        if (blob.size === 0) {`;

if (content.includes(oldBlob)) {
  content = content.replace(
    oldBlob,
    newBlob
  );
} else if (
  !content.includes(
    "let blob = new Blob("
  )
) {
  throw new Error(
    "Could not find P1.4 audio Blob block."
  );
}

/* Repair WebM duration before creating the File. */
if (
  !content.includes(
    "[P1.4b WebM duration metadata]"
  )
) {
  const anchor = `        if (blob.size === 0) {
          setError(
            "O navegador não gerou conteúdo para esta gravação."
          );
          return;
        }

        const extension =`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Could not find empty recording validation block."
    );
  }

  const replacement = `        if (blob.size === 0) {
          setError(
            "O navegador não gerou conteúdo para esta gravação."
          );
          return;
        }

        // [P1.4b WebM duration metadata]
        // Chromium can produce MediaRecorder WebM blobs without Duration.
        // Repair it before preview/upload so the player knows the real length.
        if (
          finalMimeType
            .toLowerCase()
            .startsWith("audio/webm")
        ) {
          try {
            blob = await fixWebmDuration(
              blob,
              durationMs,
              {
                logger: false
              }
            );
          } catch {
            // Keep the original recording if metadata repair fails.
            // Sending audio must not depend on the preview-only correction.
          }
        }

        const extension =`;

  content = content.replace(
    anchor,
    replacement
  );
}

fs.writeFileSync(path, content);

console.log("WebM recordings now receive explicit duration metadata.");
NODE

echo "[P1.4b] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.4b] WebM duration fix installed."
echo "No API change or Prisma migration is required."
echo
echo "Restart if needed:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Record a fresh 5-10 second audio and verify the preview duration."
