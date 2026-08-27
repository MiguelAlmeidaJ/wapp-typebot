import { EventEmitter } from "node:events";
import { randomUUID } from "node:crypto";

import { Redis } from "ioredis";

import { env } from "../../config/env.js";

export type RealtimeEventType =
  | "message.created"
  | "message.updated"
  | "note.created"
  | "quick-reply.updated"
  | "tag.updated"
  | "sla.updated"
  | "ticket.event.created"
  | "ticket.updated"
  | "ticket.created"
  | "queue.updated"
  | "connection.updated"
  | "presence.updated";

export interface RealtimeEvent {
  id: string;
  type: RealtimeEventType;
  occurredAt: string;
  ticketId?: string;
  messageId?: string;
  noteId?: string;
  quickReplyId?: string;
  tagId?: string;
  eventId?: string;
  queueId?: string;
  connectionId?: string;
  membershipId?: string;
  online?: boolean;
}

const emitter =
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
  return `company:${companyId}`;
}

function redisCompanyChannel(
  companyId: string
) {
  return `${REDIS_CHANNEL_PREFIX}${companyId}`;
}

function presenceKey(
  companyId: string
) {
  return `${PRESENCE_KEY_PREFIX}${companyId}`;
}

function presenceMember(
  membershipId: string,
  connectionId: string
) {
  return `${membershipId}:${connectionId}`;
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
    `[realtime] ${message}`,
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
    `
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      end
      return 0
    `,
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
          `${REDIS_CHANNEL_PREFIX}*`
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
