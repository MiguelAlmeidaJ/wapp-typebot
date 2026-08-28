import type {
  FastifyInstance,
  FastifyRequest
} from "fastify";

import { requireAuth } from "../auth/auth.guard.js";
import {
  type AuditEntityType,
  recordAudit,
  snapshotAuditEntity
} from "./audit.service.js";

interface AuditContext {
  companyId: string;
  membershipId: string;
  role: string;
  action: string;
  entityType: AuditEntityType;
  entityId:
    | string
    | null;
  before:
    unknown;
  responseBody:
    unknown;
  requestId: string;
  ipAddress: string;
  userAgent:
    | string
    | undefined;
}

const contexts =
  new WeakMap<
    FastifyRequest,
    AuditContext
  >();

function objectValue(
  value: unknown
) {
  return value &&
    typeof value ===
      "object"
    ? value as
        Record<
          string,
          unknown
        >
    : {};
}

function idParam(
  request:
    FastifyRequest
) {
  const params =
    objectValue(
      request.params
    );

  return typeof params.id ===
    "string"
    ? params.id
    : null;
}

function routeDescriptor(
  request:
    FastifyRequest
):
  | {
      action: string;
      entityType:
        AuditEntityType;
      entityId:
        | string
        | null;
    }
  | null {
  const method =
    request.method
      .toUpperCase();

  const route =
    request.routeOptions
      .url;

  const key =
    `${method} ${route}`;

  const param =
    idParam(
      request
    );

  switch (key) {
    case "POST /api/v1/team/memberships":
      return {
        action:
          "TEAM_MEMBERSHIP_CREATED",
        entityType:
          "TEAM_MEMBERSHIP",
        entityId:
          null
      };

    case "PATCH /api/v1/team/memberships/:id":
      return {
        action:
          "TEAM_MEMBERSHIP_UPDATED",
        entityType:
          "TEAM_MEMBERSHIP",
        entityId:
          param
      };

    case "POST /api/v1/queues":
      return {
        action:
          "QUEUE_CREATED",
        entityType:
          "QUEUE",
        entityId:
          null
      };

    case "PUT /api/v1/queues/:id/members":
      return {
        action:
          "QUEUE_MEMBERS_UPDATED",
        entityType:
          "QUEUE",
        entityId:
          param
      };

    case "PUT /api/v1/sla/settings":
      return {
        action:
          "SLA_SETTINGS_UPDATED",
        entityType:
          "SLA_SETTINGS",
        entityId:
          null
      };

    case "POST /api/v1/tags":
      return {
        action:
          "TAG_CREATED",
        entityType:
          "TAG",
        entityId:
          null
      };

    case "PATCH /api/v1/tags/:id":
      return {
        action:
          "TAG_UPDATED",
        entityType:
          "TAG",
        entityId:
          param
      };

    case "POST /api/v1/quick-replies":
      return {
        action:
          "QUICK_REPLY_CREATED",
        entityType:
          "QUICK_REPLY",
        entityId:
          null
      };

    case "PATCH /api/v1/quick-replies/:id":
      return {
        action:
          "QUICK_REPLY_UPDATED",
        entityType:
          "QUICK_REPLY",
        entityId:
          param
      };

    case "POST /api/v1/whatsapp/connections":
      return {
        action:
          "WHATSAPP_CONNECTION_CREATED",
        entityType:
          "WHATSAPP_CONNECTION",
        entityId:
          null
      };

    case "PATCH /api/v1/whatsapp/connections/:id/settings":
      return {
        action:
          "WHATSAPP_CONNECTION_SETTINGS_UPDATED",
        entityType:
          "WHATSAPP_CONNECTION",
        entityId:
          param
      };

    case "POST /api/v1/whatsapp/connections/:id/connect":
      return {
        action:
          "WHATSAPP_CONNECTION_CONNECT_REQUESTED",
        entityType:
          "WHATSAPP_CONNECTION",
        entityId:
          param
      };

    default:
      return null;
  }
}

