import type { Metadata } from "next";
import type { ReactNode } from "react";

import "./globals.css";

export const metadata: Metadata = {
  title: "Wapp",
  description: "Plataforma de atendimento e automação para WhatsApp.",
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
      <body>{children}</body>
    </html>
  );
}
