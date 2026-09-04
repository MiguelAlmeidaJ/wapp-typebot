"use client";

import Link from "next/link";
import {
  Bot,
  Workflow
} from "lucide-react";

import styles from "./automation-tabs.module.css";

type AutomationArea = "rules" | "chatbots";

const tabs: Array<{
  id: AutomationArea;
  href: string;
  label: string;
  description: string;
  icon: typeof Workflow;
}> = [
  {
    id: "rules",
    href: "/dashboard/automations",
    label: "Regras",
    description: "Ações operacionais automáticas",
    icon: Workflow
  },
  {
    id: "chatbots",
    href: "/dashboard/automations/chatbots",
    label: "Chatbots",
    description: "Fluxos de atendimento",
    icon: Bot
  }
];

export function AutomationTabs({
  active
}: {
  active: AutomationArea;
}) {
  return (
    <nav
      aria-label="Áreas de automação"
      className={styles.tabs}
    >
      {tabs.map(tab => {
        const Icon = tab.icon;
        const selected = tab.id === active;

        return (
          <Link
            aria-current={selected ? "page" : undefined}
            className={`${styles.tab} ${
              selected ? styles.active : ""
            }`}
            href={tab.href}
            key={tab.id}
          >
            <span className={styles.icon}>
              <Icon
                aria-hidden="true"
                size={18}
                strokeWidth={1.8}
              />
            </span>

            <span>
              <strong>{tab.label}</strong>
              <small>{tab.description}</small>
            </span>
          </Link>
        );
      })}
    </nav>
  );
}
