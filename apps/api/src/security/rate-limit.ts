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
