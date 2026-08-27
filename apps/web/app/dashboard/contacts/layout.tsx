"use client";

import type { ReactNode } from "react";

import { AccessGate } from "@/components/access-gate";

export default function ContactsLayout({
  children
}: {
  children: ReactNode;
}) {
  return (
    <AccessGate permission="contacts.view">
      {children}
    </AccessGate>
  );
}
