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
    "audit.read",
    "observability.read",
    "automations.read",
    "automations.manage",
    "reports.read",
    "contacts.read",
    "contacts.manage",
    "contactFields.manage",
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
    "whatsapp.test",
    "pipelines.read",
    "pipelines.move",
    "pipelines.manage",
    "tasks.read",
    "tasks.manage",
    "tasks.admin",
    "segments.read",
    "segments.manage",
    "campaigns.read",
    "campaigns.manage",
    "campaigns.send"
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
            "audit.read",
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
            "observability.read",
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
            "observability.read",
            "audit.read",
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


describe(
  "automation permissions",
  () => {
    it(
      "automation capability follows operational roles",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN",
            "SUPERVISOR"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              role,
              "automations.read"
            ),
            true
          );

          assert.equal(
            roleHasPermission(
              role,
              "automations.manage"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "automations.read"
          ),
          true
        );

        assert.equal(
          roleHasPermission(
            "AGENT",
            "automations.manage"
          ),
          false
        );
      }
    );
  }
);


describe(
  "management report permissions",
  () => {
    it(
      "management reports are restricted to managerial roles",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN",
            "SUPERVISOR"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              role,
              "reports.read"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "reports.read"
          ),
          false
        );
      }
    );
  }
);


describe(
  "contact CRM field permissions",
  () => {
    it(
      "contact field schema is managerial only",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN",
            "SUPERVISOR"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              role,
              "contactFields.manage"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "contactFields.manage"
          ),
          false
        );
      }
    );
  }
);


describe(
  "CRM pipeline permissions",
  () => {
    it(
      "pipeline schema is managerial while movement stays operational",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN",
            "SUPERVISOR"
          ] as const
        ) {
          assert.equal(
            roleHasPermission(
              role,
              "pipelines.manage"
            ),
            true
          );

          assert.equal(
            roleHasPermission(
              role,
              "pipelines.move"
            ),
            true
          );
        }

        assert.equal(
          roleHasPermission(
            "AGENT",
            "pipelines.read"
          ),
          true
        );

        assert.equal(
          roleHasPermission(
            "AGENT",
            "pipelines.move"
          ),
          true
        );

        assert.equal(
          roleHasPermission(
            "AGENT",
            "pipelines.manage"
          ),
          false
        );
      }
    );
  }
);


describe(
  "CRM task permissions",
  () => {
    it(
      "task work is operational while team-wide scope is managerial",
      () => {
        for (
          const role
          of [
            "OWNER",
            "ADMIN",
            "SUPERVISOR"
          ] as const
        ) {
          assert.equal(roleHasPermission(role, "tasks.read"), true);
          assert.equal(roleHasPermission(role, "tasks.manage"), true);
          assert.equal(roleHasPermission(role, "tasks.admin"), true);
        }

        assert.equal(roleHasPermission("AGENT", "tasks.read"), true);
        assert.equal(roleHasPermission("AGENT", "tasks.manage"), true);
        assert.equal(roleHasPermission("AGENT", "tasks.admin"), false);
      }
    );
  }
);


describe(
  "contact segment permissions",
  () => {
    it(
      "saved segments are readable operationally and managed by leaders",
      () => {
        for (const role of ["OWNER", "ADMIN", "SUPERVISOR"] as const) {
          assert.equal(roleHasPermission(role, "segments.read"), true);
          assert.equal(roleHasPermission(role, "segments.manage"), true);
        }
        assert.equal(roleHasPermission("AGENT", "segments.read"), true);
        assert.equal(roleHasPermission("AGENT", "segments.manage"), false);
      }
    );
  }
);


describe(
  "controlled campaign permissions",
  () => {
    it(
      "campaign launch is owner/admin only",
      () => {
        for (
          const role
          of ["OWNER", "ADMIN"] as const
        ) {
          assert.equal(roleHasPermission(role, "campaigns.read"), true);
          assert.equal(roleHasPermission(role, "campaigns.manage"), true);
          assert.equal(roleHasPermission(role, "campaigns.send"), true);
        }

        assert.equal(roleHasPermission("SUPERVISOR", "campaigns.read"), true);
        assert.equal(roleHasPermission("SUPERVISOR", "campaigns.manage"), true);
        assert.equal(roleHasPermission("SUPERVISOR", "campaigns.send"), false);
        assert.equal(roleHasPermission("AGENT", "campaigns.read"), true);
        assert.equal(roleHasPermission("AGENT", "campaigns.manage"), false);
        assert.equal(roleHasPermission("AGENT", "campaigns.send"), false);
      }
    );
  }
);
