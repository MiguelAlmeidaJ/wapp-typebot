import { randomUUID } from "node:crypto";

import type { FastifyInstance } from "fastify";

import { env } from "../../config/env.js";

import { requireAuth } from "../auth/auth.guard.js";
import {
  listOnlineMembershipIds,
  markPresenceOffline,
  markPresenceOnline,
  refreshPresence,
  subscribeRealtime,
  type RealtimeEvent
} from "./realtime.bus.js";

export async function realtimeRoutes(app: FastifyInstance) {
  app.get("/api/v1/realtime/presence", async request => {
    const auth = await requireAuth(request);

    return {
      membershipIds: await listOnlineMembershipIds(auth.companyId)
    };
  });

  app.get("/api/v1/realtime/events", async (request, reply) => {
    const auth = await requireAuth(request);

    reply.hijack();

    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
      "Access-Control-Allow-Origin": env.WEB_URL,
      "Access-Control-Allow-Credentials": "true",
      Vary: "Origin"
    });

    const send = (event: RealtimeEvent) => {
      if (
        event.type ===
          "notification.created" &&
        event.membershipId !==
          auth.membershipId
      ) {
        return;
      }

      reply.raw.write(`data: ${JSON.stringify(event)}\n\n`);
    };

    const presenceConnectionId = randomUUID();

    const unsubscribe = subscribeRealtime(auth.companyId, send);
    await markPresenceOnline(
      auth.companyId,
      auth.membershipId,
      presenceConnectionId
    );

    reply.raw.write(
      `data: ${JSON.stringify({
        id: "ready",
        type: "realtime.ready",
        occurredAt: new Date().toISOString()
      })}\n\n`
    );

    const heartbeat = setInterval(() => {
      void refreshPresence(
        auth.companyId,
        auth.membershipId,
        presenceConnectionId
      );

      reply.raw.write(": heartbeat\n\n");
    }, 25_000);

    let closed = false;

    const cleanup = () => {
      if (closed) return;
      closed = true;
      clearInterval(heartbeat);
      unsubscribe();
      void markPresenceOffline(
        auth.companyId,
        auth.membershipId,
        presenceConnectionId
      );
    };

    reply.raw.once("close", cleanup);

    return reply;
  });
}
