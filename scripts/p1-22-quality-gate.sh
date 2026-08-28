#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.22] Installing automated quality gate..."

for required in \
  "package.json" \
  "apps/api/package.json" \
  "apps/api/src/security/permissions.ts" \
  "apps/api/src/modules/tickets/ticket-message-history.service.ts"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/modules/tickets \
  apps/api/src/security \
  scripts \
  .github/workflows \
  docs

# ---------------------------------------------------------------------------
# Extract pure cursor helpers from P1.21 so they are regression-testable.
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/tickets/message-history.cursor.ts <<'EOF'
import type {
  Prisma
} from "../../generated/prisma/client.js";

export interface MessageCursor {
  id: string;
  timestamp: Date;
}

export function beforeCursorWhere(
  cursor: MessageCursor
): Prisma.MessageWhereInput {
  return {
    OR: [
      {
        timestamp: {
          lt:
            cursor.timestamp
        }
      },
      {
        timestamp:
          cursor.timestamp,
        id: {
          lt:
            cursor.id
        }
      }
    ]
  };
}

export function afterCursorWhere(
  cursor: MessageCursor
): Prisma.MessageWhereInput {
  return {
    OR: [
      {
        timestamp: {
          gt:
            cursor.timestamp
        }
      },
      {
        timestamp:
          cursor.timestamp,
        id: {
          gt:
            cursor.id
        }
      }
    ]
  };
}

export const chronologicalOrder:
  Prisma.MessageOrderByWithRelationInput[] =
  [
    {
      timestamp:
        "asc"
    },
    {
      id:
        "asc"
    }
  ];

export const reverseChronologicalOrder:
  Prisma.MessageOrderByWithRelationInput[] =
  [
    {
      timestamp:
        "desc"
    },
    {
      id:
        "desc"
    }
  ];
EOF

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tickets/ticket-message-history.service.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  );

const importBlock = `import {
  afterCursorWhere,
  beforeCursorWhere,
  chronologicalOrder,
  reverseChronologicalOrder,
  type MessageCursor
} from "./message-history.cursor.js";`;

if (
  !content.includes(
    "from \"./message-history.cursor.js\""
  )
) {
  const anchor =
    'import { getTicket } from "./ticket.service.js";';

  if (!content.includes(anchor)) {
    throw new Error(
      "ticket history service import anchor not found."
    );
  }

  content =
    content.replace(
      anchor,
      `${anchor}
${importBlock}`
    );
}

/*
 * Remove the local cursor interface/helper/order definitions now provided by
 * the pure module. Match known P1.21 blocks independently to keep the edit
 * narrow and fail loudly if local source diverged.
 */
const blocks = [
`interface MessageCursor {
  id: string;
  timestamp: Date;
}

`,
`function beforeCursorWhere(
  cursor: MessageCursor
): Prisma.MessageWhereInput {
  return {
    OR: [
      {
        timestamp: {
          lt:
            cursor.timestamp
        }
      },
      {
        timestamp:
          cursor.timestamp,
        id: {
          lt:
            cursor.id
        }
      }
    ]
  };
}

function afterCursorWhere(
  cursor: MessageCursor
): Prisma.MessageWhereInput {
  return {
    OR: [
      {
        timestamp: {
          gt:
            cursor.timestamp
        }
      },
      {
        timestamp:
          cursor.timestamp,
        id: {
          gt:
            cursor.id
        }
      }
    ]
  };
}

`,
`const ascOrder:
  Prisma.MessageOrderByWithRelationInput[] =
  [
    {
      timestamp:
        "asc"
    },
    {
      id:
        "asc"
    }
  ];

const descOrder:
  Prisma.MessageOrderByWithRelationInput[] =
  [
    {
      timestamp:
        "desc"
    },
    {
      id:
        "desc"
    }
  ];

`
];

for (const block of blocks) {
  if (content.includes(block)) {
    content =
      content.replace(
        block,
        ""
      );
  }
}

content =
  content.replaceAll(
    "orderBy:\n          descOrder",
    "orderBy:\n          reverseChronologicalOrder"
  );

content =
  content.replaceAll(
    "orderBy:\n              ascOrder",
    "orderBy:\n              chronologicalOrder"
  );

content =
  content.replaceAll(
    "orderBy:\n        descOrder",
    "orderBy:\n        reverseChronologicalOrder"
  );

content =
  content.replaceAll(
    "orderBy:\n          ascOrder",
    "orderBy:\n          chronologicalOrder"
  );

