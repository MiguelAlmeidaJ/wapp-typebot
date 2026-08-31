#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CI=".github/workflows/quality-gate.yml"
POLICY="apps/api/src/modules/campaigns/campaign.policy.ts"
POLICY_TEST="apps/api/src/modules/campaigns/campaign.policy.test.ts"
QUEUE="apps/api/src/jobs/campaign.queue.ts"
WORKER="apps/api/src/jobs/campaign.worker.ts"
SERVICE="apps/api/src/modules/campaigns/campaign.service.ts"
CONSENT="apps/api/src/modules/campaigns/campaign-consent.service.ts"
INTEGRATION="apps/api/src/integration/critical.integration.test.ts"
QUALITY_DOC="docs/QUALITY_GATE.md"
CAMPAIGN_DOC="docs/P3_05_CONTROLLED_CAMPAIGNS.md"

echo "[P3.5.1] Installing stabilization gate..."

for file in \
  "$CI" \
  "$POLICY" \
  "$POLICY_TEST" \
  "$QUEUE" \
  "$WORKER" \
  "$SERVICE" \
  "$CONSENT" \
  "$INTEGRATION" \
  "$QUALITY_DOC" \
  "$CAMPAIGN_DOC"
do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: missing $file"
    exit 1
  fi
done

for check in \
  "$CI|NEXT_PUBLIC_API_URL: http://localhost:4000" \
  "$POLICY|plannedCampaignSendAt" \
  "$QUEUE|campaign-recipient-" \
  "$WORKER|createCampaignWorker" \
  "$SERVICE|deliverCampaignRecipient" \
  "$SERVICE|refreshCampaignCompletion" \
  "$CONSENT|applyInboundCampaignOptOut" \
  "$INTEGRATION|critical API integration flow"
do
  file="${check%%|*}"
  marker="${check#*|}"
  if ! grep -Fq -- "$marker" "$file"; then
    echo "ERROR: expected P3.5.1 anchor missing: $file -> $marker"
    exit 1
  fi
done

node <<'NODE'
const fs = require("node:fs");
const path = ".github/workflows/quality-gate.yml";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("DATABASE_URL: mysql://wapp_ci:")) {
  const anchor = "    NEXT_PUBLIC_API_URL: http://localhost:4000\n";
  if (!content.includes(anchor)) {
    throw new Error("Quality Gate env anchor not found.");
  }

  content = content.replace(
    anchor,
    `${anchor}    DATABASE_URL: mysql://wapp_ci:wapp_ci@127.0.0.1:3306/wapp_ci
    SHADOW_DATABASE_URL: mysql://wapp_ci:wapp_ci@127.0.0.1:3306/wapp_ci_shadow
`
  );
}

