#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.5] Building WhatsApp / Evolution foundation..."

for required in \
  "apps/api/package.json" \
  "apps/api/prisma/schema.prisma" \
  "apps/api/src/app.ts" \
  "apps/api/src/config/env.ts" \
  "apps/web/package.json" \
  "apps/web/components/auth-provider.tsx"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  infra/evolution \
  apps/api/src/integrations/whatsapp \
  apps/api/src/modules/whatsapp \
  apps/api/src/modules/webhooks \
  apps/web/app/dashboard/connections \
  docs

# ---------------------------------------------------------------------------
# Git ignore
# ---------------------------------------------------------------------------

IGNORE_MARKER="# --- WAPP P0.5 ---"
if ! grep -Fq "$IGNORE_MARKER" .gitignore 2>/dev/null; then
  cat >> .gitignore <<'EOF'

# --- WAPP P0.5 ---
infra/evolution/.env
# --- /WAPP P0.5 ---
EOF
fi

# ---------------------------------------------------------------------------
# Evolution local infrastructure
# ---------------------------------------------------------------------------

cat > infra/evolution/.env.example <<'EOF'
EVOLUTION_API_KEY=change-me-generate-a-random-key
EVOLUTION_POSTGRES_PASSWORD=change-me-local-password
EOF

read_env_value() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2- || true
}

random_hex() {
  node -e 'console.log(require("node:crypto").randomBytes(32).toString("hex"))'
}

EVOLUTION_ENV_FILE="infra/evolution/.env"

if [[ ! -f "$EVOLUTION_ENV_FILE" ]]; then
  EVOLUTION_API_KEY="$(random_hex)"
  EVOLUTION_POSTGRES_PASSWORD="$(node -e 'console.log(require("node:crypto").randomBytes(20).toString("hex"))')"

  cat > "$EVOLUTION_ENV_FILE" <<EOF
EVOLUTION_API_KEY=${EVOLUTION_API_KEY}
EVOLUTION_POSTGRES_PASSWORD=${EVOLUTION_POSTGRES_PASSWORD}
EOF

  echo "Created local Evolution secrets: $EVOLUTION_ENV_FILE"
else
  EVOLUTION_API_KEY="$(read_env_value "$EVOLUTION_ENV_FILE" "EVOLUTION_API_KEY")"

  if [[ -z "$EVOLUTION_API_KEY" ]]; then
    EVOLUTION_API_KEY="$(random_hex)"
    echo "EVOLUTION_API_KEY=${EVOLUTION_API_KEY}" >> "$EVOLUTION_ENV_FILE"
  fi
fi

cat > infra/evolution/docker-compose.yml <<'EOF'
services:
  evolution-postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: evolution
      POSTGRES_USER: evolution
      POSTGRES_PASSWORD: ${EVOLUTION_POSTGRES_PASSWORD}
    volumes:
      - evolution_postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U evolution -d evolution"]
      interval: 5s
      timeout: 5s
      retries: 20

  evolution-redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - evolution_redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 20

  evolution-api:
    image: evoapicloud/evolution-api:v2.3.7
    restart: unless-stopped
    depends_on:
      evolution-postgres:
        condition: service_healthy
      evolution-redis:
        condition: service_healthy
    ports:
      - "8080:8080"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      SERVER_NAME: wapp-evolution
      SERVER_TYPE: http
      SERVER_PORT: 8080
      SERVER_URL: http://localhost:8080

      DATABASE_PROVIDER: postgresql
      DATABASE_CONNECTION_URI: postgresql://evolution:${EVOLUTION_POSTGRES_PASSWORD}@evolution-postgres:5432/evolution
      DATABASE_CONNECTION_CLIENT_NAME: wapp-evolution

      CACHE_REDIS_ENABLED: "true"
      CACHE_REDIS_URI: redis://evolution-redis:6379
      CACHE_REDIS_PREFIX_KEY: wapp-evolution
      CACHE_REDIS_SAVE_INSTANCES: "true"
      CACHE_LOCAL_ENABLED: "false"

      AUTHENTICATION_API_KEY: ${EVOLUTION_API_KEY}
      AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES: "false"

      CONFIG_SESSION_PHONE_CLIENT: Wapp
      CONFIG_SESSION_PHONE_NAME: Chrome
      QRCODE_LIMIT: 30

      LANGUAGE: pt-BR
      LOG_LEVEL: ERROR,WARN,INFO
      LOG_COLOR: "true"
      LOG_BAILEYS: error

      TELEMETRY_ENABLED: "false"

      WEBHOOK_GLOBAL_ENABLED: "false"

      TYPEBOT_ENABLED: "false"
      CHATWOOT_ENABLED: "false"
      OPENAI_ENABLED: "false"
      DIFY_ENABLED: "false"
      N8N_ENABLED: "false"
      EVOAI_ENABLED: "false"
      FLOWISE_ENABLED: "false"

    volumes:
      - evolution_instances:/evolution/instances

volumes:
  evolution_postgres:
  evolution_redis:
  evolution_instances:
EOF

# ---------------------------------------------------------------------------
# Wapp API local env
# ---------------------------------------------------------------------------

API_ENV="apps/api/.env"
API_ENV_EXAMPLE="apps/api/.env.example"