if (
  /\b(?:ascOrder|descOrder)\b/.test(
    content
  )
) {
  throw new Error(
    "Old message order helper reference remains."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  "P1.21 cursor logic extracted into pure testable helpers."
);
NODE

# ---------------------------------------------------------------------------
# API regression tests
# ---------------------------------------------------------------------------

cat > apps/api/src/security/permissions.test.ts <<'EOF'
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
EOF

cat > apps/api/src/modules/tickets/message-history.cursor.test.ts <<'EOF'
import assert from "node:assert/strict";
import {
  describe,
  it
} from "node:test";

import {
  afterCursorWhere,
  beforeCursorWhere,
  chronologicalOrder,
  reverseChronologicalOrder
} from "./message-history.cursor.js";

describe(
  "message history keyset cursor",
  () => {
    const timestamp =
      new Date(
        "2026-08-28T12:00:00.000Z"
      );

    const cursor = {
      id:
        "80000000-0000-4000-8000-000000000080",
      timestamp
    };

    it(
      "uses timestamp + id tie-breaker when paging older",
      () => {
        assert.deepEqual(
          beforeCursorWhere(
            cursor
          ),
          {
            OR: [
              {
                timestamp: {
                  lt:
                    timestamp
                }
              },
              {
                timestamp,
                id: {
                  lt:
                    cursor.id
                }
              }
            ]
          }
        );
      }
    );

    it(
      "uses timestamp + id tie-breaker when paging newer",
      () => {
        assert.deepEqual(
          afterCursorWhere(
            cursor
          ),
          {
            OR: [
              {
                timestamp: {
                  gt:
                    timestamp
                }
              },
              {
                timestamp,
                id: {
                  gt:
                    cursor.id
                }
              }
            ]
          }
        );
      }
    );

    it(
      "has deterministic chronological ordering",
      () => {
        assert.deepEqual(
          chronologicalOrder,
          [
            {
              timestamp:
                "asc"
            },
            {
              id:
                "asc"
            }
          ]
        );

        assert.deepEqual(
          reverseChronologicalOrder,
          [
            {
              timestamp:
                "desc"
            },
            {
              id:
                "desc"
            }
          ]
        );
      }
    );
  }
);
EOF

# ---------------------------------------------------------------------------
# API test command
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

pkg.scripts ??= {};

pkg.scripts.test =
  "tsx --test src/security/permissions.test.ts src/modules/tickets/message-history.cursor.test.ts";

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);

console.log(
  "API test command registered."
);
NODE

# ---------------------------------------------------------------------------
# Local runtime smoke check
# ---------------------------------------------------------------------------

cat > scripts/smoke-api.mjs <<'EOF'
const baseUrl =
  (
    process.env
      .WAPP_SMOKE_API_URL ??
    "http://localhost:4000"
  )
    .replace(
      /\/+$/,
      ""
    );

async function getJson(
  pathname
) {
  const url =
    `${baseUrl}${pathname}`;

  const startedAt =
    performance.now();

  let response;

  try {
    response =
      await fetch(
        url,
        {
          headers: {
            accept:
              "application/json"
          }
        }
      );
  } catch (error) {
    throw new Error(
      `${pathname}: API indisponível (${error instanceof Error ? error.message : "connection error"})`
    );
  }

  const latencyMs =
    Math.max(
      0,
      Math.round(
        performance.now() -
        startedAt
      )
    );

  const text =
    await response.text();

  let body;

  try {
    body =
      text
        ? JSON.parse(
            text
          )
        : null;
  } catch {
    body =
      text;
  }

  if (!response.ok) {
    throw new Error(
      `${pathname}: HTTP ${response.status} ${JSON.stringify(body)}`
    );
  }

  return {
    body,
    latencyMs
  };
}

try {
  console.log(
    `[smoke] API ${baseUrl}`
  );

  const live =
    await getJson(
      "/health/live"
    );

  if (
    live.body?.status !==
    "ok"
  ) {
    throw new Error(
      `/health/live respondeu estado inesperado: ${JSON.stringify(live.body)}`
    );
  }

  console.log(
    `[smoke] live: OK (${live.latencyMs} ms)`
  );

  const ready =
    await getJson(
      "/health/ready"
    );

  if (
    ready.body?.ready !==
    true
  ) {
    throw new Error(
      `/health/ready não está ready=true: ${JSON.stringify(ready.body)}`
    );
  }

  console.log(
    `[smoke] ready: OK (${ready.latencyMs} ms)`
  );

  const health =
    await getJson(
      "/health"
    );

  if (
    ![
      "ok",
      "degraded"
    ].includes(
      health.body?.status
    )
  ) {
    throw new Error(
      `/health respondeu estado inesperado: ${JSON.stringify(health.body)}`
    );
  }

  console.log(
    `[smoke] health: ${health.body.status} (${health.latencyMs} ms)`
  );

  console.log(
    "[smoke] PASS"
  );
} catch (error) {
  console.error(
    "[smoke] FAIL:",
    error instanceof Error
      ? error.message
      : error
  );

  process.exitCode = 1;
}
EOF

