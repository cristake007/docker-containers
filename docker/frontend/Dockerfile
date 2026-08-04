# syntax=docker/dockerfile:1.7

ARG NODE_VERSION=22

FROM node:${NODE_VERSION}-alpine AS deps

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