function responseEntityId(
  entityType:
    AuditEntityType,
  body: unknown
) {
  const root =
    objectValue(
      body
    );

  const key =
    entityType ===
      "TEAM_MEMBERSHIP"
      ? "membership"
      : entityType ===
          "QUEUE"
        ? "queue"
        : entityType ===
            "TAG"
          ? "tag"
          : entityType ===
              "QUICK_REPLY"
            ? "quickReply"
            : entityType ===
                "WHATSAPP_CONNECTION"
              ? "connection"
              : null;

  if (!key) {
    return null;
  }

  const entity =
    objectValue(
      root[key]
    );

  return typeof entity.id ===
    "string"
    ? entity.id
    : null;
}

function parsePayload(
  payload: unknown
) {
  try {
    if (
      typeof payload ===
        "string"
    ) {
      return JSON.parse(
        payload
      );
    }

    if (
      Buffer.isBuffer(
        payload
      )
    ) {
      return JSON.parse(
        payload.toString(
          "utf8"
        )
      );
    }
  } catch {
    return null;
  }

  return null;
}

export function installAdminAuditHooks(
  app: FastifyInstance
) {
  app.addHook(
    "preHandler",
    async request => {
      const descriptor =
        routeDescriptor(
          request
        );

      if (!descriptor) {
        return;
      }

      const auth =
        await requireAuth(
          request
        );

      const before =
        descriptor.entityId
          ? await snapshotAuditEntity({
              companyId:
                auth.companyId,
              entityType:
                descriptor.entityType,
              entityId:
                descriptor.entityId
            })
          : descriptor.entityType ===
              "SLA_SETTINGS"
            ? await snapshotAuditEntity({
                companyId:
                  auth.companyId,
                entityType:
                  descriptor.entityType,
                entityId:
                  auth.companyId
              })
            : null;

      contexts.set(
        request,
        {
          companyId:
            auth.companyId,
          membershipId:
            auth.membershipId,
          role:
            auth.role,
          action:
            descriptor.action,
          entityType:
            descriptor.entityType,
          entityId:
            descriptor.entityId,
          before,
          responseBody:
            null,
          requestId:
            request.id,
          ipAddress:
            request.ip,
          userAgent:
            request.headers[
              "user-agent"
            ]
        }
      );
    }
  );

  app.addHook(
    "onSend",
    async (
      request,
      _reply,
      payload
    ) => {
      const context =
        contexts.get(
          request
        );

      if (context) {
        context.responseBody =
          parsePayload(
            payload
          );
      }

      return payload;
    }
  );

  app.addHook(
    "onResponse",
    async (
      request,
      reply
    ) => {
      const context =
        contexts.get(
          request
        );

      if (
        !context ||
        reply.statusCode >=
          400
      ) {
        return;
      }

      try {
        const entityId =
          context.entityId ??
          (
            context.entityType ===
              "SLA_SETTINGS"
              ? context.companyId
              : responseEntityId(
                  context.entityType,
                  context.responseBody
                )
          );

        const after =
          entityId
            ? await snapshotAuditEntity({
                companyId:
                  context.companyId,
                entityType:
                  context.entityType,
                entityId
              })
            : null;

        await recordAudit({
          companyId:
            context.companyId,
          actorMembershipId:
            context.membershipId,
          action:
            context.action,
          entityType:
            context.entityType,
          entityId,
          before:
            context.before,
          after,
          metadata: {
            role:
              context.role,
            method:
              request.method,
            route:
              request
                .routeOptions
                .url
          },
          requestId:
            context.requestId,
          ipAddress:
            context.ipAddress,
          userAgent:
            context.userAgent
        });
      } catch (error) {
        request.log.error(
          {
            err:
              error
          },
          "Administrative audit write failed."
        );
      } finally {
        contexts.delete(
          request
        );
      }
    }
  );
}
