"use client";

import { type ReactNode, useEffect, useState } from "react";
import { Menu } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";

import { useAuth } from "@/components/auth-provider";
import { NotificationCenter } from "@/components/notifications/notification-center";
import { DashboardSidebar } from "./dashboard-sidebar";
import { getDashboardSection } from "./dashboard-navigation";

const SIDEBAR_STORAGE_KEY = "wapp:sidebar-collapsed";

export function DashboardShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { session, loading, logout } = useAuth();
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    setCollapsed(localStorage.getItem(SIDEBAR_STORAGE_KEY) === "true");
  }, []);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
    }
  }, [loading, router, session]);

  useEffect(() => {
    setMobileOpen(false);
  }, [pathname]);

  function toggleCollapsed() {
    setCollapsed(current => {
      const next = !current;
      localStorage.setItem(SIDEBAR_STORAGE_KEY, String(next));
      return next;
    });
  }

  async function handleLogout() {
    await logout();
    router.replace("/login");
  }

  if (loading || !session) {
    return <main className="dashboard-loading">Carregando workspace…</main>;
  }

  return (
    <div
      className={
        collapsed
          ? "dashboard-shell dashboard-shell--collapsed"
          : "dashboard-shell"
      }
    >
      <DashboardSidebar
        collapsed={collapsed}
        mobileOpen={mobileOpen}
        onCloseMobile={() => setMobileOpen(false)}
        onCollapse={toggleCollapsed}
        onLogout={() => void handleLogout()}
        pathname={pathname}
        session={session}
      />

      {mobileOpen && (
        <button
          className="dashboard-sidebar-backdrop"
          aria-label="Fechar menu"
          onClick={() => setMobileOpen(false)}
          type="button"
        />
      )}

      <section className="dashboard-shell__content">
        <header className="dashboard-shell__topbar">
          <button
            className="dashboard-shell__mobile-toggle"
            aria-controls="dashboard-sidebar"
            aria-expanded={mobileOpen}
            aria-label="Abrir menu"
            onClick={() => setMobileOpen(current => !current)}
            type="button"
          >
            <Menu aria-hidden="true" size={20} strokeWidth={2} />
          </button>

          <div className="dashboard-shell__breadcrumb">
            <span className="topbar__company">{session.company.name}</span>
            <span className="topbar__separator">/</span>
            <span className="topbar__section">
              {getDashboardSection(pathname)}
            </span>
          </div>

          <NotificationCenter />
        </header>

        <div className="dashboard-shell__page">{children}</div>
      </section>

    </div>
  );
}
