#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P0.8] Building team management..."

for required in \
  "apps/api/src/modules/team/team.routes.ts" \
  "apps/api/src/modules/team/team.service.ts" \
  "apps/api/src/lib/password.ts" \
  "apps/web/app/dashboard/page.tsx" \
  "apps/web/app/globals.css"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p apps/web/app/dashboard/team docs

cat > apps/api/src/modules/team/team.service.ts <<'EOF'
import type { MembershipRole } from "../../generated/prisma/client.js";

import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { hashPassword } from "../../lib/password.js";

type ManagedRole = "ADMIN" | "SUPERVISOR" | "AGENT";

interface TeamActor {
  companyId: string;
  membershipId: string;
  role: MembershipRole;
}

function assertManager(role: MembershipRole) {
  if (role !== "OWNER" && role !== "ADMIN") {
    throw new AppError(
      "Você não possui permissão para gerenciar a equipe.",
      403,
      "TEAM_MANAGEMENT_FORBIDDEN"
    );
  }
}

function assertAssignableRole(
  actorRole: MembershipRole,
  role: ManagedRole
) {
  if (actorRole === "ADMIN" && role === "ADMIN") {
    throw new AppError(
      "Administradores não podem promover outros administradores.",
      403,
      "ADMIN_ROLE_PROTECTED"
    );
  }
}

export async function listCompanyMemberships(
  companyId: string,
  includeInactive = false
) {
  return prisma.companyMembership.findMany({
    where: {
      companyId,
      ...(includeInactive ? {} : { isActive: true })
    },
    include: {
      user: {
        select: {
          id: true,
          name: true,
          email: true,
          isActive: true
        }
      },
      queueMemberships: {
        select: {
          queueId: true
        }
      }
    },
    orderBy: {
      createdAt: "asc"
    }
  });
}

export async function createCompanyMembership(input: {
  actor: TeamActor;
  name: string;
  email: string;
  temporaryPassword?: string;
  role: ManagedRole;
}) {
  assertManager(input.actor.role);
  assertAssignableRole(input.actor.role, input.role);

  const email = input.email.trim().toLowerCase();

  const existingUser = await prisma.user.findUnique({
    where: { email },
    include: {
      memberships: {
        where: {
          companyId: input.actor.companyId
        }
      }
    }
  });

  if (existingUser) {
    if (!existingUser.isActive) {
      throw new AppError(
        "A identidade deste usuário está desativada.",
        409,
        "USER_INACTIVE"
      );
    }

    const currentMembership = existingUser.memberships[0];

    if (currentMembership?.isActive) {
      throw new AppError(
        "Este usuário já possui acesso à empresa.",
        409,
        "MEMBERSHIP_ALREADY_EXISTS"
      );
    }

    const membership = currentMembership
      ? await prisma.companyMembership.update({
          where: { id: currentMembership.id },
          data: {
            role: input.role,
            isActive: true
          },
          include: {
            user: {
              select: {
                id: true,
                name: true,
                email: true,
                isActive: true
              }
            },
            queueMemberships: {
              select: { queueId: true }
            }
          }
        })
      : await prisma.companyMembership.create({
          data: {
            companyId: input.actor.companyId,
            userId: existingUser.id,
            role: input.role
          },
          include: {
            user: {
              select: {
                id: true,
                name: true,
                email: true,
                isActive: true
              }
            },
            queueMemberships: {
              select: { queueId: true }
            }
          }
        });

    return {
      membership,
      linkedExistingUser: true
    };
  }

  if (!input.temporaryPassword) {
    throw new AppError(
      "Informe uma senha temporária para criar um novo usuário.",
      422,
      "TEMPORARY_PASSWORD_REQUIRED"
    );
  }

  const passwordHash = await hashPassword(
    input.temporaryPassword
  );

  const membership = await prisma.$transaction(async tx => {
    const user = await tx.user.create({
      data: {
        name: input.name.trim(),
        email,
        passwordHash
      }
    });

    return tx.companyMembership.create({
      data: {
        companyId: input.actor.companyId,
        userId: user.id,
        role: input.role
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
            isActive: true
          }
        },
        queueMemberships: {
          select: { queueId: true }
        }
      }
    });
  });

  return {
    membership,
    linkedExistingUser: false
  };
}

