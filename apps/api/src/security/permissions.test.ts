import assert from "node:assert/strict";
import {
  describe,
  it
} from "node:test";

import {
  roleHasPermission,
  type WappPermission
} from "./permissions.js";

const allPermissions:
  WappPermission[] = [
    "admin.test",
    "contacts.read",
    "contacts.manage",
    "quickReplies.read",
    "quickReplies.manage",
    "tags.read",
    "tags.manage",
    "sla.read",
    "sla.manage",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ];

describe(
  "RBAC permission matrix",
  () => {
    it(
      "OWNER and ADMIN have the full current capability set",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN"
          ] as const
        ) {
          for (
            const permission
            of allPermissions
          ) {
            assert.equal(
              roleHasPermission(
                role,
                permission
              ),
              true,
              `${role} should have ${permission}`
            );
          }
        }
      }
    );

    it(
      "SUPERVISOR cannot manage team, queues or WhatsApp connections",
      () => {
        for (
          const permission
          of [
            "team.manage",
            "queues.manage",
            "whatsapp.manage",
            "admin.test"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              "SUPERVISOR",
              permission
            ),
            false,
            `SUPERVISOR must not have ${permission}`
          );
        }

        for (
          const permission
          of [
            "contacts.manage",
            "quickReplies.manage",
            "tags.manage",
            "sla.manage",
            "team.read",
            "queues.read",
            "whatsapp.read",
            "whatsapp.test"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              "SUPERVISOR",
              permission
            ),
            true,
            `SUPERVISOR should have ${permission}`
          );
        }
      }
    );

    it(
      "AGENT remains operational but cannot manage shared administration",
      () => {
        for (
          const permission
          of [
            "contacts.read",
            "contacts.manage",
            "quickReplies.read",
            "tags.read",
            "sla.read",
            "team.read",
            "queues.read",
            "whatsapp.read"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              "AGENT",
              permission
            ),
            true,
            `AGENT should have ${permission}`
          );
        }

        for (
          const permission
          of [
            "admin.test",
            "quickReplies.manage",
            "tags.manage",
            "sla.manage",
            "team.manage",
            "queues.manage",
            "whatsapp.manage",
            "whatsapp.test"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              "AGENT",
              permission
            ),
            false,
            `AGENT must not have ${permission}`
          );
        }
      }
    );
  }
);
