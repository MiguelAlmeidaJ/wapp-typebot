#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.9] Building centralized RBAC..."

for required in \
  "apps/api/src/modules/auth/auth.guard.ts" \
  "apps/api/src/modules/admin/admin.routes.ts" \
  "apps/api/src/modules/queues/queue.routes.ts" \
  "apps/api/src/modules/whatsapp/whatsapp.routes.ts" \
  "apps/api/src/modules/team/team.routes.ts" \
  "apps/web/app/dashboard/page.tsx" \
  "apps/web/lib/auth-types.ts" \
  "apps/web/components/auth-provider.tsx"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/security \
  apps/web/components \
  apps/web/lib \
  apps/web/app/dashboard/team \
  apps/web/app/dashboard/queues \
  apps/web/app/dashboard/connections \
  docs

# ---------------------------------------------------------------------------
# API permission model
# ---------------------------------------------------------------------------

cat > apps/api/src/security/permissions.ts <<'EOF'
import type { WappRole } from "../lib/tokens.js";

export type WappPermission =
  | "admin.test"
  | "team.read"
  | "team.manage"
  | "queues.read"
  | "queues.manage"
  | "whatsapp.read"
  | "whatsapp.manage"
  | "whatsapp.test";

const permissionsByRole: Record<
  WappRole,
  readonly WappPermission[]
> = {
  OWNER: [
    "admin.test",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ],
  ADMIN: [
    "admin.test",
    "team.read",
    "team.manage",
    "queues.read",
    "queues.manage",
    "whatsapp.read",
    "whatsapp.manage",
    "whatsapp.test"
  ],
  SUPERVISOR: [
    "team.read",
    "queues.read",
    "whatsapp.read",
    "whatsapp.test"
  ],
  AGENT: [
    "team.read",
    "queues.read",
    "whatsapp.read"
  ]
};

export function roleHasPermission(
  role: WappRole,
  permission: WappPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
EOF

cat > apps/api/src/modules/auth/auth.guard.ts <<'EOF'
import type { FastifyRequest } from "fastify";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import {
  type AccessContext,
  type WappRole,
  verifyAccessToken
} from "../../lib/tokens.js";
import {
  roleHasPermission,
  type WappPermission
} from "../../security/permissions.js";

export interface AuthContext extends AccessContext {
  user: {
    id: string;
    name: string;
    email: string;
  };
  company: {
    id: string;
    name: string;
    slug: string;
  };
}

function getBearerToken(request: FastifyRequest): string {
  const authorization = request.headers.authorization;

  if (!authorization?.startsWith("Bearer ")) {
    throw new AppError(
      "Token de acesso não informado.",
      401,
      "UNAUTHORIZED"
    );
  }

  return authorization.slice("Bearer ".length).trim();
}

export async function requireAuth(
  request: FastifyRequest
): Promise<AuthContext> {
  let tokenContext: AccessContext;

  try {
    tokenContext = await verifyAccessToken(
      getBearerToken(request)
    );
  } catch {
    throw new AppError(
      "Token de acesso inválido ou expirado.",
      401,
      "UNAUTHORIZED"
    );
  }

  const session = await prisma.session.findFirst({
    where: {
      id: tokenContext.sessionId,
      userId: tokenContext.userId,
      companyId: tokenContext.companyId,
      membershipId: tokenContext.membershipId,
      revokedAt: null,
      expiresAt: {
        gt: new Date()
      }
    },
    include: {
      user: true,
      company: true,
      membership: true
    }
  });

  if (
    !session ||
    !session.user.isActive ||
    session.company.status !== "ACTIVE" ||
    !session.membership.isActive
  ) {
    throw new AppError(
      "Sessão inválida ou revogada.",
      401,
      "SESSION_INVALID"
    );
  }

  if (session.membership.role !== tokenContext.role) {
    throw new AppError(
      "As permissões da sessão foram alteradas. Entre novamente.",
      401,
      "SESSION_ROLE_CHANGED"
    );
  }

  return {
    ...tokenContext,
    role: session.membership.role,
    user: {
      id: session.user.id,
      name: session.user.name,
      email: session.user.email
    },
    company: {
      id: session.company.id,
      name: session.company.name,
      slug: session.company.slug
    }
  };
}

export async function requireRoles(
  request: FastifyRequest,
  allowedRoles: readonly WappRole[]
): Promise<AuthContext> {
  const auth = await requireAuth(request);

  if (!allowedRoles.includes(auth.role)) {
    throw new AppError(
      "Você não possui permissão para executar esta ação.",
      403,
      "FORBIDDEN"
    );
  }

  return auth;
}

export async function requirePermission(
  request: FastifyRequest,
  permission: WappPermission
): Promise<AuthContext> {
  const auth = await requireAuth(request);

  if (!roleHasPermission(auth.role, permission)) {
    throw new AppError(
      "Você não possui permissão para executar esta ação.",
      403,
      "FORBIDDEN"
    );
  }

  return auth;
}
EOF

# ---------------------------------------------------------------------------
# API routes use capabilities instead of scattered role arrays
# ---------------------------------------------------------------------------

cat > apps/api/src/modules/admin/admin.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";

import { requirePermission } from "../auth/auth.guard.js";

export async function adminRoutes(app: FastifyInstance) {
  app.get("/api/v1/admin/ping", async request => {
    const auth = await requirePermission(
      request,
      "admin.test"
    );

    return {
      status: "ok",
      companyId: auth.companyId,
      role: auth.role,
      message: "RBAC funcionando."
    };
  });
}
EOF

cat > apps/api/src/modules/queues/queue.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  createQueue,
  listQueues,
  replaceQueueMembers
} from "./queue.service.js";

