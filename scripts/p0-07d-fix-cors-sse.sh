#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_FILE="apps/api/src/app.ts"
REALTIME_FILE="apps/api/src/modules/realtime/realtime.routes.ts"

for required in "$APP_FILE" "$REALTIME_FILE"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

echo "[P0.7d] Fixing CORS for operational routes and SSE..."

node <<'NODE'
const fs = require("node:fs");

function fixAppCors() {
  const path = "apps/api/src/app.ts";
  let content = fs.readFileSync(path, "utf8");

  const oldBlock = `  await app.register(cors, {
    origin: env.WEB_URL,
    credentials: true
  });`;

  const newBlock = `  await app.register(cors, {
    origin: env.WEB_URL,
    credentials: true,
    methods: [
      "GET",
      "HEAD",
      "POST",
      "PUT",
      "PATCH",
      "DELETE",
      "OPTIONS"
    ],
    allowedHeaders: [
      "Content-Type",
      "Authorization",
      "Accept"
    ]
  });`;

  if (content.includes(newBlock)) {
    console.log("CORS methods already configured.");
    return;
  }

  if (!content.includes(oldBlock)) {
    throw new Error(
      "Could not find the expected @fastify/cors registration in app.ts."
    );
  }

  content = content.replace(oldBlock, newBlock);
  fs.writeFileSync(path, content);
  console.log("Enabled PUT/PATCH/DELETE/OPTIONS in API CORS.");
}

function fixRealtimeCors() {
  const path =
    "apps/api/src/modules/realtime/realtime.routes.ts";

  let content = fs.readFileSync(path, "utf8");

  const envImport =
    'import { env } from "../../config/env.js";';

  if (!content.includes(envImport)) {
    const fastifyImport =
      'import type { FastifyInstance } from "fastify";';

    if (!content.includes(fastifyImport)) {
      throw new Error(
        "Could not find Fastify import in realtime.routes.ts."
      );
    }

    content = content.replace(
      fastifyImport,
      `${fastifyImport}\n\n${envImport}`
    );
  }

  const oldHeaders = `    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no"
    });`;

  const newHeaders = `    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
      "Access-Control-Allow-Origin": env.WEB_URL,
      "Access-Control-Allow-Credentials": "true",
      Vary: "Origin"
    });`;

  if (content.includes(newHeaders)) {
    console.log("Realtime SSE CORS headers already configured.");
  } else if (content.includes(oldHeaders)) {
    content = content.replace(oldHeaders, newHeaders);
    console.log("Added explicit CORS headers to hijacked SSE response.");
  } else {
    throw new Error(
      "Could not find the expected SSE writeHead block."
    );
  }

  fs.writeFileSync(path, content);
}

fixAppCors();
fixRealtimeCors();
NODE

echo "[P0.7d] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.7d] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.7d] CORS repaired."
echo
echo "Restart the development server:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Then test:"
echo "  1. Open /dashboard/queues"
echo "  2. Check Miguel Almeida in Comercial"
echo "  3. Confirm the counter becomes 1 atendente"
echo "  4. Keep DevTools open and verify /realtime/events remains pending without CORS errors"
