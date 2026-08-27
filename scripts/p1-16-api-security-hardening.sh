#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.16] Building API security hardening..."

for required in \
  "apps/api/src/app.ts" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/modules/auth/auth.routes.ts" \
  "apps/api/.env.example" \
  "apps/api/package.json"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! node -e '
const pkg = require("./apps/api/package.json");
process.exit(pkg.dependencies?.ioredis ? 0 : 1);
'; then
  echo "ERROR: P1.16 requires ioredis from P1.14."
  exit 1
fi

mkdir -p \
  apps/api/src/security \
  docs

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/config/env.ts";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    "TRUST_PROXY:"
  )
) {
  const anchor =
    '  WEB_URL: z.string().url().default("http://localhost:3000"),';

  if (!content.includes(anchor)) {
    throw new Error(
      "WEB_URL env anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  TRUST_PROXY: booleanFromEnv,`
    );
}

if (
  !content.includes(
    "API_BODY_MAX_BYTES:"
  )
) {
  const anchor =
    '  REDIS_URL: z.string().min(1).optional(),';

  if (!content.includes(anchor)) {
    throw new Error(
      "REDIS_URL env anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
  API_BODY_MAX_BYTES: z.coerce
    .number()
    .int()
    .positive()
    .default(1_048_576),`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Security environment settings installed."
);
NODE

if ! grep -q "^TRUST_PROXY=" apps/api/.env.example; then
  node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/.env.example";

let content =
  fs.readFileSync(path, "utf8");

const anchor =
  "WEB_URL=http://localhost:3000";

if (!content.includes(anchor)) {
  throw new Error(
    "WEB_URL .env.example anchor not found."
  );
}

content =
  content.replace(
    anchor,
    `${anchor}
TRUST_PROXY=false
API_BODY_MAX_BYTES=1048576`
  );

fs.writeFileSync(
  path,
  content
);
NODE
fi

# ---------------------------------------------------------------------------
# Distributed rate-limit store
# ---------------------------------------------------------------------------

cat > apps/api/src/security/rate-limit.ts <<'EOF'
import { createHash } from "node:crypto";

import type {
  FastifyReply,
  FastifyRequest
} from "fastify";
import { Redis } from "ioredis";

import { env } from "../config/env.js";
import { AppError } from "../errors/app-error.js";

interface RateLimitPolicy {
  scope: string;
  key: string;
  max: number;
  windowMs: number;
}

interface RateLimitResult {
  count: number;
  remaining: number;
  resetMs: number;
}

interface LocalEntry {
  count: number;
  expiresAt: number;
}

const localEntries =
  new Map<
    string,
    LocalEntry
  >();

let redis:
  | Redis
  | null =
  null;

let redisWarningShown =
  false;

const RATE_LIMIT_PREFIX =
  "wapp:rate-limit:";

const LUA_INCREMENT = `
local current = redis.call("INCR", KEYS[1])
if current == 1 then
  redis.call("PEXPIRE", KEYS[1], ARGV[1])
end
local ttl = redis.call("PTTL", KEYS[1])
return {current, ttl}
`;

function warnRedis(
  error: unknown
) {
  if (
    redisWarningShown
  ) {
    return;
  }

  redisWarningShown =
    true;

  console.warn(
    "[security] Redis rate-limit store unavailable; using process-local fallback.",
    error instanceof Error
      ? error.message
      : ""
  );
}

function initializeRedis() {
  if (
    !env.REDIS_URL
  ) {
    return;
  }

  redis =
    new Redis(
      env.REDIS_URL,
      {
        enableReadyCheck:
          true,
        maxRetriesPerRequest:
          1,
        retryStrategy(
          attempt
        ) {
          return Math.min(
            250 * attempt,
            5_000
          );
        }
      }
    );

  redis.on(
    "ready",
    () => {
      redisWarningShown =
        false;
    }
  );

  redis.on(
    "error",
    error => {
      warnRedis(
        error
      );
    }
  );
}

initializeRedis();

function hashedKey(
  scope: string,
  rawKey: string
) {
  const digest =
    createHash("sha256")
      .update(rawKey)
      .digest("hex");

  return `${RATE_LIMIT_PREFIX}${scope}:${digest}`;
}

function localConsume(
  key: string,
  max: number,
  windowMs: number
): RateLimitResult {
  const now =
    Date.now();

  const existing =
    localEntries.get(
      key
    );

  if (
    !existing ||
    existing.expiresAt <=
      now
  ) {
    const entry = {
      count: 1,
      expiresAt:
        now +
        windowMs
    };

    localEntries.set(
      key,
      entry
    );

    return {
      count: 1,
      remaining:
        Math.max(
          0,
          max - 1
        ),
      resetMs:
        windowMs
    };
  }

  existing.count += 1;

  return {
    count:
      existing.count,
    remaining:
      Math.max(
        0,
        max -
          existing.count
      ),
    resetMs:
      Math.max(
        1,
        existing.expiresAt -
          now
      )
  };
}

async function redisConsume(
  key: string,
  max: number,
  windowMs: number
): Promise<RateLimitResult> {
  if (!redis) {
    throw new Error(
      "redis_not_initialized"
    );
  }

  const raw =
    await redis.eval(
      LUA_INCREMENT,
      1,
      key,
      String(windowMs)
    );

  if (
    !Array.isArray(raw) ||
    raw.length < 2
  ) {
    throw new Error(
      "invalid_rate_limit_response"
    );
  }

  const count =
    Number(raw[0]);

  const ttl =
    Number(raw[1]);

  if (
    !Number.isFinite(count) ||
    !Number.isFinite(ttl)
  ) {
    throw new Error(
      "invalid_rate_limit_numbers"
    );
  }

  return {
    count,
    remaining:
      Math.max(
        0,
        max - count
      ),
    resetMs:
      Math.max(
        1,
        ttl > 0
          ? ttl
          : windowMs
      )
  };
}

async function consume(
  policy: RateLimitPolicy
) {
  const key =
    hashedKey(
      policy.scope,
      policy.key
    );

  if (
    redis?.status ===
    "ready"
  ) {
    try {
      return await redisConsume(
        key,
        policy.max,
        policy.windowMs
      );
    } catch (error) {
      warnRedis(
        error
      );
    }
  }

  return localConsume(
    key,
    policy.max,
    policy.windowMs
  );
}

export async function enforceRateLimit(
  request: FastifyRequest,
  reply: FastifyReply,
  policy: RateLimitPolicy
) {
  const result =
    await consume(
      policy
    );

  const resetSeconds =
    Math.max(
      1,
      Math.ceil(
        result.resetMs /
          1000
      )
    );

  reply.header(
    "RateLimit-Limit",
    String(
      policy.max
    )
  );

  reply.header(
    "RateLimit-Remaining",
    String(
      result.remaining
    )
  );

  reply.header(
    "RateLimit-Reset",
    String(
      resetSeconds
    )
  );

  if (
    result.count <=
    policy.max
  ) {
    return;
  }

  reply.header(
    "Retry-After",
    String(
      resetSeconds
    )
  );

  request.log.warn(
    {
      scope:
        policy.scope,
      requestId:
        request.id
    },
    "Rate limit exceeded"
  );

  throw new AppError(
    "Muitas tentativas. Aguarde antes de tentar novamente.",
    429,
    "RATE_LIMITED",
    {
      retryAfterSeconds:
        resetSeconds
    }
  );
}

export function normalizeIdentity(
  value: string
) {
  return value
    .trim()
    .toLowerCase();
}

export async function closeRateLimitStore() {
  const client =
    redis;

  redis =
    null;

  localEntries.clear();

  if (!client) {
    return;
  }

  try {
    await client.quit();
  } catch {
    client.disconnect();
  }
}
EOF

# ---------------------------------------------------------------------------
# Auth route limits
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/auth/auth.routes.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  `import {
  enforceRateLimit,
  normalizeIdentity
} from "../../security/rate-limit.js";`;

if (
  !content.includes(
    "enforceRateLimit,"
  )
) {
  const anchor =
    'import { AppError } from "../../errors/app-error.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "AppError import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

if (
  !content.includes(
    'scope: "auth:login:ip"'
  )
) {
  const anchor =
    `    const input = loginSchema.parse(request.body);`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Login input anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}

    await enforceRateLimit(
      request,
      reply,
      {
        scope:
          "auth:login:ip",
        key:
          request.ip,
        max:
          12,
        windowMs:
          15 * 60 * 1000
      }
    );

    await enforceRateLimit(
      request,
      reply,
      {
        scope:
          "auth:login:identity",
        key:
          \`\${normalizeIdentity(
            input.email
          )}|\${normalizeIdentity(
            input.companySlug ??
              ""
          )}\`,
        max:
          20,
        windowMs:
          15 * 60 * 1000
      }
    );`
    );
}

if (
  !content.includes(
    'scope: "auth:refresh:ip"'
  )
) {
  const anchor =
    `  app.post("/api/v1/auth/refresh", async (request, reply) => {
    const token = request.cookies[REFRESH_COOKIE];`;

  if (!content.includes(anchor)) {
    throw new Error(
      "Refresh route anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `  app.post("/api/v1/auth/refresh", async (request, reply) => {
    await enforceRateLimit(
      request,
      reply,
      {
        scope:
          "auth:refresh:ip",
        key:
          request.ip,
        max:
          60,
        windowMs:
          60 * 1000
      }
    );

    const token = request.cookies[REFRESH_COOKIE];`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Distributed auth rate limits installed."
);
NODE

# ---------------------------------------------------------------------------
# Fastify hardening / security headers / lifecycle
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/app.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  'import { closeRateLimitStore } from "./security/rate-limit.js";';

if (
  !content.includes(
    importLine
  )
) {
  const candidates = [
    'import { AppError } from "./errors/app-error.js";',
    'import { prisma } from "./lib/database.js";'
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "app.ts security import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importLine}`
    );
}

/*
 * Fastify trustProxy + body limit.
 */
const fastifyAnchor =
  `  const app = Fastify({
    logger: {`;

if (
  content.includes(
    fastifyAnchor
  ) &&
  !content.includes(
    "trustProxy: env.TRUST_PROXY"
  )
) {
  content =
    content.replace(
      fastifyAnchor,
      `  const app = Fastify({
    trustProxy:
      env.TRUST_PROXY,
    bodyLimit:
      env.API_BODY_MAX_BYTES,
    logger: {`
    );
}

if (
  !content.includes(
    '"X-Content-Type-Options"'
  )
) {
  const candidates = [
    `  app.addHook(
    "onSend",`,
    `  app.setErrorHandler((error, request, reply) => {`
  ];

  const anchor =
    candidates.find(candidate =>
      content.includes(candidate)
    );

  if (!anchor) {
    throw new Error(
      "Could not find app hook/error handler anchor."
    );
  }

  const hook = `  app.addHook(
    "onRequest",
    async (
      _request,
      reply
    ) => {
      reply.header(
        "X-Content-Type-Options",
        "nosniff"
      );

      reply.header(
        "X-Frame-Options",
        "DENY"
      );

      reply.header(
        "Referrer-Policy",
        "no-referrer"
      );

      reply.header(
        "Permissions-Policy",
        "camera=(), microphone=(), geolocation=()"
      );

      reply.header(
        "Content-Security-Policy",
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
      );

      if (
        env.NODE_ENV ===
          "production" &&
        env.COOKIE_SECURE
      ) {
        reply.header(
          "Strict-Transport-Security",
          "max-age=31536000; includeSubDomains"
        );
      }
    }
  );

`;

  content =
    content.replace(
      anchor,
      `${hook}${anchor}`
    );
}

if (
  !content.includes(
    "await closeRateLimitStore();"
  )
) {
  const marker =
    "    await closeRealtimeTransport();";

  if (!content.includes(marker)) {
    throw new Error(
      "P1.14 closeRealtimeTransport marker not found."
    );
  }

  content =
    content.replace(
      marker,
      `${marker}
    await closeRateLimitStore();`
    );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Fastify security headers, proxy awareness and body limit installed."
);
NODE

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/API_SECURITY_HARDENING.md <<'EOF'
# API security hardening

P1.16 adds targeted production hardening without rate-limiting the WhatsApp
webhook path.

## Distributed authentication rate limits

Rate-limit state uses Redis when it is healthy and falls back to process-local
memory when Redis is unavailable.

Redis keys store SHA-256 hashes rather than raw email addresses or IP-derived
identifiers.

### Login

Two independent limits are enforced:

- 12 login attempts per IP in 15 minutes;
- 20 login attempts per normalized email + company slug in 15 minutes.

This gives protection against both single-IP brute force and broad credential
stuffing against one account.

### Refresh

Refresh is limited to:

- 60 requests per IP per minute.

Normal access-token refresh behavior is far below this threshold.

### Response

A blocked request returns HTTP `429` with:

- `Retry-After`;
- `RateLimit-Limit`;
- `RateLimit-Remaining`;
- `RateLimit-Reset`;
- error code `RATE_LIMITED`.

The API log contains the request id and rate-limit scope, but not the raw rate
limit key.

## WhatsApp webhooks

Evolution webhook routes are intentionally not placed behind the authentication
rate limits.

Inbound message bursts are legitimate workload and must not be dropped because
multiple customers send messages simultaneously.

Webhook authenticity continues to rely on the existing webhook secret and
message idempotency rules.

## Proxy awareness

`TRUST_PROXY=false` by default.

When Wapp is deployed behind a trusted reverse proxy/load balancer, set:

`TRUST_PROXY=true`

This allows Fastify `request.ip` to use the forwarded client address.

Do not enable `TRUST_PROXY=true` on an API that is directly reachable from
untrusted clients without a trusted proxy boundary.

## Request body size

`API_BODY_MAX_BYTES=1048576`

This is the default JSON/body limit for regular API requests.

Multipart media uploads continue to use the dedicated `MEDIA_MAX_BYTES` limit.

## Security headers

The API emits:

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: no-referrer`
- restrictive `Permissions-Policy`
- restrictive document CSP

In production with secure cookies enabled it also emits HSTS.

## Redis outage

If Redis becomes unavailable, login protection degrades to a process-local
fallback rather than failing authentication completely.

In a multi-replica production deployment, Redis should be treated as required
infrastructure; P1.15 readiness already reports Redis failure.

## Migration

P1.16 requires no Prisma migration.
EOF

echo "[P1.16] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.16] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.16] API security hardening installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Verify:"
echo "  1. login normally"
echo "  2. inspect a response for X-Content-Type-Options and X-Request-Id"
echo "  3. keep TRUST_PROXY=false locally"
echo "  4. confirm WhatsApp inbound/outbound still works"
echo "  5. optional: intentionally exceed login attempts only in a test environment"
echo "     and confirm HTTP 429 + Retry-After"
