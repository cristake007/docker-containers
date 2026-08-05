# syntax=docker/dockerfile:1.7

ARG NODE_VERSION=22

# Pinned by digest, not just a mutable tag (see AUDIT_FINDINGS.md F-011):
# bumping NODE_VERSION or the digest is a deliberate, reviewed change.
FROM node:${NODE_VERSION}-alpine@sha256:c610fcdfb1d5b4740dd70c284ed3cb16bb857e0f7166196e36a5501df7a3aa32 AS deps

WORKDIR /app

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

FROM deps AS dev

ENV NODE_ENV=development

COPY frontend/ ./

EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

FROM deps AS build

COPY frontend/ ./
RUN npm run typecheck && npm run test && npm run build

# No runtime image: prod serves static files from ./dist directly via the
# host's nginx (see deploy/nginx/app.prod.conf.example). Build with:
#   docker build -f docker/frontend/Dockerfile --target export \
#     --output type=local,dest=./frontend/dist .
FROM scratch AS export

COPY --from=build /app/dist /