const queueIdSchema = z.object({
  id: z.string().uuid()
});

const createQueueSchema = z.object({
  name: z.string().trim().min(2).max(120)
});

const queueMembersSchema = z.object({
  membershipIds: z.array(z.string().uuid()).max(500)
});

export async function queueRoutes(app: FastifyInstance) {
  app.get("/api/v1/queues", async request => {
    const auth = await requirePermission(
      request,
      "queues.read"
    );

    return {
      queues: await listQueues(auth.companyId)
    };
  });

  app.post("/api/v1/queues", async (request, reply) => {
    const auth = await requirePermission(
      request,
      "queues.manage"
    );

    const input = createQueueSchema.parse(request.body);

    return reply.status(201).send({
      queue: await createQueue({
        companyId: auth.companyId,
        name: input.name
      })
    });
  });

  app.put(
    "/api/v1/queues/:id/members",
    async request => {
      const auth = await requirePermission(
        request,
        "queues.manage"
      );

      const params = queueIdSchema.parse(request.params);
      const input = queueMembersSchema.parse(
        request.body
      );

      return {
        queues: await replaceQueueMembers({
          companyId: auth.companyId,
          queueId: params.id,
          membershipIds: input.membershipIds
        })
      };
    }
  );
}
EOF

cat > apps/api/src/modules/whatsapp/whatsapp.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  connectConnection,
  createConnection,
  listConnections,
  sendTestMessage,
  syncConnection,
  updateConnectionSettings
} from "./whatsapp.service.js";

const connectionIdSchema = z.object({
  id: z.string().uuid()
});

const createConnectionSchema = z.object({
  name: z.string().trim().min(2).max(120)
});

const connectionSettingsSchema = z.object({
  acceptGroups: z.boolean().optional(),
  defaultQueueId: z.string().uuid().nullable().optional()
});

const testMessageSchema = z.object({
  number: z
    .string()
    .trim()
    .regex(
      /^\d{10,15}$/,
      "Use somente números com DDI e DDD."
    ),
  text: z.string().trim().min(1).max(4096)
});

