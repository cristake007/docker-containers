# Task manager: Symfony + GraphQL + Postgres + React

A small full-stack reference app: Symfony backend exposing a GraphQL API
(via [API Platform](https://api-platform.com/)) backed by Postgres, JWT
authentication delivered as an httpOnly cookie, and a React + TypeScript
frontend (Vite + Apollo Client). The demo domain is a per-user task list,
just enough to prove the whole chain works: register, log in, create/toggle/
delete your own tasks, and never see anyone else's.

## Architecture

```
┌──────────────┐        ┌───────────────────────────┐        ┌──────────────┐
│  host nginx  │──────▶ │ backend container          │──────▶ │ db container │
│ (TLS, static │  :9000 │ PHP-FPM only (no web server │ :5432  │ postgres     │
│  files, /api │fastcgi │ inside the container)       │        │              │
│  proxy)      │        └───────────────────────────┘        └──────────────┘
│              │
│              │──────▶ dev only: vite dev server (:5173)
└──────────────┘        prod: static files from frontend/dist
```

nginx runs on the **host**, not in a container. PHP-FPM only speaks FastCGI
(it is not an HTTP server), and there is no frontend container in
production at all -- the React build is a set of static files nginx serves
directly. This keeps every container minimal and puts exactly one thing
(TLS, routing, static files) in the layer designed for it. See
`deploy/nginx/*.example` for the config to install into your own nginx.

## Stack

- **Backend**: Symfony 8.1, [API Platform](https://api-platform.com/) for
  GraphQL, Doctrine ORM/Migrations, Postgres.
- **Auth**: `lexik/jwt-authentication-bundle`. The JWT is delivered as an
  **httpOnly, SameSite=Strict cookie** -- it is never readable from
  JavaScript, so an XSS bug in the frontend can't exfiltrate it. Every
  Task GraphQL operation is scoped to the authenticated user, enforced both
  by a `security` expression per operation and by a Doctrine query
  extension (`App\Doctrine\CurrentUserTaskExtension`) that filters every
  underlying query -- so it's not just "denied at the edge", other users'
  rows are never fetched at all.
- **Frontend**: React 19 + TypeScript, Vite, Apollo Client
  (`credentials: 'include'`, no token handling in JS).

## Prerequisites

- Docker + Docker Compose v2.
- nginx installed on the host (not in a container) for anything beyond
  `npm run dev` / a bare PHP-FPM socket -- see [nginx setup](#nginx-setup).

## Development

```bash
docker compose up --build -d
```

This starts three services (`compose.override.yaml` is applied
automatically): `db` (Postgres, published to `127.0.0.1:5432` for local
psql), `backend` (PHP-FPM dev image, published to `127.0.0.1:9000`,
source bind-mounted from `./backend`), and `frontend` (Vite dev server,
published to `127.0.0.1:5173`, source bind-mounted from `./frontend`).

Then [set up host nginx](#nginx-setup) once, and open
`http://tasks.localhost/`.

Useful commands:

```bash
docker compose exec backend php bin/console doctrine:migrations:migrate
docker compose exec backend php bin/console make:migration   # after entity changes
docker compose exec backend composer require vendor/package
docker compose logs -f backend frontend
docker compose down            # stop, keep volumes (db data, vendor, node_modules)
docker compose down -v         # stop and wipe volumes too
```

After changing `backend/composer.json` or `composer.lock`:

```bash
docker compose run --rm backend composer install
```

## Environment variables

The root [`.env`](./.env) is committed with obviously-fake dev defaults, so
`docker compose up` works with zero setup. **Deploying to production
means overriding every one of these** with real secrets -- export real
environment variables before running `docker compose -f compose.yaml up`
(or inject them via your CI/CD secrets manager). Real environment variables
always take precedence over the committed file.

| Variable | Purpose |
| --- | --- |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Postgres credentials, shared with `DATABASE_URL` |
| `APP_SECRET` | Symfony's internal signing secret |
| `JWT_PASSPHRASE` | Passphrase protecting the generated JWT private key |
| `CORS_ALLOW_ORIGIN` | Regex matched against `Origin` for cross-origin requests (irrelevant if frontend + API share one nginx origin) |

As a safety net, `docker/backend/entrypoint.sh` **refuses to boot in prod**
if it detects the committed placeholder values are still active, so a
forgotten override fails loudly instead of silently running with public
secrets.

The JWT signing keypair itself (not a plain string secret) is generated on
first boot into the `backend_jwt` volume by the same entrypoint script.

## Production

```bash
docker compose -f compose.yaml up --build -d
```

This starts only `db` and `backend` -- no frontend container. The backend
image:

- runs PHP-FPM only, with `clear_env=no` in its pool config so Docker
  Compose's `environment:` actually reaches the app (PHP-FPM's default,
  `clear_env=yes`, silently strips it otherwise -- a common footgun for
  Dockerized PHP-FPM apps);
- installs dependencies from the committed `backend/composer.lock`,
  `--no-dev`, `--classmap-authoritative`;
- validates Composer metadata, platform requirements, and runs
  `composer audit` during the build;
- contains neither Composer nor Git;
- keeps application source owned by `root`, with `var/` and `config/jwt/`
  writable by `www-data`;
- publishes port 9000 on `127.0.0.1` only, for the host's nginx to
  `fastcgi_pass` to (see below) -- never bind this to a non-loopback
  address, PHP-FPM does no request validation of its own.

Build the frontend as static files (no container runs in prod):

```bash
docker build -f docker/frontend/Dockerfile --target export \
  --output type=local,dest=./frontend/dist .
```

Then apply the database migrations (a deliberate, explicit step -- not run
automatically on every container start, to avoid races if you ever scale
`backend` to more than one replica):

```bash
docker compose -f compose.yaml run --rm backend php bin/console doctrine:migrations:migrate --no-interaction
```

## nginx setup

Copy the example matching your environment into your host nginx config,
adjust `server_name` / `root` / TLS certificate paths, then reload nginx:

- [`deploy/nginx/app.dev.conf.example`](./deploy/nginx/app.dev.conf.example) --
  proxies `/` to the Vite dev server and `/api` to the backend's FastCGI
  port.
- [`deploy/nginx/app.prod.conf.example`](./deploy/nginx/app.prod.conf.example) --
  serves `frontend/dist` as static files at `/` and proxies `/api` to the
  backend's FastCGI port. TLS certificates are your host's responsibility
  (e.g. certbot/Let's Encrypt); this repo doesn't manage them.

Serving the frontend and API through the same nginx origin is what makes
the httpOnly cookie and CORS work with zero extra configuration -- the
browser sees one same-origin app, not two.

## Test

```bash
sh tests/backend-smoke.sh   # container-level: both PHP-FPM images boot correctly, migrations apply, composer audit is clean
sh tests/stack-smoke.sh     # application-level: register/login/GraphQL CRUD/per-user isolation/logout, for real, over HTTP
```

CI runs both, plus a separate frontend job (lint, typecheck, Vitest,
production build, `npm audit`) -- see `.github/workflows/`.

## Repository layout

```
backend/            Symfony app (API Platform, Doctrine, JWT)
frontend/            React + TypeScript app (Vite, Apollo Client)
docker/backend/      Backend Dockerfile + PHP-FPM config
docker/frontend/      Frontend Dockerfile (dev server + static export stages)
deploy/nginx/        Host-nginx config templates (not run by Compose)
compose.yaml          Production: db + backend
compose.override.yaml Development additions: frontend, published ports, bind mounts
tests/                Smoke tests (container-level and application-level)
```
