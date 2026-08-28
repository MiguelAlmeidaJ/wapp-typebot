#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.25] Installing isolated integration tests..."

for required in \
  "package.json" \
  "apps/api/package.json" \
  "apps/api/src/app.ts" \
  "apps/api/src/lib/password.ts" \
  "apps/api/src/modules/tickets/ticket-message-history.service.ts" \
  "infra/docker-compose.yml"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/integration \
  infra/test \
  docs

cat > infra/test/docker-compose.integration.yml <<'EOF'
name: wapp-integration

services:
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_DATABASE: wapp_test
      MYSQL_USER: wapp_test
      MYSQL_PASSWORD: wapp_test_password
      MYSQL_ROOT_PASSWORD: wapp_test_root_password
    ports:
      - "127.0.0.1::3306"
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "MYSQL_PWD=$$MYSQL_ROOT_PASSWORD mysqladmin ping --host=127.0.0.1 --user=root --silent"
        ]
      interval: 2s
      timeout: 3s
      retries: 40
      start_period: 10s

  redis:
    image: redis:7-alpine
    ports:
      - "127.0.0.1::6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 2s
      timeout: 3s
      retries: 30
EOF

cat > apps/api/src/integration/critical.integration.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  randomUUID
} from "node:crypto";
import {
  after,
  before,
  test
} from "node:test";

import type {
  FastifyInstance
} from "fastify";

import { buildApp } from "../app.js";
import { prisma } from "../lib/database.js";
import { hashPassword } from "../lib/password.js";

const OWNER_EMAIL =
  "owner.integration@wapp.test";

const AGENT_EMAIL =
  "agent.integration@wapp.test";

const PASSWORD =
  "IntegrationPassword!123";

let app:
  FastifyInstance;

let ticketId = "";
let aroundMessageId = "";

function cookieHeader(
  value:
    | string
    | string[]
    | undefined
) {
  const raw =
    Array.isArray(value)
      ? value[0]
      : value;

  assert.ok(
    raw,
    "Expected Set-Cookie header."
  );

  return raw.split(
    ";",
    1
  )[0]!;
}

async function login(
  email: string
) {
  const response =
    await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: {
        email,
        password:
          PASSWORD,
        companySlug:
          "integration"
      }
    });

  assert.equal(
    response.statusCode,
    200,
    response.body
  );

  const body =
    response.json<{
      accessToken: string;
      role: string;
    }>();

  return {
    accessToken:
      body.accessToken,
    role:
      body.role,
    cookie:
      cookieHeader(
        response.headers[
          "set-cookie"
        ]
      )
  };
}

before(async () => {
  const passwordHash =
    await hashPassword(
      PASSWORD
    );

  const company =
    await prisma.company.create({
      data: {
        name:
          "Wapp Integration",
        slug:
          "integration"
      }
    });

  const owner =
    await prisma.user.create({
      data: {
        name:
          "Integration Owner",
        email:
          OWNER_EMAIL,
        passwordHash
      }
    });

  const agent =
    await prisma.user.create({
      data: {
        name:
          "Integration Agent",
        email:
          AGENT_EMAIL,
        passwordHash
      }
    });

  await prisma.companyMembership.createMany({
    data: [
      {
        companyId:
          company.id,
        userId:
          owner.id,
        role:
          "OWNER"
      },
      {
        companyId:
          company.id,
        userId:
          agent.id,
        role:
          "AGENT"
      }
    ]
  });

  /*
   * META_CLOUD is used only as a database fixture so the Evolution health
   * monitor has no instance to probe during this isolated test.
   */
  const connection =
    await prisma.whatsAppConnection.create({
      data: {
        companyId:
          company.id,
        name:
          "Integration fixture",
        instanceName:
          `integration-${randomUUID()}`,
        provider:
          "META_CLOUD",
        status:
          "CONNECTED"
      }
    });

  const contact =
    await prisma.contact.create({
      data: {
        companyId:
          company.id,
        remoteJid:
          "5511999999999@s.whatsapp.net",
        phoneNumber:
          "5511999999999",
        name:
          "Integration Contact"
      }
    });

  const ticket =
    await prisma.ticket.create({
      data: {
        companyId:
          company.id,
        whatsappConnectionId:
          connection.id,
        contactId:
          contact.id,
        activeKey:
          `${connection.id}:${contact.id}`,
        status:
          "OPEN",
        lastMessage:
          "message-124",
        lastMessageAt:
          new Date(
            "2026-08-28T12:02:04.000Z"
          )
      }
    });

  ticketId =
    ticket.id;

  const rows =
    Array.from(
      {
        length: 125
      },
      (
        _,
        index
      ) => ({
        id:
          randomUUID(),
        companyId:
          company.id,
        ticketId:
          ticket.id,
        whatsappConnectionId:
          connection.id,
        externalId:
          `integration-${index}`,
        direction:
          index % 2 === 0
            ? "INBOUND" as const
            : "OUTBOUND" as const,
        type:
          "TEXT" as const,
        body:
          `message-${String(
            index
          ).padStart(
            3,
            "0"
          )}`,
        timestamp:
          new Date(
            Date.UTC(
              2026,
              7,
              28,
              12,
              0,
              index
            )
          )
      })
    );

  aroundMessageId =
    rows[60]!.id;

  await prisma.message.createMany({
    data:
      rows
  });

  app =
    await buildApp();

  await app.ready();
});

