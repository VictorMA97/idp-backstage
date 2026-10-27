# syntax=docker/dockerfile:1
#
# Imagen de Backstage en varias etapas. La imagen final no lleva compiladores ni gestor de
# paquetes de apt de más: las dependencias nativas se compilan en una etapa aparte y solo se copia
# el resultado. Se ejecuta como el usuario "node" (no root).
#
# Contexto de construcción: la raíz del repo.

ARG NODE_IMAGE=node:24-trixie-slim

# ---- 1) esqueleto: solo los package.json, para cachear la instalación de dependencias ----
FROM ${NODE_IMAGE} AS packages
WORKDIR /app
COPY package.json yarn.lock backstage.json .yarnrc.yml ./
COPY .yarn ./.yarn
COPY packages packages
COPY plugins plugins
RUN find packages \! -name "package.json" -mindepth 2 -maxdepth 2 -exec rm -rf {} \+

# ---- 2) build: compila TypeScript, el frontend y empaqueta el backend ----
FROM ${NODE_IMAGE} AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 g++ make \
 && rm -rf /var/lib/apt/lists/*
USER node
WORKDIR /app
COPY --from=packages --chown=node:node /app .
RUN mkdir -p /home/node/.yarn/berry
RUN --mount=type=cache,target=/home/node/.yarn/berry/cache,uid=1000,gid=1000 \
    yarn install --immutable
COPY --chown=node:node . .
RUN yarn tsc
RUN yarn build:backend

# ---- 3) deps: dependencias de producción (compila los módulos nativos aquí) ----
FROM ${NODE_IMAGE} AS deps
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 g++ make \
 && rm -rf /var/lib/apt/lists/*
USER node
WORKDIR /app
COPY --chown=node:node .yarn ./.yarn
COPY --chown=node:node .yarnrc.yml backstage.json ./
COPY --from=build --chown=node:node /app/yarn.lock /app/package.json /app/packages/backend/dist/skeleton.tar.gz ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz
RUN mkdir -p /home/node/.yarn/berry
RUN --mount=type=cache,target=/home/node/.yarn/berry/cache,uid=1000,gid=1000 \
    yarn workspaces focus --all --production
COPY --from=build --chown=node:node /app/packages/backend/dist/bundle.tar.gz ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz

# ---- 4) final: solo lo necesario para ejecutar ----
FROM ${NODE_IMAGE}
ENV NODE_ENV=production
USER node
WORKDIR /app
COPY --from=deps --chown=node:node /app .
COPY --chown=node:node app-config.yaml app-config.production.yaml ./
COPY --chown=node:node catalog ./catalog
EXPOSE 7007
CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
