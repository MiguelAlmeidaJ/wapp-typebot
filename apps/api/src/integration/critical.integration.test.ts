import assert from "node:assert/strict";
import {
  randomUUID
} from "node:crypto";
import {
  after,
  before,
  test
} from "node:test";

import type {
  FastifyInstance
} from "fastify";

import { buildApp } from "../app.js";
import { prisma } from "../lib/database.js";
import { hashPassword } from "../lib/password.js";

const OWNER_EMAIL =
  "owner.integration@wapp.test";

const AGENT_EMAIL =
  "agent.integration@wapp.test";

const PASSWORD =
  "IntegrationPassword!123";

let app:
  FastifyInstance;

let ticketId = "";
let aroundMessageId = "";

function cookieHeader(
  value:
    | string
    | string[]
    | undefined
) {
  const raw =
    Array.isArray(value)
      ? value[0]
      : value;

  assert.ok(
    raw,
    "Expected Set-Cookie header."
  );

  return raw.split(
    ";",
    1
  )[0]!;
}

async function login(
  email: string
) {
  const response =
    await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: {
        email,
        password:
          PASSWORD,
        companySlug:
          "integration"
      }
    });

  assert.equal(
    response.statusCode,
    200,
    response.body
  );

  const body =
    response.json<{
      accessToken: string;
      role: string;
    }>();

  return {
    accessToken:
      body.accessToken,
    role:
      body.role,
    cookie:
      cookieHeader(
        response.headers[
          "set-cookie"
        ]
      )
  };
}

before(async () => {
  const passwordHash =
    await hashPassword(
      PASSWORD
    );

  const company =
    await prisma.company.create({
      data: {
        name:
          "Wapp Integration",
        slug:
          "integration"
      }
    });

  const owner =
    await prisma.user.create({
      data: {
        name:
          "Integration Owner",
        email:
          OWNER_EMAIL,
        passwordHash
      }
    });

  const agent =
    await prisma.user.create({
      data: {
        name:
          "Integration Agent",
        email:
          AGENT_EMAIL,
        passwordHash
      }
    });

  await prisma.companyMembership.createMany({
    data: [
      {
        companyId:
          company.id,
        userId:
          owner.id,
        role:
          "OWNER"
      },
      {
        companyId:
          company.id,
        userId:
          agent.id,
        role:
          "AGENT"
      }
    ]
  });

  /*
   * META_CLOUD is used only as a database fixture so the Evolution health
   * monitor has no instance to probe during this isolated test.
   */
  const connection =
    await prisma.whatsAppConnection.create({
      data: {
        companyId:
          company.id,
        name:
          "Integration fixture",
        instanceName:
          `integration-${randomUUID()}`,
        provider:
          "META_CLOUD",
        status:
          "CONNECTED"
      }
    });

  const contact =
    await prisma.contact.create({
      data: {
        companyId:
          company.id,
        remoteJid:
          "5511999999999@s.whatsapp.net",
        phoneNumber:
          "5511999999999",
        name:
          "Integration Contact"
      }
    });

  const ticket =
    await prisma.ticket.create({
      data: {
        companyId:
          company.id,
        whatsappConnectionId:
          connection.id,
        contactId:
          contact.id,
        activeKey:
          `${connection.id}:${contact.id}`,
        status:
          "OPEN",
        lastMessage:
          "message-124",
        lastMessageAt:
          new Date(
            "2026-08-28T12:02:04.000Z"
          )
      }
    });

  ticketId =
    ticket.id;

  const rows =
    Array.from(
      {
        length: 125
      },
      (
        _,
        index
      ) => ({
        id:
          randomUUID(),
        companyId:
          company.id,
        ticketId:
          ticket.id,
        whatsappConnectionId:
          connection.id,
        externalId:
          `integration-${index}`,
        direction:
          index % 2 === 0
            ? "INBOUND" as const
            : "OUTBOUND" as const,
        type:
          "TEXT" as const,
        body:
          `message-${String(
            index
          ).padStart(
            3,
            "0"
          )}`,
        timestamp:
          new Date(
            Date.UTC(
              2026,
              7,
              28,
              12,
              0,
              index
            )
          )
      })
    );

  aroundMessageId =
    rows[60]!.id;

  await prisma.message.createMany({
    data:
      rows
  });

  app =
    await buildApp();

  await app.ready();
});

after(async () => {
  if (app) {
    await app.close();
  }
});

