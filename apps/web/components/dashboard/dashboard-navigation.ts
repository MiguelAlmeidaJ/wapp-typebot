import {
  BarChart3,
  Cable,
  ChartNoAxesCombined,
  CircleGauge,
  ContactRound,
  DatabaseZap,
  Kanban,
  ListChecks,
  Megaphone,
  MessagesSquare,
  Tags,
  UsersRound,
  Workflow,
  type LucideIcon
} from "lucide-react";

import type { Role } from "@/lib/auth-types";
import type { UiPermission } from "@/lib/permissions";

export interface DashboardNavigationItem {
  label: string;
  href: string;
  permission: UiPermission;
  icon: LucideIcon;
}

export interface DashboardNavigationGroup {
  id: string;
  label: string;
  items: readonly DashboardNavigationItem[];
}

export const roleLabels: Record<Role, string> = {
  OWNER: "Proprietário",
  ADMIN: "Administrador",
  SUPERVISOR: "Supervisor",
  AGENT: "Atendente"
};

export const dashboardNavigation: readonly DashboardNavigationGroup[] = [
  {
    id: "atendimento",
    label: "Atendimento",
    items: [
      {
        label: "Visão geral",
        href: "/dashboard",
        permission: "dashboard.view",
        icon: CircleGauge
      },
      {
        label: "Conversas",
        href: "/dashboard/conversations",
        permission: "conversations.view",
        icon: MessagesSquare
      },
      {
        label: "Contatos",
        href: "/dashboard/contacts",
        permission: "contacts.view",
        icon: ContactRound
      }
    ]
  },
  {
    id: "operacao",
    label: "Operação",
    items: [
      {
        label: "Pipeline",
        href: "/dashboard/pipeline",
        permission: "pipeline.view",
        icon: Kanban
      },
      {
        label: "Tarefas",
        href: "/dashboard/tasks",
        permission: "tasks.view",
        icon: ListChecks
      },
      {
        label: "Automações",
        href: "/dashboard/automations",
        permission: "conversations.view",
        icon: Workflow
      }
    ]
  },
  {
    id: "marketing",
    label: "Marketing",
    items: [
      {
        label: "Segmentos",
        href: "/dashboard/segments",
        permission: "segments.view",
        icon: Tags
      },
      {
        label: "Campanhas",
        href: "/dashboard/campaigns",
        permission: "campaigns.view",
        icon: Megaphone
      }
    ]
  },
  {
    id: "gestao",
    label: "Gestão",
    items: [
      {
        label: "Qualidade dos dados",
        href: "/dashboard/data-quality",
        permission: "dataQuality.view",
        icon: DatabaseZap
      },
      {
        label: "Relatórios",
        href: "/dashboard/reports",
        permission: "reports.view",
        icon: ChartNoAxesCombined
      }
    ]
  },
  {
    id: "administracao",
    label: "Administração",
    items: [
      {
        label: "Filas",
        href: "/dashboard/queues",
        permission: "queues.manage",
        icon: BarChart3
      },
      {
        label: "Conexões",
        href: "/dashboard/connections",
        permission: "connections.manage",
        icon: Cable
      },
      {
        label: "Equipe",
        href: "/dashboard/team",
        permission: "team.manage",
        icon: UsersRound
      }
    ]
  }
];

export function isDashboardItemActive(
  pathname: string,
  href: string
) {
  if (href === "/dashboard") {
    return pathname === href;
  }

  return pathname === href || pathname.startsWith(`${href}/`);
}

export function getDashboardSection(pathname: string) {
  for (const group of dashboardNavigation) {
    const item = group.items.find(candidate =>
      isDashboardItemActive(pathname, candidate.href)
    );

    if (item) {
      return item.label;
    }
  }

  return "Workspace";
}
