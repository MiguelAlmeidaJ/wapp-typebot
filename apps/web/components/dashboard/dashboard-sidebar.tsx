"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ChevronDown, LogOut, PanelLeftClose } from "lucide-react";

import { WappMark } from "@/components/wapp-mark";
import type { AuthSession } from "@/lib/auth-types";
import { roleCan } from "@/lib/permissions";
import {
  dashboardNavigation,
  isDashboardItemActive,
  roleLabels
} from "./dashboard-navigation";

interface DashboardSidebarProps {
  session: AuthSession;
  pathname: string;
  collapsed: boolean;
  mobileOpen: boolean;
  onCollapse(): void;
  onCloseMobile(): void;
  onLogout(): void;
}

export function DashboardSidebar({
  session,
  pathname,
  collapsed,
  mobileOpen,
  onCollapse,
  onCloseMobile,
  onLogout
}: DashboardSidebarProps) {
  const visibleGroups = useMemo(
    () =>
      dashboardNavigation
        .map(group => ({
          ...group,
          items: group.items.filter(item =>
            roleCan(session.role, item.permission)
          )
        }))
        .filter(group => group.items.length > 0),
    [session.role]
  );

  const activeGroup = visibleGroups.find(group =>
    group.items.some(item =>
      isDashboardItemActive(pathname, item.href)
    )
  )?.id;

  const [openGroups, setOpenGroups] = useState<Set<string>>(
    () => new Set([activeGroup ?? visibleGroups[0]?.id].filter(Boolean) as string[])
  );

  useEffect(() => {
    if (!activeGroup) {
      return;
    }

    setOpenGroups(current => {
      if (current.has(activeGroup)) {
        return current;
      }

      const next = new Set(current);
      next.add(activeGroup);
      return next;
    });
  }, [activeGroup]);

  function toggleGroup(groupId: string) {
    setOpenGroups(current => {
      const next = new Set(current);

      if (next.has(groupId)) {
        next.delete(groupId);
      } else {
        next.add(groupId);
      }

      return next;
    });
  }

  return (
    <aside
      className={
        mobileOpen
          ? "dashboard-sidebar dashboard-sidebar--mobile-open"
          : "dashboard-sidebar"
      }
      id="dashboard-sidebar"
    >
      <div className="dashboard-sidebar__header">
        <WappMark compact />
        <button
          className="dashboard-sidebar__collapse"
          aria-label={collapsed ? "Expandir menu" : "Recolher menu"}
          onClick={onCollapse}
          title={collapsed ? "Expandir menu" : "Recolher menu"}
          type="button"
        >
          <PanelLeftClose aria-hidden="true" size={17} strokeWidth={1.9} />
        </button>
      </div>

      <nav className="dashboard-sidebar__nav" aria-label="Navegação principal">
        {visibleGroups.map(group => {
          const isOpen =
            (collapsed && !mobileOpen) ||
            openGroups.has(group.id);

          return (
            <section className="sidebar-group" key={group.id}>
              <button
                className="sidebar-group__trigger"
                aria-controls={`sidebar-group-${group.id}`}
                aria-expanded={isOpen}
                onClick={() => toggleGroup(group.id)}
                type="button"
              >
                <span>{group.label}</span>
                <ChevronDown aria-hidden="true" size={14} strokeWidth={2} />
              </button>

              <div
                className="sidebar-group__items"
                hidden={!isOpen}
                id={`sidebar-group-${group.id}`}
              >
                {group.items.map(item => {
                  const Icon = item.icon;
                  const active = isDashboardItemActive(pathname, item.href);

                  return (
                    <Link
                      className={
                        active
                          ? "sidebar-link sidebar-link--active"
                          : "sidebar-link"
                      }
                      aria-current={active ? "page" : undefined}
                      href={item.href}
                      key={item.href}
                      onClick={onCloseMobile}
                      title={collapsed ? item.label : undefined}
                    >
                      <span className="sidebar-link__icon">
                        <Icon aria-hidden="true" size={18} strokeWidth={1.8} />
                      </span>
                      <span className="sidebar-link__label">{item.label}</span>
                    </Link>
                  );
                })}
              </div>
            </section>
          );
        })}
      </nav>

      <div className="dashboard-sidebar__footer">
        <div className="dashboard-sidebar__user">
          <div className="avatar" aria-hidden="true">
            {session.user.name.slice(0, 1).toUpperCase()}
          </div>
          <div className="dashboard-sidebar__user-copy">
            <strong>{session.user.name}</strong>
            <span>{roleLabels[session.role]}</span>
          </div>
        </div>
        <button
          className="dashboard-sidebar__logout"
          aria-label="Sair"
          onClick={onLogout}
          title="Sair"
          type="button"
        >
          <LogOut aria-hidden="true" size={17} strokeWidth={1.9} />
        </button>
      </div>
    </aside>
  );
}
