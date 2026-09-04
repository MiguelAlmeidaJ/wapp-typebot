import cookie from "@fastify/cookie";
import cors from "@fastify/cors";
import multipart from "@fastify/multipart";
import Fastify from "fastify";
import { ZodError } from "zod";

import { env } from "./config/env.js";
import {
  closeJobRuntime,
  startEmbeddedJobWorker
} from "./jobs/job-runtime.js";
import { AppError } from "./errors/app-error.js";
import { closeRateLimitStore } from "./security/rate-limit.js";
import { prisma } from "./lib/database.js";
import { adminRoutes } from "./modules/admin/admin.routes.js";
import { automationRoutes } from "./modules/automations/automation.routes.js";
import { auditRoutes } from "./modules/audit/audit.routes.js";
import { installAdminAuditHooks } from "./modules/audit/audit.hooks.js";
import { authRoutes } from "./modules/auth/auth.routes.js";
import { contactRoutes } from "./modules/contacts/contact.routes.js";
import { contactCrmRoutes } from "./modules/contact-crm/contact-crm.routes.js";
import { pipelineRoutes } from "./modules/pipelines/pipeline.routes.js";
import { taskRoutes } from "./modules/tasks/task.routes.js";
import { segmentRoutes } from "./modules/segments/segment.routes.js";
import { campaignRoutes } from "./modules/campaigns/campaign.routes.js";
import { dataQualityRoutes } from "./modules/data-quality/data-quality.routes.js";
import { whatsappRoutes } from "./modules/whatsapp/whatsapp.routes.js";
import {
  startEvolutionHealthMonitor,
  stopEvolutionHealthMonitor
} from "./modules/whatsapp/evolution-health-monitor.service.js";
import { ticketRoutes } from "./modules/tickets/ticket.routes.js";
import { ticketMediaRoutes } from "./modules/tickets/ticket-media.routes.js";
import { mediaRoutes } from "./modules/media/media.routes.js";
import { messageSearchRoutes } from "./modules/messages/message-search.routes.js";
import { teamRoutes } from "./modules/team/team.routes.js";
import { tagRoutes } from "./modules/tags/tag.routes.js";
import { slaRoutes } from "./modules/sla/sla.routes.js";
import { operationalAnalyticsRoutes } from "./modules/analytics/operational-analytics.routes.js";
import { managementReportRoutes } from "./modules/analytics/management-report.routes.js";
import { realtimeRoutes } from "./modules/realtime/realtime.routes.js";
import { notificationRoutes } from "./modules/notifications/notification.routes.js";
import { healthRoutes } from "./modules/health/health.routes.js";
import { observabilityRoutes } from "./modules/observability/observability.routes.js";
import { installHttpMetricsHooks } from "./modules/observability/metrics.service.js";
import {
  closeRealtimeTransport,
  getRealtimeTransportStatus
} from "./modules/realtime/realtime.bus.js";
import { queueRoutes } from "./modules/queues/queue.routes.js";
import { quickReplyRoutes } from "./modules/quick-replies/quick-reply.routes.js";
import { scheduledMessageRoutes } from "./modules/scheduled-messages/scheduled-message.routes.js";
import { evolutionWebhookRoutes } from "./modules/webhooks/evolution-webhook.routes.js";
import { chatbotRoutes } from "./modules/chatbots/chatbot.routes.js";

export async function buildApp() {
  const app = Fastify({
    trustProxy:
      env.TRUST_PROXY,
    bodyLimit:
      env.API_BODY_MAX_BYTES,
    logger: {
      level: env.NODE_ENV === "production" ? "info" : "debug"
    }
  });

  await app.register(cors, {
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
    ],
    exposedHeaders: ["X-Request-Id"]
  });

  await app.register(cookie);

  await app.register(multipart, {
    limits: {
      fileSize: env.MEDIA_MAX_BYTES,
      files: 1,
      fields: 4,
      parts: 5
    }
  });

  app.addHook(
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

  app.addHook(
    "onSend",
    async (
      request,
      reply,
      payload
    ) => {
      reply.header(
        "X-Request-Id",
        request.id
      );

      return payload;
    }
  );

  installAdminAuditHooks(app);
  installHttpMetricsHooks(app);

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof AppError) {
      return reply.status(error.statusCode).send({
        error: {
          code: error.code,
          message: error.message,
          details: error.details,
          requestId: request.id
        }
      });
    }

    if (error instanceof ZodError) {
      return reply.status(422).send({
        error: {
          code: "VALIDATION_ERROR",
          message: "Dados inválidos.",
          details: error.flatten().fieldErrors,
          requestId: request.id
        }
      });
    }

    request.log.error(error);

    return reply.status(500).send({
      error: {
        code: "INTERNAL_ERROR",
        message: "Erro interno do servidor.",
        requestId: request.id
      }
    });
  });

  app.get("/api/v1", async () => ({
    name: "Wapp API",
    version: "0.1.0"
  }));

  await app.register(healthRoutes);
  await app.register(observabilityRoutes);
  await app.register(authRoutes);
  await app.register(automationRoutes);
  await app.register(chatbotRoutes);
  await app.register(contactRoutes);
  await app.register(contactCrmRoutes);
  await app.register(pipelineRoutes);
  await app.register(taskRoutes);
  await app.register(segmentRoutes);
  await app.register(campaignRoutes);
  await app.register(dataQualityRoutes);
  await app.register(adminRoutes);
  await app.register(auditRoutes);
  await app.register(whatsappRoutes);
  await app.register(ticketRoutes);
  await app.register(ticketMediaRoutes);
  await app.register(mediaRoutes);
  await app.register(messageSearchRoutes);
  await app.register(realtimeRoutes);
  await app.register(notificationRoutes);
  await app.register(teamRoutes);
  await app.register(tagRoutes);
  await app.register(slaRoutes);
  await app.register(operationalAnalyticsRoutes);
  await app.register(managementReportRoutes);
  await app.register(queueRoutes);
  await app.register(quickReplyRoutes);
  await app.register(scheduledMessageRoutes);
  await app.register(evolutionWebhookRoutes);

  app.addHook("onClose", async () => {
    await stopEvolutionHealthMonitor();
    await closeJobRuntime();
    await closeRealtimeTransport();
    await closeRateLimitStore();
    await prisma.$disconnect();
  });

  startEmbeddedJobWorker();

  startEvolutionHealthMonitor();

  return app;
}
