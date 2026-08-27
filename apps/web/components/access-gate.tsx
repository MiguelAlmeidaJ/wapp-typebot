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