export async function updateCompanyMembership(input: {
  actor: TeamActor;
  membershipId: string;
  role?: ManagedRole;
  isActive?: boolean;
}) {
  assertManager(input.actor.role);

  const target = await prisma.companyMembership.findFirst({
    where: {
      id: input.membershipId,
      companyId: input.actor.companyId
    }
  });

  if (!target) {
    throw new AppError(
      "Membro da equipe não encontrado.",
      404,
      "MEMBERSHIP_NOT_FOUND"
    );
  }

  if (target.id === input.actor.membershipId) {
    throw new AppError(
      "Você não pode alterar o próprio acesso por esta tela.",
      409,
      "SELF_MEMBERSHIP_PROTECTED"
    );
  }

  if (target.role === "OWNER") {
    throw new AppError(
      "O acesso OWNER é protegido.",
      403,
      "OWNER_MEMBERSHIP_PROTECTED"
    );
  }

  if (
    input.actor.role === "ADMIN" &&
    target.role === "ADMIN"
  ) {
    throw new AppError(
      "Administradores não podem alterar outro administrador.",
      403,
      "ADMIN_MEMBERSHIP_PROTECTED"
    );
  }

  if (input.role) {
    assertAssignableRole(input.actor.role, input.role);
  }

  const nextRole = input.role ?? target.role;
  const nextActive =
    input.isActive ?? target.isActive;

  return prisma.$transaction(async tx => {
    const membership = await tx.companyMembership.update({
      where: { id: target.id },
      data: {
        role: nextRole,
        isActive: nextActive
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
            isActive: true
          }
        },
        queueMemberships: {
          select: { queueId: true }
        }
      }
    });

    if (
      nextRole !== target.role ||
      nextActive !== target.isActive
    ) {
      await tx.session.updateMany({
        where: {
          membershipId: target.id,
          revokedAt: null
        },
        data: {
          revokedAt: new Date()
        }
      });
    }

    if (!nextActive) {
      await tx.queueMember.deleteMany({
        where: {
          membershipId: target.id
        }
      });

      await tx.ticket.updateMany({
        where: {
          companyId: input.actor.companyId,
          assignedMembershipId: target.id,
          status: {
            in: ["OPEN", "PENDING"]
          }
        },
        data: {
          assignedMembershipId: null,
          status: "PENDING"
        }
      });
    }

    return membership;
  });
}
EOF