after(async () => {
  if (app) {
    await app.close();
  }
});

test(
  "critical API integration flow",
  async t => {
    await t.test(
      "database + redis readiness",
      async () => {
        const live =
          await app.inject({
            method: "GET",
            url:
              "/health/live"
          });

        assert.equal(
          live.statusCode,
          200
        );

        assert.equal(
          live.json<{
            status: string;
          }>().status,
          "ok"
        );

        const ready =
          await app.inject({
            method: "GET",
            url:
              "/health/ready"
          });

        assert.equal(
          ready.statusCode,
          200,
          ready.body
        );

        assert.equal(
          ready.json<{
            ready: boolean;
          }>().ready,
          true
        );
      }
    );

    const owner =
      await login(
        OWNER_EMAIL
      );

    await t.test(
      "owner login + authenticated session",
      async () => {
        assert.equal(
          owner.role,
          "OWNER"
        );

        const me =
          await app.inject({
            method: "GET",
            url:
              "/api/v1/auth/me",
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          me.statusCode,
          200,
          me.body
        );

        assert.equal(
          me.json<{
            role: string;
          }>().role,
          "OWNER"
        );
      }
    );

    await t.test(
      "RBAC denies AGENT admin capability",
      async () => {
        const agent =
          await login(
            AGENT_EMAIL
          );

        const denied =
          await app.inject({
            method: "GET",
            url:
              "/api/v1/admin/ping",
            headers: {
              authorization:
                `Bearer ${agent.accessToken}`
            }
          });

        assert.equal(
          denied.statusCode,
          403,
          denied.body
        );

        const allowed =
          await app.inject({
            method: "GET",
            url:
              "/api/v1/admin/ping",
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          allowed.statusCode,
          200,
          allowed.body
        );
      }
    );

    await t.test(
      "P1.21 opens newest page and pages backward",
      async () => {
        const latest =
          await app.inject({
            method: "GET",
            url:
              `/api/v1/tickets/${ticketId}/messages?limit=80`,
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          latest.statusCode,
          200,
          latest.body
        );

        const page =
          latest.json<{
            messages: Array<{
              id: string;
              body: string;
            }>;
            pagination: {
              hasMoreBefore: boolean;
              olderCursor:
                | string
                | null;
            };
          }>();

        assert.equal(
          page.messages.length,
          80
        );

        assert.equal(
          page.messages[0]?.body,
          "message-045"
        );

        assert.equal(
          page.messages[79]?.body,
          "message-124"
        );

        assert.equal(
          page.pagination
            .hasMoreBefore,
          true
        );

        assert.ok(
          page.pagination
            .olderCursor
        );

        const older =
          await app.inject({
            method: "GET",
            url:
              `/api/v1/tickets/${ticketId}/messages?limit=80&before=${page.pagination.olderCursor}`,
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          older.statusCode,
          200,
          older.body
        );

        const olderPage =
          older.json<{
            messages: Array<{
              body: string;
            }>;
            pagination: {
              hasMoreBefore:
                boolean;
            };
          }>();

        assert.equal(
          olderPage.messages.length,
          45
        );

        assert.equal(
          olderPage.messages[0]?.body,
          "message-000"
        );

        assert.equal(
          olderPage.messages[44]?.body,
          "message-044"
        );

        assert.equal(
          olderPage.pagination
            .hasMoreBefore,
          false
        );
      }
    );

    await t.test(
      "P1.21 around cursor returns exact searched message",
      async () => {
        const response =
          await app.inject({
            method: "GET",
            url:
              `/api/v1/tickets/${ticketId}/messages?limit=80&around=${aroundMessageId}`,
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          response.statusCode,
          200,
          response.body
        );

        const payload =
          response.json<{
            messages: Array<{
              id: string;
            }>;
            pagination: {
              hasMoreBefore:
                boolean;
              hasMoreAfter:
                boolean;
            };
          }>();

        assert.ok(
          payload.messages.some(
            message =>
              message.id ===
              aroundMessageId
          )
        );

        assert.equal(
          payload.pagination
            .hasMoreBefore,
          true
        );

        assert.equal(
          payload.pagination
            .hasMoreAfter,
          true
        );
      }
    );

    await t.test(
      "refresh rotation invalidates previous refresh token and logout revokes session",
      async () => {
        const refreshed =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/auth/refresh",
            headers: {
              cookie:
                owner.cookie
            }
          });

        assert.equal(
          refreshed.statusCode,
          200,
          refreshed.body
        );

        const rotatedCookie =
          cookieHeader(
            refreshed.headers[
              "set-cookie"
            ]
          );

        assert.notEqual(
          rotatedCookie,
          owner.cookie
        );

        const oldToken =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/auth/refresh",
            headers: {
              cookie:
                owner.cookie
            }
          });

        assert.equal(
          oldToken.statusCode,
          401
        );

        const logout =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/auth/logout",
            headers: {
              cookie:
                rotatedCookie
            }
          });

        assert.equal(
          logout.statusCode,
          200,
          logout.body
        );

        const revoked =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/auth/refresh",
            headers: {
              cookie:
                rotatedCookie
            }
          });

        assert.equal(
          revoked.statusCode,
          401
        );
      }
    );
  }
);
EOF

