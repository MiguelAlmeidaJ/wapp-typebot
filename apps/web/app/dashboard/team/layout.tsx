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
