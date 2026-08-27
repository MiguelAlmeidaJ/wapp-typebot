#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.14] Building Redis-backed distributed realtime..."

for required in \
  "apps/api/package.json" \
  "apps/api/src/config/env.ts" \
  "apps/api/src/app.ts" \
  "apps/api/src/modules/realtime/realtime.bus.ts" \
  "apps/api/src/modules/realtime/realtime.routes.ts" \
  "docs/OPERATIONS.md"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

if ! grep -q "REDIS_URL" apps/api/src/config/env.ts; then
  echo "ERROR: REDIS_URL is not defined in API env schema."
  exit 1
fi

# ---------------------------------------------------------------------------
# Redis client dependency
# ---------------------------------------------------------------------------

if ! node -e '
const pkg = require("./apps/api/package.json");
process.exit(pkg.dependencies?.ioredis ? 0 : 1);
'; then
  echo "[P1.14] Installing ioredis..."
  pnpm --filter @wapp/api add ioredis@^5.4.1
else
  echo "[P1.14] ioredis already installed."
fi

# ---------------------------------------------------------------------------
# Realtime bus
#
# Preserve the local RealtimeEvent union/interface because newer P1 patches
# add event types/fields there. Replace only the implementation below it.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/realtime/realtime.bus.ts";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    'import Redis from "ioredis";'
  )
) {
  const imports = [];

  if (
    !content.includes(
      'import { EventEmitter } from "node:events";'
    )
  ) {
    throw new Error(
      "EventEmitter import not found."
    );
  }

  if (
    !content.includes(
      'import { randomUUID } from "node:crypto";'
    )
  ) {
    throw new Error(
      "randomUUID import not found."
    );
  }

  content = content.replace(
    'import { randomUUID } from "node:crypto";',
    `import { randomUUID } from "node:crypto";

import Redis from "ioredis";

import { env } from "../../config/env.js";`
  );
}

const marker =
  "const emitter = new EventEmitter();";

const implementationStart =
  content.indexOf(marker);

if (implementationStart < 0) {
  if (
    content.includes(
      "const REDIS_CHANNEL_PREFIX"
    )
  ) {
    console.log(
      "Distributed realtime bus already installed."
    );
    process.exit(0);
  }

  throw new Error(
    "Realtime implementation marker not found."
  );
}

const prefix =
  content.slice(
    0,
    implementationStart
  );