cat > scripts/test-integration.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE="infra/test/docker-compose.integration.yml"
PROJECT="wapp-it-${RANDOM}-$$"

if ! docker version >/dev/null 2>&1; then
  echo "ERROR: Docker is required for P1.25 integration tests."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose is required for P1.25 integration tests."
  exit 1
fi

cleanup() {
  docker compose \
    -p "$PROJECT" \
    -f "$COMPOSE_FILE" \
    down \
    --remove-orphans \
    >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

echo "[integration] Starting disposable MySQL + Redis..."
docker compose \
  -p "$PROJECT" \
  -f "$COMPOSE_FILE" \
  up \
  -d \
  --wait

MYSQL_PORT="$(
  docker compose \
    -p "$PROJECT" \
    -f "$COMPOSE_FILE" \
    port mysql 3306 |
    tail -n 1 |
    awk -F: '{print $NF}' |
    tr -d '\r'
)"

REDIS_PORT="$(
  docker compose \
    -p "$PROJECT" \
    -f "$COMPOSE_FILE" \
    port redis 6379 |
    tail -n 1 |
    awk -F: '{print $NF}' |
    tr -d '\r'
)"

if [[ -z "$MYSQL_PORT" || -z "$REDIS_PORT" ]]; then
  echo "ERROR: could not resolve disposable service ports."
  exit 1
fi

