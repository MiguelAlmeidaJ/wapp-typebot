# Wapp

Plataforma de atendimento e automação para WhatsApp em reconstrução como
monorepo TypeScript.

## Desenvolvedor

- Miguel Almeida
- miguel@anoar.com.br
- https://github.com/MiguelAlmeidaJ
- https://www.instagram.com/miguelalmeida.j/

## Estrutura

```text
apps/
  api/       Node.js + Fastify + TypeScript
  web/       Next.js + TypeScript

packages/
  contracts/

infra/
docs/
legacy/
```

Veja a [documentação da integração com Typebot](docs/typebot-integration.md).

## Ambiente local

```bash
corepack enable
pnpm install

cp apps/api/.env.example apps/api/.env
cp apps/web/.env.example apps/web/.env.local

pnpm infra:up
pnpm dev
```

- Web: http://localhost:3000
- API: http://localhost:4000
- Health: http://localhost:4000/health

O código herdado fica temporariamente em `legacy/` somente como referência de
comportamento durante a migração.