append_env_if_missing() {
  local file="$1"
  local key="$2"
  local value="$3"

  touch "$file"

  if ! grep -Eq "^${key}=" "$file"; then
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

EVOLUTION_WEBHOOK_SECRET="$(read_env_value "$API_ENV" "EVOLUTION_WEBHOOK_SECRET")"
if [[ -z "$EVOLUTION_WEBHOOK_SECRET" ]]; then
  EVOLUTION_WEBHOOK_SECRET="$(random_hex)"
fi

append_env_if_missing "$API_ENV" "EVOLUTION_BASE_URL" "http://localhost:8080"
append_env_if_missing "$API_ENV" "EVOLUTION_API_KEY" "$EVOLUTION_API_KEY"
append_env_if_missing "$API_ENV" "EVOLUTION_WEBHOOK_BASE_URL" "http://host.docker.internal:4000"
append_env_if_missing "$API_ENV" "EVOLUTION_WEBHOOK_SECRET" "$EVOLUTION_WEBHOOK_SECRET"

if ! grep -Fq "# WhatsApp / Evolution" "$API_ENV_EXAMPLE"; then
  cat >> "$API_ENV_EXAMPLE" <<'EOF'

# WhatsApp / Evolution
EVOLUTION_BASE_URL=http://localhost:8080
EVOLUTION_API_KEY=change-me-use-the-same-key-as-infra-evolution
EVOLUTION_WEBHOOK_BASE_URL=http://host.docker.internal:4000
EVOLUTION_WEBHOOK_SECRET=change-me-generate-a-long-random-secret
EOF
fi

# ---------------------------------------------------------------------------
# Prisma model
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "apps/api/prisma/schema.prisma";
let schema = fs.readFileSync(path, "utf8");

if (!schema.includes("enum WhatsAppConnectionStatus")) {
  const enumAnchor = "enum MembershipRole {";

  const enums = `enum WhatsAppProvider {
  EVOLUTION_BAILEYS
  META_CLOUD
}

enum WhatsAppConnectionStatus {
  CREATED
  CONNECTING
  CONNECTED
  DISCONNECTED
  ERROR
}

`;

  if (!schema.includes(enumAnchor)) {
    throw new Error("Could not find MembershipRole enum anchor in Prisma schema.");
  }

  schema = schema.replace(enumAnchor, enums + enumAnchor);
}

if (
  !schema.includes("whatsappConnections WhatsAppConnection[]") &&
  schema.includes("memberships CompanyMembership[]")
) {
  schema = schema.replace(
    "memberships CompanyMembership[]",
    "memberships CompanyMembership[]\n  whatsappConnections WhatsAppConnection[]"
  );
}

if (!schema.includes("model WhatsAppConnection {")) {
  schema += `

model WhatsAppConnection {
  id           String                   @id @default(uuid()) @db.Char(36)
  companyId    String                   @db.Char(36)
  name         String                   @db.VarChar(120)
  provider     WhatsAppProvider         @default(EVOLUTION_BAILEYS)
  instanceName String                   @unique @db.VarChar(120)
  status       WhatsAppConnectionStatus @default(CREATED)
  phoneNumber  String?                  @db.VarChar(32)
  profileName  String?                  @db.VarChar(160)
  lastError    String?                  @db.Text
  lastEventAt  DateTime?
  company      Company                  @relation(fields: [companyId], references: [id], onDelete: Cascade)
  createdAt    DateTime                 @default(now())
  updatedAt    DateTime                 @updatedAt

  @@index([companyId, status])
  @@index([companyId, createdAt])
}
`;
}

fs.writeFileSync(path, schema);
NODE

# ---------------------------------------------------------------------------
# API env validation
# ---------------------------------------------------------------------------

cat > apps/api/src/config/env.ts <<'EOF'
import "dotenv/config";

import { z } from "zod";

const booleanFromEnv = z
  .enum(["true", "false"])
  .default("false")
  .transform(value => value === "true");

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("0.0.0.0"),
  PORT: z.coerce.number().int().positive().default(4000),
  WEB_URL: z.string().url().default("http://localhost:3000"),

  DATABASE_URL: z.string().url().startsWith("mysql://"),
  REDIS_URL: z.string().min(1).optional(),

  JWT_SECRET: z.string().min(32),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  COOKIE_SECURE: booleanFromEnv,

  EVOLUTION_BASE_URL: z.string().url().default("http://localhost:8080"),
  EVOLUTION_API_KEY: z.string().min(32),
  EVOLUTION_WEBHOOK_BASE_URL: z.string().url(),
  EVOLUTION_WEBHOOK_SECRET: z.string().min(32),

  WHATSAPP_SESSION_PATH: z.string().default(".runtime/whatsapp"),
  TYPEBOT_URL: z.string().url().optional().or(z.literal(""))
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error(
    "Invalid environment configuration",
    parsed.error.flatten().fieldErrors
  );
  process.exit(1);
}

export const env = parsed.data;
EOF

# ---------------------------------------------------------------------------
# Evolution provider
# ---------------------------------------------------------------------------

cat > apps/api/src/integrations/whatsapp/provider.ts <<'EOF'
export interface CreateWhatsAppInstanceInput {
  instanceName: string;
  webhookUrl: string;
}

export interface WhatsAppQrResult {
  code?: string;
  base64?: string;
  pairingCode?: string;
  count?: number;
}

export interface WhatsAppConnectionState {
  state: string;
}

export interface SendTextInput {
  instanceName: string;
  number: string;
  text: string;
}

export interface WhatsAppProviderClient {
  createInstance(
    input: CreateWhatsAppInstanceInput
  ): Promise<WhatsAppQrResult>;

  connect(instanceName: string): Promise<WhatsAppQrResult>;

  connectionState(
    instanceName: string
  ): Promise<WhatsAppConnectionState>;

  sendText(input: SendTextInput): Promise<unknown>;
}
EOF

cat > apps/api/src/integrations/whatsapp/evolution.client.ts <<'EOF'
import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import type {
  CreateWhatsAppInstanceInput,
  SendTextInput,
  WhatsAppConnectionState,
  WhatsAppProviderClient,
  WhatsAppQrResult
} from "./provider.js";

interface EvolutionErrorBody {
  status?: number;
  error?: string;
  response?: {
    message?: string | string[];
  };
  message?: string;
}

interface EvolutionCreateResponse {
  qrcode?: {
    code?: string;
    base64?: string;
    pairingCode?: string;
    count?: number;
  };
  instance?: {
    instanceName?: string;
    instanceId?: string;
    status?: string;
  };
}

interface EvolutionConnectResponse {
  code?: string;
  base64?: string;
  pairingCode?: string;
  count?: number;
}

interface EvolutionStateResponse {
  instance?: {
    instanceName?: string;
    state?: string;
  };
}