const implementation = `const emitter =
  new EventEmitter();

emitter.setMaxListeners(0);

const REDIS_CHANNEL_PREFIX =
  "wapp:realtime:";

const PRESENCE_KEY_PREFIX =
  "wapp:presence:";

const PRESENCE_COMPANIES_KEY =
  "wapp:presence:companies";

const PRESENCE_SWEEP_LOCK_KEY =
  "wapp:presence:sweep-lock";

const PRESENCE_TTL_MS =
  75_000;

const PRESENCE_SWEEP_INTERVAL_MS =
  30_000;

const PRESENCE_SWEEP_LOCK_MS =
  20_000;

const localPresence =
  new Map<
    string,
    Map<
      string,
      Set<string>
    >
  >();

let publisher:
  | Redis
  | null =
  null;

let subscriber:
  | Redis
  | null =
  null;

let redisSubscriptionReady =
  false;

let redisTransportReady =
  false;

let redisWarningShown =
  false;

let presenceSweep:
  | NodeJS.Timeout
  | null =
  null;

function localCompanyChannel(
  companyId: string
) {
  return \`company:\${companyId}\`;
}

function redisCompanyChannel(
  companyId: string
) {
  return \`\${REDIS_CHANNEL_PREFIX}\${companyId}\`;
}

function presenceKey(
  companyId: string
) {
  return \`\${PRESENCE_KEY_PREFIX}\${companyId}\`;
}

function presenceMember(
  membershipId: string,
  connectionId: string
) {
  return \`\${membershipId}:\${connectionId}\`;
}

function membershipFromPresenceMember(
  member: string
) {
  const separator =
    member.indexOf(":");

  return separator >= 0
    ? member.slice(
        0,
        separator
      )
    : member;
}

function redisIsUsable() {
  return Boolean(
    redisTransportReady &&
    publisher &&
    subscriber &&
    publisher.status ===
      "ready" &&
    subscriber.status ===
      "ready"
  );
}

function updateRedisTransportState() {
  const next =
    Boolean(
      publisher?.status ===
        "ready" &&
      subscriber?.status ===
        "ready" &&
      redisSubscriptionReady
    );

  if (
    next &&
    !redisTransportReady
  ) {
    /*
     * Redis becomes the source of truth. Existing SSE clients
     * repopulate their presence entries on the next heartbeat.
     */
    localPresence.clear();
  }

  redisTransportReady =
    next;
}

function warnRedis(
  message: string,
  error?: unknown
) {
  if (redisWarningShown) {
    return;
  }

  redisWarningShown =
    true;

  console.warn(
    \`[realtime] \${message}\`,
    error instanceof Error
      ? error.message
      : ""
  );
}

function clearRedisWarning() {
  redisWarningShown =
    false;
}

function emitLocal(
  companyId: string,
  event: RealtimeEvent
) {
  emitter.emit(
    localCompanyChannel(
      companyId
    ),
    event
  );
}

function activeMembershipIds(
  members: string[]
) {
  return [
    ...new Set(
      members.map(
        membershipFromPresenceMember
      )
    )
  ];
}

function localMarkOnline(
  companyId: string,
  membershipId: string,
  connectionId: string
) {
  const companyPresence =
    localPresence.get(
      companyId
    ) ??
    new Map<
      string,
      Set<string>
    >();

  const connections =
    companyPresence.get(
      membershipId
    ) ??
    new Set<string>();

  const wasOnline =
    connections.size > 0;

  connections.add(
    connectionId
  );

  companyPresence.set(
    membershipId,
    connections
  );

  localPresence.set(
    companyId,
    companyPresence
  );

  return !wasOnline;
}

function localMarkOffline(
  companyId: string,
  membershipId: string,
  connectionId: string
) {
  const companyPresence =
    localPresence.get(
      companyId
    );

  if (!companyPresence) {
    return false;
  }

  const connections =
    companyPresence.get(
      membershipId
    );

  if (!connections) {
    return false;
  }

  connections.delete(
    connectionId
  );

  if (
    connections.size === 0
  ) {
    companyPresence.delete(
      membershipId
    );

    if (
      companyPresence.size ===
      0
    ) {
      localPresence.delete(
        companyId
      );
    }

    return true;
  }

  return false;
}

function localOnlineMembershipIds(
  companyId: string
) {
  return [
    ...(
      localPresence
        .get(companyId)
        ?.keys() ??
      []
    )
  ];
}

async function redisMarkOnline(
  companyId: string,
  membershipId: string,
  connectionId: string
) {
  if (!publisher) {
    return false;
  }

  const now =
    Date.now();

  const key =
    presenceKey(
      companyId
    );

  await publisher.zremrangebyscore(
    key,
    "-inf",
    now
  );

  const activeBefore =
    await publisher.zrangebyscore(
      key,
      now,
      "+inf"
    );

  const wasOnline =
    activeBefore.some(
      member =>
        membershipFromPresenceMember(
          member
        ) ===
        membershipId
    );

  await publisher
    .multi()
    .zadd(
      key,
      now +
        PRESENCE_TTL_MS,
      presenceMember(
        membershipId,
        connectionId
      )
    )
    .sadd(
      PRESENCE_COMPANIES_KEY,
      companyId
    )
    .exec();

  return !wasOnline;
}

async function redisMarkOffline(
  companyId: string,
  membershipId: string,
  connectionId: string
) {
  if (!publisher) {
    return false;
  }

  const now =
    Date.now();

  const key =
    presenceKey(
      companyId
    );

  await publisher.zrem(
    key,
    presenceMember(
      membershipId,
      connectionId
    )
  );

  await publisher.zremrangebyscore(
    key,
    "-inf",
    now
  );

  const activeAfter =
    await publisher.zrangebyscore(
      key,
      now,
      "+inf"
    );

  const stillOnline =
    activeAfter.some(
      member =>
        membershipFromPresenceMember(
          member
        ) ===
        membershipId
    );

  if (
    activeAfter.length ===
    0
  ) {
    await publisher.srem(
      PRESENCE_COMPANIES_KEY,
      companyId
    );
  }

  return !stillOnline;
}

async function redisListOnlineMembershipIds(
  companyId: string
) {
  if (!publisher) {
    return [];
  }

  const now =
    Date.now();

  const key =
    presenceKey(
      companyId
    );

  await publisher.zremrangebyscore(
    key,
    "-inf",
    now
  );

  const members =
    await publisher.zrangebyscore(
      key,
      now,
      "+inf"
    );

  if (
    members.length === 0
  ) {
    await publisher.srem(
      PRESENCE_COMPANIES_KEY,
      companyId
    );
  }

  return activeMembershipIds(
    members
  );
}

async function releaseSweepLock(
  token: string
) {
  if (!publisher) {
    return;
  }

  await publisher.eval(
    \`
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      end
      return 0
    \`,
    1,
    PRESENCE_SWEEP_LOCK_KEY,
    token
  );
}

async function sweepExpiredPresence() {
  if (
    !redisIsUsable() ||
    !publisher
  ) {
    return;
  }

  const token =
    randomUUID();

  const lock =
    await publisher.set(
      PRESENCE_SWEEP_LOCK_KEY,
      token,
      "PX",
      PRESENCE_SWEEP_LOCK_MS,
      "NX"
    );

  if (lock !== "OK") {
    return;
  }

  try {
    const now =
      Date.now();

    const companies =
      await publisher.smembers(
        PRESENCE_COMPANIES_KEY
      );

    for (
      const companyId
      of companies
    ) {
      const key =
        presenceKey(
          companyId
        );

      const expired =
        await publisher.zrangebyscore(
          key,
          "-inf",
          now
        );

      if (
        expired.length ===
        0
      ) {
        continue;
      }

      const impacted =
        activeMembershipIds(
          expired
        );

      await publisher.zremrangebyscore(
        key,
        "-inf",
        now
      );

      const remaining =
        await publisher.zrangebyscore(
          key,
          now,
          "+inf"
        );

      const remainingMemberships =
        new Set(
          activeMembershipIds(
            remaining
          )
        );

      for (
        const membershipId
        of impacted
      ) {
        if (
          !remainingMemberships.has(
            membershipId
          )
        ) {
          publishRealtime(
            companyId,
            {
              type:
                "presence.updated",
              membershipId,
              online: false
            }
          );
        }
      }

      if (
        remaining.length ===
        0
      ) {
        await publisher.srem(
          PRESENCE_COMPANIES_KEY,
          companyId
        );
      }
    }
  } finally {
    await releaseSweepLock(
      token
    ).catch(() => {});
  }
}

function startPresenceSweep() {
  if (presenceSweep) {
    return;
  }

  presenceSweep =
    setInterval(
      () => {
        void sweepExpiredPresence()
          .catch(error => {
            warnRedis(
              "presence sweep failed; local realtime remains available.",
              error
            );
          });
      },
      PRESENCE_SWEEP_INTERVAL_MS
    );

  presenceSweep.unref();
}

function initializeRedis() {
  if (!env.REDIS_URL) {
    return;
  }

  const options = {
    enableReadyCheck: true,
    maxRetriesPerRequest: 1,
    retryStrategy(
      attempt: number
    ) {
      return Math.min(
        250 * attempt,
        5_000
      );
    }
  };

  publisher =
    new Redis(
      env.REDIS_URL,
      options
    );

  subscriber =
    new Redis(
      env.REDIS_URL,
      options
    );

  publisher.on(
    "ready",
    () => {
      clearRedisWarning();
      updateRedisTransportState();
    }
  );

  publisher.on(
    "close",
    () => {
      updateRedisTransportState();
    }
  );

  publisher.on(
    "error",
    error => {
      updateRedisTransportState();
      warnRedis(
        "Redis publisher unavailable; using local fallback where possible.",
        error
      );
    }
  );

  subscriber.on(
    "ready",
    () => {
      void subscriber
        ?.psubscribe(
          \`\${REDIS_CHANNEL_PREFIX}*\`
        )
        .then(() => {
          redisSubscriptionReady =
            true;

          clearRedisWarning();
          updateRedisTransportState();
        })
        .catch(error => {
          redisSubscriptionReady =
            false;

          updateRedisTransportState();

          warnRedis(
            "Redis realtime subscription failed; using local fallback.",
            error
          );
        });
    }
  );

  subscriber.on(
    "close",
    () => {
      redisSubscriptionReady =
        false;

      updateRedisTransportState();
    }
  );

  subscriber.on(
    "error",
    error => {
      redisSubscriptionReady =
        false;

      updateRedisTransportState();

      warnRedis(
        "Redis subscriber unavailable; using local fallback where possible.",
        error
      );
    }
  );

  subscriber.on(
    "pmessage",
    (
      _pattern,
      channel,
      raw
    ) => {
      if (
        !channel.startsWith(
          REDIS_CHANNEL_PREFIX
        )
      ) {
        return;
      }

      const companyId =
        channel.slice(
          REDIS_CHANNEL_PREFIX.length
        );

      try {
        const event =
          JSON.parse(
            raw
          ) as RealtimeEvent;

        emitLocal(
          companyId,
          event
        );
      } catch {
        warnRedis(
          "ignored malformed realtime event from Redis."
        );
      }
    }
  );

  startPresenceSweep();
}

initializeRedis();

export function publishRealtime(
  companyId: string,
  event: Omit<
    RealtimeEvent,
    "id" |
      "occurredAt"
  >
) {
  const payload: RealtimeEvent = {
    id:
      randomUUID(),
    occurredAt:
      new Date()
        .toISOString(),
    ...event
  };

  if (
    redisIsUsable() &&
    publisher
  ) {
    void publisher
      .publish(
        redisCompanyChannel(
          companyId
        ),
        JSON.stringify(
          payload
        )
      )
      .catch(error => {
        warnRedis(
          "Redis publish failed; delivering event locally.",
          error
        );

        emitLocal(
          companyId,
          payload
        );
      });

    return;
  }

  emitLocal(
    companyId,
    payload
  );
}

export function subscribeRealtime(
  companyId: string,
  listener: (
    event: RealtimeEvent
  ) => void
) {
  const channel =
    localCompanyChannel(
      companyId
    );

  emitter.on(
    channel,
    listener
  );

  return () => {
    emitter.off(
      channel,
      listener
    );
  };
}

export async function markPresenceOnline(
  companyId: string,
  membershipId: string,
  connectionId: string
) {
  if (
    redisIsUsable()
  ) {
    try {
      const becameOnline =
        await redisMarkOnline(
          companyId,
          membershipId,
          connectionId
        );

      if (becameOnline) {
        publishRealtime(
          companyId,
          {
            type:
              "presence.updated",
            membershipId,
            online: true
          }
        );
      }

      return;
    } catch (error) {
      warnRedis(
        "Redis presence online failed; falling back locally.",
        error
      );
    }
  }

  const becameOnline =
    localMarkOnline(
      companyId,
      membershipId,
      connectionId
    );

  if (becameOnline) {
    publishRealtime(
      companyId,
      {
        type:
          "presence.updated",
        membershipId,
        online: true
      }
    );
  }
}

export async function refreshPresence(
  companyId: string,
  membershipId: string,
  connectionId: string
) {
  /*
   * Using the same online operation is intentional:
   * - refreshes Redis TTL;
   * - migrates a connection from local fallback to Redis
   *   after Redis recovers;
   * - only emits online when the membership was not already present.
   */
  await markPresenceOnline(
    companyId,
    membershipId,
    connectionId
  );
}

export async function markPresenceOffline(
  companyId: string,
  membershipId: string,
  connectionId: string
) {
  if (
    redisIsUsable()
  ) {
    try {
      const becameOffline =
        await redisMarkOffline(
          companyId,
          membershipId,
          connectionId
        );

      if (becameOffline) {
        publishRealtime(
          companyId,
          {
            type:
              "presence.updated",
            membershipId,
            online: false
          }
        );
      }

      return;
    } catch (error) {
      warnRedis(
        "Redis presence offline failed; falling back locally.",
        error
      );
    }
  }

  const becameOffline =
    localMarkOffline(
      companyId,
      membershipId,
      connectionId
    );

  if (becameOffline) {
    publishRealtime(
      companyId,
      {
        type:
          "presence.updated",
        membershipId,
        online: false
      }
    );
  }
}

export async function listOnlineMembershipIds(
  companyId: string
) {
  if (
    redisIsUsable()
  ) {
    try {
      return await redisListOnlineMembershipIds(
        companyId
      );
    } catch (error) {
      warnRedis(
        "Redis presence list failed; using local fallback.",
        error
      );
    }
  }

  return localOnlineMembershipIds(
    companyId
  );
}

export function getRealtimeTransportStatus() {
  return {
    mode:
      redisIsUsable()
        ? "redis"
        : "local",
    redisConfigured:
      Boolean(
        env.REDIS_URL
      ),
    redisReady:
      redisIsUsable()
  } as const;
}

export async function closeRealtimeTransport() {
  if (presenceSweep) {
    clearInterval(
      presenceSweep
    );

    presenceSweep =
      null;
  }

  redisSubscriptionReady =
    false;

  redisTransportReady =
    false;

  const clients =
    [
      subscriber,
      publisher
    ].filter(
      (
        client
      ): client is Redis =>
        Boolean(client)
    );

  subscriber =
    null;

  publisher =
    null;

  await Promise.allSettled(
    clients.map(
      client =>
        client.quit()
    )
  );
}
`;