# ---------------------------------------------------------------------------
# Root quality commands
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const path =
  "package.json";

const pkg =
  JSON.parse(
    fs.readFileSync(
      path,
      "utf8"
    )
  );

pkg.scripts ??= {};

pkg.scripts.test =
  "pnpm --filter @wapp/api test";

pkg.scripts.verify =
  "pnpm db:generate && pnpm test && pnpm typecheck && pnpm build";

pkg.scripts.smoke =
  "node scripts/smoke-api.mjs";

fs.writeFileSync(
  path,
  `${JSON.stringify(
    pkg,
    null,
    2
  )}\n`
);

console.log(
  "Root test, verify and smoke commands registered."
);
NODE

# ---------------------------------------------------------------------------
# GitHub Actions quality gate
# ---------------------------------------------------------------------------

cat > .github/workflows/quality-gate.yml <<'EOF'
name: Quality Gate

on:
  pull_request:
  push:
    branches:
      - develop
      - main

permissions:
  contents: read

concurrency:
  group: quality-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  verify:
    name: Test, typecheck and build
    runs-on: ubuntu-latest
    timeout-minutes: 20

    env:
      NEXT_PUBLIC_API_URL: http://localhost:4000

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 11.16.0
          run_install: false

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: pnpm

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Generate Prisma client
        run: pnpm db:generate

      - name: Unit regression tests
        run: pnpm test

      - name: Typecheck
        run: pnpm typecheck

      - name: Build
        run: pnpm build
EOF

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------

cat > docs/QUALITY_GATE.md <<'EOF'
# P1.22 Automated quality gate

P1.22 introduces the first automated regression gate for Wapp.

## Local commands

Fast deterministic tests:

```bash
pnpm test
```

Full pre-commit/release verification:

```bash
pnpm verify
```

`verify` runs:

1. Prisma client generation;
2. API regression tests;
3. workspace typecheck;
4. production builds.

No database, Redis or Evolution instance is required by the unit tests.

## Runtime smoke

With the local stack running:

```bash
pnpm smoke
```

The smoke check validates:

- `/health/live`;
- `/health/ready`;
- `/health`.

`/health/ready` must return HTTP 200 with `ready=true`, therefore the smoke
check also exercises the configured MySQL and Redis readiness path.

Override the target API:

```bash
WAPP_SMOKE_API_URL=https://api.example.com pnpm smoke
```

The smoke command does not use credentials and does not mutate application
data.

## Regression coverage

### RBAC

The centralized backend permission matrix is tested for OWNER, ADMIN,
SUPERVISOR and AGENT.

The tests specifically protect the management boundaries around:

- team;
- queues;
- WhatsApp connections;
- quick replies;
- tags;
- SLA;
- admin test operations.

### Message history pagination

P1.21 keyset pagination is protected by tests for:

- older cursor;
- newer cursor;
- deterministic timestamp + UUID tie-break;
- ascending browser order;
- descending newest-page database order.

This prevents duplicate/omitted rows when two WhatsApp messages share the same
timestamp.

## GitHub Actions

`.github/workflows/quality-gate.yml` runs on:

- pull requests;
- pushes to `develop`;
- pushes to `main`.

The job performs the same test/typecheck/build sequence used locally.

The CI workflow intentionally does not require production secrets and does not
start MySQL, Redis or Evolution.

Integration/runtime behavior remains validated by `pnpm smoke` and the manual
feature acceptance checks.

## Rule going forward

A P1/P2 patch should not be treated as complete if it causes:

```bash
pnpm test
pnpm typecheck
```

to fail.

Before a release/deploy candidate, use:

```bash
pnpm verify
```

and then run `pnpm smoke` against the target environment.
EOF

# ---------------------------------------------------------------------------
# Validate this installation on the real checkout.
# ---------------------------------------------------------------------------

echo "[P1.22] Generating Prisma client..."
pnpm db:generate

echo "[P1.22] Running regression tests..."
pnpm test

echo "[P1.22] Typechecking workspace..."
pnpm typecheck

echo
echo "[P1.22] Quality gate installed."
echo
echo "Build remains part of:"
echo "  pnpm verify"
echo
echo "After pnpm dev is running, runtime check:"
echo "  pnpm smoke"
