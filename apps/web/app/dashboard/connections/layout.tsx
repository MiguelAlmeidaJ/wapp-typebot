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