function evolutionMessage(body: EvolutionErrorBody | undefined) {
  const responseMessage = body?.response?.message;

  if (Array.isArray(responseMessage)) {
    return responseMessage.join(" ");
  }

  return (
    responseMessage ??
    body?.message ??
    body?.error ??
    "Evolution API request failed."
  );
}

export class EvolutionWhatsAppClient implements WhatsAppProviderClient {
  private async request<T>(
    path: string,
    init: RequestInit = {}
  ): Promise<T> {
    let response: Response;

    try {
      response = await fetch(`${env.EVOLUTION_BASE_URL}${path}`, {
        ...init,
        headers: {
          apikey: env.EVOLUTION_API_KEY,
          ...(init.body ? { "Content-Type": "application/json" } : {}),
          ...init.headers
        },
        signal: AbortSignal.timeout(15_000)
      });
    } catch (error) {
      throw new AppError(
        "Não foi possível acessar a Evolution API.",
        502,
        "EVOLUTION_UNAVAILABLE",
        error instanceof Error ? error.message : undefined
      );
    }

    let body: unknown;

    try {
      body = await response.json();
    } catch {
      body = undefined;
    }

    if (!response.ok) {
      throw new AppError(
        evolutionMessage(body as EvolutionErrorBody | undefined),
        502,
        "EVOLUTION_ERROR",
        {
          upstreamStatus: response.status
        }
      );
    }

    return body as T;
  }

  async createInstance(
    input: CreateWhatsAppInstanceInput
  ): Promise<WhatsAppQrResult> {
    const response = await this.request<EvolutionCreateResponse>(
      "/instance/create",
      {
        method: "POST",
        body: JSON.stringify({
          instanceName: input.instanceName,
          qrcode: true,
          integration: "WHATSAPP-BAILEYS",
          groupsIgnore: false,
          alwaysOnline: false,
          readMessages: false,
          readStatus: false,
          syncFullHistory: false,
          webhook: {
            url: input.webhookUrl,
            byEvents: false,
            base64: false,
            events: [
              "QRCODE_UPDATED",
              "MESSAGES_UPSERT",
              "CONNECTION_UPDATE"
            ]
          }
        })
      }
    );

    return {
      code: response.qrcode?.code,
      base64: response.qrcode?.base64,
      pairingCode: response.qrcode?.pairingCode,
      count: response.qrcode?.count
    };
  }

  async connect(instanceName: string): Promise<WhatsAppQrResult> {
    const response = await this.request<EvolutionConnectResponse>(
      `/instance/connect/${encodeURIComponent(instanceName)}`
    );

    return {
      code: response.code,
      base64: response.base64,
      pairingCode: response.pairingCode,
      count: response.count
    };
  }

  async connectionState(
    instanceName: string
  ): Promise<WhatsAppConnectionState> {
    const response = await this.request<EvolutionStateResponse>(
      `/instance/connectionState/${encodeURIComponent(instanceName)}`
    );

    return {
      state: response.instance?.state ?? "unknown"
    };
  }

  async sendText(input: SendTextInput): Promise<unknown> {
    return this.request(
      `/message/sendText/${encodeURIComponent(input.instanceName)}`,
      {
        method: "POST",
        body: JSON.stringify({
          number: input.number,
          text: input.text
        })
      }
    );
  }
}

export const evolutionWhatsAppClient = new EvolutionWhatsAppClient();
EOF

# ---------------------------------------------------------------------------
# WhatsApp module
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/whatsapp/whatsapp.service.ts <<'EOF'
import { randomBytes } from "node:crypto";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { evolutionWhatsAppClient } from "../../integrations/whatsapp/evolution.client.js";
import { prisma } from "../../lib/database.js";

function normalizeInstancePart(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 45);
}

function instanceName(companySlug: string, name: string) {
  const company = normalizeInstancePart(companySlug) || "company";
  const connection = normalizeInstancePart(name) || "whatsapp";
  const suffix = randomBytes(4).toString("hex");

  return `wapp-${company}-${connection}-${suffix}`.slice(0, 100);
}

function webhookUrl() {
  return `${env.EVOLUTION_WEBHOOK_BASE_URL}/api/v1/webhooks/evolution/${env.EVOLUTION_WEBHOOK_SECRET}`;
}

function mapEvolutionState(
  state: string
): "CREATED" | "CONNECTING" | "CONNECTED" | "DISCONNECTED" | "ERROR" {
  switch (state.toLowerCase()) {
    case "open":
    case "connected":
      return "CONNECTED";
    case "connecting":
      return "CONNECTING";
    case "close":
    case "closed":
    case "disconnected":
      return "DISCONNECTED";
    default:
      return "CREATED";
  }
}

export async function listConnections(companyId: string) {
  return prisma.whatsAppConnection.findMany({
    where: {
      companyId
    },
    orderBy: {
      createdAt: "desc"
    }
  });
}

export async function createConnection(input: {
  companyId: string;
  companySlug: string;
  name: string;
}) {
  const generatedInstanceName = instanceName(
    input.companySlug,
    input.name
  );

  const connection = await prisma.whatsAppConnection.create({
    data: {
      companyId: input.companyId,
      name: input.name.trim(),
      instanceName: generatedInstanceName,
      provider: "EVOLUTION_BAILEYS",
      status: "CREATED"
    }
  });

  try {
    const qr = await evolutionWhatsAppClient.createInstance({
      instanceName: generatedInstanceName,
      webhookUrl: webhookUrl()
    });

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: "CONNECTING",
        lastError: null,
        lastEventAt: new Date()
      }
    });

    return {
      connection: {
        ...connection,
        status: "CONNECTING" as const
      },
      qr
    };
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Evolution API error";

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: "ERROR",
        lastError: message,
        lastEventAt: new Date()
      }
    });

    throw error;
  }
}

export async function getCompanyConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await prisma.whatsAppConnection.findFirst({
    where: {
      id: connectionId,
      companyId
    }
  });

  if (!connection) {
    throw new AppError(
      "Conexão WhatsApp não encontrada.",
      404,
      "WHATSAPP_CONNECTION_NOT_FOUND"
    );
  }

  return connection;
}