fs.writeFileSync(
  path,
  `${prefix}${implementation}`
);

console.log(
  "Distributed realtime bus installed while preserving current event types."
);
NODE

# ---------------------------------------------------------------------------
# SSE routes: distributed presence with connection IDs + heartbeat refresh
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/realtime/realtime.routes.ts";

let content =
  fs.readFileSync(path, "utf8");

if (
  !content.includes(
    'import { randomUUID } from "node:crypto";'
  )
) {
  content =
    `import { randomUUID } from "node:crypto";

${content}`;
}

if (
  !content.includes(
    "refreshPresence,"
  )
) {
  const anchor =
    "  markPresenceOnline,";

  if (!content.includes(anchor)) {
    throw new Error(
      "markPresenceOnline import anchor not found."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
  refreshPresence,`
  );
}

content = content.replace(
  "membershipIds: listOnlineMembershipIds(auth.companyId)",
  "membershipIds: await listOnlineMembershipIds(auth.companyId)"
);

if (
  !content.includes(
    "const presenceConnectionId = randomUUID();"
  )
) {
  const anchor =
    "    const unsubscribe = subscribeRealtime(auth.companyId, send);";

  if (!content.includes(anchor)) {
    throw new Error(
      "SSE subscribe anchor not found."
    );
  }

  content = content.replace(
    anchor,
    `    const presenceConnectionId = randomUUID();

${anchor}`
  );
}

const oldOnline =
  "    markPresenceOnline(auth.companyId, auth.membershipId);";

if (
  content.includes(
    oldOnline
  )
) {
  content = content.replace(
    oldOnline,
    `    await markPresenceOnline(
      auth.companyId,
      auth.membershipId,
      presenceConnectionId
    );`
  );
}

const oldHeartbeat = `    const heartbeat = setInterval(() => {
      reply.raw.write(": heartbeat\\n\\n");
    }, 25_000);`;

if (
  content.includes(
    oldHeartbeat
  )
) {
  content = content.replace(
    oldHeartbeat,
    `    const heartbeat = setInterval(() => {
      void refreshPresence(
        auth.companyId,
        auth.membershipId,
        presenceConnectionId
      );

      reply.raw.write(": heartbeat\\n\\n");
    }, 25_000);`
  );
} else if (
  !content.includes(
    "void refreshPresence("
  )
) {
  throw new Error(
    "Heartbeat block did not match expected source."
  );
}

const oldOffline =
  "      markPresenceOffline(auth.companyId, auth.membershipId);";

if (
  content.includes(
    oldOffline
  )
) {
  content = content.replace(
    oldOffline,
    `      void markPresenceOffline(
        auth.companyId,
        auth.membershipId,
        presenceConnectionId
      );`
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "SSE routes now maintain distributed Redis presence."
);
NODE

# ---------------------------------------------------------------------------
# App lifecycle + health diagnostics
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/app.ts";

let content =
  fs.readFileSync(path, "utf8");

const importLine =
  `import {
  closeRealtimeTransport,
  getRealtimeTransportStatus
} from "./modules/realtime/realtime.bus.js";`;

if (
  !content.includes(
    "closeRealtimeTransport,"
  )
) {
  const candidates = [
    'import { realtimeRoutes } from "./modules/realtime/realtime.routes.js";',
    'import { env } from "./config/env.js";'
  ];

  const anchor =
    candidates.find(
      candidate =>
        content.includes(
          candidate
        )
    );

  if (!anchor) {
    throw new Error(
      "App realtime import anchor not found."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
${importLine}`
  );
}

if (
  !content.includes(
    "realtime: getRealtimeTransportStatus()"
  )
) {
  const anchor =
    '      database: "ok",';

  if (!content.includes(anchor)) {
    throw new Error(
      "Health response database anchor not found."
    );
  }

  content = content.replace(
    anchor,
    `${anchor}
      realtime: getRealtimeTransportStatus(),`
  );
}

if (
  !content.includes(
    "await closeRealtimeTransport();"
  )
) {
  const anchor =
    `  app.addHook("onClose", async () => {
    await prisma.$disconnect();
  });`;

  if (!content.includes(anchor)) {
    throw new Error(
      "App onClose hook did not match expected source."
    );
  }

  content = content.replace(
    anchor,
    `  app.addHook("onClose", async () => {
    await closeRealtimeTransport();
    await prisma.$disconnect();
  });`
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "Realtime lifecycle and health diagnostics installed."
);
NODE

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/REDIS_REALTIME.md <<'EOF'
# Redis distributed realtime

P1.14 moves Wapp's realtime transport from a process-local EventEmitter to
Redis Pub/Sub while keeping the existing authenticated SSE browser contract.

## Browser contract

The web application continues to connect to:

`GET /api/v1/realtime/events`

No frontend event API changes are required.

## Transport

When `REDIS_URL` is configured and Redis is healthy:

```text
API replica A ── publish ──┐
                           │
                      Redis Pub/Sub
                           │
API replica B ── subscribe ┤
API replica C ── subscribe ┘
          │
          └── local EventEmitter -> SSE clients on that replica
```

Every API replica subscribes to `wapp:realtime:*`.

A published company event therefore reaches SSE clients connected to any API
replica.

## Local fallback

If Redis is missing or temporarily unavailable, Wapp falls back to the local
EventEmitter.

This keeps a single API process usable during local development or a transient
Redis outage.

The fallback cannot distribute events between multiple replicas. Production
multi-replica deployments must treat Redis availability as required
infrastructure.

## Presence

Presence is also distributed.

Each SSE connection receives a unique connection ID and stores a Redis sorted
set member with a 75-second expiry timestamp.

The SSE heartbeat refreshes the entry every 25 seconds.

This preserves multiple-tabs semantics:

- opening a second tab does not emit a second logical online transition;
- closing one of multiple tabs does not mark the membership offline;
- the final connection closing marks the membership offline.

A distributed sweep removes expired connection entries left by crashed API
processes or abruptly disconnected clients.

The sweep uses a Redis lock so only one API replica performs expiry cleanup at
a time.

## Health

`GET /health` now includes:

```json
{
  "realtime": {
    "mode": "redis",
    "redisConfigured": true,
    "redisReady": true
  }
}
```

`mode=local` means the process is currently using the fallback.

## Shutdown

Fastify's `onClose` hook closes Redis subscriber/publisher clients before
disconnecting Prisma.

## Migration

P1.14 requires no Prisma migration.
EOF

if ! grep -q "P1.14 distributed realtime" docs/OPERATIONS.md; then
  cat >> docs/OPERATIONS.md <<'EOF'

## P1.14 distributed realtime

The original P0.7 EventEmitter transport was intentionally limited to one API
process.

P1.14 keeps the same SSE contract but distributes company events and operator
presence through Redis Pub/Sub / Redis presence state.

See `docs/REDIS_REALTIME.md`.
EOF
fi

echo "[P1.14] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.14] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.14] Redis distributed realtime installed."
echo "No Prisma migration is required."
echo
echo "Restart:"
echo "  Ctrl+C"
echo "  pnpm dev"
echo
echo "Verify:"
echo "  1. open http://localhost:4000/health"
echo "  2. realtime.mode should be redis"
echo "  3. redisConfigured and redisReady should be true"
echo "  4. open Wapp in two browser tabs"
echo "  5. send/receive a WhatsApp message and confirm both tabs update"
echo "  6. close only one tab; the membership should remain online"
echo "  7. close the final tab; presence should become offline"