fs.writeFileSync(path, content);
console.log("[P3.5.1] CI Prisma environment fixed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/modules/campaigns/campaign.policy.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("export function nextCampaignDispatchAt(")) {
  const anchor = `export function campaignWindowError(input: {`;
  if (!content.includes(anchor)) {
    throw new Error("campaignWindowError anchor not found.");
  }

  const helper = `export function nextCampaignDispatchAt(input: {
  now: Date;
  lastActivityAt: Date | null;
  ratePerMinute: number;
}) {
  if (!input.lastActivityAt) return input.now;

  const safeRate = Math.max(1, Math.min(10, input.ratePerMinute));
  const cadenceMs = Math.ceil(60_000 / safeRate);

  return new Date(
    Math.max(
      input.now.getTime(),
      input.lastActivityAt.getTime() + cadenceMs
    )
  );
}

`;

  content = content.replace(anchor, helper + anchor);
}

fs.writeFileSync(path, content);
console.log("[P3.5.1] Campaign cadence policy installed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/modules/campaigns/campaign.policy.test.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("nextCampaignDispatchAt")) {
  const importAnchor = `  isCampaignOptOutKeyword,
  plannedCampaignSendAt`;
  if (!content.includes(importAnchor)) {
    throw new Error("campaign policy test import anchor not found.");
  }
  content = content.replace(
    importAnchor,
    `  isCampaignOptOutKeyword,
  nextCampaignDispatchAt,
  plannedCampaignSendAt`
  );
}

if (!content.includes('"recovered campaign backlog keeps its configured cadence"')) {
  content += `

test("recovered campaign backlog keeps its configured cadence", () => {
  const now = new Date("2026-08-31T12:10:00.000Z");
  const lastActivityAt = new Date("2026-08-31T12:09:30.000Z");

  assert.equal(
    nextCampaignDispatchAt({
      now,
      lastActivityAt,
      ratePerMinute: 1
    }).toISOString(),
    "2026-08-31T12:10:30.000Z"
  );

  assert.equal(
    nextCampaignDispatchAt({
      now,
      lastActivityAt: null,
      ratePerMinute: 1
    }).toISOString(),
    now.toISOString()
  );
});
`;
}

fs.writeFileSync(path, content);
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/jobs/campaign.queue.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

const oldJobId = '      jobId: `campaign-recipient-${input.recipientId}`,';
const newJobId =
  '      jobId: `campaign-recipient-${input.recipientId}-${input.plannedFor.getTime()}`,';

if (content.includes(oldJobId)) {
  content = content.replace(oldJobId, newJobId);
} else if (!content.includes(newJobId)) {
  throw new Error("Campaign queue jobId anchor not found.");
}

fs.writeFileSync(path, content);
console.log("[P3.5.1] Campaign reschedule job identity installed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/jobs/campaign.worker.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("result.rescheduleAt")) {
  const anchor = `        return deliverCampaignRecipient(recipientId);`;
  if (!content.includes(anchor)) {
    throw new Error("Campaign worker delivery anchor not found.");
  }

  content = content.replace(
    anchor,
    `        const result = await deliverCampaignRecipient(recipientId);

        if (
          "rescheduleAt" in result &&
          result.rescheduleAt
        ) {
          await enqueueCampaignRecipient({
            recipientId,
            plannedFor: result.rescheduleAt
          });
        }

        return result;`
  );
}

if (content.includes("      concurrency: 2,")) {
  content = content.replace(
    "      concurrency: 2,",
    "      concurrency: 1,"
  );
} else if (!content.includes("      concurrency: 1,")) {
  throw new Error("Campaign worker concurrency anchor not found.");
}

fs.writeFileSync(path, content);
console.log("[P3.5.1] Campaign worker pacing hardened.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/modules/campaigns/campaign.service.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("  nextCampaignDispatchAt,")) {
  const anchor = `  MAX_CAMPAIGN_AUDIENCE,
  plannedCampaignSendAt`;
  if (!content.includes(anchor)) {
    throw new Error("Campaign policy import anchor not found in service.");
  }

  content = content.replace(
    anchor,
    `  MAX_CAMPAIGN_AUDIENCE,
  nextCampaignDispatchAt,
  plannedCampaignSendAt`
  );
}

if (content.includes("async function refreshCampaignCompletion(campaignId: string)")) {
  content = content.replace(
    "async function refreshCampaignCompletion(campaignId: string)",
    "export async function refreshCampaignCompletion(campaignId: string)"
  );
} else if (!content.includes(
  "export async function refreshCampaignCompletion(campaignId: string)"
)) {
  throw new Error("refreshCampaignCompletion declaration not found.");
}

if (!content.includes('reason: "rate_limited"')) {
  const anchor = `  const claimed = await prisma.campaignRecipient.updateMany({
    where: { id: recipient.id, status: "PENDING" },
    data: { status: "PROCESSING", claimedAt: now, error: null }
  });`;

  if (!content.includes(anchor)) {
    throw new Error("Campaign recipient claim anchor not found.");
  }

  const rateGuard = `  const lastActivity =
    await prisma.campaignRecipient.findFirst({
      where: {
        campaignId: recipient.campaignId,
        id: { not: recipient.id },
        OR: [
          {
            status: "SENT",
            sentAt: { not: null }
          },
          {
            status: "PROCESSING",
            claimedAt: { not: null }
          }
        ]
      },
      orderBy: { updatedAt: "desc" },
      select: {
        sentAt: true,
        claimedAt: true
      }
    });

  const lastActivityAt =
    lastActivity?.sentAt ??
    lastActivity?.claimedAt ??
    null;

  const nextAllowedAt = nextCampaignDispatchAt({
    now,
    lastActivityAt,
    ratePerMinute: recipient.campaign.ratePerMinute
  });

  if (nextAllowedAt.getTime() > now.getTime()) {
    if (
      nextAllowedAt.getTime() >
      recipient.campaign.windowEndAt.getTime()
    ) {
      await prisma.campaignRecipient.updateMany({
        where: {
          id: recipient.id,
          status: "PENDING"
        },
        data: {
          status: "FAILED",
          error:
            "A janela de envio terminou antes do próximo slot seguro da campanha."
        }
      });
      await refreshCampaignCompletion(recipient.campaignId);
      return {
        delivered: false,
        reason: "rate_window_expired" as const,
        rescheduleAt: null
      };
    }

    const rescheduled =
      await prisma.campaignRecipient.updateMany({
        where: {
          id: recipient.id,
          status: "PENDING"
        },
        data: {
          plannedFor: nextAllowedAt
        }
      });

    if (rescheduled.count !== 1) {
      return {
        delivered: false,
        reason: "already_claimed" as const,
        rescheduleAt: null
      };
    }

    return {
      delivered: false,
      reason: "rate_limited" as const,
      rescheduleAt: nextAllowedAt
    };
  }

`;

  content = content.replace(anchor, rateGuard + anchor);
}

fs.writeFileSync(path, content);
console.log("[P3.5.1] Campaign delivery cadence hardened.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path =
  "apps/api/src/modules/campaigns/campaign-consent.service.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes('from "./campaign.service.js";')) {
  const anchor =
    'import { isCampaignOptOutKeyword } from "./campaign.policy.js";';
  if (!content.includes(anchor)) {
    throw new Error("Campaign consent import anchor not found.");
  }

  content = content.replace(
    anchor,
    `${anchor}
import { refreshCampaignCompletion } from "./campaign.service.js";`
  );
}

if (!content.includes("async function suppressPendingCampaignRecipients(")) {
  const anchor = `export async function getCampaignConsent`;
  if (!content.includes(anchor)) {
    throw new Error("getCampaignConsent anchor not found.");
  }

  const helper = `async function suppressPendingCampaignRecipients(input: {
  companyId: string;
  contactId: string;
  reason: string;
}) {
  const affected =
    await prisma.campaignRecipient.findMany({
      where: {
        contactId: input.contactId,
        status: "PENDING",
        campaign: {
          companyId: input.companyId,
          status: "RUNNING"
        }
      },
      select: {
        campaignId: true
      }
    });

  if (affected.length === 0) return;

  await prisma.campaignRecipient.updateMany({
    where: {
      contactId: input.contactId,
      status: "PENDING",
      campaign: {
        companyId: input.companyId,
        status: "RUNNING"
      }
    },
    data: {
      status: "SUPPRESSED",
      exclusionReason: input.reason
    }
  });

  for (const campaignId of new Set(
    affected.map(item => item.campaignId)
  )) {
    await refreshCampaignCompletion(campaignId);
  }
}

`;

  content = content.replace(anchor, helper + anchor);
}

const manualOld = `    await prisma.campaignRecipient.updateMany({
      where: {
        contactId: contact.id,
        status: "PENDING",
        campaign: { companyId: input.companyId, status: "RUNNING" }
      },
      data: {
        status: "SUPPRESSED",
        exclusionReason: "OPTED_OUT_AFTER_START"
      }
    });`;

const manualNew = `    await suppressPendingCampaignRecipients({
      companyId: input.companyId,
      contactId: contact.id,
      reason: "OPTED_OUT_AFTER_START"
    });`;

if (content.includes(manualOld)) {
  content = content.replace(manualOld, manualNew);
} else if (!content.includes(manualNew)) {
  throw new Error("Manual opt-out suppression block not found.");
}

const inboundOld = `  await prisma.campaignRecipient.updateMany({
    where: {
      contactId: contact.id,
      status: "PENDING",
      campaign: { companyId: input.companyId, status: "RUNNING" }
    },
    data: { status: "SUPPRESSED", exclusionReason: "INBOUND_OPT_OUT" }
  });`;

const inboundNew = `  await suppressPendingCampaignRecipients({
    companyId: input.companyId,
    contactId: contact.id,
    reason: "INBOUND_OPT_OUT"
  });`;

if (content.includes(inboundOld)) {
  content = content.replace(inboundOld, inboundNew);
} else if (!content.includes(inboundNew)) {
  throw new Error("Inbound opt-out suppression block not found.");
}

fs.writeFileSync(path, content);
console.log("[P3.5.1] Opt-out completion reconciliation installed.");
NODE

node <<'NODE'
const fs = require("node:fs");
const path = "apps/api/src/integration/critical.integration.test.ts";
let content = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");

if (!content.includes("let integrationContactId =")) {
  const anchor = `let aroundMessageId = "";`;
  if (!content.includes(anchor)) {
    throw new Error("Integration variable anchor not found.");
  }

  content = content.replace(
    anchor,
    `${anchor}
let integrationContactId = "";
let integrationConnectionId = "";
let ownerMembershipId = "";`
  );
}

if (!content.includes("ownerMembershipId = ownerMembership.id;")) {
  const anchor = `  const connection =
    await prisma.whatsAppConnection.create({`;
  if (!content.includes(anchor)) {
    throw new Error("Integration connection anchor not found.");
  }

  const setup = `  const ownerMembership =
    await prisma.companyMembership.findFirstOrThrow({
      where: {
        companyId: company.id,
        userId: owner.id
      }
    });

  ownerMembershipId = ownerMembership.id;

`;

  content = content.replace(anchor, setup + anchor);
}

if (!content.includes("integrationContactId = contact.id;")) {
  const anchor = `  const ticket =
    await prisma.ticket.create({`;
  if (!content.includes(anchor)) {
    throw new Error("Integration ticket anchor not found.");
  }

  content = content.replace(
    anchor,
    `  integrationContactId = contact.id;
  integrationConnectionId = connection.id;

${anchor}`
  );
}

if (!content.includes('"P3 CRM chain: field, pipeline, task, segment and campaign consent"')) {
  const anchor = `    await t.test(
      "RBAC denies AGENT admin capability",`;

  if (!content.includes(anchor)) {
    throw new Error("Integration RBAC subtest anchor not found.");
  }

  const testBlock = `    await t.test(
      "P3 CRM chain: field, pipeline, task, segment and campaign consent",
      async () => {
        const headers = {
          authorization:
            \`Bearer \${owner.accessToken}\`
        };

        const fieldResponse =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/contact-crm/fields",
            headers,
            payload: {
              label:
                "Origem integração",
              type:
                "TEXT",
              required:
                false
            }
          });

        assert.equal(
          fieldResponse.statusCode,
          201,
          fieldResponse.body
        );

        const field =
          fieldResponse.json<{
            field: {
              id: string;
            };
          }>().field;

        const fieldValue =
          await app.inject({
            method: "PUT",
            url:
              \`/api/v1/contacts/\${integrationContactId}/crm-fields\`,
            headers,
            payload: {
              values: [
                {
                  fieldId:
                    field.id,
                  value:
                    "Integração"
                }
              ]
            }
          });

        assert.equal(
          fieldValue.statusCode,
          200,
          fieldValue.body
        );

        const pipelineResponse =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/pipelines",
            headers,
            payload: {
              name:
                "Pipeline integração",
              stages: [
                "Novo",
                "Qualificado"
              ]
            }
          });

        assert.equal(
          pipelineResponse.statusCode,
          201,
          pipelineResponse.body
        );

        const pipeline =
          pipelineResponse.json<{
            pipeline: {
              id: string;
              stages: Array<{
                id: string;
              }>;
            };
          }>().pipeline;

        assert.equal(
          pipeline.stages.length,
          2
        );

        const moved =
          await app.inject({
            method: "POST",
            url:
              \`/api/v1/contacts/\${integrationContactId}/pipeline-stage\`,
            headers,
            payload: {
              pipelineId:
                pipeline.id,
              stageId:
                pipeline.stages[1]!.id
            }
          });

        assert.equal(
          moved.statusCode,
          200,
          moved.body
        );

        const taskResponse =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/tasks",
            headers,
            payload: {
              contactId:
                integrationContactId,
              assigneeMembershipId:
                ownerMembershipId,
              title:
                "Follow-up integração",
              dueAt:
                new Date(
                  Date.now() +
                  10 * 60 * 1000
                ).toISOString()
            }
          });

        assert.equal(
          taskResponse.statusCode,
          201,
          taskResponse.body
        );

        const segmentResponse =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/segments",
            headers,
            payload: {
              name:
                "Com telefone integração",
              definition: {
                hasPhone:
                  "YES"
              }
            }
          });

        assert.equal(
          segmentResponse.statusCode,
          201,
          segmentResponse.body
        );

        const segment =
          segmentResponse.json<{
            segment: {
              id: string;
            };
          }>().segment;

        const consentIn =
          await app.inject({
            method: "PUT",
            url:
              \`/api/v1/contacts/\${integrationContactId}/campaign-consent\`,
            headers,
            payload: {
              status:
                "OPTED_IN",
              note:
                "Fixture de integração"
            }
          });

        assert.equal(
          consentIn.statusCode,
          200,
          consentIn.body
        );

        const startAt =
          new Date(
            Date.now() +
            2 * 60 * 1000
          );

        const campaignResponse =
          await app.inject({
            method: "POST",
            url:
              "/api/v1/campaigns",
            headers,
            payload: {
              segmentId:
                segment.id,
              whatsappConnectionId:
                integrationConnectionId,
              name:
                "Campanha integração",
              body:
                "Olá, {{primeiro_nome}}!",
              ratePerMinute:
                1,
              windowStartAt:
                startAt.toISOString(),
              windowEndAt:
                new Date(
                  startAt.getTime() +
                  30 * 60 * 1000
                ).toISOString()
            }
          });

        assert.equal(
          campaignResponse.statusCode,
          201,
          campaignResponse.body
        );

        const campaign =
          campaignResponse.json<{
            campaign: {
              id: string;
            };
          }>().campaign;

        const previewIn =
          await app.inject({
            method: "POST",
            url:
              \`/api/v1/campaigns/\${campaign.id}/preview\`,
            headers
          });

        assert.equal(
          previewIn.statusCode,
          200,
          previewIn.body
        );

        const eligible =
          previewIn.json<{
            eligibleRecipients: number;
            optedOutRecipients: number;
            unknownConsent: number;
            blocked: boolean;
          }>();

        assert.equal(
          eligible.eligibleRecipients,
          1
        );
        assert.equal(
          eligible.optedOutRecipients,
          0
        );
        assert.equal(
          eligible.unknownConsent,
          0
        );
        assert.equal(
          eligible.blocked,
          false
        );

        const consentOut =
          await app.inject({
            method: "PUT",
            url:
              \`/api/v1/contacts/\${integrationContactId}/campaign-consent\`,
            headers,
            payload: {
              status:
                "OPTED_OUT",
              note:
                "Fixture opt-out"
            }
          });

        assert.equal(
          consentOut.statusCode,
          200,
          consentOut.body
        );

        const previewOut =
          await app.inject({
            method: "POST",
            url:
              \`/api/v1/campaigns/\${campaign.id}/preview\`,
            headers
          });

        assert.equal(
          previewOut.statusCode,
          200,
          previewOut.body
        );

        const suppressed =
          previewOut.json<{
            eligibleRecipients: number;
            optedOutRecipients: number;
            blocked: boolean;
          }>();

        assert.equal(
          suppressed.eligibleRecipients,
          0
        );
        assert.equal(
          suppressed.optedOutRecipients,
          1
        );
        assert.equal(
          suppressed.blocked,
          true
        );
      }
    );

`;

  content = content.replace(anchor, testBlock + anchor);
}

fs.writeFileSync(path, content);
console.log("[P3.5.1] P3 integration chain installed.");
NODE

if ! grep -Fq -- "P3.5.1 CI stabilization" "$QUALITY_DOC"; then
cat >> "$QUALITY_DOC" <<'EOF'

## P3.5.1 CI stabilization

The Quality Gate now provides non-secret placeholder `DATABASE_URL` and
`SHADOW_DATABASE_URL` values so Prisma configuration can load during
`prisma generate`. Client generation does not connect to those placeholder
databases.

The workflow also runs `pnpm test:integration`. That integration suite starts
disposable MySQL 8.4 and Redis containers, overrides `DATABASE_URL`, applies
the real migration chain and destroys the disposable containers afterwards.

The P3 integration coverage now crosses:

- Contact 360 custom field persistence;
- pipeline creation and contact stage movement;
- CRM follow-up task creation;
- saved segment resolution;
- explicit campaign consent and campaign audience preview.

A green local unit suite alone is therefore not the release gate for P3.
EOF
fi

if ! grep -Fq -- "P3.5.1 runtime hardening" "$CAMPAIGN_DOC"; then
cat >> "$CAMPAIGN_DOC" <<'EOF'

## P3.5.1 runtime hardening

P3.5.1 adds two runtime invariants.

First, suppressing the final pending recipient by manual or inbound opt-out
immediately re-evaluates campaign completion. A campaign cannot remain RUNNING
only because its final pending recipient answered `SAIR`.

Second, overdue BullMQ jobs do not bypass the campaign's configured
`ratePerMinute`. Before a provider call, the campaign checks its most recent
SENT/PROCESSING recipient and reschedules the current recipient to the next
safe slot when needed.

The queue job id includes that planned slot, allowing an overdue job to finish
and a new delayed job to coexist without being mistaken for the same BullMQ
job.

The campaign worker uses concurrency 1 in the initial rollout. The database
remains the source of truth and the global BullMQ limiter remains an additional
10/minute ceiling.
EOF
fi

cat > scripts/p3-05-01-stabilization-smoke.mjs <<'EOF'
import fs from "node:fs";

const ci = fs.readFileSync(
  ".github/workflows/quality-gate.yml",
  "utf8"
);
const policy = fs.readFileSync(
  "apps/api/src/modules/campaigns/campaign.policy.ts",
  "utf8"
);
const queue = fs.readFileSync(
  "apps/api/src/jobs/campaign.queue.ts",
  "utf8"
);
const worker = fs.readFileSync(
  "apps/api/src/jobs/campaign.worker.ts",
  "utf8"
);
const service = fs.readFileSync(
  "apps/api/src/modules/campaigns/campaign.service.ts",
  "utf8"
);
const consent = fs.readFileSync(
  "apps/api/src/modules/campaigns/campaign-consent.service.ts",
  "utf8"
);
const integration = fs.readFileSync(
  "apps/api/src/integration/critical.integration.test.ts",
  "utf8"
);

for (const marker of [
  "DATABASE_URL: mysql://wapp_ci:",
  "SHADOW_DATABASE_URL: mysql://wapp_ci:"
]) {
  if (!ci.includes(marker)) {
    throw new Error(`CI marker missing: ${marker}`);
  }
}

for (const marker of [
  "nextCampaignDispatchAt",
  "rate_limited",
  "export async function refreshCampaignCompletion"
]) {
  if (!(policy + service).includes(marker)) {
    throw new Error(`Campaign pacing marker missing: ${marker}`);
  }
}

if (!queue.includes("input.plannedFor.getTime()")) {
  throw new Error("Reschedulable campaign job id missing.");
}
if (!worker.includes("concurrency: 1")) {
  throw new Error("Campaign worker single concurrency marker missing.");
}
if (!worker.includes('"rescheduleAt" in result')) {
  throw new Error("Campaign worker reschedule marker missing.");
}
if (!consent.includes("suppressPendingCampaignRecipients")) {
  throw new Error("Opt-out completion helper missing.");
}
if (!integration.includes(
  "P3 CRM chain: field, pipeline, task, segment and campaign consent"
)) {
  throw new Error("P3 integration chain missing.");
}

console.log("[P3.5.1] stabilization smoke PASS");
EOF

echo "[P3.5.1] Prisma generate..."
pnpm --filter @wapp/api db:generate

echo "[P3.5.1] Stabilization smoke..."
node scripts/p3-05-01-stabilization-smoke.mjs

echo "[P3.5.1] Security scan..."
pnpm security:scan

echo "[P3.5.1] Unit tests..."
pnpm test

echo "[P3.5.1] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.5.1] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo "[P3.5.1] Isolated integration tests..."
pnpm test:integration

echo "[P3.5.1] Production build..."
pnpm build

echo
echo "[P3.5.1] STABILIZATION GATE PASS."
echo
echo "No Prisma migration is required for P3.5.1."
echo "After commit + push, confirm GitHub Quality Gate is green."