export async function connectConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await getCompanyConnection(
    companyId,
    connectionId
  );

  const qr = await evolutionWhatsAppClient.connect(
    connection.instanceName
  );

  await prisma.whatsAppConnection.update({
    where: {
      id: connection.id
    },
    data: {
      status: "CONNECTING",
      lastError: null,
      lastEventAt: new Date()
    }
  });

  return {
    qr
  };
}

export async function syncConnection(
  companyId: string,
  connectionId: string
) {
  const connection = await getCompanyConnection(
    companyId,
    connectionId
  );

  try {
    const state = await evolutionWhatsAppClient.connectionState(
      connection.instanceName
    );

    return prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        status: mapEvolutionState(state.state),
        lastError: null,
        lastEventAt: new Date()
      }
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Evolution API error";

    await prisma.whatsAppConnection.update({
      where: {
        id: connection.id
      },
      data: {
        lastError: message,
        lastEventAt: new Date()
      }
    });

    throw error;
  }
}

export async function sendTestMessage(input: {
  companyId: string;
  connectionId: string;
  number: string;
  text: string;
}) {
  const connection = await getCompanyConnection(
    input.companyId,
    input.connectionId
  );

  if (connection.status !== "CONNECTED") {
    throw new AppError(
      "Conecte o WhatsApp antes de enviar mensagens.",
      409,
      "WHATSAPP_NOT_CONNECTED"
    );
  }

  return evolutionWhatsAppClient.sendText({
    instanceName: connection.instanceName,
    number: input.number,
    text: input.text
  });
}
EOF

cat > apps/api/src/modules/whatsapp/whatsapp.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import {
  requireAuth,
  requireRoles
} from "../auth/auth.guard.js";
import {
  connectConnection,
  createConnection,
  listConnections,
  sendTestMessage,
  syncConnection
} from "./whatsapp.service.js";

const connectionIdSchema = z.object({
  id: z.string().uuid()
});

const createConnectionSchema = z.object({
  name: z.string().trim().min(2).max(120)
});

const testMessageSchema = z.object({
  number: z
    .string()
    .trim()
    .regex(/^\d{10,15}$/, "Use somente números com DDI e DDD."),
  text: z.string().trim().min(1).max(4096)
});