test(
  "critical API integration flow",
  async t => {
    await t.test(
      "database + redis readiness",
      async () => {
        const live =
          await app.inject({
            method: "GET",
            url:
              "/health/live"
          });

        assert.equal(
          live.statusCode,
          200
        );

        assert.equal(
          live.json<{
            status: string;
          }>().status,
          "ok"
        );

        const ready =
          await app.inject({
            method: "GET",
            url:
              "/health/ready"
          });

        assert.equal(
          ready.statusCode,
          200,
          ready.body
        );

        assert.equal(
          ready.json<{
            ready: boolean;
          }>().ready,
          true
        );
      }
    );

    const owner =
      await login(
        OWNER_EMAIL
      );

    await t.test(
      "owner login + authenticated session",
      async () => {
        assert.equal(
          owner.role,
          "OWNER"
        );

        const me =
          await app.inject({
            method: "GET",
            url:
              "/api/v1/auth/me",
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          me.statusCode,
          200,
          me.body
        );

        assert.equal(
          me.json<{
            role: string;
          }>().role,
          "OWNER"
        );
      }
    );

    await t.test(
      "RBAC denies AGENT admin capability",
      async () => {
        const agent =
          await login(
            AGENT_EMAIL
          );

        const denied =
          await app.inject({
            method: "GET",
            url:
              "/api/v1/admin/ping",
            headers: {
              authorization:
                `Bearer ${agent.accessToken}`
            }
          });

        assert.equal(
          denied.statusCode,
          403,
          denied.body
        );

        const allowed =
          await app.inject({
            method: "GET",
            url:
              "/api/v1/admin/ping",
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          allowed.statusCode,
          200,
          allowed.body
        );
      }
    );

    await t.test(
      "P1.21 opens newest page and pages backward",
      async () => {
        const latest =
          await app.inject({
            method: "GET",
            url:
              `/api/v1/tickets/${ticketId}/messages?limit=80`,
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          latest.statusCode,
          200,
          latest.body
        );

        const page =
          latest.json<{
            messages: Array<{
              id: string;
              body: string;
            }>;
            pagination: {
              hasMoreBefore: boolean;
              olderCursor:
                | string
                | null;
            };
          }>();

        assert.equal(
          page.messages.length,
          80
        );

        assert.equal(
          page.messages[0]?.body,
          "message-045"
        );

        assert.equal(
          page.messages[79]?.body,
          "message-124"
        );

        assert.equal(
          page.pagination
            .hasMoreBefore,
          true
        );

        assert.ok(
          page.pagination
            .olderCursor
        );

        const older =
          await app.inject({
            method: "GET",
            url:
              `/api/v1/tickets/${ticketId}/messages?limit=80&before=${page.pagination.olderCursor}`,
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          older.statusCode,
          200,
          older.body
        );

        const olderPage =
          older.json<{
            messages: Array<{
              body: string;
            }>;
            pagination: {
              hasMoreBefore:
                boolean;
            };
          }>();

        assert.equal(
          olderPage.messages.length,
          45
        );

        assert.equal(
          olderPage.messages[0]?.body,
          "message-000"
        );

        assert.equal(
          olderPage.messages[44]?.body,
          "message-044"
        );

        assert.equal(
          olderPage.pagination
            .hasMoreBefore,
          false
        );
      }
    );

    await t.test(
      "P1.21 around cursor returns exact searched message",
      async () => {
        const response =
          await app.inject({
            method: "GET",
            url:
              `/api/v1/tickets/${ticketId}/messages?limit=80&around=${aroundMessageId}`,
            headers: {
              authorization:
                `Bearer ${owner.accessToken}`
            }
          });

        assert.equal(
          response.statusCode,
          200,
          response.body
        );

        const payload =
          response.json<{
            messages: Array<{
              id: string;
            }>;
            pagination: {
              hasMoreBefore:
                boolean;
              hasMoreAfter:
                boolean;
            };
          }>();

        assert.ok(
          payload.messages.some(
            message =>
              message.id ===
              aroundMessageId
          )
        );

        assert.equal(
          payload.pagination
            .hasMoreBefore,
          true
        );

        assert.equal(
          payload.pagination
            .hasMoreAfter,
          true
        );
      }
    );

    await t.test(
      "refresh rotation invalidates previous refresh token and logout revokes session",
      async () => {
        const refreshed =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/auth/refresh",
            headers: {
              cookie:
                owner.cookie
            }
          });

        assert.equal(
          refreshed.statusCode,
          200,
          refreshed.body
        );

        const rotatedCookie =
          cookieHeader(
            refreshed.headers[
              "set-cookie"
            ]
          );

        assert.notEqual(
          rotatedCookie,
          owner.cookie
        );

        const oldToken =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/auth/refresh",
            headers: {
              cookie:
                owner.cookie
            }
          });

        assert.equal(
          oldToken.statusCode,
          401
        );

        const logout =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/auth/logout",
            headers: {
              cookie:
                rotatedCookie
            }
          });

        assert.equal(
          logout.statusCode,
          200,
          logout.body
        );

        const revoked =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/auth/refresh",
            headers: {
              cookie:
                rotatedCookie
            }
          });

        assert.equal(
          revoked.statusCode,
          401
        );
      }
    );
  }
);
