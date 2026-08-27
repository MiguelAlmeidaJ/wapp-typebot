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