export async function whatsappRoutes(app: FastifyInstance) {
  app.get("/api/v1/whatsapp/connections", async request => {
    const auth = await requireAuth(request);

    return {
      connections: await listConnections(auth.companyId)
    };
  });

  app.post("/api/v1/whatsapp/connections", async (request, reply) => {
    const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
    const input = createConnectionSchema.parse(request.body);

    const result = await createConnection({
      companyId: auth.companyId,
      companySlug: auth.company.slug,
      name: input.name
    });

    return reply.status(201).send(result);
  });

  app.post(
    "/api/v1/whatsapp/connections/:id/connect",
    async request => {
      const auth = await requireRoles(request, ["OWNER", "ADMIN"]);
      const params = connectionIdSchema.parse(request.params);

      return connectConnection(auth.companyId, params.id);
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/sync",
    async request => {
      const auth = await requireAuth(request);
      const params = connectionIdSchema.parse(request.params);

      return {
        connection: await syncConnection(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/test-message",
    async request => {
      const auth = await requireRoles(request, [
        "OWNER",
        "ADMIN",
        "SUPERVISOR"
      ]);

      const params = connectionIdSchema.parse(request.params);
      const input = testMessageSchema.parse(request.body);

      return {
        result: await sendTestMessage({
          companyId: auth.companyId,
          connectionId: params.id,
          number: input.number,
          text: input.text
        })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Evolution webhook
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/webhooks/evolution-webhook.routes.ts <<'EOF'
import { timingSafeEqual } from "node:crypto";

import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { env } from "../../config/env.js";
import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";

const paramsSchema = z.object({
  secret: z.string().min(1)
});

function secretsMatch(received: string, expected: string) {
  const receivedBuffer = Buffer.from(received);
  const expectedBuffer = Buffer.from(expected);

  return (
    receivedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(receivedBuffer, expectedBuffer)
  );
}

function normalizeEvent(value: unknown) {
  return String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/[.\-\s]+/g, "_");
}

function getInstanceName(body: Record<string, unknown>) {
  if (typeof body.instance === "string") {
    return body.instance;
  }

  if (typeof body.instanceName === "string") {
    return body.instanceName;
  }

  const data = body.data;

  if (data && typeof data === "object") {
    const dataRecord = data as Record<string, unknown>;

    if (typeof dataRecord.instance === "string") {
      return dataRecord.instance;
    }

    if (typeof dataRecord.instanceName === "string") {
      return dataRecord.instanceName;
    }
  }

  return undefined;
}

function connectionState(body: Record<string, unknown>) {
  const data = body.data;

  if (!data || typeof data !== "object") {
    return undefined;
  }

  const record = data as Record<string, unknown>;

  if (typeof record.state === "string") {
    return record.state;
  }

  if (typeof record.status === "string") {
    return record.status;
  }

  return undefined;
}

function mapState(state: string | undefined) {
  switch (state?.toLowerCase()) {
    case "open":
    case "connected":
      return "CONNECTED" as const;
    case "connecting":
      return "CONNECTING" as const;
    case "close":
    case "closed":
    case "disconnected":
      return "DISCONNECTED" as const;
    default:
      return undefined;
  }
}

export async function evolutionWebhookRoutes(
  app: FastifyInstance
) {
  app.post(
    "/api/v1/webhooks/evolution/:secret",
    async (request, reply) => {
      const params = paramsSchema.parse(request.params);

      if (
        !secretsMatch(
          params.secret,
          env.EVOLUTION_WEBHOOK_SECRET
        )
      ) {
        throw new AppError(
          "Webhook não autorizado.",
          401,
          "WEBHOOK_UNAUTHORIZED"
        );
      }

      if (!request.body || typeof request.body !== "object") {
        return reply.status(204).send();
      }

      const body = request.body as Record<string, unknown>;
      const event = normalizeEvent(body.event);
      const instance = getInstanceName(body);

      if (!instance) {
        request.log.warn(
          { event },
          "Evolution webhook without instance name"
        );

        return reply.status(204).send();
      }

      const connection = await prisma.whatsAppConnection.findUnique({
        where: {
          instanceName: instance
        }
      });

      if (!connection) {
        request.log.warn(
          { event, instance },
          "Evolution webhook for unknown instance"
        );

        return reply.status(204).send();
      }

      if (event === "CONNECTION_UPDATE") {
        const mappedState = mapState(connectionState(body));

        if (mappedState) {
          const data =
            body.data && typeof body.data === "object"
              ? (body.data as Record<string, unknown>)
              : {};

          const owner =
            typeof data.wuid === "string"
              ? data.wuid
              : typeof data.number === "string"
                ? data.number
                : undefined;

          await prisma.whatsAppConnection.update({
            where: {
              id: connection.id
            },
            data: {
              status: mappedState,
              phoneNumber: owner?.replace(/\D/g, "") || undefined,
              lastError: null,
              lastEventAt: new Date()
            }
          });
        }
      } else {
        await prisma.whatsAppConnection.update({
          where: {
            id: connection.id
          },
          data: {
            lastEventAt: new Date()
          }
        });
      }

      if (event === "MESSAGES_UPSERT") {
        request.log.info(
          {
            companyId: connection.companyId,
            connectionId: connection.id,
            instance
          },
          "Evolution message received; ingestion will be implemented in P0.6"
        );
      }

      return {
        received: true
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Register API routes
# ---------------------------------------------------------------------------

cat > apps/api/src/app.ts <<'EOF'
import cookie from "@fastify/cookie";
import cors from "@fastify/cors";
import Fastify from "fastify";
import { ZodError } from "zod";

import { env } from "./config/env.js";
import { AppError } from "./errors/app-error.js";
import { prisma } from "./lib/database.js";
import { adminRoutes } from "./modules/admin/admin.routes.js";
import { authRoutes } from "./modules/auth/auth.routes.js";
import { whatsappRoutes } from "./modules/whatsapp/whatsapp.routes.js";
import { evolutionWebhookRoutes } from "./modules/webhooks/evolution-webhook.routes.js";

export async function buildApp() {
  const app = Fastify({
    logger: {
      level: env.NODE_ENV === "production" ? "info" : "debug"
    }
  });

  await app.register(cors, {
    origin: env.WEB_URL,
    credentials: true
  });

  await app.register(cookie);

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof AppError) {
      return reply.status(error.statusCode).send({
        error: {
          code: error.code,
          message: error.message,
          details: error.details
        }
      });
    }

    if (error instanceof ZodError) {
      return reply.status(422).send({
        error: {
          code: "VALIDATION_ERROR",
          message: "Dados inválidos.",
          details: error.flatten().fieldErrors
        }
      });
    }

    request.log.error(error);

    return reply.status(500).send({
      error: {
        code: "INTERNAL_ERROR",
        message: "Erro interno do servidor."
      }
    });
  });

  app.get("/health", async () => {
    await prisma.$queryRaw`SELECT 1`;

    return {
      status: "ok",
      service: "wapp-api",
      database: "ok",
      timestamp: new Date().toISOString()
    };
  });

  app.get("/api/v1", async () => ({
    name: "Wapp API",
    version: "0.1.0"
  }));

  await app.register(authRoutes);
  await app.register(adminRoutes);
  await app.register(whatsappRoutes);
  await app.register(evolutionWebhookRoutes);

  app.addHook("onClose", async () => {
    await prisma.$disconnect();
  });

  return app;
}
EOF

# ---------------------------------------------------------------------------
# Web interface
# ---------------------------------------------------------------------------

echo "[P0.5] Installing QR renderer..."
pnpm --filter @wapp/web add qrcode
pnpm --filter @wapp/web add -D @types/qrcode

cat > apps/web/app/dashboard/connections/page.tsx <<'EOF'
"use client";

import QRCode from "qrcode";
import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type ConnectionStatus =
  | "CREATED"
  | "CONNECTING"
  | "CONNECTED"
  | "DISCONNECTED"
  | "ERROR";

interface WhatsAppConnection {
  id: string;
  name: string;
  provider: "EVOLUTION_BAILEYS" | "META_CLOUD";
  instanceName: string;
  status: ConnectionStatus;
  phoneNumber: string | null;
  profileName: string | null;
  lastError: string | null;
  lastEventAt: string | null;
  createdAt: string;
}

interface QrPayload {
  code?: string;
  base64?: string;
  pairingCode?: string;
  count?: number;
}

interface ListResponse {
  connections: WhatsAppConnection[];
}

interface CreateResponse {
  connection: WhatsAppConnection;
  qr: QrPayload;
}

interface ConnectResponse {
  qr: QrPayload;
}

interface SyncResponse {
  connection: WhatsAppConnection;
}

const statusLabels: Record<ConnectionStatus, string> = {
  CREATED: "Criada",
  CONNECTING: "Aguardando QR",
  CONNECTED: "Conectada",
  DISCONNECTED: "Desconectada",
  ERROR: "Erro"
};

function normalizeBase64(value?: string) {
  if (!value) {
    return undefined;
  }

  if (value.startsWith("data:image")) {
    return value;
  }

  return `data:image/png;base64,${value}`;
}

export default function ConnectionsPage() {
  const router = useRouter();
  const { session, loading, request } = useAuth();

  const [connections, setConnections] = useState<WhatsAppConnection[]>([]);
  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [qrConnectionId, setQrConnectionId] = useState<string | null>(null);
  const [qrImage, setQrImage] = useState<string | null>(null);
  const [pairingCode, setPairingCode] = useState<string | null>(null);
  const [testConnectionId, setTestConnectionId] = useState<string | null>(null);
  const [testNumber, setTestNumber] = useState("");
  const [testText, setTestText] = useState("Teste enviado pelo Wapp.");
  const [testResult, setTestResult] = useState("");

  const loadConnections = useCallback(async () => {
    const payload = await request<ListResponse>(
      "/api/v1/whatsapp/connections"
    );

    setConnections(payload.connections);
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void loadConnections().catch(() => {
        setError("Não foi possível carregar as conexões.");
      });
    }
  }, [loading, loadConnections, router, session]);

  useEffect(() => {
    if (!session) {
      return;
    }

    const timer = window.setInterval(() => {
      void Promise.all(
        connections
          .filter(connection =>
            ["CONNECTING", "CONNECTED", "DISCONNECTED"].includes(
              connection.status
            )
          )
          .map(async connection => {
            try {
              const payload = await request<SyncResponse>(
                `/api/v1/whatsapp/connections/${connection.id}/sync`,
                {
                  method: "POST"
                }
              );

              setConnections(current =>
                current.map(item =>
                  item.id === payload.connection.id
                    ? payload.connection
                    : item
                )
              );

              if (
                payload.connection.id === qrConnectionId &&
                payload.connection.status === "CONNECTED"
              ) {
                setQrConnectionId(null);
                setQrImage(null);
                setPairingCode(null);
              }
            } catch {
              // The manual status and error remain visible on the card.
            }
          })
      );
    }, 5000);

    return () => window.clearInterval(timer);
  }, [connections, qrConnectionId, request, session]);

  async function showQr(connectionId: string, qr: QrPayload) {
    setQrConnectionId(connectionId);
    setPairingCode(qr.pairingCode ?? null);

    const imageFromEvolution = normalizeBase64(qr.base64);

    if (imageFromEvolution) {
      setQrImage(imageFromEvolution);
      return;
    }

    if (qr.code) {
      const image = await QRCode.toDataURL(qr.code, {
        width: 340,
        margin: 2,
        errorCorrectionLevel: "M"
      });

      setQrImage(image);
      return;
    }

    setQrImage(null);
  }

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setCreating(true);

    try {
      const payload = await request<CreateResponse>(
        "/api/v1/whatsapp/connections",
        {
          method: "POST",
          body: JSON.stringify({
            name
          })
        }
      );

      setConnections(current => [
        payload.connection,
        ...current.filter(item => item.id !== payload.connection.id)
      ]);

      setName("");
      await showQr(payload.connection.id, payload.qr);
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível criar a conexão."
      );
    } finally {
      setCreating(false);
    }
  }

  async function handleConnect(connection: WhatsAppConnection) {
    setBusyId(connection.id);
    setError("");

    try {
      const payload = await request<ConnectResponse>(
        `/api/v1/whatsapp/connections/${connection.id}/connect`,
        {
          method: "POST"
        }
      );

      await showQr(connection.id, payload.qr);
      await loadConnections();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível gerar o QR Code."
      );
    } finally {
      setBusyId(null);
    }
  }

  async function handleSync(connection: WhatsAppConnection) {
    setBusyId(connection.id);

    try {
      const payload = await request<SyncResponse>(
        `/api/v1/whatsapp/connections/${connection.id}/sync`,
        {
          method: "POST"
        }
      );

      setConnections(current =>
        current.map(item =>
          item.id === payload.connection.id
            ? payload.connection
            : item
        )
      );
    } finally {
      setBusyId(null);
    }
  }

  async function handleTestMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!testConnectionId) {
      return;
    }

    setBusyId(testConnectionId);
    setTestResult("");

    try {
      await request(
        `/api/v1/whatsapp/connections/${testConnectionId}/test-message`,
        {
          method: "POST",
          body: JSON.stringify({
            number: testNumber,
            text: testText
          })
        }
      );

      setTestResult("Mensagem enviada pela Evolution API.");
    } catch (caught) {
      setTestResult(
        caught instanceof ApiError
          ? caught.message
          : "Falha ao enviar mensagem."
      );
    } finally {
      setBusyId(null);
    }
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando conexões…</main>;
  }

  const isAdmin =
    session.role === "OWNER" || session.role === "ADMIN";

  return (
    <main className="connections-screen">
      <header className="connections-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">WhatsApp</span>
          <h1>Conexões</h1>
          <p>
            Cada conexão pertence à empresa ativa e é isolada em uma instância
            própria na Evolution API.
          </p>
        </div>

        <div className="connections-company">
          <span>{session.company.name}</span>
          <small>{session.role}</small>
        </div>
      </header>

      {error && <div className="form-error">{error}</div>}

      {isAdmin && (
        <form className="connection-create" onSubmit={handleCreate}>
          <div>
            <strong>Nova conexão</strong>
            <span>
              Crie uma instância e escaneie o QR Code com o WhatsApp.
            </span>
          </div>

          <input
            maxLength={120}
            onChange={event => setName(event.target.value)}
            placeholder="Ex.: Comercial, Suporte, Matriz"
            required
            value={name}
          />

          <button
            className="primary-button connection-create__button"
            disabled={creating}
            type="submit"
          >
            <span>{creating ? "Criando…" : "Criar conexão"}</span>
            <span>+</span>
          </button>
        </form>
      )}

      <section className="connection-list">
        {connections.length === 0 ? (
          <div className="connection-empty">
            <strong>Nenhuma conexão criada.</strong>
            <p>
              Crie a primeira instância para iniciar o vínculo com WhatsApp.
            </p>
          </div>
        ) : (
          connections.map(connection => (
            <article className="connection-card" key={connection.id}>
              <div className="connection-card__main">
                <div>
                  <div className="connection-card__title">
                    <h2>{connection.name}</h2>
                    <span
                      className={`connection-status connection-status--${connection.status.toLowerCase()}`}
                    >
                      {statusLabels[connection.status]}
                    </span>
                  </div>

                  <p>{connection.instanceName}</p>

                  <div className="connection-meta">
                    <span>
                      Provider <strong>Evolution / Baileys</strong>
                    </span>
                    {connection.phoneNumber && (
                      <span>
                        Número <strong>{connection.phoneNumber}</strong>
                      </span>
                    )}
                  </div>

                  {connection.lastError && (
                    <div className="connection-error">
                      {connection.lastError}
                    </div>
                  )}
                </div>

                <div className="connection-actions">
                  {isAdmin && connection.status !== "CONNECTED" && (
                    <button
                      className="secondary-button"
                      disabled={busyId === connection.id}
                      onClick={() => handleConnect(connection)}
                      type="button"
                    >
                      Gerar QR
                    </button>
                  )}

                  <button
                    className="ghost-button"
                    disabled={busyId === connection.id}
                    onClick={() => handleSync(connection)}
                    type="button"
                  >
                    Atualizar status
                  </button>

                  {connection.status === "CONNECTED" && (
                    <button
                      className="secondary-button"
                      onClick={() =>
                        setTestConnectionId(connection.id)
                      }
                      type="button"
                    >
                      Testar envio
                    </button>
                  )}
                </div>
              </div>
            </article>
          ))
        )}
      </section>

      {qrConnectionId && (
        <div className="modal-backdrop">
          <section className="qr-modal">
            <button
              aria-label="Fechar"
              className="modal-close"
              onClick={() => {
                setQrConnectionId(null);
                setQrImage(null);
                setPairingCode(null);
              }}
              type="button"
            >
              ×
            </button>

            <span className="eyebrow">Conectar aparelho</span>
            <h2>Escaneie pelo WhatsApp</h2>
            <p>
              No celular, abra WhatsApp → Aparelhos conectados → Conectar um
              aparelho.
            </p>

            {qrImage ? (
              <div className="qr-frame">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img alt="QR Code do WhatsApp" src={qrImage} />
              </div>
            ) : (
              <div className="qr-waiting">
                O QR ainda não foi retornado. Feche e tente gerar novamente
                em alguns segundos.
              </div>
            )}

            {pairingCode && (
              <div className="pairing-code">
                Código de pareamento: <strong>{pairingCode}</strong>
              </div>
            )}

            <small>
              A tela fecha automaticamente quando a conexão for identificada
              como conectada.
            </small>
          </section>
        </div>
      )}

      {testConnectionId && (
        <div className="modal-backdrop">
          <form className="test-modal" onSubmit={handleTestMessage}>
            <button
              aria-label="Fechar"
              className="modal-close"
              onClick={() => {
                setTestConnectionId(null);
                setTestResult("");
              }}
              type="button"
            >
              ×
            </button>

            <span className="eyebrow">Teste controlado</span>
            <h2>Enviar mensagem</h2>
            <p>
              Use um número que você controla, no formato DDI + DDD + número,
              somente dígitos.
            </p>

            <label className="field">
              <span>Número</span>
              <input
                inputMode="numeric"
                onChange={event =>
                  setTestNumber(event.target.value.replace(/\D/g, ""))
                }
                placeholder="5531999999999"
                required
                value={testNumber}
              />
            </label>

            <label className="field">
              <span>Mensagem</span>
              <textarea
                onChange={event => setTestText(event.target.value)}
                required
                rows={4}
                value={testText}
              />
            </label>

            <button
              className="primary-button"
              disabled={busyId === testConnectionId}
              type="submit"
            >
              <span>
                {busyId === testConnectionId
                  ? "Enviando…"
                  : "Enviar teste"}
              </span>
              <span>→</span>
            </button>

            {testResult && (
              <div className="connection-test-result">{testResult}</div>
            )}
          </form>
        </div>
      )}
    </main>
  );
}
EOF

cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P0.5 / Connections ------------------------------------------- */

.connections-screen {
  min-height: 100vh;
  background: var(--background);
  padding: 48px clamp(20px, 5vw, 72px) 80px;
}

.connections-header {
  display: flex;
  max-width: 1180px;
  align-items: flex-end;
  justify-content: space-between;
  gap: 32px;
  margin: 0 auto 32px;
}

.connections-header h1 {
  margin: 8px 0 12px;
  font-size: clamp(40px, 6vw, 64px);
  font-weight: 640;
  letter-spacing: -0.055em;
  line-height: 1;
}

.connections-header p {
  max-width: 650px;
  margin: 0;
  color: var(--muted);
  line-height: 1.6;
}

.connections-back {
  display: block;
  margin: 0 0 30px;
  border: 0;
  background: transparent;
  color: var(--muted);
  padding: 0;
  font-size: 12px;
  font-weight: 700;
}

.connections-company {
  display: grid;
  min-width: 180px;
  gap: 5px;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: white;
  padding: 14px 16px;
}

.connections-company span {
  font-size: 13px;
  font-weight: 750;
}

.connections-company small {
  color: var(--muted);
  font-size: 10px;
}

.connections-screen > .form-error,
.connection-create,
.connection-list {
  max-width: 1180px;
  margin-left: auto;
  margin-right: auto;
}

.connection-create {
  display: grid;
  grid-template-columns: minmax(220px, 1fr) minmax(240px, 0.8fr) 180px;
  align-items: center;
  gap: 20px;
  border: 1px solid var(--line);
  border-radius: 18px;
  background: white;
  padding: 22px;
}

.connection-create > div {
  display: grid;
  gap: 5px;
}

.connection-create strong {
  font-size: 14px;
}

.connection-create span {
  color: var(--muted);
  font-size: 11px;
}

.connection-create input {
  height: 50px;
  border: 1px solid var(--line);
  border-radius: 12px;
  outline: none;
  background: var(--surface-subtle);
  padding: 0 14px;
}

.connection-create input:focus {
  border-color: var(--accent);
}

.connection-create__button {
  margin: 0;
}

.connection-list {
  display: grid;
  gap: 12px;
  margin-top: 18px;
}

.connection-empty {
  border: 1px dashed var(--line-strong);
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.55);
  padding: 54px 28px;
  text-align: center;
}

.connection-empty strong {
  font-size: 15px;
}

.connection-empty p {
  margin: 8px 0 0;
  color: var(--muted);
  font-size: 12px;
}

.connection-card {
  border: 1px solid var(--line);
  border-radius: 18px;
  background: white;
  padding: 22px;
}

.connection-card__main {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 30px;
}

.connection-card__title {
  display: flex;
  align-items: center;
  gap: 12px;
}

.connection-card h2 {
  margin: 0;
  font-size: 18px;
  letter-spacing: -0.025em;
}

.connection-card p {
  margin: 7px 0 0;
  color: #989f9b;
  font-family: monospace;
  font-size: 10px;
}

.connection-status {
  border-radius: 999px;
  padding: 6px 9px;
  font-size: 9px;
  font-weight: 800;
  text-transform: uppercase;
}

.connection-status--connected {
  background: var(--accent-soft);
  color: var(--accent-dark);
}

.connection-status--connecting,
.connection-status--created {
  background: #f2eee2;
  color: #76632b;
}

.connection-status--disconnected {
  background: #eceeed;
  color: #66706a;
}

.connection-status--error {
  background: var(--danger-soft);
  color: var(--danger);
}

.connection-meta {
  display: flex;
  gap: 22px;
  margin-top: 18px;
  color: var(--muted);
  font-size: 10px;
}

.connection-meta strong {
  color: var(--ink);
}

.connection-error {
  margin-top: 14px;
  border-radius: 9px;
  background: var(--danger-soft);
  color: var(--danger);
  padding: 10px 12px;
  font-size: 11px;
}

.connection-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 8px;
}

