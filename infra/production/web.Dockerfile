# syntax=docker/dockerfile:1

FROM node:24-bookworm-slim AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm install --global pnpm@11.16.0

WORKDIR /app

FROM base AS deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install \
  --frozen-lockfile \
  --filter @wapp/web... \
  --filter @wapp/contracts...

FROM deps AS build

COPY tsconfig.base.json ./
COPY apps/web apps/web
COPY packages/contracts packages/contracts

ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

RUN mkdir -p apps/web/public \
  && pnpm --filter @wapp/contracts build \
  && pnpm --filter @wapp/web build

FROM node:24-bookworm-slim AS runtime

ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

WORKDIR /app

COPY --from=build --chown=node:node \
  /app/apps/web/.next/standalone \
  /app

COPY --from=build --chown=node:node \
  /app/apps/web/.next/static \
  /app/apps/web/.next/static

COPY --from=build --chown=node:node \
  /app/apps/web/public \
  /app/apps/web/public

USER node

EXPOSE 3000

CMD ["node", "apps/web/server.js"]