cat > apps/api/src/modules/team/team.routes.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import {
  requireAuth,
  requireRoles
} from "../auth/auth.guard.js";
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
  app.get("/api/v1/team/memberships", async request => {
    const auth = await requireAuth(request);
    const query = listSchema.parse(request.query);

    return {
      memberships: await listCompanyMemberships(
        auth.companyId,
        query.includeInactive
      )
    };
  });

  app.post(
    "/api/v1/team/memberships",
    async (request, reply) => {
      const auth = await requireRoles(request, [
        "OWNER",
        "ADMIN"
      ]);

      const input = createSchema.parse(request.body);

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
      const auth = await requireRoles(request, [
        "OWNER",
        "ADMIN"
      ]);

      const params = paramsSchema.parse(request.params);
      const input = updateSchema.parse(request.body);

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

cat > apps/web/app/dashboard/team/page.tsx <<'EOF'
"use client";

import {
  type FormEvent,
  useCallback,
  useEffect,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type Role =
  | "OWNER"
  | "ADMIN"
  | "SUPERVISOR"
  | "AGENT";

interface TeamMembership {
  id: string;
  role: Role;
  isActive: boolean;
  user: {
    id: string;
    name: string;
    email: string;
    isActive: boolean;
  };
  queueMemberships: Array<{
    queueId: string;
  }>;
}

const labels: Record<Role, string> = {
  OWNER: "Proprietário",
  ADMIN: "Administrador",
  SUPERVISOR: "Supervisor",
  AGENT: "Atendente"
};

export default function TeamPage() {
  const router = useRouter();
  const { session, loading, request } = useAuth();

  const [members, setMembers] = useState<TeamMembership[]>([]);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] =
    useState<"ADMIN" | "SUPERVISOR" | "AGENT">("AGENT");
  const [busy, setBusy] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const canManage =
    session?.role === "OWNER" ||
    session?.role === "ADMIN";

  const load = useCallback(async () => {
    const response = await request<{
      memberships: TeamMembership[];
    }>("/api/v1/team/memberships?includeInactive=true");

    setMembers(response.memberships);
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }

    if (session) {
      void load();
    }
  }, [load, loading, router, session]);

  async function create(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCreating(true);
    setError("");
    setNotice("");

    try {
      const response = await request<{
        linkedExistingUser: boolean;
      }>("/api/v1/team/memberships", {
        method: "POST",
        body: JSON.stringify({
          name,
          email,
          temporaryPassword: password || undefined,
          role
        })
      });

      setNotice(
        response.linkedExistingUser
          ? "Usuário existente vinculado à empresa."
          : "Usuário criado com sucesso."
      );

      setName("");
      setEmail("");
      setPassword("");
      setRole("AGENT");
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível adicionar a pessoa."
      );
    } finally {
      setCreating(false);
    }
  }

  async function update(
    member: TeamMembership,
    data: {
      role?: "ADMIN" | "SUPERVISOR" | "AGENT";
      isActive?: boolean;
    }
  ) {
    setBusy(member.id);
    setError("");
    setNotice("");

    try {
      await request(
        `/api/v1/team/memberships/${member.id}`,
        {
          method: "PATCH",
          body: JSON.stringify(data)
        }
      );

      setNotice("Acesso atualizado.");
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível alterar o acesso."
      );
    } finally {
      setBusy(null);
    }
  }

  if (loading || !session) {
    return (
      <main className="dashboard-loading">
        Carregando equipe…
      </main>
    );
  }

  const createRoles =
    session.role === "OWNER"
      ? ["ADMIN", "SUPERVISOR", "AGENT"] as const
      : ["SUPERVISOR", "AGENT"] as const;

  return (
    <main className="team-screen">
      <header className="team-header">
        <div>
          <button
            className="connections-back"
            onClick={() => router.push("/dashboard")}
            type="button"
          >
            ← Visão geral
          </button>
          <span className="eyebrow">Administração</span>
          <h1>Equipe</h1>
          <p>
            Usuários, papéis e acesso à empresa atual.
          </p>
        </div>
        <button
          className="ghost-button"
          onClick={() => router.push("/dashboard/queues")}
          type="button"
        >
          Filas
        </button>
      </header>

      {error && <div className="team-feedback team-feedback--error">{error}</div>}
      {notice && <div className="team-feedback">{notice}</div>}

      {canManage && (
        <form className="team-create" onSubmit={create}>
          <input
            onChange={event => setName(event.target.value)}
            placeholder="Nome"
            required
            value={name}
          />
          <input
            onChange={event => setEmail(event.target.value)}
            placeholder="E-mail"
            required
            type="email"
            value={email}
          />
          <input
            minLength={12}
            onChange={event => setPassword(event.target.value)}
            placeholder="Senha temporária (novo usuário)"
            type="password"
            value={password}
          />
          <select
            onChange={event =>
              setRole(
                event.target.value as
                  | "ADMIN"
                  | "SUPERVISOR"
                  | "AGENT"
              )
            }
            value={role}
          >
            {createRoles.map(item => (
              <option key={item} value={item}>
                {labels[item]}
              </option>
            ))}
          </select>
          <button
            className="primary-button"
            disabled={creating}
            type="submit"
          >
            <span>{creating ? "Criando…" : "Adicionar"}</span>
            <span>+</span>
          </button>
        </form>
      )}

      <section className="team-list">
        {members.map(member => {
          const protectedMember =
            member.role === "OWNER" ||
            member.user.id === session.user.id ||
            (session.role === "ADMIN" &&
              member.role === "ADMIN");

          const editableRoles =
            session.role === "OWNER"
              ? ["ADMIN", "SUPERVISOR", "AGENT"] as const
              : ["SUPERVISOR", "AGENT"] as const;

          return (
            <article
              className={
                member.isActive
                  ? "team-member"
                  : "team-member team-member--inactive"
              }
              key={member.id}
            >
              <div className="team-avatar">
                {member.user.name.slice(0, 1).toUpperCase()}
              </div>

              <div className="team-copy">
                <strong>{member.user.name}</strong>
                <span>{member.user.email}</span>
                <small>
                  {member.queueMemberships.length} fila(s)
                </small>
              </div>

              <div>
                {protectedMember || !canManage ? (
                  <span className="team-badge">
                    {labels[member.role]}
                  </span>
                ) : (
                  <select
                    disabled={busy === member.id}
                    onChange={event =>
                      void update(member, {
                        role: event.target.value as
                          | "ADMIN"
                          | "SUPERVISOR"
                          | "AGENT"
                      })
                    }
                    value={
                      member.role as
                        | "ADMIN"
                        | "SUPERVISOR"
                        | "AGENT"
                    }
                  >
                    {editableRoles.map(item => (
                      <option key={item} value={item}>
                        {labels[item]}
                      </option>
                    ))}
                  </select>
                )}
              </div>

              <div className="team-actions">
                <span className="team-badge">
                  {member.isActive ? "Ativo" : "Desativado"}
                </span>

                {canManage && !protectedMember && (
                  <button
                    className="ghost-button"
                    disabled={busy === member.id}
                    onClick={() =>
                      void update(member, {
                        isActive: !member.isActive
                      })
                    }
                    type="button"
                  >
                    {member.isActive ? "Desativar" : "Reativar"}
                  </button>
                )}
              </div>
            </article>
          );
        })}
      </section>
    </main>
  );
}
EOF