.modal-backdrop {
  position: fixed;
  z-index: 100;
  inset: 0;
  display: grid;
  place-items: center;
  overflow-y: auto;
  background: rgba(11, 16, 13, 0.72);
  padding: 24px;
  backdrop-filter: blur(8px);
}

.qr-modal,
.test-modal {
  position: relative;
  width: min(470px, 100%);
  border-radius: 22px;
  background: white;
  box-shadow: var(--shadow);
  padding: 32px;
}

.qr-modal h2,
.test-modal h2 {
  margin: 9px 0 10px;
  font-size: 27px;
  letter-spacing: -0.04em;
}

.qr-modal > p,
.test-modal > p {
  margin: 0 0 24px;
  color: var(--muted);
  font-size: 12px;
  line-height: 1.6;
}

.modal-close {
  position: absolute;
  top: 18px;
  right: 18px;
  display: grid;
  width: 32px;
  height: 32px;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: 9px;
  background: white;
  color: var(--muted);
  font-size: 20px;
}

.qr-frame {
  display: grid;
  width: fit-content;
  margin: 10px auto 20px;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: 18px;
  background: white;
  padding: 14px;
}

.qr-frame img {
  display: block;
  width: min(300px, 70vw);
  height: auto;
}

.qr-waiting {
  margin: 20px 0;
  border-radius: 12px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 30px 20px;
  text-align: center;
  font-size: 12px;
  line-height: 1.55;
}

