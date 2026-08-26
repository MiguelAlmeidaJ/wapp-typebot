import { PrismaMariaDb } from "@prisma/adapter-mariadb";

import { env } from "../config/env.js";
import { PrismaClient } from "../generated/prisma/client.js";

function createAdapter() {
  const databaseUrl = new URL(env.DATABASE_URL);

  if (databaseUrl.protocol !== "mysql:") {
    throw new Error("DATABASE_URL must use the mysql:// protocol");
  }

  return new PrismaMariaDb({
    host: databaseUrl.hostname,
    port: Number(databaseUrl.port || 3306),
    user: decodeURIComponent(databaseUrl.username),
    password: decodeURIComponent(databaseUrl.password),
    database: databaseUrl.pathname.replace(/^\//, ""),
    connectionLimit: 10
  });
}

export const prisma = new PrismaClient({
  adapter: createAdapter()
});