cat >> apps/web/app/globals.css <<'EOF'

/* --- WAPP P0.8 / Team -------------------------------------------------- */

.team-screen {
  min-height: 100vh;
  padding: 44px clamp(20px, 5vw, 72px) 80px;
  background: var(--background);
}

.team-header,
.team-create,
.team-list,
.team-feedback {
  max-width: 1180px;
  margin-left: auto;
  margin-right: auto;
}

.team-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 24px;
}

.team-header h1 {
  margin: 8px 0 10px;
  font-size: clamp(42px, 6vw, 64px);
  letter-spacing: -0.055em;
}

.team-header p {
  margin: 0;
  color: var(--muted);
}

.team-feedback {
  margin-bottom: 12px;
  border-radius: 10px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 11px 13px;
  font-size: 11px;
}

.team-feedback--error {
  background: var(--danger-soft);
  color: var(--danger);
}

.team-create {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 180px 130px;
  gap: 10px;
  border: 1px solid var(--line);
  border-radius: 16px;
  background: white;
  padding: 16px;
}

.team-create input,
.team-create select,
.team-member select {
  min-width: 0;
  height: 44px;
  border: 1px solid var(--line);
  border-radius: 10px;
  background: var(--surface-subtle);
  padding: 0 12px;
  font-size: 11px;
}

.team-create .primary-button {
  height: 44px;
  margin: 0;
}

.team-list {
  overflow: hidden;
  margin-top: 14px;
  border: 1px solid var(--line);
  border-radius: 16px;
  background: white;
}

.team-member {
  display: grid;
  grid-template-columns: 42px minmax(220px, 1fr) 190px 210px;
  align-items: center;
  gap: 14px;
  border-bottom: 1px solid var(--line);
  padding: 14px 16px;
}

.team-member:last-child {
  border-bottom: 0;
}

.team-member--inactive {
  opacity: 0.55;
}

.team-avatar {
  display: grid;
  width: 40px;
  height: 40px;
  place-items: center;
  border-radius: 11px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  font-weight: 800;
}

.team-copy {
  display: grid;
  gap: 3px;
}

.team-copy strong {
  font-size: 12px;
}

.team-copy span {
  color: var(--muted);
  font-size: 10px;
}

.team-copy small {
  color: #9aa19c;
  font-size: 8px;
}

.team-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 8px;
}

.team-badge {
  display: inline-flex;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-dark);
  padding: 6px 9px;
  font-size: 9px;
  font-weight: 750;
}

@media (max-width: 900px) {
  .team-create {
    grid-template-columns: 1fr 1fr;
  }

  .team-member {
    grid-template-columns: 42px 1fr;
  }

  .team-member > div:nth-child(3),
  .team-actions {
    grid-column: 2;
  }

  .team-actions {
    justify-content: flex-start;
  }
}
EOF

node <<'NODE'
const fs = require("node:fs");

const path = "apps/web/app/dashboard/page.tsx";
let content = fs.readFileSync(path, "utf8");

if (!content.includes('"Equipe"')) {
  content = content.replace(
    '"Automações"\n];',
    '"Automações",\n  "Equipe"\n];'
  );
}

if (!content.includes('router.push("/dashboard/team")')) {
  const anchor = `                  if (item === "Filas") {
                    router.push("/dashboard/queues");
                  }`;

  if (content.includes(anchor)) {
    content = content.replace(
      anchor,
      `${anchor}

                  if (item === "Equipe") {
                    router.push("/dashboard/team");
                  }`
    );
  }
}

fs.writeFileSync(path, content);
NODE

cat > docs/TEAM.md <<'EOF'
# Team management

P0.8 manages access through `CompanyMembership`.

The global `User` identity remains separate from company access. This matters
because the same identity may participate in more than one company later.

Rules:

- OWNER can add ADMIN, SUPERVISOR and AGENT.
- ADMIN can add SUPERVISOR and AGENT.
- OWNER memberships are protected.
- A user cannot modify their own membership from this screen.
- Role/access changes revoke active sessions for that company membership.
- Deactivating a membership removes it from queues and returns its assigned
  active tickets to PENDING.
- If an email already exists globally, Wapp links the existing identity without
  changing its password.
- A temporary password is only required for a brand-new identity.
EOF

echo "[P0.8] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P0.8] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P0.8] Team management created."
echo "No Prisma migration is required."
echo
echo "Open:"
echo "  http://localhost:3000/dashboard/team"
