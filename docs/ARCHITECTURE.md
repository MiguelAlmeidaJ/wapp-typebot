# Arquitetura

## Objetivo

Reconstruir a aplicação como produto independente, mantendo o sistema herdado
temporariamente apenas como referência de comportamento.

## Stack

- Monorepo: pnpm + Turborepo
- Web: Next.js + React + TypeScript
- API: Node.js + Fastify + TypeScript
- Contratos: Zod + TypeScript
- Infra local: MySQL + Redis via Docker

## Módulos planejados

- identity
- companies
- users
- contacts
- queues
- tickets
- messages
- whatsapp
- realtime
- automations
- typebot
- campaigns
- schedules
- audit

## Estratégia de migração

Para cada domínio:

1. mapear o comportamento legado;
2. definir contrato novo;
3. implementar o módulo novo;
4. validar;
5. migrar somente os dados necessários;
6. remover a dependência legada.

## Desenvolvedor do projeto novo

Miguel Almeida

- miguel@anoar.com.br
- https://github.com/MiguelAlmeidaJ
- https://www.instagram.com/miguelalmeida.j/

Avisos legais e licenças aplicáveis ao código herdado devem ser preservados.
