import type {
  ReactNode
} from "react";

import {
  NotificationCenter
} from "@/components/notifications/notification-center";

export default function DashboardLayout({
  children
}: Readonly<{
  children:
    ReactNode;
}>) {
  return (
    <>
      {children}
      <NotificationCenter />
    </>
  );
}