.pairing-code {
  margin-bottom: 18px;
  border-radius: 10px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 12px 14px;
  text-align: center;
  font-size: 12px;
}

.qr-modal > small {
  display: block;
  color: #949b97;
  text-align: center;
  font-size: 10px;
  line-height: 1.5;
}

.test-modal {
  display: grid;
  gap: 18px;
}

.test-modal > p {
  margin: -8px 0 2px;
}

.test-modal textarea {
  width: 100%;
  resize: vertical;
  border: 1px solid var(--line);
  border-radius: 12px;
  outline: none;
  background: var(--surface-subtle);
  padding: 13px 14px;
}

.test-modal textarea:focus {
  border-color: var(--accent);
}

.connection-test-result {
  border-radius: 10px;
  background: var(--surface-subtle);
  color: var(--muted);
  padding: 12px;
  font-size: 11px;
  line-height: 1.5;
}

@media (max-width: 860px) {
  .connections-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .connection-create {
    grid-template-columns: 1fr;
  }

  .connection-card__main {
    align-items: flex-start;
    flex-direction: column;
  }

  .connection-actions {
    justify-content: flex-start;
  }
}
EOF

# ---------------------------------------------------------------------------
# Root scripts
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path = "package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));

pkg.scripts = {
  ...pkg.scripts,
  "evolution:up":
    "docker compose --env-file infra/evolution/.env -f infra/evolution/docker-compose.yml up -d",
  "evolution:down":
    "docker compose --env-file infra/evolution/.env -f infra/evolution/docker-compose.yml down",
  "evolution:logs":
    "docker compose --env-file infra/evolution/.env -f infra/evolution/docker-compose.yml logs -f evolution-api"
};

fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
NODE

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/WHATSAPP.md <<'EOF'
# WhatsApp provider architecture

Wapp does not call Baileys directly from the application domain.

```text
Wapp API
   |
   +-- WhatsAppProviderClient
           |
           +-- EvolutionWhatsAppClient
                    |
                    +-- Evolution API
                            |
                            +-- WHATSAPP-BAILEYS
```

This keeps tickets, contacts and messages independent from the WhatsApp engine.

## Local services

- Wapp API: http://localhost:4000
- Evolution API: http://localhost:8080
- Evolution PostgreSQL: internal Docker network only
- Evolution Redis: internal Docker network only

Evolution has its own PostgreSQL and Redis so its internal state is isolated from
Wapp's application database.

## Events subscribed in P0.5

- QRCODE_UPDATED
- CONNECTION_UPDATE
- MESSAGES_UPSERT

P0.5 only records connection state. Message ingestion starts in P0.6.

## Security

The Evolution global API key never reaches the browser.

Webhooks use a long secret URL path in the local P0.5 environment. In production
this must be combined with HTTPS and may be upgraded to signed/custom webhook
headers.
EOF

# ---------------------------------------------------------------------------
# Generate and validate
# ---------------------------------------------------------------------------

echo "[P0.5] Generating Prisma client..."
pnpm --filter @wapp/api db:generate

echo "[P0.5] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.5] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.5] Foundation created."
echo
echo "Next:"
echo "  pnpm evolution:up"
echo "  pnpm evolution:logs"
echo
echo "In another terminal:"
echo "  pnpm --filter @wapp/api exec prisma migrate dev --name whatsapp_connections"
echo "  pnpm dev"
echo
echo "Open:"
echo "  http://localhost:8080"
echo "  http://localhost:3000/dashboard/connections"
