import { PrismaMariaDb } from "@prisma/adapter-mariadb";

import { env } from "../config/env.js";
import { PrismaClient } from "../generated/prisma/client.js";
import {
  buildDatabaseTlsOptions
} from "./database-tls.js";


function createAdapter() {
  const databaseUrl = new URL(env.DATABASE_URL);

  if (databaseUrl.protocol !== "mysql:") {
    throw new Error("DATABASE_URL must use the mysql:// protocol");
  }

const databaseTls =
  buildDatabaseTlsOptions({
    nodeEnv:
      env.NODE_ENV,
    caPath:
      env.DATABASE_TLS_CA_PATH
  });

  return new PrismaMariaDb({
    host: databaseUrl.hostname,
    port: Number(databaseUrl.port || 3306),
    user: decodeURIComponent(databaseUrl.username),
    password: decodeURIComponent(databaseUrl.password),
    database: databaseUrl.pathname.replace(/^\//, ""),
    connectionLimit: 10,

    /*
     * MySQL 8.x defaults to caching_sha2_password.
     * MariaDB Connector/Node does not retrieve the server RSA key unless
     * explicitly allowed.
     *
     * Local development runs without TLS, so allow key retrieval here.
     * Production must use TLS and/or an explicitly configured server key.
     */
    allowPublicKeyRetrieval: env.NODE_ENV !== "production",
  ssl: databaseTls
  });
}

export const prisma = new PrismaClient({
  adapter: createAdapter()
});
