import type { RedisOptions } from "ioredis";

import { env } from "../config/env.js";

function redisUrl() {
  if (!env.REDIS_URL) {
    throw new Error(
      "REDIS_URL is required for durable jobs."
    );
  }

  return new URL(
    env.REDIS_URL
  );
}

function baseOptions():
  RedisOptions {
  const url =
    redisUrl();

  const pathname =
    url.pathname
      .replace(
        /^\/+/,
        ""
      );

  const db =
    pathname
      ? Number(
          pathname
        )
      : 0;

  if (
    !Number.isInteger(
      db
    ) ||
    db < 0
  ) {
    throw new Error(
      "Invalid Redis database in REDIS_URL."
    );
  }

  return {
    host:
      url.hostname,
    port:
      Number(
        url.port ||
        "6379"
      ),
    username:
      url.username
        ? decodeURIComponent(
            url.username
          )
        : undefined,
    password:
      url.password
        ? decodeURIComponent(
            url.password
          )
        : undefined,
    db,
    ...(url.protocol ===
      "rediss:"
      ? {
          tls: {}
        }
      : {})
  };
}

export function jobProducerRedisOptions():
  RedisOptions {
  return {
    ...baseOptions(),
    maxRetriesPerRequest:
      1,
    enableReadyCheck:
      true
  };
}

export function jobWorkerRedisOptions():
  RedisOptions {
  return {
    ...baseOptions(),
    /*
     * BullMQ workers require null so blocking commands can survive normal
     * Redis reconnects without ioredis aborting the request.
     */
    maxRetriesPerRequest:
      null,
    enableReadyCheck:
      true
  };
}
