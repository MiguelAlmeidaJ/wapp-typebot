import cookie from "@fastify/cookie";
import cors from "@fastify/cors";
import Fastify from "fastify";
import { ZodError } from "zod";

import { env } from "./config/env.js";
import { AppError } from "./errors/app-error.js";
import { prisma } from "./lib/database.js";
import { adminRoutes } from "./modules/admin/admin.routes.js";
import { authRoutes } from "./modules/auth/auth.routes.js";
import { contactRoutes } from "./modules/contacts/contact.routes.js";
import { whatsappRoutes } from "./modules/whatsapp/whatsapp.routes.js";
import { ticketRoutes } from "./modules/tickets/ticket.routes.js";
import { mediaRoutes } from "./modules/media/media.routes.js";
import { teamRoutes } from "./modules/team/team.routes.js";
import { realtimeRoutes } from "./modules/realtime/realtime.routes.js";
import { queueRoutes } from "./modules/queues/queue.routes.js";
import { evolutionWebhookRoutes } from "./modules/webhooks/evolution-webhook.routes.js";

export async function buildApp() {
  const app = Fastify({
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
    ]
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
  await app.register(contactRoutes);
  await app.register(adminRoutes);
  await app.register(whatsappRoutes);
  await app.register(ticketRoutes);
  await app.register(mediaRoutes);
  await app.register(realtimeRoutes);
  await app.register(teamRoutes);
  await app.register(queueRoutes);
  await app.register(evolutionWebhookRoutes);

  app.addHook("onClose", async () => {
    await prisma.$disconnect();
  });

  return app;
}
