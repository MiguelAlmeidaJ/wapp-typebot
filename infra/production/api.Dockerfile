# syntax=docker/dockerfile:1

FROM node:24-bookworm-slim AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm install --global pnpm@11.16.0

WORKDIR /app

FROM base AS build-deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install \
  --frozen-lockfile \
  --filter @wapp/api... \
  --filter @wapp/contracts...

FROM build-deps AS build

COPY tsconfig.base.json ./
COPY apps/api apps/api
COPY packages/contracts packages/contracts

RUN pnpm --filter @wapp/contracts build \
  && pnpm --filter @wapp/api db:generate \
  && pnpm --filter @wapp/api build

FROM base AS production-deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install \
  --frozen-lockfile \
  --prod \
  --filter @wapp/api...

FROM base AS runtime

ENV NODE_ENV=production

COPY --from=production-deps /app/node_modules /app/node_modules
COPY --from=production-deps /app/apps/api/node_modules /app/apps/api/node_modules
COPY --from=production-deps /app/apps/api/package.json /app/apps/api/package.json
COPY --from=production-deps /app/packages/contracts /app/packages/contracts

COPY --from=build /app/apps/api/dist /app/apps/api/dist
COPY --from=build /app/packages/contracts/dist /app/packages/contracts/dist

WORKDIR /app/apps/api

USER node

EXPOSE 4000

CMD ["node", "dist/server.js"]

FROM build AS migrate

ENV NODE_ENV=production

WORKDIR /app/apps/api

CMD ["pnpm", "db:deploy"]