export async function whatsappRoutes(
  app: FastifyInstance
) {
  app.get(
    "/api/v1/whatsapp/connections",
    async request => {
      const auth = await requirePermission(
        request,
        "whatsapp.read"
      );

      return {
        connections: await listConnections(
          auth.companyId
        )
      };
    }
  );

  app.post(
    "/api/v1/whatsapp/connections",
    async (request, reply) => {
      const auth = await requirePermission(
        request,
        "whatsapp.manage"
      );

      const input = createConnectionSchema.parse(
        request.body
      );

      const result = await createConnection({
        companyId: auth.companyId,
        companySlug: auth.company.slug,
        name: input.name
      });

      return reply.status(201).send(result);
    }
  );

  app.patch(
    "/api/v1/whatsapp/connections/:id/settings",
    async request => {
      const auth = await requirePermission(
        request,
        "whatsapp.manage"
      );

      const params = connectionIdSchema.parse(
        request.params
      );

      const input = connectionSettingsSchema.parse(
        request.body
      );

      return {
        connection: await updateConnectionSettings({
          companyId: auth.companyId,
          connectionId: params.id,
          ...input
        })
      };
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/connect",
    async request => {
      const auth = await requirePermission(
        request,
        "whatsapp.manage"
      );

      const params = connectionIdSchema.parse(
        request.params
      );

      return connectConnection(
        auth.companyId,
        params.id
      );
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/sync",
    async request => {
      const auth = await requirePermission(
        request,
        "whatsapp.read"
      );

      const params = connectionIdSchema.parse(
        request.params
      );

      return {
        connection: await syncConnection(
          auth.companyId,
          params.id
        )
      };
    }
  );

  app.post(
    "/api/v1/whatsapp/connections/:id/test-message",
    async request => {
      const auth = await requirePermission(
        request,
        "whatsapp.test"
      );

      const params = connectionIdSchema.parse(
        request.params
      );

      const input = testMessageSchema.parse(
        request.body
      );

      return {
        result: await sendTestMessage({
          companyId: auth.companyId,
          connectionId: params.id,
          number: input.number,
          text: input.text
        })
      };
    }
  );
}
EOF

# Team routes preserve P0.8 behavior but centralize authorization.
cat > apps/api/src/modules/team/team.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requirePermission } from "../auth/auth.guard.js";
import {
  createCompanyMembership,
  listCompanyMemberships,
  updateCompanyMembership
} from "./team.service.js";

const managedRoleSchema = z.enum([
  "ADMIN",
  "SUPERVISOR",
  "AGENT"
]);

const listSchema = z.object({
  includeInactive: z
    .enum(["true", "false"])
    .optional()
    .transform(value => value === "true")
});

const paramsSchema = z.object({
  id: z.string().uuid()
});

const createSchema = z.object({
  name: z.string().trim().min(2).max(160),
  email: z
    .string()
    .email()
    .transform(value => value.trim().toLowerCase()),
  temporaryPassword: z
    .string()
    .min(12)
    .max(128)
    .optional(),
  role: managedRoleSchema.default("AGENT")
});

const updateSchema = z
  .object({
    role: managedRoleSchema.optional(),
    isActive: z.boolean().optional()
  })
  .refine(
    value =>
      value.role !== undefined ||
      value.isActive !== undefined,
    {
      message: "Informe ao menos uma alteração."
    }
  );

export async function teamRoutes(app: FastifyInstance) {
  app.get(
    "/api/v1/team/memberships",
    async request => {
      const auth = await requirePermission(
        request,
        "team.read"
      );

      const query = listSchema.parse(
        request.query
      );

      return {
        memberships: await listCompanyMemberships(
          auth.companyId,
          query.includeInactive
        )
      };
    }
  );

  app.post(
    "/api/v1/team/memberships",
    async (request, reply) => {
      const auth = await requirePermission(
        request,
        "team.manage"
      );

      const input = createSchema.parse(
        request.body
      );

      const result = await createCompanyMembership({
        actor: {
          companyId: auth.companyId,
          membershipId: auth.membershipId,
          role: auth.role
        },
        ...input
      });

      return reply.status(201).send(result);
    }
  );

  app.patch(
    "/api/v1/team/memberships/:id",
    async request => {
      const auth = await requirePermission(
        request,
        "team.manage"
      );

      const params = paramsSchema.parse(
        request.params
      );

      const input = updateSchema.parse(
        request.body
      );

      return {
        membership: await updateCompanyMembership({
          actor: {
            companyId: auth.companyId,
            membershipId: auth.membershipId,
            role: auth.role
          },
          membershipId: params.id,
          ...input
        })
      };
    }
  );
}
EOF

# ---------------------------------------------------------------------------
# Frontend permission model
# ---------------------------------------------------------------------------

cat > apps/web/lib/permissions.ts <<'EOF'
import type { Role } from "./auth-types";

export type UiPermission =
  | "dashboard.view"
  | "conversations.view"
  | "queues.manage"
  | "connections.manage"
  | "team.manage"
  | "admin.test";

const permissionsByRole: Record<
  Role,
  readonly UiPermission[]
> = {
  OWNER: [
    "dashboard.view",
    "conversations.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test"
  ],
  ADMIN: [
    "dashboard.view",
    "conversations.view",
    "queues.manage",
    "connections.manage",
    "team.manage",
    "admin.test"
  ],
  SUPERVISOR: [
    "dashboard.view",
    "conversations.view"
  ],
  AGENT: [
    "dashboard.view",
    "conversations.view"
  ]
};

export function roleCan(
  role: Role,
  permission: UiPermission
): boolean {
  return permissionsByRole[role].includes(permission);
}
EOF

cat > apps/web/components/access-gate.tsx <<'EOF'
"use client";

import {
  type ReactNode,
  useEffect
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "./auth-provider";
import {
  roleCan,
  type UiPermission
} from "@/lib/permissions";

export function AccessGate({
  permission,
  children
}: {
  permission: UiPermission;
  children: ReactNode;
}) {
  const router = useRouter();
  const { session, loading } = useAuth();

  const allowed =
    session &&
    roleCan(session.role, permission);

  useEffect(() => {
    if (loading) {
      return;
    }

    if (!session) {
      router.replace("/login");
      return;
    }

    if (!roleCan(session.role, permission)) {
      router.replace("/dashboard");
    }
  }, [
    loading,
    permission,
    router,
    session
  ]);

  if (loading || !allowed) {
    return (
      <main className="dashboard-loading">
        Validando acesso…
      </main>
    );
  }

  return children;
}
EOF

cat > apps/web/app/dashboard/team/layout.tsx <<'EOF'
"use client";

import type { ReactNode } from "react";

import { AccessGate } from "@/components/access-gate";

export default function TeamLayout({
  children
}: {
  children: ReactNode;
}) {
  return (
    <AccessGate permission="team.manage">
      {children}
    </AccessGate>
  );
}
EOF

cat > apps/web/app/dashboard/queues/layout.tsx <<'EOF'
"use client";

import type { ReactNode } from "react";

import { AccessGate } from "@/components/access-gate";

export default function QueuesLayout({
  children
}: {
  children: ReactNode;
}) {
  return (
    <AccessGate permission="queues.manage">
      {children}
    </AccessGate>
  );
}
EOF

cat > apps/web/app/dashboard/connections/layout.tsx <<'EOF'
"use client";

import type { ReactNode } from "react";

import { AccessGate } from "@/components/access-gate";

export default function ConnectionsLayout({
  children
}: {
  children: ReactNode;
}) {
  return (
    <AccessGate permission="connections.manage">
      {children}
    </AccessGate>
  );
}
EOF

# ---------------------------------------------------------------------------
# Dashboard navigation + admin-only card
# ---------------------------------------------------------------------------

cat > apps/web/app/dashboard/page.tsx <<'EOF'
"use client";

import {
  useEffect,
  useMemo,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { WappMark } from "@/components/wapp-mark";
import { ApiError } from "@/lib/api";
import {
  roleCan,
  type UiPermission
} from "@/lib/permissions";

interface AdminPingResponse {
  status: "ok";
  companyId: string;
  role: string;
  message: string;
}

const roleLabels = {
  OWNER: "Proprietário",
  ADMIN: "Administrador",
  SUPERVISOR: "Supervisor",
  AGENT: "Atendente"
} as const;

const navigation: Array<{
  label: string;
  href: string;
  permission: UiPermission;
}> = [
  {
    label: "Visão geral",
    href: "/dashboard",
    permission: "dashboard.view"
  },
  {
    label: "Conversas",
    href: "/dashboard/conversations",
    permission: "conversations.view"
  },
  {
    label: "Filas",
    href: "/dashboard/queues",
    permission: "queues.manage"
  },
  {
    label: "Conexões",
    href: "/dashboard/connections",
    permission: "connections.manage"
  },
  {
    label: "Equipe",
    href: "/dashboard/team",
    permission: "team.manage"
  }
];

export default function DashboardPage() {
  const router = useRouter();
  const {
    session,
    loading,
    logout,
    request,
    subscribe
  } = useAuth();

  const [rbacState, setRbacState] = useState<
    "idle" |
    "checking" |
    "success" |
    "forbidden" |
    "error"
  >("idle");

  const visibleNavigation = useMemo(
    () =>
      session
        ? navigation.filter(item =>
            roleCan(
              session.role,
              item.permission
            )
          )
        : [],
    [session]
  );

  const canTestAdmin =
    session &&
    roleCan(session.role, "admin.test");

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
    }
  }, [loading, router, session]);

  useEffect(() => {
    if (!session) {
      return;
    }

    return subscribe(
      "/api/v1/realtime/events",
      () => {}
    );
  }, [session, subscribe]);

  async function handleLogout() {
    await logout();
    router.replace("/login");
  }

  async function testRbac() {
    setRbacState("checking");

    try {
      await request<AdminPingResponse>(
        "/api/v1/admin/ping"
      );

      setRbacState("success");
    } catch (error) {
      if (
        error instanceof ApiError &&
        error.status === 403
      ) {
        setRbacState("forbidden");
        return;
      }

      setRbacState("error");
    }
  }

  if (loading || !session) {
    return (
      <main className="dashboard-loading">
        Carregando workspace…
      </main>
    );
  }

  return (
    <main className="workspace">
      <aside className="sidebar">
        <div className="sidebar__top">
          <WappMark compact />

          <nav
            className="sidebar__nav"
            aria-label="Navegação principal"
          >
            {visibleNavigation.map(
              (item, index) => (
                <button
                  className={
                    index === 0
                      ? "nav-item nav-item--active"
                      : "nav-item"
                  }
                  key={item.href}
                  onClick={() =>
                    router.push(item.href)
                  }
                  type="button"
                >
                  <span
                    className="nav-item__dot"
                    aria-hidden="true"
                  />
                  <span>{item.label}</span>
                </button>
              )
            )}
          </nav>
        </div>

        <div className="sidebar__user">
          <div className="avatar">
            {session.user.name
              .slice(0, 1)
              .toUpperCase()}
          </div>
          <div className="sidebar__user-copy">
            <strong>
              {session.user.name}
            </strong>
            <span>
              {roleLabels[session.role]}
            </span>
          </div>
        </div>
      </aside>

      <section className="workspace__content">
        <header className="topbar">
          <div>
            <span className="topbar__company">
              {session.company.name}
            </span>
            <span className="topbar__separator">
              /
            </span>
            <span className="topbar__section">
              Visão geral
            </span>
          </div>

          <button
            className="ghost-button"
            onClick={handleLogout}
            type="button"
          >
            Sair
          </button>
        </header>

        <div className="dashboard">
          <div className="dashboard__intro">
            <div>
              <span className="eyebrow">
                Workspace ativo
              </span>
              <h1>
                Olá,{" "}
                {session.user.name.split(" ")[0]}.
              </h1>
              <p>
                Seu acesso está carregado conforme
                o papel definido nesta empresa.
              </p>
            </div>

            <span className="role-badge">
              {roleLabels[session.role]}
            </span>
          </div>

          <div className="metric-grid">
            <article className="metric-card">
              <span className="metric-card__label">
                Conversas
              </span>
              <strong>—</strong>
              <small>
                Acompanhe em Conversas
              </small>
            </article>

            <article className="metric-card">
              <span className="metric-card__label">
                Filas
              </span>
              <strong>—</strong>
              <small>
                Distribuição operacional
              </small>
            </article>

            <article className="metric-card">
              <span className="metric-card__label">
                Conexões
              </span>
              <strong>—</strong>
              <small>
                WhatsApp conectado ao Wapp
              </small>
            </article>
          </div>

          <div
            className={
              canTestAdmin
                ? "dashboard-grid"
                : "dashboard-grid dashboard-grid--single"
            }
          >
            <article className="panel">
              <div className="panel__heading">
                <div>
                  <span className="eyebrow">
                    Sessão
                  </span>
                  <h2>
                    Fundação autenticada
                  </h2>
                </div>
                <span className="status-pill status-pill--online">
                  online
                </span>
              </div>

              <dl className="details-list">
                <div>
                  <dt>Usuário</dt>
                  <dd>
                    {session.user.email}
                  </dd>
                </div>
                <div>
                  <dt>Empresa</dt>
                  <dd>
                    {session.company.slug}
                  </dd>
                </div>
                <div>
                  <dt>Perfil</dt>
                  <dd>{session.role}</dd>
                </div>
              </dl>
            </article>

            {canTestAdmin && (
              <article className="panel">
                <div className="panel__heading">
                  <div>
                    <span className="eyebrow">
                      Permissões
                    </span>
                    <h2>Teste de RBAC</h2>
                  </div>
                </div>

                <p className="panel__description">
                  Esta rota administrativa
                  valida sessão, empresa e
                  capability diretamente na API.
                </p>

                <button
                  className="secondary-button"
                  disabled={
                    rbacState === "checking"
                  }
                  onClick={testRbac}
                  type="button"
                >
                  {rbacState === "checking"
                    ? "Validando…"
                    : "Testar permissão administrativa"}
                </button>

                {rbacState === "success" && (
                  <p className="inline-result inline-result--success">
                    RBAC validado.
                  </p>
                )}

                {rbacState === "forbidden" && (
                  <p className="inline-result">
                    Acesso administrativo negado.
                  </p>
                )}

                {rbacState === "error" && (
                  <p className="inline-result">
                    Não foi possível validar
                    agora.
                  </p>
                )}
              </article>
            )}
          </div>
        </div>
      </section>
    </main>
  );
}
EOF

cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P0.9 / RBAC -------------------------------------------------- */

.dashboard-grid--single {
  grid-template-columns: minmax(0, 720px);
}
EOF

cat > docs/PERMISSIONS.md <<'EOF'
# Wapp permission model

P0.9 moves authorization away from scattered `role === ...` checks.

## API capabilities

| Capability | OWNER | ADMIN | SUPERVISOR | AGENT |
| --- | --- | --- | --- | --- |
| admin.test | yes | yes | no | no |
| team.read | yes | yes | yes | yes |
| team.manage | yes | yes | no | no |
| queues.read | yes | yes | yes | yes |
| queues.manage | yes | yes | no | no |
| whatsapp.read | yes | yes | yes | yes |
| whatsapp.manage | yes | yes | no | no |
| whatsapp.test | yes | yes | yes | no |

Read permissions remain available to operational roles because ticket routing
and transfer flows need queue, team and connection metadata.

Management screens are separately protected in the Next application.

## UI capabilities

OWNER and ADMIN:
- Dashboard
- Conversations
- Queues management
- Connections management
- Team management
- Administrative RBAC test

SUPERVISOR and AGENT:
- Dashboard
- Conversations

The API is always the security boundary. Hiding a menu item is only UX.

## Ticket authorization

Ticket ownership/assignment rules remain inside the ticket domain service.
P0.9 intentionally does not replace those contextual checks with static role
permissions.
EOF

echo "[P0.9] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.9] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.9] RBAC foundation created."
echo "No Prisma migration is required."
echo
echo "Test with OWNER/ADMIN and AGENT accounts."
