import type {
  ReactNode
} from "react";

import {
  DashboardShell
} from "@/components/dashboard/dashboard-shell";

export default function DashboardLayout({
  children
}: Readonly<{
  children:
    ReactNode;
}>) {
  return (
    <DashboardShell>
      {children}
    </DashboardShell>
  );
}