export NODE_ENV=test
export DATABASE_URL="mysql://wapp_test:wapp_test_password@127.0.0.1:${MYSQL_PORT}/wapp_test"
export REDIS_URL="redis://127.0.0.1:${REDIS_PORT}/0"
export WEB_URL="http://localhost:3000"
export TRUST_PROXY=false
export JWT_SECRET="integration_jwt_secret_abcdefghijklmnopqrstuvwxyz_123456"
export COOKIE_SECURE=false
export EVOLUTION_BASE_URL="http://127.0.0.1:9"
export EVOLUTION_API_KEY="integration_evolution_api_key_abcdefghijklmnopqrstuvwxyz"
export EVOLUTION_WEBHOOK_BASE_URL="http://localhost:4000"
export EVOLUTION_WEBHOOK_SECRET="integration_webhook_secret_abcdefghijklmnopqrstuvwxyz"
export EVOLUTION_HEALTHCHECK_INTERVAL_SECONDS=3600
export MEDIA_STORAGE_DRIVER=local
export MEDIA_STORAGE_PATH=".runtime/integration-media"
export JOBS_EMBEDDED_WORKER=false

echo "[integration] Applying real Prisma migrations..."
pnpm --filter @wapp/api db:deploy

echo "[integration] Running API integration suite..."
pnpm --filter @wapp/api exec \
  tsx --test \
  src/integration/critical.integration.test.ts

echo "[integration] PASS"
EOF

chmod +x scripts/test-integration.sh

node <<'NODE'
const fs = require("node:fs");

function readJson(path) {
  return JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );
}

function writeJson(
  path,
  value
) {
  fs.writeFileSync(
    path,
    `${JSON.stringify(
      value,
      null,
      2
    )}\n`
  );
}

const apiPath =
  "apps/api/package.json";

const api =
  readJson(
    apiPath
  );

api.scripts ??= {};

api.scripts[
  "test:integration"
] =
  "bash ../../scripts/test-integration.sh";

writeJson(
  apiPath,
  api
);

const rootPath =
  "package.json";

const root =
  readJson(
    rootPath
  );

root.scripts ??= {};

root.scripts[
  "test:integration"
] =
  "pnpm --filter @wapp/api test:integration";

writeJson(
  rootPath,
  root
);
NODE

if [[ -f ".github/workflows/quality-gate.yml" ]] &&
   ! grep -q "Integration tests" .github/workflows/quality-gate.yml
then
  node <<'NODE'
const fs = require("node:fs");

const path =
  ".github/workflows/quality-gate.yml";

let content =
  fs.readFileSync(
    path,
    "utf8"
  )
    .replace(
      /\r\n/g,
      "\n"
    );

const anchor =
  `      - name: Typecheck
        run: pnpm typecheck`;

if (!content.includes(anchor)) {
  throw new Error(
    "Quality Gate typecheck step anchor not found."
  );
}

content =
  content.replace(
    anchor,
    `      - name: Integration tests
        run: pnpm test:integration

${anchor}`
  );

fs.writeFileSync(
  path,
  content
);
NODE
fi

cat > docs/INTEGRATION_TESTS.md <<'EOF'
# P1.25 Isolated integration tests

`pnpm test:integration` starts disposable MySQL 8.4 and Redis containers using
random host ports.

It never points at the normal Wapp database or Redis instance.

The suite applies all Prisma migrations and validates the real Fastify/Prisma
stack for:

- `/health/live`;
- `/health/ready` with MySQL + Redis;
- login and authenticated `/me`;
- OWNER/AGENT RBAC;
- refresh-token rotation;
- logout/session revocation;
- P1.21 newest message page;
- older cursor pagination;
- exact `around=<messageId>` history lookup.

Containers are removed by a shell trap on success or failure.

No named Docker volume is created and no `down -v` command is used.
EOF

echo "[P1.25] Bash syntax..."
bash -n scripts/test-integration.sh

echo "[P1.25] Unit tests..."
pnpm test

echo "[P1.25] Typechecking..."
pnpm typecheck

echo "[P1.25] Running isolated integration tests..."
pnpm test:integration

echo
echo "[P1.25] Integration test baseline installed and validated."
