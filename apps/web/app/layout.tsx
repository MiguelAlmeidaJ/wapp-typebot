import type { Metadata } from "next";
import type { ReactNode } from "react";

import { AuthProvider } from "@/components/auth-provider";

import "./globals.css";
import "./dashboard/conversations/conversations.css";

export const metadata: Metadata = {
  title: {
    default: "Wapp",
    template: "%s · Wapp"
  },
  description: "Atendimento, automação e operação de conversas.",
  authors: [
    {
      name: "Miguel Almeida",
      url: "https://github.com/MiguelAlmeidaJ"
    }
  ]
};

export default function RootLayout({
  children
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <html lang="pt-BR">
      <body suppressHydrationWarning>
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
