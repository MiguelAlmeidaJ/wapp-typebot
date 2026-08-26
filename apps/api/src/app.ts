import cors from "@fastify/cors";
import Fastify from "fastify";

import { env } from "./config/env.js";

export async function buildApp() {
  const app = Fastify({
    logger: {
      level: env.NODE_ENV === "production" ? "info" : "debug"
    }
  });

  await app.register(cors, {
    origin: env.WEB_URL,
    credentials: true
  });

  app.get("/health", async () => ({
    status: "ok",
    service: "wapp-api",
    timestamp: new Date().toISOString()
  }));

  app.get("/api/v1", async () => ({
    name: "Wapp API",
    version: "0.1.0"
  }));

  return app;
}
